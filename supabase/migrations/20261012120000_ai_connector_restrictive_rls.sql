-- =============================================================================
-- AI connector S1: an OAuth client token never reaches user data directly
-- =============================================================================
-- Supabase Auth's OAuth 2.1 server issues access tokens with role
-- "authenticated", the user's `sub` and a `client_id` claim. Scopes do not
-- gate database access, so without this migration an AI assistant holding a
-- user's grant could read user_stacks, submissions and Storage objects through
-- the Data API, or call the app's SECURITY DEFINER RPCs as that user.
-- https://supabase.com/docs/guides/auth/oauth-server/token-security
--
-- App sessions and the anon key carry no `client_id`, so nothing here changes
-- what the app, the website or the pipeline can do. The personal MCP server
-- (supabase/functions/mcp-personal) verifies the OAuth token itself and reads
-- with the service role filtered by the verified `sub`; it never forwards the
-- token, and the service role bypasses RLS.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).
-- Idempotent: policies are dropped and recreated, functions are replaced.
-- Test: scripts/test_ai_connector_rls.sh (supabase/tests/ai_connector/).

-- One owner for the RPC guard. SECURITY DEFINER functions run as their owner,
-- which bypasses RLS, so a restrictive policy alone does not cover them.
CREATE OR REPLACE FUNCTION public.reject_oauth_client_request()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  IF (auth.jwt() ->> 'client_id') IS NOT NULL THEN
    RAISE EXCEPTION 'AI assistant connections cannot call this function'
      USING ERRCODE = '42501';
  END IF;
END
$$;
REVOKE ALL ON FUNCTION public.reject_oauth_client_request() FROM PUBLIC, anon, authenticated;

-- Restrictive policies are ANDed with every permissive policy, so an OAuth
-- client token sees zero rows and can write none, whatever else grants access.
-- A missing table or a table without RLS is a schema drift this migration must
-- not paper over, so both fail loudly instead of being skipped.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_stacks',
    'user_usage',
    'device_push_tokens',
    'product_submissions',
    'product_submission_mismatch_details',
    'product_submission_missing_details',
    'product_submission_photos',
    'product_submission_evidence_revisions',
    'product_contribution_ledger'
  ] LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE EXCEPTION 'S1: user-owned table public.% is missing', t;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = format('public.%I', t)::regclass) THEN
      RAISE EXCEPTION 'S1: RLS is disabled on public.%', t;
    END IF;
    EXECUTE format('DROP POLICY IF EXISTS ai_connector_no_oauth_client ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY ai_connector_no_oauth_client ON public.%I AS RESTRICTIVE FOR ALL '
      'USING ((SELECT auth.jwt() ->> %L) IS NULL) '
      'WITH CHECK ((SELECT auth.jwt() ->> %L) IS NULL)',
      t, 'client_id', 'client_id');
  END LOOP;
END
$$;

-- Storage: every bucket, not only the submission and label-mismatch ones. An
-- OAuth client has no legitimate Storage use; public catalog blobs are served
-- through public URLs and the service role, neither of which RLS touches.
DROP POLICY IF EXISTS ai_connector_no_oauth_client ON storage.objects;
CREATE POLICY ai_connector_no_oauth_client ON storage.objects
  AS RESTRICTIVE FOR ALL
  USING ((SELECT auth.jwt() ->> 'client_id') IS NULL)
  WITH CHECK ((SELECT auth.jwt() ->> 'client_id') IS NULL);

-- The SECURITY DEFINER RPCs the app calls (lib/services/product_submission_service.dart).
-- Each body below is the current definition from the migration chain,
-- unchanged except for the first statement, which calls the guard.

CREATE OR REPLACE FUNCTION public.add_product_submission_evidence(p_submission_id uuid, p_expected_revision integer, p_photos jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_expected_revision IS NULL OR p_expected_revision < 2 THEN
    RAISE EXCEPTION 'expected evidence revision required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_photos) = 0 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;
  IF submission.evidence_revision <> p_expected_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state <> 'pending'
     OR submission.evidence_revision < 2
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open evidence revision required' USING ERRCODE = '55000';
  END IF;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    submission.evidence_revision
  );
  RETURN true;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.create_product_submission(p_submission_id uuid, p_kind product_submission_kind, p_upc text DEFAULT NULL::text, p_mismatch_detail jsonb DEFAULT NULL::jsonb, p_no_separate_ingredient_panel boolean DEFAULT false, p_photos jsonb DEFAULT '[]'::jsonb, p_resubmission_of uuid DEFAULT NULL::uuid, p_consent_version text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  target_submission public.product_submissions%ROWTYPE;
  existing_lineage uuid;
  had_existing boolean := false;
  persisted_count integer := 0;
  result_value boolean;
  consent_version_value text := NULLIF(btrim(coalesce(p_consent_version, '')), '');
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission id required' USING ERRCODE = '22023';
  END IF;
  IF p_resubmission_of = p_submission_id THEN
    RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
  END IF;
  IF consent_version_value IS NULL
     OR consent_version_value !~ '^[A-Za-z0-9._-]{1,80}$' THEN
    RAISE EXCEPTION 'consent version required' USING ERRCODE = '22023';
  END IF;
  -- Only a registered, unretired version for this kind can be attested; the
  -- registry pins the copy hash and purposes the version stands for.
  IF NOT EXISTS (
    SELECT 1
    FROM public.product_submission_consent_versions AS consent
    WHERE consent.version = consent_version_value
      AND consent.kind = p_kind
      AND consent.retired_at IS NULL
      AND consent.effective_from <= now()
  ) THEN
    RAISE EXCEPTION 'consent version not recognized' USING ERRCODE = '22023';
  END IF;

  -- An absent row cannot be locked with FOR UPDATE. Serialize first-create
  -- replays by UUID across owners before reading lineage, so a concurrent
  -- request cannot turn the original NULL lineage into a different value.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('product_submission_create:' || p_submission_id::text, 0)
  );

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[^0-9]',
    '',
    'g'
  ), '');

  IF p_resubmission_of IS NOT NULL THEN
    SELECT target.*
      INTO target_submission
    FROM public.product_submissions AS target
    WHERE target.id = p_resubmission_of
      AND target.user_id = caller_id
      AND target.review_status = 'rejected'
      AND target.resolution_code IN (
        'photo_quality',
        'missing_panel',
        'label_unreadable',
        'product_identity_mismatch',
        'other'
      )
      AND target.kind = p_kind
      AND public.product_submission_canonical_gtin(target.normalized_upc)
        IS NOT DISTINCT FROM
          public.product_submission_canonical_gtin(normalized_upc_value)
    FOR SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'label_mismatch' AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_mismatch_details AS target_detail
      WHERE target_detail.submission_id = p_resubmission_of
        AND target_detail.user_id = caller_id
        AND target_detail.dsld_id = btrim(p_mismatch_detail->>'dsld_id')
    ) THEN
      RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT submission.resubmission_of
    INTO existing_lineage
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
    AND submission.user_id = caller_id
  FOR UPDATE;
  had_existing := FOUND;
  IF had_existing
     AND existing_lineage IS DISTINCT FROM p_resubmission_of THEN
    RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
  END IF;
  IF had_existing AND EXISTS (
    SELECT 1 FROM public.product_submissions WHERE id = p_submission_id
      AND consent_version IS DISTINCT FROM consent_version_value
  ) THEN
    RAISE EXCEPTION 'consent replay conflict' USING ERRCODE = '23505';
  END IF;

  result_value := public.create_product_submission_v2_internal(
    p_submission_id,
    p_kind,
    p_upc,
    p_mismatch_detail,
    p_no_separate_ingredient_panel,
    p_photos
  );

  IF NOT had_existing THEN
    UPDATE public.product_submissions AS submission
    SET resubmission_of = p_resubmission_of,
        consent_version = consent_version_value,
        consented_at = now()
    WHERE submission.id = p_submission_id
      AND submission.user_id = caller_id
      AND (
        submission.resubmission_of IS NULL
        OR submission.resubmission_of IS NOT DISTINCT FROM p_resubmission_of
      )
      AND submission.consent_version IS NULL;
    GET DIAGNOSTICS persisted_count = ROW_COUNT;
    IF persisted_count <> 1 THEN
      RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
    END IF;
    UPDATE public.product_submission_evidence_revisions
    SET consent_version = consent_version_value, consented_at = now()
    WHERE submission_id = p_submission_id AND revision = 1;
  END IF;

  RETURN result_value;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.finalize_product_submission(p_submission_id uuid, p_expected_revision integer DEFAULT 1)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  manifest jsonb;
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;
  IF p_expected_revision IS DISTINCT FROM submission.evidence_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state = 'ready' THEN
    RETURN true;
  END IF;
  IF submission.upload_state <> 'pending' THEN
    RETURN false;
  END IF;

  SELECT revision.*
    INTO current_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = submission.evidence_revision
    AND revision.ready_at IS NULL
    AND revision.abandoned_at IS NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF submission.evidence_revision > 1 AND NOT EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = submission.evidence_revision
  ) THEN
    RETURN false;
  END IF;

  IF submission.kind = 'missing_product'
     AND NOT public.product_submission_has_required_evidence(
       p_submission_id,
       caller_id
     ) THEN
    RETURN false;
  END IF;
  IF submission.kind = 'label_mismatch' AND NOT EXISTS (
    SELECT 1
    FROM public.product_submission_mismatch_details AS mismatch
    WHERE mismatch.submission_id = p_submission_id
      AND mismatch.user_id = caller_id
  ) THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.user_id = caller_id
      AND photo.photo_id = ANY(current_revision.photo_ids)
      AND NOT EXISTS (
        SELECT 1
        FROM storage.objects AS object
        WHERE object.bucket_id = 'product-submission-photos'
          AND object.owner_id = caller_id::text
          AND object.name = photo.object_path
          AND coalesce((object.metadata->>'size')::bigint, -1)
            = photo.byte_size
          AND lower(coalesce(object.metadata->>'mimetype', ''))
            = photo.content_type
          AND lower(
            coalesce(object.user_metadata->>'content_sha256', '')
          ) = photo.content_sha256
      )
  ) THEN
    RETURN false;
  END IF;

  manifest := public.product_submission_evidence_manifest(
    p_submission_id, submission.evidence_revision
  );
  UPDATE public.product_submission_evidence_revisions
  SET ready_at = now(),
      manifest = public.product_submission_evidence_records(p_submission_id, submission.evidence_revision),
      manifest_sha256 = public.product_submission_manifest_sha256(
        public.product_submission_evidence_records(p_submission_id, submission.evidence_revision))
  WHERE submission_id = p_submission_id
    AND revision = submission.evidence_revision;
  UPDATE public.product_submissions
  SET upload_state = 'ready',
      submitted_at = coalesce(submitted_at, now()),
      evidence_ready_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id
    AND upload_state = 'pending';

  INSERT INTO public.admin_submission_notifications (submission_id)
  VALUES (p_submission_id)
  ON CONFLICT (submission_id) DO NOTHING;

  RETURN true;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.get_product_submission_intake(p_kind product_submission_kind, p_upc text, p_dsld_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  dsld_value text := NULLIF(btrim(coalesce(p_dsld_id, '')), '');
  candidate public.product_submissions%ROWTYPE;
  action_value text;
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL THEN
    RAISE EXCEPTION 'submission kind required' USING ERRCODE = '22023';
  END IF;
  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''), '[^0-9]', '', 'g'
  ), '');
  IF (
    NULLIF(btrim(coalesce(p_upc, '')), '') IS NOT NULL
    AND (
      normalized_upc_value IS NULL
      OR NOT public.is_valid_product_submission_gtin(normalized_upc_value)
    )
  ) OR (p_kind = 'missing_product' AND normalized_upc_value IS NULL) THEN
    RAISE EXCEPTION 'invalid UPC/EAN' USING ERRCODE = '22023';
  END IF;
  IF (p_kind = 'label_mismatch'
      AND (dsld_value IS NULL OR dsld_value !~ '^[0-9]{1,30}$'))
     OR (p_kind = 'missing_product' AND dsld_value IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid mismatch target' USING ERRCODE = '22023';
  END IF;

  SELECT submission.*
    INTO candidate
  FROM public.product_submissions AS submission
  WHERE submission.user_id = caller_id
    AND submission.kind = p_kind
    AND public.product_submission_canonical_gtin(submission.normalized_upc)
      IS NOT DISTINCT FROM
        public.product_submission_canonical_gtin(normalized_upc_value)
    AND (
      p_kind = 'missing_product'
      OR (
        -- The create guard blocks open corrections for the same barcode
        -- across catalog targets. Refer to that receipt; never reuse its
        -- evidence or suggest it as a different target's retry lineage.
        normalized_upc_value IS NOT NULL
        AND (submission.upload_state = 'ready' OR submission.evidence_revision > 1)
        AND submission.review_status IN ('submitted', 'under_review', 'approved')
      )
      OR EXISTS (
        SELECT 1
        FROM public.product_submission_mismatch_details AS detail
        WHERE detail.submission_id = submission.id
          AND detail.user_id = caller_id
          AND detail.dsld_id = dsld_value
      )
    )
  ORDER BY
    ((submission.upload_state = 'ready' OR submission.evidence_revision > 1)
      AND submission.review_status IN (
        'submitted', 'under_review', 'approved', 'duplicate'
      )) DESC,
    submission.created_at DESC,
    submission.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('action', 'start_new');
  END IF;
  IF candidate.upload_state = 'pending'
     AND candidate.evidence_revision > 1
     AND candidate.review_status IN ('submitted', 'under_review') THEN
    -- Batch 2 owns the resume UI. Existing clients can safely open this same
    -- receipt now, without throwing on an unsupported action or creating a twin.
    action_value := 'open_existing';
  ELSIF candidate.upload_state = 'ready'
     AND candidate.review_status IN (
       'submitted', 'under_review', 'approved', 'duplicate'
     ) THEN
    action_value := 'open_existing';
  ELSIF candidate.upload_state = 'pending'
        AND candidate.review_status = 'submitted' THEN
    action_value := 'incomplete_upload';
  ELSIF candidate.upload_state = 'ready'
        AND candidate.review_status = 'rejected'
        AND candidate.resolution_code IN (
          'photo_quality', 'missing_panel', 'label_unreadable', 'other'
        ) THEN
    action_value := 'retry_rejected';
  ELSE
    RETURN jsonb_build_object('action', 'start_new');
  END IF;

  -- Existing clients understand open_existing. A revision-resume UI is a
  -- later batch; do not emit an action they cannot parse.
  RETURN jsonb_build_object(
    'action', action_value,
    'submission_id', candidate.id,
    'normalized_upc', candidate.normalized_upc,
    'resolution_code', candidate.resolution_code,
    'resolution_detail', candidate.resolution_detail
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.hide_product_submission(p_submission_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  candidate public.product_submissions%ROWTYPE;
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT submission.*
  INTO candidate
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
  FOR UPDATE;

  IF NOT FOUND OR candidate.user_id <> caller_id THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = 'P0002';
  END IF;

  IF candidate.upload_state <> 'ready'
     OR candidate.review_status NOT IN ('rejected', 'duplicate') THEN
    RAISE EXCEPTION 'only failed terminal submissions can be hidden'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.product_submissions
  SET dismissed_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id;

  RETURN true;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.open_product_submission_evidence_revision(p_submission_id uuid, p_expected_revision integer, p_request_key uuid, p_keep_photo_ids uuid[] DEFAULT '{}'::uuid[], p_consent_version text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  replayed_revision integer;
  replay public.product_submission_evidence_revisions%ROWTYPE;
  next_revision integer;
  kept uuid[] := coalesce(p_keep_photo_ids, '{}'::uuid[]);
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_request_key IS NULL THEN
    RAISE EXCEPTION 'evidence revision request key required' USING ERRCODE = '22023';
  END IF;
  IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'expected evidence revision required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;

  SELECT revision.*
    INTO replay
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.request_key = p_request_key;
  IF FOUND THEN
    IF replay.replaces_revision IS DISTINCT FROM p_expected_revision
       OR replay.kept_photo_ids IS DISTINCT FROM kept
       OR replay.consent_version IS DISTINCT FROM p_consent_version THEN
      RAISE EXCEPTION 'evidence revision replay conflict' USING ERRCODE = '23505';
    END IF;
    RETURN replay.revision;
  END IF;

  IF submission.evidence_revision <> p_expected_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state <> 'ready'
     OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.promoted_at IS NOT NULL
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.product_submission_consent_versions consent
    WHERE consent.version = p_consent_version AND consent.kind = submission.kind
      AND consent.retired_at IS NULL AND consent.effective_from <= now()) THEN
    RAISE EXCEPTION 'consent version not recognized' USING ERRCODE = '22023';
  END IF;
  IF submission.review_status = 'under_review'
     AND (
       submission.evidence_requested_at IS NULL
       OR submission.evidence_requested_revision IS DISTINCT FROM submission.evidence_revision
     ) THEN
    RAISE EXCEPTION 'evidence revision requires a reviewer request'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.*
    INTO current_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = submission.evidence_revision;
  IF cardinality(kept) >= 8 THEN
    RAISE EXCEPTION 'retake must leave room for new evidence' USING ERRCODE='22023';
  END IF;
  IF cardinality(kept) <> (SELECT count(DISTINCT id) FROM unnest(kept) AS id)
     OR array_position(kept, NULL) IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM unnest(kept) AS kept_id
       WHERE NOT (kept_id = ANY(current_revision.photo_ids))
     ) THEN
    RAISE EXCEPTION 'kept photos must belong to the current revision'
      USING ERRCODE = '22023';
  END IF;

  SELECT max(revision.revision) + 1
    INTO next_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id;

  INSERT INTO public.product_submission_evidence_revisions (
    submission_id, revision, request_key, opened_by, photo_ids, kept_photo_ids,
    replaces_revision, consent_version, consented_at
  ) VALUES (
    p_submission_id, next_revision, p_request_key, caller_id, kept, kept,
    p_expected_revision, p_consent_version, now()
  );
  UPDATE public.product_submissions
  SET upload_state = 'pending',
      evidence_revision = next_revision,
      evidence_revision_opened_at = now()
  WHERE id = p_submission_id;
  DELETE FROM public.product_submission_push_deliveries
  WHERE submission_id = p_submission_id AND sent_at IS NULL;
  RETURN next_revision;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.set_product_submission_display_name(p_submission_id uuid, p_display_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_display_name IS NULL OR char_length(btrim(p_display_name)) NOT BETWEEN 1 AND 160
     OR p_display_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'display name must be 1 to 160 printable characters' USING ERRCODE = '22023';
  END IF;
  UPDATE public.product_submissions SET display_name = btrim(p_display_name)
    WHERE id = p_submission_id AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission unavailable' USING ERRCODE = '42501';
  END IF;
  RETURN true;
END;
$function$

;

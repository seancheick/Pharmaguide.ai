-- Repair correction workflows without rewriting deployed approval history.


CREATE OR REPLACE FUNCTION public.protect_product_submission_approval_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE current_revision integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Auth cascades remove the parent first. A separate parent guard denies
    -- ordinary parent deletion while the account still exists.
    IF pg_catalog.pg_trigger_depth() > 1 AND NOT EXISTS (
      SELECT 1 FROM public.product_submissions WHERE id=OLD.submission_id
    ) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'approval revisions are immutable' USING ERRCODE = '55000';
  END IF;

  SELECT approval_revision INTO current_revision
  FROM public.product_submissions
  WHERE id = OLD.submission_id;

  -- The existing approval transition writes the chosen image/evidence after
  -- inserting the row in the same transaction. Permit that single fill only.
  IF OLD.approval_revision = current_revision
     AND OLD.evidence_revision IS NULL
     AND NEW.evidence_revision IS NOT NULL
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id, NEW.promoted_catalog_version,
       NEW.promoted_dsld_id, NEW.promoted_at
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id, OLD.promoted_catalog_version,
       OLD.promoted_dsld_id, OLD.promoted_at
     ) THEN
    RETURN NEW;
  END IF;

  -- A promotion stamps an approval once; payload, evidence, identity and
  -- reviewer remain byte-for-byte immutable.
  IF OLD.promoted_at IS NULL
     AND NEW.promoted_at IS NOT NULL
     AND NEW.promoted_catalog_version IS NOT NULL
     AND NEW.promoted_dsld_id IS NOT NULL
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.approved_product_image_photo_id,
       NEW.approved_product_image_reviewer_object_id,
       NEW.evidence_revision, NEW.evidence_manifest_sha256,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.approved_product_image_photo_id,
       OLD.approved_product_image_reviewer_object_id,
       OLD.evidence_revision, OLD.evidence_manifest_sha256,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id
     ) THEN
    RETURN NEW;
  END IF;

  -- The legacy approval function addresses all rows for a submission when it
  -- fills evidence. Older revisions ignore that mechanical update.
  IF OLD.approval_revision < current_revision
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id, NEW.promoted_catalog_version,
       NEW.promoted_dsld_id, NEW.promoted_at
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id, OLD.promoted_catalog_version,
       OLD.promoted_dsld_id, OLD.promoted_at
     ) THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'approval revisions are immutable' USING ERRCODE = '55000';
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_product_submission_approved_parent()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.product_submission_approved_labels WHERE submission_id=OLD.id)
     AND EXISTS (SELECT 1 FROM auth.users WHERE id=OLD.user_id) THEN
    RAISE EXCEPTION 'approved submission requires account deletion' USING ERRCODE='55000';
  END IF;
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION public.protect_product_submission_approved_parent() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER product_submission_approved_parent_delete_guard
BEFORE DELETE ON public.product_submissions FOR EACH ROW
EXECUTE FUNCTION public.protect_product_submission_approved_parent();

CREATE OR REPLACE FUNCTION public.create_product_submission_reviewer_evidence_revision(
  p_submission_id uuid,
  p_expected_approval_revision integer,
  p_expected_payload_sha256 text,
  p_request_key uuid,
  p_photos jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  existing public.product_submission_evidence_revisions%ROWTYPE;
  next_revision integer;
  uploads jsonb;
  persisted_manifest jsonb;
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF p_request_key IS NULL THEN
    RAISE EXCEPTION 'request key required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.review_status <> 'under_review'
     OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.approval_revision <> p_expected_approval_revision
     OR NOT EXISTS (
       SELECT 1 FROM public.product_submission_approved_labels AS approved
       WHERE approved.submission_id = p_submission_id
         AND approved.approval_revision = p_expected_approval_revision
         AND approved.payload_sha256 = p_expected_payload_sha256
     ) THEN
    RAISE EXCEPTION 'approval changed since review' USING ERRCODE = '55000';
  END IF;

  SELECT revision.* INTO existing
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.request_key = p_request_key;
  IF FOUND THEN
    IF existing.abandoned_at IS NOT NULL
       OR existing.revision <> submission.evidence_revision
       OR submission.upload_state NOT IN ('pending','ready') THEN
      RAISE EXCEPTION 'reviewer evidence revision abandoned or superseded' USING ERRCODE='55000';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'photo_id', photo.photo_id,
      'seq', photo.seq,
      'categories', to_jsonb(photo.categories),
      'content_type', photo.content_type,
      'byte_size', photo.byte_size,
      'content_sha256', photo.content_sha256
    ) ORDER BY photo.seq), '[]'::jsonb) INTO persisted_manifest
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = existing.revision
      AND photo.uploader_id = v_reviewer_id
      AND photo.uploader_role = 'reviewer';
    IF persisted_manifest <> p_photos THEN
      RAISE EXCEPTION 'reviewer evidence replay conflict'
        USING ERRCODE = '23505';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'photo_id', photo.photo_id,
      'object_path', photo.object_path
    ) ORDER BY photo.seq), '[]'::jsonb) INTO uploads
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = existing.revision
      AND photo.uploader_id = v_reviewer_id
      AND photo.uploader_role = 'reviewer';
    RETURN jsonb_build_object(
      'evidence_revision', existing.revision,
      'uploads', uploads
    );
  END IF;

  IF submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'replacement evidence upload already pending'
      USING ERRCODE = '55000';
  END IF;

  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_photos) NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(max(revision),0)+1 INTO next_revision
  FROM public.product_submission_evidence_revisions WHERE submission_id=p_submission_id;
  INSERT INTO public.product_submission_evidence_revisions(
    submission_id, revision, request_key, opened_by, photo_ids,
    consent_version, consented_at
  ) VALUES (
    p_submission_id, next_revision, p_request_key, v_reviewer_id, '{}'::uuid[],
    submission.consent_version, submission.consented_at
  );
  UPDATE public.product_submissions
  SET evidence_revision = next_revision,
      evidence_revision_opened_at = now(),
      upload_state = 'pending',
      evidence_requested_at = NULL,
      evidence_requested_revision = NULL,
      evidence_requested_by = NULL,
      evidence_request_reason = NULL,
      evidence_request_panels = NULL,
      cleanup_claimed_at = NULL,
      cleanup_claim_token = NULL
  WHERE id = p_submission_id;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id, submission.user_id, p_photos, next_revision);
  UPDATE public.product_submission_photos
  SET uploader_id = v_reviewer_id,
      uploader_role = 'reviewer'
  WHERE submission_id = p_submission_id
    AND revision = next_revision;
  DELETE FROM public.product_submission_field_verifications
  WHERE submission_id = p_submission_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'photo_id', photo.photo_id,
    'object_path', photo.object_path
  ) ORDER BY photo.seq), '[]'::jsonb) INTO uploads
  FROM public.product_submission_photos AS photo
  WHERE photo.submission_id = p_submission_id
    AND photo.revision = next_revision;
  RETURN jsonb_build_object(
    'evidence_revision', next_revision,
    'uploads', uploads
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_product_submission_reviewer_evidence_revision(
  p_submission_id uuid,
  p_evidence_revision integer,
  p_manifest_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  v_revision public.product_submission_evidence_revisions%ROWTYPE;
  records jsonb;
  manifest_hash text;
BEGIN
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  SELECT candidate.* INTO v_revision
  FROM public.product_submission_evidence_revisions AS candidate
  WHERE candidate.submission_id = p_submission_id
    AND candidate.revision = p_evidence_revision
  FOR UPDATE;
  IF submission.id IS NULL OR v_revision.submission_id IS NULL
     OR submission.review_status <> 'under_review'
     OR submission.upload_state NOT IN ('pending','ready')
     OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.cleanup_claim_token IS NOT NULL
     OR submission.evidence_revision <> p_evidence_revision
     OR v_revision.abandoned_at IS NOT NULL THEN
    RAISE EXCEPTION 'current correction evidence required'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.ready_at IS NOT NULL THEN
    IF v_revision.manifest_sha256 = p_manifest_sha256 THEN RETURN true; END IF;
    RAISE EXCEPTION 'evidence revision already finalized'
      USING ERRCODE = '23505';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    LEFT JOIN storage.objects AS object
      ON object.bucket_id = 'product-submission-photos'
     AND object.name = photo.object_path
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = p_evidence_revision
      AND (
        object.name IS NULL
        OR coalesce((object.metadata->>'size')::bigint, -1) <> photo.byte_size
        OR coalesce(object.metadata->>'mimetype', '') <> photo.content_type
        OR coalesce(object.user_metadata->>'content_sha256', '')
             <> photo.content_sha256
      )
  ) THEN
    RAISE EXCEPTION 'reviewer evidence bytes are incomplete'
      USING ERRCODE = '55000';
  END IF;
  IF NOT public.product_submission_has_required_evidence(
    p_submission_id, submission.user_id) THEN
    RAISE EXCEPTION 'complete replacement evidence required'
      USING ERRCODE = '55000';
  END IF;
  records := public.product_submission_evidence_records(
    p_submission_id, p_evidence_revision);
  manifest_hash := public.product_submission_manifest_sha256(records);
  IF manifest_hash <> p_manifest_sha256 THEN
    RAISE EXCEPTION 'evidence manifest changed' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submission_evidence_revisions
  SET ready_at = now(), manifest = records, manifest_sha256 = manifest_hash
  WHERE submission_id = p_submission_id
    AND revision = p_evidence_revision;
  UPDATE public.product_submissions
  SET upload_state = 'ready',
      evidence_purged_at = NULL,
      evidence_revision_opened_at = NULL,
      evidence_requested_at = NULL,
      evidence_requested_revision = NULL,
      evidence_request_reason = NULL,
      evidence_request_panels = NULL
  WHERE id = p_submission_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_product_submission_evidence(
  p_submission_id uuid,
  p_reason text,
  p_panels text[],
  p_expected_revision integer,
  p_manifest_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  reason_value public.product_submission_resolution_code;
  panels_value public.product_submission_evidence_category[];
BEGIN
  PERFORM public.reject_oauth_client_request();
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_revision,p_manifest_sha256);
  BEGIN
    reason_value := btrim(coalesce(p_reason, ''))::public.product_submission_resolution_code;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'evidence request reason required' USING ERRCODE = '22023';
  END;
  IF reason_value NOT IN ('photo_quality', 'missing_panel', 'label_unreadable', 'other') THEN
    RAISE EXCEPTION 'evidence request reason required' USING ERRCODE = '22023';
  END IF;
  BEGIN
    panels_value := p_panels::public.product_submission_evidence_category[];
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'evidence request panels required' USING ERRCODE = '22023';
  END;
  IF coalesce(cardinality(panels_value), 0) = 0
     OR array_position(panels_value, NULL) IS NOT NULL
     OR cardinality(panels_value)
        <> (SELECT count(DISTINCT panel) FROM unnest(panels_value) AS panel) THEN
    RAISE EXCEPTION 'evidence request panels required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.upload_state <> 'ready'
     OR submission.cleanup_claimed_at IS NOT NULL
     OR (submission.promoted_at IS NOT NULL AND NOT (
       submission.review_status='under_review' AND submission.promoted_approval_revision>0
       AND EXISTS (SELECT 1 FROM public.product_submission_review_events event
         WHERE event.submission_id=submission.id AND event.from_status='approved' AND event.to_status='under_review')
     ))
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submissions
  SET evidence_requested_at = now(),
      evidence_requested_revision = submission.evidence_revision,
      evidence_requested_by = reviewer_id,
      evidence_request_reason = reason_value,
      evidence_request_panels = panels_value
  WHERE id = p_submission_id;
  IF submission.evidence_requested_revision IS DISTINCT FROM submission.evidence_revision THEN
    INSERT INTO public.product_submission_push_deliveries (
      submission_id, user_id, to_status
    ) VALUES (
      p_submission_id, submission.user_id, submission.review_status
    );
  END IF;
  RETURN true;
END;
$$;

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
     OR (submission.promoted_at IS NOT NULL AND NOT (
       submission.review_status='under_review' AND submission.promoted_approval_revision>0
       AND EXISTS (SELECT 1 FROM public.product_submission_review_events event
         WHERE event.submission_id=submission.id AND event.from_status='approved' AND event.to_status='under_review')
     ))
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

CREATE OR REPLACE FUNCTION "public"."review_product_submission_human_internal"("p_submission_id" "uuid", "p_reviewer_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  submission public.product_submissions%ROWTYPE;
  transition_allowed boolean;
  review_target_key text;
  resolution_code_value public.product_submission_resolution_code;
  resolution_detail_value text;
  resolved_dsld_value text;
BEGIN
  IF p_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'reviewer identity required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;

  transition_allowed := CASE submission.review_status
    WHEN 'submitted' THEN p_to_status IN (
      'under_review',
      'rejected',
      'duplicate'
    )
    WHEN 'under_review' THEN p_to_status IN (
      'approved',
      'rejected',
      'duplicate'
    )
    ELSE false
  END;
  IF NOT transition_allowed THEN
    RAISE EXCEPTION 'invalid review transition' USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(coalesce(p_resolution_code, '')), '') IS NOT NULL THEN
    BEGIN
      resolution_code_value := btrim(p_resolution_code)
        ::public.product_submission_resolution_code;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid resolution code' USING ERRCODE = '22023';
    END;
  END IF;
  resolution_detail_value := NULLIF(btrim(regexp_replace(
    coalesce(p_resolution_detail, ''),
    '[\x00-\x1F\x7F]',
    '',
    'g'
  )), '');
  IF resolution_detail_value IS NOT NULL
     AND char_length(resolution_detail_value) > 280 THEN
    RAISE EXCEPTION 'resolution detail too long' USING ERRCODE = '22023';
  END IF;
  resolved_dsld_value := NULLIF(btrim(coalesce(p_resolved_dsld_id, '')), '');
  IF resolved_dsld_value IS NOT NULL
     AND resolved_dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid resolved product id' USING ERRCODE = '22023';
  END IF;

  IF p_to_status IN ('under_review', 'approved') THEN
    IF resolution_code_value IS NOT NULL
       OR resolution_detail_value IS NOT NULL
       OR resolved_dsld_value IS NOT NULL THEN
      RAISE EXCEPTION 'resolution not allowed for this transition'
        USING ERRCODE = '22023';
    END IF;
    IF p_duplicate_of IS NOT NULL THEN
      RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
    END IF;
  ELSIF p_to_status = 'rejected' THEN
    IF resolution_code_value IS NULL
       OR resolution_code_value NOT IN (
         'photo_quality',
         'missing_panel',
         'label_unreadable',
         'product_identity_mismatch',
         'not_a_supplement',
         'other'
       ) THEN
      RAISE EXCEPTION 'rejection resolution code required'
        USING ERRCODE = '22023';
    END IF;
    IF resolution_code_value = 'other'
       AND resolution_detail_value IS NULL THEN
      RAISE EXCEPTION 'resolution detail required' USING ERRCODE = '22023';
    END IF;
    IF resolved_dsld_value IS NOT NULL OR p_duplicate_of IS NOT NULL THEN
      RAISE EXCEPTION 'resolution not allowed for this transition'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF resolution_code_value IS NULL
       OR resolution_code_value NOT IN (
         'already_in_catalog',
         'duplicate_submission'
       ) THEN
      RAISE EXCEPTION 'duplicate resolution code required'
        USING ERRCODE = '22023';
    END IF;
    IF resolution_code_value = 'already_in_catalog' THEN
      IF resolved_dsld_value IS NULL OR p_duplicate_of IS NOT NULL THEN
        RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF p_duplicate_of IS NULL OR resolved_dsld_value IS NOT NULL THEN
        RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  IF p_to_status = 'approved' AND (
    p_approved_schema_version IS DISTINCT FROM 'manual_label_v1'
    OR p_approved_payload IS NULL
    OR jsonb_typeof(p_approved_payload) <> 'object'
    OR p_approved_payload_canonical IS NULL
    OR octet_length(p_approved_payload_canonical) NOT BETWEEN 2 AND 524288
    OR p_approved_payload_canonical::jsonb <> p_approved_payload
    OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
    OR encode(
      extensions.digest(p_approved_payload_canonical, 'sha256'),
      'hex'
    ) <> p_payload_sha256
  ) THEN
    RAISE EXCEPTION 'approved canonical payload required'
      USING ERRCODE = '22023';
  END IF;
  IF p_to_status <> 'approved' AND (
    p_approved_schema_version IS NOT NULL
    OR p_approved_payload IS NOT NULL
    OR p_approved_payload_canonical IS NOT NULL
    OR p_payload_sha256 IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'approved payload not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;
  IF p_duplicate_of = p_submission_id THEN
    RAISE EXCEPTION 'submission cannot duplicate itself'
      USING ERRCODE = '22023';
  END IF;
  IF p_to_status = 'duplicate'
     AND resolution_code_value = 'duplicate_submission'
     AND NOT EXISTS (
    SELECT 1
    FROM public.product_submissions AS target
    LEFT JOIN public.product_submission_mismatch_details AS current_mismatch
      ON current_mismatch.submission_id = submission.id
    LEFT JOIN public.product_submission_mismatch_details AS target_mismatch
      ON target_mismatch.submission_id = target.id
    WHERE target.id = p_duplicate_of
      AND target.upload_state = 'ready'
      AND target.review_status = 'approved'
      AND target.kind = submission.kind
      AND (
        (
          submission.kind = 'missing_product'
          AND public.product_submission_canonical_gtin(target.normalized_upc)
            = public.product_submission_canonical_gtin(submission.normalized_upc)
        )
        OR (
          submission.kind = 'label_mismatch'
          AND target_mismatch.dsld_id = current_mismatch.dsld_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'duplicate target must be an approved matching submission'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' THEN
    review_target_key :=
      public.product_submission_review_target_key(p_submission_id);
    IF NULLIF(review_target_key, '') IS NULL THEN
      RAISE EXCEPTION 'review target identity is unavailable'
        USING ERRCODE = '55000';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(review_target_key, 0)
    );
    IF EXISTS (
      SELECT 1
      FROM public.product_submissions AS other
      WHERE other.id <> p_submission_id
        AND other.review_status = 'approved'
        AND other.approval_revision > other.promoted_approval_revision
        AND public.product_submission_review_target_key(other.id)
          = review_target_key
    ) THEN
      RAISE EXCEPTION 'another approved submission awaits promotion'
        USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.product_submission_approved_labels (
      submission_id,
      schema_version,
      approved_payload,
      approved_payload_canonical,
      payload_sha256,
      reviewer_id
    ) VALUES (
      p_submission_id,
      p_approved_schema_version,
      p_approved_payload,
      p_approved_payload_canonical,
      p_payload_sha256,
      p_reviewer_id
    );
  END IF;

  INSERT INTO public.product_submission_review_events (
    submission_id,
    from_status,
    to_status,
    reviewer_id,
    review_notes,
    resolution_code,
    resolved_dsld_id
  ) VALUES (
    p_submission_id,
    submission.review_status,
    p_to_status,
    p_reviewer_id,
    NULLIF(btrim(p_review_notes), ''),
    resolution_code_value,
    resolved_dsld_value
  );

  UPDATE public.product_submissions
  SET review_status = p_to_status,
      reviewed_at = now(),
      reviewed_by = p_reviewer_id,
      duplicate_of = p_duplicate_of,
      resolution_code = resolution_code_value,
      resolution_detail = resolution_detail_value,
      resolved_dsld_id = resolved_dsld_value
  WHERE id = p_submission_id;

  INSERT INTO public.product_submission_push_deliveries (
    submission_id,
    user_id,
    to_status
  ) VALUES (
    p_submission_id,
    submission.user_id,
    p_to_status
  );

  RETURN true;
END;
$_$;

-- CREATE OR REPLACE retains existing ACLs; restate the intended RPC boundary.
REVOKE ALL ON FUNCTION public.protect_product_submission_approval_revision() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_product_submission_reviewer_evidence_revision(uuid,integer,text,uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission_reviewer_evidence_revision(uuid,integer,text,uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.finalize_product_submission_reviewer_evidence_revision(uuid,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission_reviewer_evidence_revision(uuid,integer,text) TO service_role;
REVOKE ALL ON FUNCTION public.request_product_submission_evidence(uuid,text,text[],integer,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.request_product_submission_evidence(uuid,text,text[],integer,text) TO authenticated;
REVOKE ALL ON FUNCTION public.open_product_submission_evidence_revision(uuid,integer,uuid,uuid[],text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.open_product_submission_evidence_revision(uuid,integer,uuid,uuid[],text) TO authenticated;
REVOKE ALL ON FUNCTION public.review_product_submission_human_internal(uuid,uuid,public.product_submission_review_status,text,text,jsonb,text,text,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;

-- Restore the existing active-stack index omitted from the historical live schema.
CREATE INDEX IF NOT EXISTS idx_user_stacks_user_active
  ON public.user_stacks(user_id) WHERE deleted_at IS NULL;

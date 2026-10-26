-- Alternate contributor identity stays private and revision-bound. Existing
-- numbered approvals and legacy evidence hashes are never rewritten.
ALTER TYPE public.product_submission_match_outcome ADD VALUE IF NOT EXISTS 'new_product_verified';
ALTER TABLE public.product_submissions ADD COLUMN identifier jsonb;
ALTER TABLE public.product_submission_evidence_revisions ADD COLUMN identifier jsonb;

CREATE FUNCTION public.validate_product_submission_identifier(p_identifier jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE k text; v text; result jsonb := p_identifier;
BEGIN
 IF p_identifier IS NULL THEN RETURN NULL; END IF;
 IF jsonb_typeof(p_identifier) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_identifier) key)
 IS DISTINCT FROM ARRAY['brandName','code_type','fullName','issuer','listing_url','no_code','observed_code']::text[] THEN
  RAISE EXCEPTION 'invalid identifier fields' USING ERRCODE='22023'; END IF;
 FOREACH k IN ARRAY ARRAY['observed_code','issuer','brandName','fullName','listing_url'] LOOP
  IF jsonb_typeof(p_identifier->k) NOT IN ('string','null') THEN
   RAISE EXCEPTION 'invalid identifier text' USING ERRCODE='22023'; END IF;
  v:=p_identifier->>k;
  IF v ~ U&'[\0001-\001F\007F-\009F]' OR char_length(v)>(CASE k WHEN 'observed_code' THEN 128 WHEN 'issuer' THEN 200 WHEN 'listing_url' THEN 2048 ELSE 300 END)
  OR (k IN ('brandName','fullName','observed_code') AND v IS NOT NULL AND btrim(v)='')
  OR (k IN ('brandName','fullName') AND v IS NULL) THEN
   RAISE EXCEPTION 'invalid identifier text' USING ERRCODE='22023'; END IF;
  IF k IN ('issuer','listing_url') AND v ~ U&'^[\0020\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]*$' THEN result:=jsonb_set(result,ARRAY[k],'null'); END IF;
 END LOOP;
 IF jsonb_typeof(p_identifier->'no_code') IS DISTINCT FROM 'boolean'
 OR p_identifier->>'code_type' NOT IN ('other','amazon_fnsku','amazon_asin','manufacturer_sku','retailer_sku','lot','none')
 OR jsonb_typeof(p_identifier->'code_type') IS DISTINCT FROM 'string'
 OR ((p_identifier->>'no_code')::boolean IS DISTINCT FROM (p_identifier->>'observed_code' IS NULL))
 OR ((p_identifier->>'code_type'='none') IS DISTINCT FROM (p_identifier->>'observed_code' IS NULL))
 OR (result->>'listing_url' IS NOT NULL AND result->>'listing_url' !~* '^https?://[^[:space:]/?#]+[^[:space:]]*$') THEN
  RAISE EXCEPTION 'invalid identifier declaration' USING ERRCODE='22023'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.validate_product_submission_identifier(jsonb) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.product_submissions DROP CONSTRAINT product_submissions_missing_upc_required;
ALTER TABLE public.product_submissions ADD CONSTRAINT product_submissions_missing_upc_required CHECK (
 kind<>'missing_product' OR normalized_upc IS NOT NULL OR identifier IS NOT NULL);
ALTER TABLE public.product_submissions ADD CONSTRAINT product_submissions_identifier_valid CHECK (
 identifier IS NOT DISTINCT FROM public.validate_product_submission_identifier(identifier));
ALTER TABLE public.product_submission_evidence_revisions ADD CONSTRAINT product_submission_revision_identifier_valid CHECK (
 identifier IS NOT DISTINCT FROM public.validate_product_submission_identifier(identifier));
ALTER TABLE public.product_submissions DROP CONSTRAINT product_submissions_catalog_relation_valid;
ALTER TABLE public.product_submissions ADD CONSTRAINT product_submissions_catalog_relation_valid CHECK (
 num_nonnulls(correction_target_dsld_id,edition_of_dsld_id)<=1
 AND (correction_target_dsld_id IS NULL OR kind='missing_product' AND correction_target_dsld_id ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$')
 AND (edition_of_dsld_id IS NULL OR kind='missing_product' AND edition_of_dsld_id ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'));

-- One short transaction fence, always before row/target/manifest locks.
CREATE FUNCTION public.lock_product_submission_identity() RETURNS void
LANGUAGE sql VOLATILE SET search_path='' AS $$
 SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('product_submission_identity',0));
$$;
REVOKE ALL ON FUNCTION public.lock_product_submission_identity() FROM PUBLIC,anon,authenticated,service_role;


DROP FUNCTION public.create_product_submission_v2_internal(uuid,public.product_submission_kind,text,jsonb,boolean,jsonb);

CREATE OR REPLACE FUNCTION public.create_product_submission_v2_internal(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_identifier jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  persisted public.product_submissions%ROWTYPE;
  detail_keys text[];
  category_values public.label_mismatch_category[];
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission id required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_photos) > 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[[:space:]-]',
    '',
    'g'
  ), '');
  IF NULLIF(btrim(coalesce(p_upc, '')), '') IS NOT NULL
     AND (
       normalized_upc_value IS NULL
       OR NOT public.is_valid_product_submission_gtin(normalized_upc_value)
     ) THEN
    RAISE EXCEPTION 'invalid UPC/EAN' USING ERRCODE = '22023';
  END IF;

  IF p_kind = 'missing_product' THEN
    IF (normalized_upc_value IS NULL AND p_identifier IS NULL) OR p_mismatch_detail IS NOT NULL THEN
      RAISE EXCEPTION 'invalid missing-product payload'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF p_mismatch_detail IS NULL
       OR jsonb_typeof(p_mismatch_detail) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'mismatch detail required' USING ERRCODE = '22023';
    END IF;
    SELECT array_agg(key ORDER BY key)
      INTO detail_keys
    FROM jsonb_object_keys(p_mismatch_detail) AS key;
    IF detail_keys IS DISTINCT FROM ARRAY[
      'catalog_source_version',
      'dsld_id',
      'formula_fingerprint',
      'mismatch_categories',
      'source_record_id'
    ]::text[] THEN
      RAISE EXCEPTION 'unexpected mismatch detail field'
        USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_mismatch_detail->'mismatch_categories') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'mismatch categories required'
        USING ERRCODE = '22023';
    END IF;
    SELECT array_agg(
      DISTINCT item.value::public.label_mismatch_category
      ORDER BY item.value::public.label_mismatch_category
    )
      INTO category_values
    FROM jsonb_array_elements_text(
      p_mismatch_detail->'mismatch_categories'
    ) AS item(value);
    IF coalesce(cardinality(category_values), 0) NOT BETWEEN 1 AND 8 THEN
      RAISE EXCEPTION 'invalid mismatch categories'
        USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_mismatch_detail->'mismatch_categories')
       <> cardinality(category_values) THEN
      RAISE EXCEPTION 'duplicate mismatch category'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.product_submissions (
    id,
    user_id,
    kind,
    normalized_upc,
    identifier,
    declared_no_separate_ingredient_panel
  ) VALUES (
    p_submission_id,
    caller_id,
    p_kind,
    normalized_upc_value,
    public.validate_product_submission_identifier(p_identifier),
    coalesce(p_no_separate_ingredient_panel, false)
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT submission.*
    INTO persisted
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR persisted.user_id <> caller_id
     OR persisted.kind <> p_kind
     OR persisted.normalized_upc IS DISTINCT FROM normalized_upc_value
     OR persisted.identifier IS DISTINCT FROM public.validate_product_submission_identifier(p_identifier)
     OR persisted.declared_no_separate_ingredient_panel
       IS DISTINCT FROM coalesce(p_no_separate_ingredient_panel, false)
     OR persisted.upload_state NOT IN ('pending', 'ready')
     OR persisted.review_status <> 'submitted'
     OR persisted.evidence_revision <> 1 THEN
    RAISE EXCEPTION 'submission replay conflict' USING ERRCODE = '23505';
  END IF;

  IF p_kind = 'label_mismatch' THEN
    INSERT INTO public.product_submission_mismatch_details (
      submission_id,
      user_id,
      dsld_id,
      source_record_id,
      catalog_source_version,
      formula_fingerprint,
      mismatch_categories
    ) VALUES (
      p_submission_id,
      caller_id,
      btrim(p_mismatch_detail->>'dsld_id'),
      NULLIF(btrim(p_mismatch_detail->>'source_record_id'), ''),
      NULLIF(btrim(p_mismatch_detail->>'catalog_source_version'), ''),
      NULLIF(btrim(p_mismatch_detail->>'formula_fingerprint'), ''),
      category_values
    )
    ON CONFLICT (submission_id) DO NOTHING;
    IF NOT EXISTS (
      SELECT 1
      FROM public.product_submission_mismatch_details AS detail
      WHERE detail.submission_id = p_submission_id
        AND detail.user_id = caller_id
        AND detail.dsld_id = btrim(p_mismatch_detail->>'dsld_id')
        AND detail.source_record_id IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'source_record_id'), '')
        AND detail.catalog_source_version IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'catalog_source_version'), '')
        AND detail.formula_fingerprint IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'formula_fingerprint'), '')
        AND detail.mismatch_categories = category_values
    ) THEN
      RAISE EXCEPTION 'submission detail replay conflict'
        USING ERRCODE = '23505';
    END IF;
  ELSE
    INSERT INTO public.product_submission_missing_details (
      submission_id,
      user_id
    ) VALUES (
      p_submission_id,
      caller_id
    )
    ON CONFLICT (submission_id) DO NOTHING;
    IF NOT EXISTS (
      SELECT 1
      FROM public.product_submission_missing_details AS detail
      WHERE detail.submission_id = p_submission_id
        AND detail.user_id = caller_id
    ) THEN
      RAISE EXCEPTION 'submission detail replay conflict'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Revision 1 is opened with the submission; its membership is the first
  -- manifest. The request key is the submission id (one first upload).
  INSERT INTO public.product_submission_evidence_revisions (
    submission_id, revision, request_key, opened_by, identifier
  ) VALUES (p_submission_id, 1, p_submission_id, caller_id, public.validate_product_submission_identifier(p_identifier))
  ON CONFLICT (submission_id, revision) DO NOTHING;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    1
  );

  -- Fail fast on evidence coverage so the user learns before uploading bytes.
  IF p_kind = 'missing_product'
     AND NOT public.product_submission_has_required_evidence(
       p_submission_id,
       caller_id
     ) THEN
    RAISE EXCEPTION 'missing required evidence categories'
      USING ERRCODE = '22023';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.create_product_submission_v2_internal(uuid,public.product_submission_kind,text,jsonb,boolean,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION public.create_product_submission(uuid,public.product_submission_kind,text,jsonb,boolean,jsonb,uuid,text);

CREATE OR REPLACE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_resubmission_of uuid DEFAULT NULL,
  p_consent_version text DEFAULT NULL,
  p_identifier jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
  PERFORM public.lock_product_submission_identity();
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
  IF p_identifier IS NOT NULL AND consent_version_value<>'pharmaguide.submission_consent.2026-10-26.v2' THEN
    RAISE EXCEPTION 'identifier consent version required' USING ERRCODE='22023';
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
    '[[:space:]-]',
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
      AND target.identifier IS NOT DISTINCT FROM public.validate_product_submission_identifier(p_identifier)
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
    p_photos,
    p_identifier
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
$$;

REVOKE ALL ON FUNCTION public.create_product_submission(uuid,public.product_submission_kind,text,jsonb,boolean,jsonb,uuid,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission(uuid,public.product_submission_kind,text,jsonb,boolean,jsonb,uuid,text,jsonb) TO authenticated;

ALTER FUNCTION public.product_submission_evidence_records(uuid,integer) RENAME TO product_submission_evidence_records_without_identifier;

CREATE FUNCTION public.product_submission_evidence_records(p_submission_id uuid,p_revision integer)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN r.identifier IS NULL THEN public.product_submission_evidence_records_without_identifier(p_submission_id,p_revision)
 ELSE (SELECT coalesce(jsonb_agg(photo || jsonb_build_object('identifier',r.identifier)),'[]'::jsonb) FROM jsonb_array_elements(public.product_submission_evidence_records_without_identifier(p_submission_id,p_revision)) photo) END
 FROM public.product_submission_evidence_revisions r WHERE r.submission_id=p_submission_id AND r.revision=p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_evidence_records(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.product_submission_has_required_evidence(
  p_submission_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (
    SELECT count(DISTINCT category) = CASE WHEN EXISTS (SELECT 1 FROM public.product_submission_evidence_revisions r JOIN public.product_submissions s ON s.id=r.submission_id AND s.evidence_revision=r.revision WHERE s.id=p_submission_id AND r.identifier->>'no_code'='true') THEN 3 ELSE 4 END
    FROM public.product_submissions AS submission
    JOIN public.product_submission_evidence_revisions AS revision
      ON revision.submission_id = submission.id
     AND revision.revision = submission.evidence_revision
    JOIN public.product_submission_photos AS photo
      ON photo.submission_id = submission.id
     AND photo.photo_id = ANY(revision.photo_ids),
    unnest(photo.categories) AS category
    WHERE submission.id = p_submission_id
      AND photo.user_id = p_user_id
      AND (category<>'barcode' OR revision.identifier->>'no_code' IS DISTINCT FROM 'true')
      AND category IN (
        'front_identity',
        'supplement_facts',
        'ingredient_disclosure',
        'barcode'
      )
  );
$$;

CREATE FUNCTION public.inherit_product_submission_revision_identifier() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 SELECT identifier INTO NEW.identifier FROM public.product_submissions WHERE id=NEW.submission_id;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.inherit_product_submission_revision_identifier() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER product_submission_revision_identifier BEFORE INSERT ON public.product_submission_evidence_revisions FOR EACH ROW EXECUTE FUNCTION public.inherit_product_submission_revision_identifier();

DROP FUNCTION public.open_product_submission_evidence_revision(uuid,integer,uuid,uuid[],text);

CREATE OR REPLACE FUNCTION public.open_product_submission_evidence_revision(p_submission_id uuid, p_expected_revision integer, p_request_key uuid, p_keep_photo_ids uuid[] DEFAULT '{}'::uuid[], p_consent_version text DEFAULT NULL::text, p_identifier jsonb DEFAULT NULL)
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
  PERFORM public.lock_product_submission_identity();
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

  IF p_identifier IS NOT NULL AND public.validate_product_submission_identifier(p_identifier) IS DISTINCT FROM submission.identifier THEN
    UPDATE public.product_submissions SET identifier=public.validate_product_submission_identifier(p_identifier) WHERE id=p_submission_id;
    submission.identifier:=public.validate_product_submission_identifier(p_identifier);
  END IF;
  SELECT revision.*
    INTO replay
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.request_key = p_request_key;
  IF FOUND THEN
    IF replay.replaces_revision IS DISTINCT FROM p_expected_revision
       OR replay.kept_photo_ids IS DISTINCT FROM kept
       OR replay.consent_version IS DISTINCT FROM p_consent_version
       OR replay.identifier IS DISTINCT FROM coalesce(public.validate_product_submission_identifier(p_identifier),submission.identifier) THEN
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
  IF submission.identifier IS NOT NULL AND p_consent_version IS DISTINCT FROM 'pharmaguide.submission_consent.2026-10-26.v2' THEN
    RAISE EXCEPTION 'identifier consent version required' USING ERRCODE='22023'; END IF;
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
$function$;

REVOKE ALL ON FUNCTION public.open_product_submission_evidence_revision(uuid,integer,uuid,uuid[],text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.open_product_submission_evidence_revision(uuid,integer,uuid,uuid[],text,jsonb) TO authenticated;

ALTER TABLE public.product_submission_match_checks ALTER COLUMN canonical_gtin14 DROP NOT NULL;
ALTER TABLE public.product_submission_match_checks ADD COLUMN identity_method text NOT NULL DEFAULT 'gtin' CHECK(identity_method IN ('gtin','label_review')),
 ADD COLUMN identifier_decision jsonb;
ALTER TABLE public.product_submission_match_checks DROP CONSTRAINT product_submission_match_check_shape;
ALTER TABLE public.product_submission_match_checks ADD CONSTRAINT product_submission_match_check_shape CHECK (
 CASE outcome::text WHEN 'catalog_match' THEN matched_dsld_id IS NOT NULL AND (identity_method='label_review' OR cardinality(candidate_dsld_ids)=0) AND reason IS NULL
 WHEN 'dsld_match' THEN matched_dsld_id IS NOT NULL AND (identity_method='label_review' OR cardinality(candidate_dsld_ids)=0) AND reason IS NULL
 WHEN 'identity_ambiguous' THEN matched_dsld_id IS NULL AND cardinality(candidate_dsld_ids)>=CASE WHEN identity_method='label_review' THEN 1 ELSE 2 END AND reason IS NULL
 WHEN 'no_match_verified' THEN matched_dsld_id IS NULL AND cardinality(candidate_dsld_ids)=0 AND reason IS NULL AND identity_method='gtin'
 WHEN 'new_product_verified' THEN matched_dsld_id IS NULL AND identity_method='label_review' AND identifier_decision IS NOT NULL
 WHEN 'not_this_product' THEN matched_dsld_id IS NOT NULL AND cardinality(candidate_dsld_ids)=0 AND reason IS NOT NULL ELSE false END);
ALTER TABLE public.product_submission_match_checks ADD CONSTRAINT product_submission_match_identity CHECK (
 (identity_method='gtin' AND canonical_gtin14 IS NOT NULL) OR (identity_method='label_review' AND identifier_decision IS NOT NULL));


-- Canonical JSON array avoids delimiter collisions in brand/name buckets.
CREATE FUNCTION public.product_submission_label_bucket(p_brand text,p_name text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT 'label:' || jsonb_build_array(lower(regexp_replace(btrim(normalize(coalesce(p_brand,''),NFC)),'[[:space:]]+',' ','g')),lower(regexp_replace(btrim(normalize(coalesce(p_name,''),NFC)),'[[:space:]]+',' ','g')))::text;
$$;
REVOKE ALL ON FUNCTION public.product_submission_label_bucket(text,text) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.product_submission_match_checks ADD COLUMN candidate_review_complete boolean NOT NULL DEFAULT false,
 ADD COLUMN index_revision text, ADD COLUMN conflict_snapshot jsonb,
 ADD COLUMN label_payload_sha256 text CHECK(label_payload_sha256 IS NULL OR label_payload_sha256 ~ '^[0-9a-f]{64}$');

-- All active catalog and pending-approved conflicts are enumerated here;
-- a bounded suggestion page is never substituted for this set.
CREATE FUNCTION public.product_submission_identity_conflicts(p_submission_id uuid,p_catalog_version text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH subject AS (
 SELECT s.*,coalesce(d.payload,CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload->'label' ELSE a.approved_payload END) AS label FROM public.product_submissions s
 LEFT JOIN public.product_submission_approved_labels a ON a.submission_id=s.id AND a.approval_revision=s.approval_revision
 LEFT JOIN public.product_submission_reviewer_drafts d ON d.submission_id=s.id AND d.reviewer_id=auth.uid()
 WHERE s.id=p_submission_id), conflicts AS (
 SELECT 'catalog' AS source,c.dsld_id AS id,c.catalog_version AS revision
 FROM public.catalog_search c CROSS JOIN subject s
 WHERE (c.catalog_version=p_catalog_version OR p_catalog_version IS NULL AND EXISTS(SELECT 1 FROM public.export_manifest m WHERE m.db_version=c.catalog_version AND m.is_current))
 AND (c.dsld_id IN (s.correction_target_dsld_id,s.edition_of_dsld_id,s.resolved_dsld_id)
 OR public.product_submission_canonical_gtin(c.upc_sku)=public.product_submission_canonical_gtin(s.normalized_upc)
 OR public.product_submission_label_bucket(c.brand_name,c.product_name)=public.product_submission_label_bucket(coalesce(s.label->>'brandName',s.identifier->>'brandName'),coalesce(s.label->>'fullName',s.identifier->>'fullName')))
 UNION ALL
 SELECT 'pending',coalesce(a.correction_target_dsld_id,a.target_dsld_id,'PG_SUB_'||upper(replace(o.id::text,'-',''))),a.approval_revision::text
 FROM public.product_submissions o JOIN public.product_submission_approved_labels a ON a.submission_id=o.id AND a.approval_revision=o.approval_revision CROSS JOIN subject s
 WHERE o.id<>s.id AND o.review_status='approved' AND o.approval_revision>o.promoted_approval_revision
 AND (coalesce(a.correction_target_dsld_id,a.target_dsld_id)=coalesce(s.correction_target_dsld_id,s.resolved_dsld_id)
 OR public.product_submission_canonical_gtin(CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload#>>'{identity,decision,verified_gtin}' ELSE o.normalized_upc END)=public.product_submission_canonical_gtin(s.normalized_upc)
 OR public.product_submission_label_bucket(CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload#>>'{label,brandName}' ELSE a.approved_payload->>'brandName' END,CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload#>>'{label,fullName}' ELSE a.approved_payload->>'fullName' END)=public.product_submission_label_bucket(coalesce(s.label->>'brandName',s.identifier->>'brandName'),coalesce(s.label->>'fullName',s.identifier->>'fullName')))
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('source',source,'id',id,'revision',revision) ORDER BY source,id,revision),'[]') FROM conflicts;
$$;
REVOKE ALL ON FUNCTION public.product_submission_identity_conflicts(uuid,text) FROM PUBLIC,anon,authenticated,service_role;


-- The active catalog, not a reviewer flag or private account row, owns
-- whether an existing target is released. PG_SUB's UUID survives deletion of
-- the original contributor account; importer derives its public lineage.
CREATE FUNCTION public.product_submission_catalog_target_is_live(p_target text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p_target IS NOT NULL AND p_target ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' AND EXISTS(
 SELECT 1 FROM public.catalog_search c JOIN public.export_manifest m ON m.db_version=c.catalog_version AND m.is_current
 WHERE c.dsld_id=p_target);
$$;
REVOKE ALL ON FUNCTION public.product_submission_catalog_target_is_live(text) FROM PUBLIC,anon,authenticated,service_role;
DROP FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text,integer,text);
CREATE FUNCTION public.record_product_submission_match_check(
 p_submission_id uuid,p_outcome public.product_submission_match_outcome,p_canonical_gtin14 text,p_index_built_at timestamptz,
 p_matched_dsld_id text DEFAULT NULL,p_candidate_dsld_ids text[] DEFAULT '{}',p_reason text DEFAULT NULL,
 p_expected_evidence_revision integer DEFAULT NULL,p_evidence_manifest_sha256 text DEFAULT NULL,
 p_identity_method text DEFAULT 'gtin',p_identifier_decision jsonb DEFAULT NULL,
 p_candidate_review_complete boolean DEFAULT false,p_index_revision text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.product_submissions%ROWTYPE; mid bigint; conflicts jsonb; k text; v text; label_digest text;
BEGIN
 PERFORM public.reject_oauth_client_request();
 PERFORM public.assert_product_submission_reviewer();
 PERFORM public.lock_product_submission_identity();
 PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_evidence_revision,p_evidence_manifest_sha256);
 SELECT * INTO s FROM public.product_submissions WHERE id=p_submission_id FOR UPDATE;
 IF p_identity_method='gtin' AND p_identifier_decision IS NULL AND s.identifier IS NULL THEN
  RETURN public.record_product_submission_match_check_internal(p_submission_id,p_outcome,p_canonical_gtin14,p_index_built_at,p_matched_dsld_id,p_candidate_dsld_ids,p_reason);
 END IF;
 IF s.kind<>'missing_product' OR s.upload_state<>'ready' OR s.review_status NOT IN ('submitted','under_review') THEN
  RAISE EXCEPTION 'open missing-product submission required' USING ERRCODE='55000'; END IF;
 IF p_outcome::text='catalog_match' AND NOT public.product_submission_catalog_target_is_live(p_matched_dsld_id) THEN
  RAISE EXCEPTION 'matched catalog target is not active' USING ERRCODE='55000'; END IF;
 IF p_identity_method NOT IN ('gtin','label_review') OR p_identity_method IS NULL
 OR NOT coalesce(p_candidate_review_complete,false) OR nullif(btrim(p_index_revision),'') IS NULL OR char_length(p_index_revision)>200
 OR p_index_built_at IS NULL OR p_index_built_at<now()-interval '60 days' OR p_index_built_at>now()+interval '5 minutes'
 OR jsonb_typeof(p_identifier_decision) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_identifier_decision) key) IS DISTINCT FROM ARRAY['code_type','issuer','package','reason','verified_gtin']::text[]
 OR p_identifier_decision->>'code_type' NOT IN ('other','amazon_fnsku','amazon_asin','manufacturer_sku','retailer_sku','lot','none')
 OR char_length(btrim(coalesce(p_identifier_decision->>'reason',''))) NOT BETWEEN 5 AND 2000
 OR (p_identity_method='label_review' AND char_length(btrim(coalesce(p_identifier_decision->>'package',''))) NOT BETWEEN 1 AND 300) THEN
  RAISE EXCEPTION 'complete reviewed identifier decision required' USING ERRCODE='22023'; END IF;
 FOREACH k IN ARRAY ARRAY['code_type','issuer','package','reason','verified_gtin'] LOOP
  IF jsonb_typeof(p_identifier_decision->k) NOT IN ('string','null') OR (p_identifier_decision->>k) ~ U&'[\0001-\001F\007F-\009F]' THEN RAISE EXCEPTION 'invalid identifier decision' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF char_length(p_identifier_decision->>'issuer')>200 OR char_length(p_identifier_decision->>'package')>300
 OR (p_identifier_decision->>'verified_gtin' IS NOT NULL AND NOT public.is_valid_product_submission_gtin(p_identifier_decision->>'verified_gtin'))
 OR public.product_submission_canonical_gtin(p_identifier_decision->>'verified_gtin') IS DISTINCT FROM public.product_submission_canonical_gtin(s.normalized_upc)
 OR (p_outcome::text='new_product_verified' AND p_identifier_decision->>'verified_gtin' IS NOT NULL)
 OR (p_identity_method='gtin' AND (p_canonical_gtin14 IS NULL OR p_canonical_gtin14 IS DISTINCT FROM public.product_submission_canonical_gtin(s.normalized_upc)))
 OR (p_canonical_gtin14 IS NOT NULL AND p_canonical_gtin14 IS DISTINCT FROM public.product_submission_canonical_gtin(s.normalized_upc))
 OR p_candidate_dsld_ids IS NULL OR cardinality(p_candidate_dsld_ids)>100 OR cardinality(p_candidate_dsld_ids)<>(SELECT count(DISTINCT x) FROM unnest(p_candidate_dsld_ids) x)
 OR EXISTS(SELECT 1 FROM unnest(p_candidate_dsld_ids) x WHERE x !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$')
 OR (p_matched_dsld_id IS NOT NULL AND p_matched_dsld_id !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$') THEN
  RAISE EXCEPTION 'invalid reviewed identifier or candidates' USING ERRCODE='22023'; END IF;
 IF p_identifier_decision->>'issuer' ~ U&'^[\0020\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]*$' THEN p_identifier_decision:=jsonb_set(p_identifier_decision,'{issuer}','null'::jsonb); END IF;
 SELECT d.payload_sha256 INTO label_digest FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid();
 IF label_digest IS NULL THEN RAISE EXCEPTION 'reviewed label draft required for identity decision' USING ERRCODE='55000'; END IF;
 conflicts:=public.product_submission_identity_conflicts(p_submission_id);
 IF p_identity_method='label_review' AND p_outcome::text='identity_ambiguous' AND cardinality(p_candidate_dsld_ids)=1
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(conflicts) c WHERE c->>'source'='pending' AND c->>'id'=p_candidate_dsld_ids[1]) THEN
  RAISE EXCEPTION 'single-candidate ambiguity requires an actual pending intake' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(conflicts) c WHERE c->>'id' IS DISTINCT FROM p_matched_dsld_id AND NOT (c->>'id'=ANY(p_candidate_dsld_ids))) THEN
  RAISE EXCEPTION 'complete current conflict candidates required' USING ERRCODE='55000'; END IF;
 INSERT INTO public.product_submission_match_checks(submission_id,reviewer_id,outcome,canonical_gtin14,index_built_at,matched_dsld_id,candidate_dsld_ids,reason,identity_method,identifier_decision,candidate_review_complete,index_revision,conflict_snapshot,label_payload_sha256)
 VALUES(p_submission_id,auth.uid(),p_outcome,p_canonical_gtin14,p_index_built_at,p_matched_dsld_id,p_candidate_dsld_ids,p_reason,p_identity_method,p_identifier_decision,true,p_index_revision,conflicts,label_digest) RETURNING id INTO mid;
 RETURN mid;
END $$;
REVOKE ALL ON FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text,integer,text,text,jsonb,boolean,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text,integer,text,text,jsonb,boolean,text) TO authenticated;


CREATE OR REPLACE FUNCTION public.product_submission_identity_check(
  p_submission_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  latest_match public.product_submission_match_checks%ROWTYPE;
  binds_to_this_evidence boolean;
BEGIN
  SELECT * INTO submission FROM public.product_submissions
  WHERE id = p_submission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '55000';
  END IF;

  SELECT match_check.*
    INTO latest_match
  FROM public.product_submission_match_checks AS match_check
  WHERE match_check.submission_id = p_submission_id
  ORDER BY match_check.created_at DESC, match_check.id DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'recorded', false,
      'satisfies_approval', false,
      'catalog_match_live', false
    );
  END IF;

  -- Only a missing-product approval consults this. For other kinds the record
  -- is reported but never gates, so nothing is claimed as satisfied.
  binds_to_this_evidence :=
    submission.kind = 'missing_product'
    AND latest_match.evidence_revision IS NOT DISTINCT FROM
      submission.evidence_revision
    AND latest_match.index_built_at >= now() - interval '60 days'
    AND latest_match.index_built_at <= now() + interval '5 minutes'
    AND (latest_match.identifier_decision IS NULL OR latest_match.label_payload_sha256=(SELECT d.payload_sha256 FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid()))
    AND ((latest_match.identity_method='gtin' AND latest_match.canonical_gtin14=public.product_submission_canonical_gtin(submission.normalized_upc)) OR (latest_match.identity_method='label_review' AND latest_match.candidate_review_complete AND latest_match.conflict_snapshot IS NOT DISTINCT FROM public.product_submission_identity_conflicts(p_submission_id)));

  RETURN jsonb_build_object(
    'recorded', true,
    'identity_method',latest_match.identity_method,
    'identifier_decision',latest_match.identifier_decision,
    'match_check_id',latest_match.id,
    'outcome', latest_match.outcome,
    'matched_dsld_id', latest_match.matched_dsld_id,
    'evidence_revision', latest_match.evidence_revision,
    'index_built_at', latest_match.index_built_at,
    'checked_at', latest_match.created_at,
    'satisfies_approval',
      binds_to_this_evidence AND latest_match.outcome::text IN ('no_match_verified','new_product_verified'),
    'catalog_match_live',
      binds_to_this_evidence AND latest_match.outcome = 'catalog_match'
      AND latest_match.matched_dsld_id IS NOT NULL
      AND (latest_match.identifier_decision IS NULL OR public.product_submission_catalog_target_is_live(latest_match.matched_dsld_id))
  );
END $$;

CREATE OR REPLACE FUNCTION public.product_submission_review_target_key(
  p_submission_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT CASE
    WHEN submission.kind = 'label_mismatch' THEN
      'label_mismatch:' || mismatch.dsld_id
    WHEN submission.correction_target_dsld_id IS NOT NULL THEN
      'label_mismatch:' || submission.correction_target_dsld_id
    WHEN submission.normalized_upc IS NULL THEN
      public.product_submission_label_bucket(coalesce((SELECT payload->>'brandName' FROM public.product_submission_reviewer_drafts WHERE submission_id=submission.id AND reviewer_id=auth.uid()),submission.identifier->>'brandName'),coalesce((SELECT payload->>'fullName' FROM public.product_submission_reviewer_drafts WHERE submission_id=submission.id AND reviewer_id=auth.uid()),submission.identifier->>'fullName'))
    ELSE
      'missing_product:'
        || public.product_submission_canonical_gtin(submission.normalized_upc)
  END
  FROM public.product_submissions AS submission
  LEFT JOIN public.product_submission_mismatch_details AS mismatch
    ON mismatch.submission_id = submission.id
  WHERE submission.id = p_submission_id;
$$;


CREATE FUNCTION public.product_submission_approval_catalog_ids(p_submission_id uuid,p_payload jsonb)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE
 WHEN p_payload#>>'{identity,correction_target_dsld_id}' IS NOT NULL THEN ARRAY[p_payload#>>'{identity,correction_target_dsld_id}']
 WHEN p_payload#>>'{identity,edition_of_dsld_id}' IS NOT NULL THEN ARRAY[p_payload#>>'{identity,edition_of_dsld_id}',coalesce(s.resolved_dsld_id,'PG_SUB_'||upper(replace(s.id::text,'-','')))]
 ELSE ARRAY[coalesce(s.resolved_dsld_id,'PG_SUB_'||upper(replace(s.id::text,'-','')))] END
 FROM public.product_submissions s WHERE s.id=p_submission_id;
$$;
REVOKE ALL ON FUNCTION public.product_submission_approval_catalog_ids(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- A private duplicate is a human decision about two fully reviewed labels.
-- Raw code equality and a blank GTIN never establish product equivalence.
CREATE FUNCTION public.product_submission_label_duplicate_is_verified(p_submission_id uuid,p_target_id uuid,p_reason text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d public.product_submission_reviewer_drafts%ROWTYPE; m public.product_submission_match_checks%ROWTYPE; a public.product_submission_approved_labels%ROWTYPE; sid public.product_submissions%ROWTYPE;
BEGIN
 SELECT * INTO sid FROM public.product_submissions WHERE id=p_submission_id;
 SELECT * INTO d FROM public.product_submission_reviewer_drafts WHERE submission_id=p_submission_id AND reviewer_id=auth.uid();
 SELECT * INTO m FROM public.product_submission_match_checks WHERE submission_id=p_submission_id ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT approval.* INTO a FROM public.product_submission_approved_labels approval JOIN public.product_submissions t ON t.id=approval.submission_id AND t.approval_revision=approval.approval_revision
 WHERE t.id=p_target_id AND t.kind='missing_product' AND t.review_status='approved' AND t.upload_state='ready';
 IF sid.kind<>'missing_product' OR sid.normalized_upc IS NOT NULL OR sid.identifier IS NULL
 OR a.schema_version IS DISTINCT FROM 'manual_label_v2' OR a.approved_payload#>>'{identity,decision,verified_gtin}' IS NOT NULL
 OR d.payload IS DISTINCT FROM a.approved_payload->'label'
 OR nullif(btrim(d.payload->>'brandName'),'') IS NULL OR nullif(btrim(d.payload->>'fullName'),'') IS NULL
 OR char_length(btrim(coalesce(p_reason,''))) NOT BETWEEN 5 AND 2000
 OR m.identity_method IS DISTINCT FROM 'label_review' OR m.identifier_decision IS NULL OR NOT m.candidate_review_complete
 OR m.evidence_revision IS DISTINCT FROM sid.evidence_revision OR m.label_payload_sha256 IS DISTINCT FROM d.payload_sha256
 OR m.conflict_snapshot IS DISTINCT FROM public.product_submission_identity_conflicts(p_submission_id)
 OR m.index_built_at<now()-interval '60 days' OR m.index_built_at>now()+interval '5 minutes'
 OR m.identifier_decision->>'verified_gtin' IS NOT NULL
 OR nullif(btrim(m.identifier_decision->>'package'),'') IS NULL
 OR m.identifier_decision->>'package' IS DISTINCT FROM a.approved_payload#>>'{identity,decision,package}'
 OR m.identifier_decision->>'issuer' IS DISTINCT FROM a.approved_payload#>>'{identity,decision,issuer}' THEN RETURN false; END IF;
 PERFORM public.assert_product_submission_fully_verified(p_submission_id,d.payload_sha256);
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.product_submission_label_duplicate_is_verified(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION "public"."review_product_submission_human_internal"("p_submission_id" "uuid", "p_reviewer_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  submission public.product_submissions%ROWTYPE;
  matched public.product_submission_match_checks%ROWTYPE;
  identity_revision public.product_submission_evidence_revisions%ROWTYPE;
  transition_allowed boolean;
  review_target_key text;
  resolution_code_value public.product_submission_resolution_code;
  resolution_detail_value text;
  resolved_dsld_value text;
BEGIN
  PERFORM public.lock_product_submission_identity();
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

  IF p_to_status='approved' AND p_approved_schema_version='manual_label_v2' THEN
    IF p_approved_payload IS NULL OR p_approved_payload_canonical IS NULL
       OR p_approved_payload_canonical::jsonb IS DISTINCT FROM p_approved_payload
       OR encode(extensions.digest(p_approved_payload_canonical,'sha256'),'hex') IS DISTINCT FROM p_payload_sha256 THEN
      RAISE EXCEPTION 'approved canonical label payload required' USING ERRCODE='22023'; END IF;
    SELECT * INTO matched FROM public.product_submission_match_checks WHERE submission_id=p_submission_id ORDER BY created_at DESC,id DESC LIMIT 1;
    SELECT * INTO identity_revision FROM public.product_submission_evidence_revisions r WHERE r.submission_id=p_submission_id AND r.revision=submission.evidence_revision;
    IF matched.outcome::text='catalog_match' AND NOT public.product_submission_catalog_target_is_live(matched.matched_dsld_id) THEN
      RAISE EXCEPTION 'matched catalog target is not active' USING ERRCODE='55000'; END IF;
    IF matched.identifier_decision IS NULL OR NOT matched.candidate_review_complete
       OR matched.label_payload_sha256 IS DISTINCT FROM (SELECT d.payload_sha256 FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid())
       OR matched.conflict_snapshot IS DISTINCT FROM public.product_submission_identity_conflicts(p_submission_id) THEN
      RAISE EXCEPTION 'current complete reviewed identifier decision required' USING ERRCODE='55000'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(matched.conflict_snapshot) c WHERE c->>'source'='pending')
       OR EXISTS(SELECT 1 FROM jsonb_array_elements(matched.conflict_snapshot) c WHERE c->>'source'='catalog' AND NOT (c->>'id'=ANY(public.product_submission_approval_catalog_ids(p_submission_id,p_approved_payload)))) THEN
      RAISE EXCEPTION 'catalog identity conflict requires explicit resolution' USING ERRCODE='23505'; END IF;
    IF submission.promoted_at IS NOT NULL AND submission.correction_target_dsld_id IS NOT NULL AND submission.correction_target_dsld_id IS DISTINCT FROM submission.resolved_dsld_id THEN
      RAISE EXCEPTION 'published submission identity cannot be reassigned' USING ERRCODE='55000'; END IF;
    IF p_approved_payload IS DISTINCT FROM public.prepare_product_submission_approval_payload(p_submission_id,p_approved_payload->'label',submission.correction_target_dsld_id,submission.edition_of_dsld_id) THEN
      RAISE EXCEPTION 'approved identity envelope changed' USING ERRCODE='55000'; END IF;
  ELSIF p_to_status='approved' AND submission.identifier IS NOT NULL THEN
    RAISE EXCEPTION 'manual_label_v2 required for alternate identifier' USING ERRCODE='22023';
  END IF;
  IF p_to_status = 'approved' AND (
    p_approved_schema_version NOT IN ('manual_label_v1','manual_label_v2') OR p_approved_schema_version IS NULL
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
          AND (public.product_submission_canonical_gtin(target.normalized_upc)
            = public.product_submission_canonical_gtin(submission.normalized_upc)
            OR public.product_submission_label_duplicate_is_verified(p_submission_id,p_duplicate_of,p_review_notes))
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

CREATE OR REPLACE FUNCTION public.review_product_submission(
  p_submission_id uuid,
  p_to_status public.product_submission_review_status,
  p_review_notes text DEFAULT NULL,
  p_approved_schema_version text DEFAULT NULL,
  p_approved_payload jsonb DEFAULT NULL,
  p_approved_payload_canonical text DEFAULT NULL,
  p_payload_sha256 text DEFAULT NULL,
  p_duplicate_of uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_detail text DEFAULT NULL,
  p_resolved_dsld_id text DEFAULT NULL,
  p_product_image_photo_id uuid DEFAULT NULL,
  p_product_image_reviewer_object_id uuid DEFAULT NULL,
  p_expected_evidence_revision integer DEFAULT NULL,
  p_evidence_manifest_sha256 text DEFAULT NULL,
  p_correction_target_dsld_id text DEFAULT NULL,
  p_edition_of_dsld_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  PERFORM public.assert_product_submission_reviewer();
  PERFORM public.lock_product_submission_identity();
  IF p_to_status = 'approved' THEN
    -- The same required-path rule used by single and batch actions, inside the
    -- RPC so a direct authenticated call cannot manufacture an approval with
    -- no attestations.
    IF p_approved_schema_version='manual_label_v2' THEN
      IF NOT EXISTS(SELECT 1 FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid() AND d.payload IS NOT DISTINCT FROM p_approved_payload->'label') THEN
        RAISE EXCEPTION 'this label was not the one reviewed' USING ERRCODE='55000'; END IF;
      PERFORM public.assert_product_submission_fully_verified(p_submission_id,(SELECT d.payload_sha256 FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid()));
    ELSE
      PERFORM public.assert_product_submission_fully_verified(p_submission_id,p_payload_sha256);
    END IF;
  END IF;

  RETURN public.review_product_submission_unchecked(
    p_submission_id,
    p_to_status,
    p_review_notes,
    p_approved_schema_version,
    p_approved_payload,
    p_approved_payload_canonical,
    p_payload_sha256,
    p_duplicate_of,
    p_resolution_code,
    p_resolution_detail,
    p_resolved_dsld_id,
    p_product_image_photo_id,
    p_product_image_reviewer_object_id,
    p_expected_evidence_revision,
    p_evidence_manifest_sha256,
    p_correction_target_dsld_id,
    p_edition_of_dsld_id
  );
END;
$$;



CREATE OR REPLACE FUNCTION public.reopen_product_submission_approval(
  p_submission_id uuid,
  p_expected_approval_revision integer,
  p_expected_payload_sha256 text,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  approved public.product_submission_approved_labels%ROWTYPE;
  reason_value text := NULLIF(btrim(regexp_replace(
    coalesce(p_reason, ''), '[\x00-\x1F\x7F]', '', 'g')), '');
  latest_event public.product_submission_review_events%ROWTYPE;
BEGIN
  PERFORM public.assert_product_submission_reviewer();
  PERFORM public.lock_product_submission_identity();
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF reason_value IS NULL THEN
    RAISE EXCEPTION 'correction reason required' USING ERRCODE = '22023';
  END IF;
  IF char_length(reason_value) > 2000 THEN
    RAISE EXCEPTION 'correction reason too long' USING ERRCODE = '22023';
  END IF;
  IF p_expected_approval_revision IS NULL
     OR p_expected_payload_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'expected approval required' USING ERRCODE = '22023';
  END IF;

  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready'
     OR submission.cleanup_claimed_at IS NOT NULL THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;
  SELECT candidate.* INTO approved
  FROM public.product_submission_approved_labels AS candidate
  WHERE candidate.submission_id = p_submission_id
    AND candidate.approval_revision = p_expected_approval_revision;
  IF NOT FOUND
     OR submission.approval_revision <> p_expected_approval_revision
     OR approved.payload_sha256 <> p_expected_payload_sha256 THEN
    RAISE EXCEPTION 'approval changed since review' USING ERRCODE = '55000';
  END IF;

  IF submission.review_status = 'under_review' THEN
    SELECT event.* INTO latest_event
    FROM public.product_submission_review_events AS event
    WHERE event.submission_id = p_submission_id
    ORDER BY event.created_at DESC, event.id DESC
    LIMIT 1;
    IF FOUND
       AND latest_event.from_status = 'approved'
       AND latest_event.to_status = 'under_review'
       AND latest_event.reviewer_id = v_reviewer_id
       AND latest_event.review_notes = reason_value THEN
      RETURN true;
    END IF;
    RAISE EXCEPTION 'approval already reopened' USING ERRCODE = '55000';
  END IF;
  IF submission.review_status <> 'approved' THEN
    RAISE EXCEPTION 'approved submission required' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.product_submission_review_events(
    submission_id, from_status, to_status, reviewer_id, review_notes)
  VALUES (p_submission_id, 'approved', 'under_review', v_reviewer_id, reason_value);

  UPDATE public.product_submissions
  SET review_status = 'under_review',
      reviewed_at = now(),
      reviewed_by = v_reviewer_id
  WHERE id = p_submission_id;

  INSERT INTO public.product_submission_reviewer_drafts(
    submission_id, reviewer_id, evidence_revision,
    evidence_manifest_sha256, payload, payload_canonical, payload_sha256,
    product_image
  ) VALUES (
    p_submission_id, v_reviewer_id, approved.evidence_revision,
    approved.evidence_manifest_sha256, CASE WHEN approved.schema_version='manual_label_v2' THEN approved.approved_payload->'label' ELSE approved.approved_payload END,
    CASE WHEN approved.schema_version='manual_label_v2' THEN (approved.approved_payload->'label')::text ELSE approved.approved_payload_canonical END, CASE WHEN approved.schema_version='manual_label_v2' THEN encode(extensions.digest((approved.approved_payload->'label')::text,'sha256'),'hex') ELSE approved.payload_sha256 END,
    CASE
      WHEN approved.approved_product_image_photo_id IS NOT NULL THEN
        jsonb_build_object('kind','photo','id',
          approved.approved_product_image_photo_id,
          'evidence_revision', approved.evidence_revision,
          'manifest', approved.evidence_manifest_sha256)
      WHEN approved.approved_product_image_reviewer_object_id IS NOT NULL THEN
        jsonb_build_object('kind','reviewer','id',
          approved.approved_product_image_reviewer_object_id,
          'evidence_revision', approved.evidence_revision,
          'manifest', approved.evidence_manifest_sha256)
      ELSE NULL
    END
  )
  ON CONFLICT (submission_id, reviewer_id) DO UPDATE SET
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
    payload = EXCLUDED.payload,
    payload_canonical = EXCLUDED.payload_canonical,
    payload_sha256 = EXCLUDED.payload_sha256,
    product_image = EXCLUDED.product_image,
    updated_at = now();

  DELETE FROM public.product_submission_field_verifications
  WHERE submission_id = p_submission_id;

  INSERT INTO public.product_submission_push_deliveries(
    submission_id, user_id, to_status)
  VALUES (p_submission_id, submission.user_id, 'under_review');
  RETURN true;
END;
$$;

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
  PERFORM public.lock_product_submission_identity();
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

CREATE OR REPLACE FUNCTION public.correct_product_submission_barcode(
  p_submission_id uuid,
  p_new_upc text,
  p_reason text,
  p_expected_revision integer,
  p_manifest_sha256 text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  new_upc text;
  reason_value text := btrim(coalesce(p_reason, ''));
  new_target_key text;
BEGIN
  PERFORM public.assert_product_submission_reviewer();
  PERFORM public.lock_product_submission_identity();
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, p_expected_revision, p_manifest_sha256);

  -- Printed barcodes carry spaces ("0067 1422"); strip exactly what intake
  -- strips, then hold the result to the same GTIN rule intake applies.
  new_upc := NULLIF(regexp_replace(coalesce(p_new_upc, ''), '[[:space:]-]', '', 'g'), '');
  IF new_upc IS NULL OR NOT public.is_valid_product_submission_gtin(new_upc) THEN
    RAISE EXCEPTION 'valid barcode required' USING ERRCODE = '22023';
  END IF;
  IF reason_value = '' OR char_length(reason_value) > 500 THEN
    RAISE EXCEPTION 'barcode correction reason required' USING ERRCODE = '22023';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.kind <> 'missing_product'
     OR submission.upload_state <> 'ready'
     OR submission.review_status <> 'under_review' THEN
    RAISE EXCEPTION 'missing-product submission under review required'
      USING ERRCODE = '55000';
  END IF;
  IF public.product_submission_canonical_gtin(new_upc)
     = public.product_submission_canonical_gtin(submission.normalized_upc) THEN
    RAISE EXCEPTION 'barcode unchanged' USING ERRCODE = '22023';
  END IF;

  -- Approval serializes on the review target and refuses a second approved
  -- submission for the same one. Take the same lock on the new barcode, so a
  -- correction cannot slip in beside an approval that is deciding it.
  new_target_key := 'missing_product:'
    || public.product_submission_canonical_gtin(new_upc);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new_target_key, 0));
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS other
    WHERE other.id <> p_submission_id
      AND other.review_status = 'approved'
      AND other.promoted_at IS NULL
      AND public.product_submission_review_target_key(other.id) = new_target_key
  ) THEN
    RAISE EXCEPTION 'another approved submission awaits promotion'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.product_submission_barcode_corrections (
    submission_id, reviewer_id, from_upc, to_upc, reason, evidence_revision
  ) VALUES (
    p_submission_id, reviewer_id, submission.normalized_upc, new_upc,
    reason_value, submission.evidence_revision
  );
  -- idx_product_submissions_user_open_upc refuses a barcode the same owner
  -- already has an open submission for, which is the right answer here too.
  UPDATE public.product_submissions
  SET normalized_upc = new_upc
  WHERE id = p_submission_id;
  DELETE FROM public.product_submission_field_verifications WHERE submission_id=p_submission_id;

  RETURN jsonb_build_object(
    'from_upc', submission.normalized_upc,
    'to_upc', new_upc
  );
END;
$$;

CREATE OR REPLACE FUNCTION "public"."review_product_submission_unchecked"("p_submission_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text", "p_product_image_photo_id" "uuid" DEFAULT NULL::"uuid", "p_product_image_reviewer_object_id" "uuid" DEFAULT NULL::"uuid", "p_expected_evidence_revision" integer DEFAULT NULL::integer, "p_evidence_manifest_sha256" "text" DEFAULT NULL::"text", "p_correction_target_dsld_id" "text" DEFAULT NULL::"text", "p_edition_of_dsld_id" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  identity jsonb;
  transitioned boolean;
BEGIN
  PERFORM public.lock_product_submission_identity();
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_evidence_revision,p_evidence_manifest_sha256);

  IF p_to_status = 'approved' THEN
    IF p_expected_evidence_revision IS NULL THEN
      RAISE EXCEPTION 'expected evidence revision required'
        USING ERRCODE = '22023';
    END IF;
    IF p_expected_evidence_revision <> submission.evidence_revision THEN
      RAISE EXCEPTION 'evidence revision changed since review'
        USING ERRCODE = '55000';
    END IF;
    SELECT revision.*
      INTO current_revision
    FROM public.product_submission_evidence_revisions AS revision
    WHERE revision.submission_id = p_submission_id
      AND revision.revision = submission.evidence_revision
      AND revision.ready_at IS NOT NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
    END IF;
  ELSIF p_expected_evidence_revision IS NOT NULL
        AND p_expected_evidence_revision <> submission.evidence_revision THEN
    RAISE EXCEPTION 'evidence revision changed since review'
      USING ERRCODE = '55000';
  END IF;

  IF num_nonnulls(p_correction_target_dsld_id, p_edition_of_dsld_id) > 0
     AND NOT (p_to_status = 'approved' AND submission.kind = 'missing_product')
  THEN
    RAISE EXCEPTION 'catalog relation is not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' AND submission.kind = 'missing_product' THEN
    -- Three honest answers, and the reviewer must have recorded one of them.
    -- A barcode nobody else uses is a new product. A barcode that already
    -- names a catalog record is either that record transcribed wrongly, or a
    -- different edition sold under the same barcode — and those are different
    -- decisions with different consequences, so neither is inferred here.
    identity := public.product_submission_identity_check(p_submission_id);
    IF num_nonnulls(p_correction_target_dsld_id, p_edition_of_dsld_id) = 1 THEN
      IF NOT (identity ->> 'catalog_match_live')::boolean
         OR identity ->> 'matched_dsld_id' IS DISTINCT FROM
            coalesce(p_correction_target_dsld_id, p_edition_of_dsld_id) THEN
        RAISE EXCEPTION
          'recorded catalog match must name the catalog record being decided'
          USING ERRCODE = '55000';
      END IF;
    ELSIF NOT (identity ->> 'satisfies_approval')::boolean THEN
      RAISE EXCEPTION 'fresh verified no-match required before approval'
        USING ERRCODE = '55000';
    END IF;
    IF num_nonnulls(
      p_product_image_photo_id,
      p_product_image_reviewer_object_id
    ) <> 1 THEN
      RAISE EXCEPTION 'exactly one approved product image required'
        USING ERRCODE = '22023';
    END IF;
    IF p_product_image_photo_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      WHERE photo.submission_id = p_submission_id
        AND photo.photo_id = p_product_image_photo_id
        AND photo.photo_id = ANY(current_revision.photo_ids)
        AND 'front_identity' = ANY(photo.categories)
    ) THEN
      RAISE EXCEPTION 'front evidence photo required for product image'
        USING ERRCODE = '22023';
    END IF;
    IF p_product_image_reviewer_object_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_reviewer_images AS image
      WHERE image.submission_id = p_submission_id
        AND image.object_id = p_product_image_reviewer_object_id
        AND image.reviewer_id = v_reviewer_id
        AND image.evidence_revision = submission.evidence_revision
        AND image.finalized_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'finalized reviewer product image required'
        USING ERRCODE = '22023';
    END IF;
  ELSIF p_product_image_photo_id IS NOT NULL
     OR p_product_image_reviewer_object_id IS NOT NULL THEN
    RAISE EXCEPTION 'product image is not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' THEN
    -- Recorded before the transition, inside the same transaction: the
    -- transition decides which catalog record this approval contends for, and
    -- a correction contends for the record it rewrites. A refusal below rolls
    -- this back with everything else.
    UPDATE public.product_submissions
    SET correction_target_dsld_id = p_correction_target_dsld_id,
        edition_of_dsld_id = p_edition_of_dsld_id
    WHERE id = p_submission_id;
  END IF;

  transitioned := public.review_product_submission_human_internal(
    p_submission_id,
    v_reviewer_id,
    p_to_status,
    p_review_notes,
    p_approved_schema_version,
    p_approved_payload,
    p_approved_payload_canonical,
    p_payload_sha256,
    p_duplicate_of,
    p_resolution_code,
    p_resolution_detail,
    p_resolved_dsld_id
  );
  IF transitioned AND p_to_status = 'approved' THEN
    UPDATE public.product_submission_approved_labels
    SET approved_product_image_photo_id = p_product_image_photo_id,
        approved_product_image_reviewer_object_id =
          p_product_image_reviewer_object_id,
        evidence_revision = current_revision.revision,
        evidence_manifest_sha256 = current_revision.manifest_sha256
    WHERE submission_id = p_submission_id;
  END IF;
  RETURN transitioned;
END;
$$;

ALTER TABLE public.product_submission_barcode_corrections ALTER COLUMN from_upc DROP NOT NULL;
ALTER TABLE public.product_submission_barcode_corrections DROP CONSTRAINT product_submission_barcode_correction_changes_identity;
ALTER TABLE public.product_submission_barcode_corrections ADD CONSTRAINT product_submission_barcode_correction_changes_identity CHECK (public.product_submission_canonical_gtin(from_upc) IS DISTINCT FROM public.product_submission_canonical_gtin(to_upc));

CREATE OR REPLACE FUNCTION public.export_approved_product_submissions(
  p_limit integer DEFAULT 100,
  p_after_approved_at timestamptz DEFAULT NULL,
  p_after_submission_id uuid DEFAULT NULL
)
RETURNS TABLE(
  submission_id uuid,
  approval_revision integer,
  kind public.product_submission_kind,
  normalized_upc text,
  target_dsld_id text,
  schema_version text,
  approved_payload_canonical text,
  payload_sha256 text,
  reviewer_id uuid,
  approved_at timestamptz,
  correction_target_dsld_id text,
  edition_of_dsld_id text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE candidate record;
BEGIN
  PERFORM public.assert_product_submission_catalog_identity();
  FOR candidate IN
    SELECT submission.id AS submission_id,
      approved.approval_revision,
      submission.kind,
      CASE WHEN approved.schema_version='manual_label_v2' THEN approved.approved_payload#>>'{identity,decision,verified_gtin}' ELSE submission.normalized_upc END AS normalized_upc,
      approved.target_dsld_id,
      approved.schema_version,
      approved.approved_payload_canonical,
      approved.payload_sha256,
      approved.reviewer_id,
      approved.approved_at,
      approved.correction_target_dsld_id,
      approved.edition_of_dsld_id
    FROM public.product_submissions AS submission
    JOIN public.product_submission_approved_labels AS approved
      ON approved.submission_id = submission.id
     AND approved.approval_revision = submission.approval_revision
    WHERE submission.upload_state = 'ready'
      AND submission.review_status = 'approved'
      AND submission.approval_revision > submission.promoted_approval_revision
      AND (
        p_after_approved_at IS NULL AND p_after_submission_id IS NULL
        OR p_after_approved_at IS NOT NULL AND p_after_submission_id IS NOT NULL
          AND (approved.approved_at, submission.id) >
            (p_after_approved_at, p_after_submission_id)
      )
    ORDER BY approved.approved_at, submission.id
    LIMIT greatest(0, least(p_limit, 500))
  LOOP
    PERFORM public.assert_product_submission_approval_revision(
      candidate.submission_id, candidate.approval_revision,
      candidate.payload_sha256);
    RETURN QUERY SELECT
      candidate.submission_id,
      candidate.approval_revision,
      candidate.kind,
      candidate.normalized_upc,
      candidate.target_dsld_id,
      candidate.schema_version,
      candidate.approved_payload_canonical,
      candidate.payload_sha256,
      candidate.reviewer_id,
      candidate.approved_at,
      candidate.correction_target_dsld_id,
      candidate.edition_of_dsld_id;
  END LOOP;
END;
$$;

-- Active search generations and manifest rotation share the approval fence.
-- Statement triggers run before PostgreSQL acquires individual tuple locks.
CREATE FUNCTION public.fence_product_submission_catalog_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM public.lock_product_submission_identity(); RETURN NULL; END $$;
REVOKE ALL ON FUNCTION public.fence_product_submission_catalog_identity() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER catalog_search_submission_identity_fence BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.catalog_search FOR EACH STATEMENT EXECUTE FUNCTION public.fence_product_submission_catalog_identity();
CREATE TRIGGER export_manifest_submission_identity_fence BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.export_manifest FOR EACH STATEMENT EXECUTE FUNCTION public.fence_product_submission_catalog_identity();
CREATE FUNCTION public.assert_product_submission_catalog_identity() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pending record; conflicts jsonb;
BEGIN
 FOR pending IN SELECT s.id,a.approved_payload FROM public.product_submissions s JOIN public.product_submission_approved_labels a ON a.submission_id=s.id AND a.approval_revision=s.approval_revision
 WHERE s.review_status='approved' AND s.approval_revision>s.promoted_approval_revision AND a.schema_version='manual_label_v2'
 LOOP
  conflicts:=public.product_submission_identity_conflicts(pending.id);
  IF pending.approved_payload#>>'{identity,outcome}'='catalog_match' AND NOT public.product_submission_catalog_target_is_live(coalesce(pending.approved_payload#>>'{identity,correction_target_dsld_id}',pending.approved_payload#>>'{identity,edition_of_dsld_id}')) THEN
    RAISE EXCEPTION 'reviewed catalog target is not active during activation' USING ERRCODE='23505'; END IF;
  IF EXISTS(
    SELECT 1 FROM public.product_submission_match_checks m,
      jsonb_array_elements(m.conflict_snapshot) reviewed
    WHERE m.id=(pending.approved_payload#>>'{identity,match_check_id}')::bigint
      AND reviewed->>'source'='catalog'
      AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(conflicts) current_candidate
        WHERE current_candidate->>'source'='catalog' AND current_candidate->>'id'=reviewed->>'id')
  ) THEN
    RAISE EXCEPTION 'reviewed catalog target disappeared during activation' USING ERRCODE='23505';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(conflicts) c WHERE c->>'source'='catalog' AND NOT (c->>'id'=ANY(public.product_submission_approval_catalog_ids(pending.id,pending.approved_payload)))) THEN
    RAISE EXCEPTION 'catalog activation conflicts with pending submission approval' USING ERRCODE='23505';
  END IF;
 END LOOP;
 RETURN;
END $$;
REVOKE ALL ON FUNCTION public.assert_product_submission_catalog_identity() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.revalidate_product_submission_catalog_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM public.assert_product_submission_catalog_identity(); RETURN NULL; END $$;
REVOKE ALL ON FUNCTION public.revalidate_product_submission_catalog_identity() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER catalog_search_submission_identity_revalidate AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.catalog_search FOR EACH STATEMENT EXECUTE FUNCTION public.revalidate_product_submission_catalog_identity();
-- A manifest rotation temporarily has no current row. Revalidate its final
-- state at transaction end; rotate/export/promotion also assert explicitly
-- before consuming approvals, so deferral never authorizes stale promotion.
CREATE CONSTRAINT TRIGGER export_manifest_submission_identity_revalidate
AFTER INSERT OR UPDATE OR DELETE ON public.export_manifest
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION public.revalidate_product_submission_catalog_identity();
CREATE TRIGGER export_manifest_submission_identity_truncate_revalidate
AFTER TRUNCATE ON public.export_manifest FOR EACH STATEMENT
EXECUTE FUNCTION public.revalidate_product_submission_catalog_identity();
CREATE OR REPLACE FUNCTION public.rotate_manifest_with_submission_approvals(
  p_db_version text,
  p_pipeline_version text,
  p_scoring_version text,
  p_schema_version text,
  p_product_count integer,
  p_checksum text,
  p_generated_at timestamptz,
  p_min_app_version text DEFAULT '1.0.0',
  p_submission_approvals jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  new_id uuid;
  current_manifest public.export_manifest%ROWTYPE;
  item jsonb;
  sid uuid;
  revision integer;
  payload_hash text;
  resolved_id text;
BEGIN
  PERFORM public.lock_product_submission_identity();
  IF p_product_count < 0 THEN
    RAISE EXCEPTION 'product_count cannot be negative' USING ERRCODE='22023';
  END IF;
  IF jsonb_typeof(p_submission_approvals) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_submission_approvals) > 500 THEN
    RAISE EXCEPTION 'invalid submission approvals' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_submission_approvals) value
    WHERE jsonb_typeof(value) IS DISTINCT FROM 'object'
      OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(value) key)
        NOT IN (
          ARRAY['approval_revision','payload_sha256','submission_id']::text[],
          ARRAY['approval_revision','payload_sha256','resolved_dsld_id','submission_id']::text[]
        )
  ) THEN
    RAISE EXCEPTION 'invalid submission approval entry' USING ERRCODE='22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_submission_approvals))
     <> (SELECT count(DISTINCT value->>'submission_id')
         FROM jsonb_array_elements(p_submission_approvals) value) THEN
    RAISE EXCEPTION 'duplicate submission approval' USING ERRCODE='22023';
  END IF;

  -- Lock in deterministic order before validating any exact revision.
  PERFORM submission.id
  FROM public.product_submissions AS submission
  WHERE submission.id IN (
    SELECT (value->>'submission_id')::uuid
    FROM jsonb_array_elements(p_submission_approvals) value
  )
  ORDER BY submission.id
  FOR UPDATE;

  FOR item IN SELECT value FROM jsonb_array_elements(p_submission_approvals)
  LOOP
    BEGIN
      sid := (item->>'submission_id')::uuid;
      revision := (item->>'approval_revision')::integer;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid submission approval identity'
        USING ERRCODE='22023';
    END;
    payload_hash := item->>'payload_sha256';
    PERFORM public.assert_product_submission_approval_revision(
      sid, revision, payload_hash);
  END LOOP;

  SELECT manifest.* INTO current_manifest
  FROM public.export_manifest AS manifest
  WHERE manifest.db_version = p_db_version
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION 'catalog version was already used; use a fresh version'
      USING ERRCODE='55000';
  END IF;
  UPDATE public.export_manifest SET is_current=false WHERE is_current;
  INSERT INTO public.export_manifest(
    db_version,pipeline_version,scoring_version,schema_version,
    product_count,checksum,min_app_version,generated_at,is_current
  ) VALUES (
    p_db_version,p_pipeline_version,p_scoring_version,p_schema_version,
    p_product_count,p_checksum,p_min_app_version,p_generated_at,true
  ) RETURNING id INTO new_id;

  PERFORM public.assert_product_submission_catalog_identity();

  FOR item IN SELECT value FROM jsonb_array_elements(p_submission_approvals)
  LOOP
    resolved_id := nullif(item->>'resolved_dsld_id','');
    IF resolved_id IS NOT NULL THEN
      PERFORM public.mark_product_submission_promoted(
        (item->>'submission_id')::uuid,
        (item->>'approval_revision')::integer,
        item->>'payload_sha256',
        p_db_version,
        resolved_id);
    END IF;
  END LOOP;
  RETURN new_id;
END;
$$;

-- Reviewer-only candidate enumeration also makes pending approvals visible
-- in the existing workstation, before recording a complete receipt.
CREATE FUNCTION public.get_product_submission_identity_candidates(p_submission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.assert_product_submission_reviewer();
 SELECT jsonb_build_object('complete',true,'conflicts',public.product_submission_identity_conflicts(p_submission_id),
 'pending',coalesce((SELECT jsonb_agg(jsonb_build_object('submission_id',s.id,'dsld_id',c->>'id','package',a.approved_payload#>>'{identity,decision,package}','issuer',a.approved_payload#>>'{identity,decision,issuer}','brandName',CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload#>>'{label,brandName}' ELSE a.approved_payload->>'brandName' END,'fullName',CASE WHEN a.schema_version='manual_label_v2' THEN a.approved_payload#>>'{label,fullName}' ELSE a.approved_payload->>'fullName' END,'approval_revision',a.approval_revision))
 FROM jsonb_array_elements(public.product_submission_identity_conflicts(p_submission_id)) c
 JOIN public.product_submission_approved_labels a ON a.approval_revision::text=c->>'revision'
 JOIN public.product_submissions s ON s.id=a.submission_id AND s.approval_revision=a.approval_revision AND s.review_status='approved' AND s.approval_revision>s.promoted_approval_revision
 WHERE c->>'source'='pending' AND coalesce(a.correction_target_dsld_id,a.target_dsld_id,'PG_SUB_'||upper(replace(s.id::text,'-','')))=c->>'id'),'[]'::jsonb)) INTO result;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_product_submission_identity_candidates(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_submission_identity_candidates(uuid) TO authenticated;

INSERT INTO public.product_submission_consent_versions(version,kind,purposes,copy_sha256,effective_from)
VALUES
('pharmaguide.submission_consent.2026-10-26.v2','missing_product',ARRAY['private_review','ai_label_draft','human_approval','front_photo_publication'],'b84f733ee5451693c427b67f2bab5173d538e0b3a2cae54408c74256b303380e','2026-10-26T00:00:00Z'),
('pharmaguide.submission_consent.2026-10-26.v2','label_mismatch',ARRAY['private_review','ai_label_draft','human_approval','front_photo_publication'],'94dcb98d57f6e47e1eae2861f71820720d849bf962acb5a633c3e1194aee6f8e','2026-10-26T00:00:00Z');

CREATE OR REPLACE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid,
  p_approval_revision integer,
  p_payload_sha256 text,
  p_catalog_version text,
  p_resolved_dsld_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  catalog_version_value text := btrim(coalesce(p_catalog_version,''));
  resolved_dsld_value text := btrim(coalesce(p_resolved_dsld_id,''));
BEGIN
  PERFORM public.lock_product_submission_identity();
  PERFORM public.assert_product_submission_catalog_identity();
  IF catalog_version_value = '' THEN
    RAISE EXCEPTION 'catalog version required' USING ERRCODE='22023';
  END IF;
  IF resolved_dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid resolved product id' USING ERRCODE='22023';
  END IF;
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id=p_submission_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF submission.promoted_approval_revision = p_approval_revision THEN
    IF EXISTS (
      SELECT 1 FROM public.product_submission_approved_labels AS approved
      WHERE approved.submission_id=p_submission_id
        AND approved.approval_revision=p_approval_revision
        AND approved.payload_sha256=p_payload_sha256
        AND approved.promoted_catalog_version=catalog_version_value
        AND approved.promoted_dsld_id=resolved_dsld_value
    ) THEN RETURN true; END IF;
    IF submission.approval_revision <> p_approval_revision THEN
      RAISE EXCEPTION 'approval changed' USING ERRCODE='55000';
    END IF;
    RAISE EXCEPTION 'approval already promoted differently'
      USING ERRCODE='23505';
  END IF;
  PERFORM public.assert_product_submission_approval_revision(
    p_submission_id,p_approval_revision,p_payload_sha256);
  IF p_approval_revision <= submission.promoted_approval_revision THEN
    RAISE EXCEPTION 'approval revision is older than the promoted revision'
      USING ERRCODE='55000';
  END IF;
  IF EXISTS(SELECT 1 FROM public.product_submission_approved_labels a WHERE a.submission_id=p_submission_id AND a.approval_revision=p_approval_revision AND a.schema_version='manual_label_v2')
     AND resolved_dsld_value IS DISTINCT FROM coalesce(submission.resolved_dsld_id,submission.correction_target_dsld_id,(SELECT target_dsld_id FROM public.product_submission_approved_labels WHERE submission_id=p_submission_id AND approval_revision=p_approval_revision),'PG_SUB_'||upper(replace(p_submission_id::text,'-',''))) THEN
    RAISE EXCEPTION 'published submission identity cannot be reassigned' USING ERRCODE='55000'; END IF;
  UPDATE public.product_submission_approved_labels
  SET promoted_catalog_version=catalog_version_value,
      promoted_dsld_id=resolved_dsld_value,
      promoted_at=now()
  WHERE submission_id=p_submission_id
    AND approval_revision=p_approval_revision;
  UPDATE public.product_submissions
  SET promoted_approval_revision=p_approval_revision,
      promoted_catalog_version=catalog_version_value,
      promoted_at=now(),
      resolved_dsld_id=resolved_dsld_value
  WHERE id=p_submission_id;
  UPDATE public.product_submissions
  SET resolved_dsld_id=coalesce(resolved_dsld_id,resolved_dsld_value),
      promoted_catalog_version=catalog_version_value,
      promoted_at=now()
  WHERE duplicate_of=p_submission_id
    AND review_status='duplicate'
    AND promoted_catalog_version IS NULL;
  PERFORM public.award_product_contribution_points_internal(p_submission_id);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_product_submission_intake(
  p_kind public.product_submission_kind,
  p_upc text,
  p_dsld_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
    coalesce(p_upc, ''), '[[:space:]-]', '', 'g'
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
      AND (dsld_value IS NULL OR dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'))
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
$$;


CREATE FUNCTION public.prepare_product_submission_approval_payload(p_submission_id uuid,p_label jsonb,p_correction_target_dsld_id text DEFAULT NULL,p_edition_of_dsld_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE matched public.product_submission_match_checks%ROWTYPE; revision public.product_submission_evidence_revisions%ROWTYPE;
BEGIN
 PERFORM public.assert_product_submission_reviewer();
 PERFORM public.lock_product_submission_identity();
 SELECT m.* INTO matched FROM public.product_submission_match_checks m WHERE m.submission_id=p_submission_id ORDER BY m.created_at DESC,m.id DESC LIMIT 1;
 SELECT r.* INTO revision FROM public.product_submission_evidence_revisions r JOIN public.product_submissions s ON s.id=r.submission_id AND s.evidence_revision=r.revision WHERE s.id=p_submission_id;
 IF matched.outcome::text='catalog_match' AND NOT public.product_submission_catalog_target_is_live(matched.matched_dsld_id) THEN RAISE EXCEPTION 'matched catalog target is not active' USING ERRCODE='55000'; END IF;
 IF matched.identifier_decision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.product_submission_reviewer_drafts d WHERE d.submission_id=p_submission_id AND d.reviewer_id=auth.uid() AND d.payload_sha256=matched.label_payload_sha256 AND d.payload IS NOT DISTINCT FROM p_label) THEN RAISE EXCEPTION 'reviewed identity label changed' USING ERRCODE='55000'; END IF;
 IF matched.id IS NULL OR revision.ready_at IS NULL THEN RAISE EXCEPTION 'reviewed identity and ready evidence required' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('label',p_label,'identity',jsonb_build_object(
 'observed',revision.identifier,'decision',matched.identifier_decision,'identity_method',matched.identity_method,
 'outcome',matched.outcome,'matched_dsld_id',matched.matched_dsld_id,'correction_target_dsld_id',p_correction_target_dsld_id,
 'edition_of_dsld_id',p_edition_of_dsld_id,'evidence_revision',revision.revision,'evidence_manifest_sha256',revision.manifest_sha256,'match_check_id',matched.id));
END $$;
REVOKE ALL ON FUNCTION public.prepare_product_submission_approval_payload(uuid,jsonb,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_product_submission_approval_payload(uuid,jsonb,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_product_submission_reviewer_draft(
  p_submission_id uuid,
  p_expected_evidence_revision integer,
  p_evidence_manifest_sha256 text,
  p_payload jsonb,
  p_payload_canonical text,
  p_payload_sha256 text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_reviewer_id uuid := public.assert_product_submission_reviewer();
  submission public.product_submissions%ROWTYPE;
BEGIN
  PERFORM public.lock_product_submission_identity();
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'label payload object required' USING ERRCODE = '22023';
  END IF;
  IF p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
     OR p_payload_canonical IS NULL OR btrim(p_payload_canonical) = '' THEN
    RAISE EXCEPTION 'canonical payload digest required' USING ERRCODE = '22023';
  END IF;
  -- The same fence approval uses. A draft may only be written against
  -- evidence that is still current, so a retake can never be edited blind.
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, p_expected_evidence_revision, p_evidence_manifest_sha256);
  SELECT * INTO submission FROM public.product_submissions
  WHERE id = p_submission_id;
  IF submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'submission is already resolved' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.product_submission_reviewer_drafts AS existing (
    submission_id, reviewer_id, evidence_revision, evidence_manifest_sha256,
    payload, payload_canonical, payload_sha256
  ) VALUES (
    p_submission_id, v_reviewer_id, p_expected_evidence_revision,
    p_evidence_manifest_sha256, p_payload, p_payload_canonical, p_payload_sha256
  )
  ON CONFLICT (submission_id, reviewer_id) DO UPDATE SET
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
    payload = EXCLUDED.payload,
    payload_canonical = EXCLUDED.payload_canonical,
    payload_sha256 = EXCLUDED.payload_sha256,
    updated_at = now()
  -- An unchanged save is not an edit. Leaving the row untouched keeps
  -- updated_at meaningful and avoids waking concurrent readers for nothing.
  WHERE existing.payload_sha256 IS DISTINCT FROM EXCLUDED.payload_sha256
     OR existing.evidence_revision IS DISTINCT FROM EXCLUDED.evidence_revision
     OR existing.evidence_manifest_sha256
        IS DISTINCT FROM EXCLUDED.evidence_manifest_sha256;

  RETURN public.product_submission_reviewer_state_internal(
    p_submission_id, v_reviewer_id);
END $$;

CREATE OR REPLACE FUNCTION public.assert_product_submission_reviewer() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE reviewer uuid:=auth.uid();
BEGIN
 PERFORM public.reject_oauth_client_request();
 IF reviewer IS NULL OR NOT EXISTS(SELECT 1 FROM public.product_submission_reviewers r WHERE r.user_id=reviewer) THEN
  RAISE EXCEPTION 'reviewer access required' USING ERRCODE='42501'; END IF;
 RETURN reviewer;
END $$;
REVOKE ALL ON FUNCTION public.assert_product_submission_reviewer() FROM PUBLIC,anon,authenticated,service_role;

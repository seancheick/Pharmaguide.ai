-- Submission foundations (Batch 1, 2026-09-09):
--   1. consent is recorded server-side at creation;
--   2. evidence is versioned by immutable revisions — a retake appends photos
--      under a new revision, never rewrites or deletes the originals;
--   3. draft recording derives the reviewer from auth.uid() and the DB
--      allowlist (the previous signature trusted a caller-supplied id and was
--      executable by service_role) and carries usage and the revision.
-- Additive only. No historical row, event, or photo is rewritten.

-- ---------------------------------------------------------------------------
-- 1. Consent recorded at creation.
-- ---------------------------------------------------------------------------

ALTER TABLE public.product_submissions
  ADD COLUMN consent_version text
    CHECK (consent_version IS NULL OR consent_version ~ '^[A-Za-z0-9._-]{1,80}$'),
  ADD COLUMN consented_at timestamptz
    CHECK ((consent_version IS NULL) = (consented_at IS NULL));

-- ---------------------------------------------------------------------------
-- 2. Evidence revisions.
-- ---------------------------------------------------------------------------

ALTER TABLE public.product_submissions
  ADD COLUMN evidence_revision integer NOT NULL DEFAULT 1
    CHECK (evidence_revision >= 1),
  ADD COLUMN evidence_revision_opened_at timestamptz,
  ADD COLUMN evidence_ready_at timestamptz;

ALTER TABLE public.product_submission_photos
  ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision >= 1);

-- A retake revision may add photos beyond the first upload's eight.
ALTER TABLE public.product_submission_photos
  DROP CONSTRAINT product_submission_photos_seq_check;
ALTER TABLE public.product_submission_photos
  ADD CONSTRAINT product_submission_photos_seq_check CHECK (seq BETWEEN 1 AND 12);

ALTER TABLE public.product_submission_extractions
  ADD COLUMN actor_kind text NOT NULL DEFAULT 'reviewer'
    CHECK (actor_kind IN ('reviewer', 'worker')),
  ADD COLUMN evidence_revision integer
    CHECK (evidence_revision IS NULL OR evidence_revision >= 1);

-- One owner for photo-manifest validation and insertion, shared by the first
-- upload and by later revisions. Replay of an identical manifest is
-- idempotent; a differing manifest for an already-persisted photo conflicts.
CREATE FUNCTION public.insert_product_submission_photos_internal(
  p_submission_id uuid,
  p_user_id uuid,
  p_photos jsonb,
  p_revision integer,
  p_seq_floor integer,
  p_max_total integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  photo jsonb;
  photo_count integer;
  photo_id_value uuid;
  photo_seq_value integer;
  photo_categories public.product_submission_evidence_category[];
BEGIN
  IF jsonb_typeof(p_photos) <> 'array' OR jsonb_array_length(p_photos) > 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  photo_count := jsonb_array_length(p_photos);

  FOR photo IN SELECT value FROM jsonb_array_elements(p_photos)
  LOOP
    IF jsonb_typeof(photo) <> 'object'
       OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(photo) key)
          IS DISTINCT FROM ARRAY[
            'byte_size',
            'categories',
            'content_sha256',
            'content_type',
            'photo_id',
            'seq'
          ]::text[] THEN
      RAISE EXCEPTION 'invalid photo manifest entry'
        USING ERRCODE = '22023';
    END IF;

    BEGIN
      photo_id_value := (photo->>'photo_id')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid photo id' USING ERRCODE = '22023';
    END;

    IF jsonb_typeof(photo->'seq') <> 'number' THEN
      RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
    END IF;
    photo_seq_value := (photo->>'seq')::numeric::integer;
    IF (photo->>'seq')::numeric <> photo_seq_value
       OR photo_seq_value NOT BETWEEN p_seq_floor + 1 AND p_max_total THEN
      RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
    END IF;

    IF jsonb_typeof(photo->'categories') <> 'array' THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END IF;
    BEGIN
      SELECT array_agg(
        DISTINCT item.value::public.product_submission_evidence_category
        ORDER BY item.value::public.product_submission_evidence_category
      )
        INTO photo_categories
      FROM jsonb_array_elements_text(photo->'categories') AS item(value);
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END;
    IF coalesce(cardinality(photo_categories), 0) NOT BETWEEN 1 AND 6
       OR jsonb_array_length(photo->'categories')
         <> cardinality(photo_categories) THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.product_submission_photos (
      submission_id,
      user_id,
      photo_id,
      seq,
      categories,
      object_path,
      content_type,
      byte_size,
      content_sha256,
      revision
    ) VALUES (
      p_submission_id,
      p_user_id,
      photo_id_value,
      photo_seq_value,
      photo_categories,
      p_user_id::text || '/' || p_submission_id::text || '/'
        || photo_id_value::text,
      photo->>'content_type',
      (photo->>'byte_size')::bigint,
      photo->>'content_sha256',
      p_revision
    )
    ON CONFLICT (submission_id, photo_id) DO NOTHING;
  END LOOP;

  -- Every manifest photo must be persisted exactly as sent, in this revision;
  -- this revision must hold exactly the manifest's photos; the total stays
  -- within the cap.
  IF (
    SELECT count(*)
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = p_user_id
      AND persisted_photo.revision = p_revision
  ) <> photo_count
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_photos) AS expected_photo(value)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS persisted_photo
      WHERE persisted_photo.submission_id = p_submission_id
        AND persisted_photo.user_id = p_user_id
        AND persisted_photo.revision = p_revision
        AND persisted_photo.photo_id =
          (expected_photo.value->>'photo_id')::uuid
        AND persisted_photo.seq =
          (expected_photo.value->>'seq')::numeric::integer
        AND persisted_photo.categories = (
          SELECT array_agg(
            DISTINCT item.value
              ::public.product_submission_evidence_category
            ORDER BY item.value
              ::public.product_submission_evidence_category
          )
          FROM jsonb_array_elements_text(
            expected_photo.value->'categories'
          ) AS item(value)
        )
        AND persisted_photo.content_type =
          expected_photo.value->>'content_type'
        AND persisted_photo.byte_size =
          (expected_photo.value->>'byte_size')::bigint
        AND persisted_photo.content_sha256 IS NOT DISTINCT FROM
          expected_photo.value->>'content_sha256'
    )
  ) THEN
    RAISE EXCEPTION 'submission photo replay conflict'
      USING ERRCODE = '23505';
  END IF;

  IF (
    SELECT count(*)
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
  ) > p_max_total THEN
    RAISE EXCEPTION 'too many photos' USING ERRCODE = '22023';
  END IF;

  -- Sequence numbers of this revision are exactly floor+1..floor+N, no holes.
  IF photo_count > 0 AND (
    SELECT count(DISTINCT persisted_photo.seq) <> photo_count
        OR min(persisted_photo.seq) <> p_seq_floor + 1
        OR max(persisted_photo.seq) <> p_seq_floor + photo_count
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = p_user_id
      AND persisted_photo.revision = p_revision
  ) THEN
    RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.insert_product_submission_photos_internal(
  uuid, uuid, jsonb, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;

-- First upload: same contract as before, photo handling moved to the helper.
CREATE OR REPLACE FUNCTION public.create_product_submission_v2_internal(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb
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
  IF jsonb_typeof(p_photos) <> 'array' OR jsonb_array_length(p_photos) > 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[^0-9]',
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
    IF normalized_upc_value IS NULL OR p_mismatch_detail IS NOT NULL THEN
      RAISE EXCEPTION 'invalid missing-product payload'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF p_mismatch_detail IS NULL
       OR jsonb_typeof(p_mismatch_detail) <> 'object' THEN
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
    IF jsonb_typeof(p_mismatch_detail->'mismatch_categories') <> 'array' THEN
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
    declared_no_separate_ingredient_panel
  ) VALUES (
    p_submission_id,
    caller_id,
    p_kind,
    normalized_upc_value,
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

  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    1,
    0,
    8
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

-- Public wrapper: lineage handling unchanged from the intake migration; the
-- consent version the app attests is recorded once, at first creation.
DROP FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb,
  uuid
);

CREATE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_resubmission_of uuid DEFAULT NULL,
  p_consent_version text DEFAULT NULL
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
  END IF;

  RETURN result_value;
END;
$$;

REVOKE ALL ON FUNCTION public.create_product_submission(
  uuid, public.product_submission_kind, text, jsonb, boolean, jsonb, uuid, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission(
  uuid, public.product_submission_kind, text, jsonb, boolean, jsonb, uuid, text
) TO authenticated;

-- Open the next evidence revision on an open, finalized submission. The row,
-- its lineage and every earlier photo stay; the submission returns to
-- `pending` until the new revision is finalized. Replay returns the revision
-- already opened.
CREATE FUNCTION public.open_product_submission_evidence_revision(
  p_submission_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
BEGIN
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
  IF submission.upload_state = 'pending' AND submission.evidence_revision > 1 THEN
    RETURN submission.evidence_revision;
  END IF;
  IF submission.upload_state <> 'ready'
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submissions
  SET upload_state = 'pending',
      evidence_revision = submission.evidence_revision + 1,
      evidence_revision_opened_at = now()
  WHERE id = p_submission_id;
  RETURN submission.evidence_revision + 1;
END;
$$;

REVOKE ALL ON FUNCTION public.open_product_submission_evidence_revision(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.open_product_submission_evidence_revision(uuid)
  TO authenticated;

-- Append photos to the open revision. Sequence numbers continue after the
-- existing photos; bytes identical to an earlier photo are rejected by the
-- existing per-submission sha256 uniqueness.
CREATE FUNCTION public.add_product_submission_evidence(
  p_submission_id uuid,
  p_photos jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  seq_floor integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_photos) <> 'array' OR jsonb_array_length(p_photos) = 0 THEN
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
  IF submission.upload_state <> 'pending'
     OR submission.evidence_revision < 2
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open evidence revision required' USING ERRCODE = '55000';
  END IF;
  SELECT coalesce(max(photo.seq), 0)
    INTO seq_floor
  FROM public.product_submission_photos AS photo
  WHERE photo.submission_id = p_submission_id
    AND photo.revision < submission.evidence_revision;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    submission.evidence_revision,
    seq_floor,
    12
  );
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.add_product_submission_evidence(uuid, jsonb)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_product_submission_evidence(uuid, jsonb)
  TO authenticated;

-- Finalize: unchanged rules; the first submission time is kept across
-- revisions and the revision's ready time is recorded.
CREATE OR REPLACE FUNCTION public.finalize_product_submission(
  p_submission_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  current_upload_state public.product_submission_upload_state;
  submission public.product_submissions%ROWTYPE;
BEGIN
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
  current_upload_state := submission.upload_state;
  IF current_upload_state = 'ready' THEN
    RETURN true;
  END IF;
  IF current_upload_state <> 'pending' THEN
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

  UPDATE public.product_submissions
  SET upload_state = 'ready',
      submitted_at = coalesce(submitted_at, now()),
      evidence_ready_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id
    AND upload_state = 'pending';
  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Draft recording: the reviewer is who the database says is calling.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric
) FROM PUBLIC, anon, authenticated, service_role;
DROP FUNCTION public.record_product_submission_extraction(
  uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric
);

CREATE FUNCTION public.record_product_submission_extraction(
  p_submission_id uuid,
  p_schema_version text,
  p_provider text,
  p_model text,
  p_prompt_version text,
  p_input_image_hashes jsonb,
  p_draft_payload jsonb,
  p_field_provenance jsonb,
  p_confidence numeric DEFAULT NULL,
  p_usage jsonb DEFAULT NULL,
  p_evidence_revision integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  next_version integer;
  submission public.product_submissions%ROWTYPE;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF p_usage IS NOT NULL AND jsonb_typeof(p_usage) <> 'object' THEN
    RAISE EXCEPTION 'invalid extraction usage' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_draft_payload) <> 'object'
     OR jsonb_typeof(p_field_provenance) <> 'object'
     OR jsonb_typeof(p_input_image_hashes) <> 'object' THEN
    RAISE EXCEPTION 'invalid extraction payload' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.upload_state <> 'ready'
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required'
      USING ERRCODE = '55000';
  END IF;
  IF p_evidence_revision IS NOT NULL
     AND p_evidence_revision <> submission.evidence_revision THEN
    RAISE EXCEPTION 'extraction evidence revision is stale'
      USING ERRCODE = '22023';
  END IF;
  IF p_input_image_hashes IS DISTINCT FROM (
    SELECT coalesce(
      jsonb_object_agg(
        photo.photo_id::text,
        photo.content_sha256
        ORDER BY photo.photo_id::text
      ),
      '{}'::jsonb
    )
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
  ) THEN
    RAISE EXCEPTION 'extraction image hashes do not match'
      USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(max(extraction.version), 0) + 1
    INTO next_version
  FROM public.product_submission_extractions AS extraction
  WHERE extraction.submission_id = p_submission_id;
  INSERT INTO public.product_submission_extractions (
    submission_id,
    recorded_by,
    version,
    schema_version,
    provider,
    model,
    prompt_version,
    input_image_hashes,
    draft_payload,
    field_provenance,
    confidence,
    usage,
    actor_kind,
    evidence_revision
  ) VALUES (
    p_submission_id,
    reviewer_id,
    next_version,
    btrim(p_schema_version),
    btrim(p_provider),
    btrim(p_model),
    btrim(p_prompt_version),
    p_input_image_hashes,
    p_draft_payload,
    p_field_provenance,
    p_confidence,
    p_usage,
    'reviewer',
    submission.evidence_revision
  );
  RETURN next_version;
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. A submission whose retake revision is still uploading is still open:
--    the duplicate guard and the intake must count it, or a second attempt
--    for the same barcode could be created during the retake.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reject_duplicate_open_submission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.normalized_upc IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.product_submissions AS existing
    WHERE existing.id <> NEW.id
      AND existing.user_id = NEW.user_id
      AND existing.kind = NEW.kind
      AND lpad(existing.normalized_upc, 14, '0') = lpad(NEW.normalized_upc, 14, '0')
      AND (existing.upload_state = 'ready' OR existing.evidence_revision > 1)
      AND existing.promoted_at IS NULL
      AND existing.review_status IN ('submitted', 'under_review', 'approved')
  ) THEN
    RAISE EXCEPTION
      'open submission already exists for this barcode '
      '(idx_product_submissions_user_open_upc)'
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP INDEX public.idx_product_submissions_user_open_upc;
CREATE UNIQUE INDEX idx_product_submissions_user_open_upc
  ON public.product_submissions (user_id, kind, (lpad(normalized_upc, 14, '0')))
  WHERE normalized_upc IS NOT NULL
    AND promoted_at IS NULL
    AND (upload_state = 'ready' OR evidence_revision > 1)
    AND review_status IN ('submitted', 'under_review', 'approved');

-- Intake reports the revision so the app can resume a retake instead of
-- treating it as a never-finished first upload.
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
    action_value := 'resume_evidence_revision';
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

  -- The receipt stays minimal (Codex's intake contract); the revision number
  -- is added only when the caller must resume an open evidence revision.
  RETURN jsonb_build_object(
    'action', action_value,
    'submission_id', candidate.id,
    'normalized_upc', candidate.normalized_upc,
    'resolution_code', candidate.resolution_code,
    'resolution_detail', candidate.resolution_detail
  ) || CASE WHEN action_value = 'resume_evidence_revision'
    THEN jsonb_build_object('evidence_revision', candidate.evidence_revision)
    ELSE '{}'::jsonb END;
END;
$$;

-- Product submission evidence + resolution v2 (2026-08-24)
--
-- Clean-break rebuild of the submission evidence model and addition of the
-- user-facing resolution contract. Safe because production holds zero
-- submissions, photos, stored objects, and review events (verified live
-- 2026-08-24) and the app is not yet store-released.
--
-- Changes:
--   1. Evidence photos v2: photo_id identity (1..8 photos), seq ordering,
--      typed evidence categories replacing the 3-slot model.
--   2. Resolution contract: resolution_code / resolution_detail /
--      resolved_dsld_id on product_submissions (+ review-event mirrors).
--   3. "No separate Other Ingredients panel" becomes a reviewer cue on the
--      submission (declared_no_separate_ingredient_panel), NOT evidence.
--   4. mark_product_submission_promoted gains p_resolved_dsld_id and
--      cascades promotion to duplicate submissions.
--   5. Durable submission push queue written in-transaction by
--      review_product_submission; drained by the review Edge Function.
--
-- The legacy migration 20260731144527 is never edited or re-run; this file
-- performs its own DROP/CREATE ladder. All statements run in one transaction.

-- ---------------------------------------------------------------------------
-- 1. New enum types
-- ---------------------------------------------------------------------------

CREATE TYPE public.product_submission_evidence_category AS ENUM (
  'front_identity',
  'supplement_facts',
  'ingredient_disclosure',
  'directions_warnings',
  'barcode',
  'lot_expiry'
);

CREATE TYPE public.product_submission_resolution_code AS ENUM (
  'photo_quality',
  'missing_panel',
  'label_unreadable',
  'not_a_supplement',
  'already_in_catalog',
  'duplicate_submission',
  'other'
);

REVOKE ALL ON TYPE public.product_submission_evidence_category
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TYPE public.product_submission_resolution_code
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_evidence_category
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_resolution_code
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Drop SQL-language functions that hard-depend on the photos table or the
--    missing-details column being removed. (plpgsql bodies are late-bound and
--    survive; LANGUAGE sql bodies create pg_depend entries and must go first.)
-- ---------------------------------------------------------------------------

DROP FUNCTION public.product_submission_has_required_missing_evidence(uuid, uuid);
DROP FUNCTION public.list_product_submission_objects_for_user(uuid);

-- ---------------------------------------------------------------------------
-- 3. Submission envelope: reviewer cue + resolution columns + constraint
--    updates.
-- ---------------------------------------------------------------------------

ALTER TABLE public.product_submissions
  ADD COLUMN declared_no_separate_ingredient_panel boolean NOT NULL DEFAULT false,
  ADD COLUMN resolution_code public.product_submission_resolution_code,
  ADD COLUMN resolution_detail text
    CHECK (
      resolution_detail IS NULL
      OR char_length(resolution_detail) BETWEEN 1 AND 280
    ),
  ADD COLUMN resolved_dsld_id text
    CHECK (
      resolved_dsld_id IS NULL
      OR resolved_dsld_id ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'
    );

-- Resolution fields only exist on reviewed-negative states; detail never
-- exists without a code. Status-conditional *requirements* live in the RPC.
ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submissions_resolution_consistent CHECK (
    (resolution_detail IS NULL OR resolution_code IS NOT NULL)
    AND (
      resolution_code IS NULL
      OR review_status IN ('rejected', 'duplicate')
    )
  ),
  ADD CONSTRAINT product_submissions_resolved_dsld_consistent CHECK (
    resolved_dsld_id IS NULL
    OR review_status IN ('approved', 'duplicate')
  );

-- Promotion now also stamps duplicate submissions (cascade), so the
-- promotion-consistency constraint widens from approved-only.
ALTER TABLE public.product_submissions
  DROP CONSTRAINT product_submissions_promotion_consistent;
ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submissions_promotion_consistent CHECK (
    (
      promoted_catalog_version IS NULL
      AND promoted_at IS NULL
    )
    OR (
      review_status IN ('approved', 'duplicate')
      AND promoted_catalog_version IS NOT NULL
      AND promoted_at IS NOT NULL
    )
  );

-- GTIN lengths are exactly {8,12,13,14}; the old CHECK admitted 9-11 digit
-- values no validator accepts.
ALTER TABLE public.product_submissions
  DROP CONSTRAINT product_submissions_normalized_upc_check;
ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submissions_normalized_upc_check CHECK (
    normalized_upc IS NULL
    OR normalized_upc ~ '^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$'
  );

ALTER TABLE public.product_submission_review_events
  ADD COLUMN resolution_code public.product_submission_resolution_code,
  ADD COLUMN resolved_dsld_id text
    CHECK (
      resolved_dsld_id IS NULL
      OR resolved_dsld_id ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'
    );

-- The old evidence flag moves onto the envelope as a reviewer cue.
ALTER TABLE public.product_submission_missing_details
  DROP COLUMN other_ingredients_not_present;

-- ---------------------------------------------------------------------------
-- 4. Photos v2 rebuild. Storage policies reference the table in EXISTS
--    clauses (pg_depend), so they drop first and are recreated verbatim
--    afterwards.
-- ---------------------------------------------------------------------------

DROP POLICY "product_submission_objects_select_own" ON storage.objects;
DROP POLICY "product_submission_objects_insert_own" ON storage.objects;
DROP POLICY "product_submission_objects_update_own" ON storage.objects;
DROP POLICY "product_submission_objects_delete_own" ON storage.objects;

DROP TABLE public.product_submission_photos;
DROP TYPE public.product_submission_photo_slot;

CREATE TABLE public.product_submission_photos (
  submission_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_id uuid NOT NULL,
  seq smallint NOT NULL CHECK (seq BETWEEN 1 AND 8),
  categories public.product_submission_evidence_category[] NOT NULL
    CHECK (cardinality(categories) BETWEEN 1 AND 6),
  object_path text NOT NULL,
  content_type text NOT NULL
    CHECK (
      content_type IN (
        'image/jpeg',
        'image/png',
        'image/heic',
        'image/heif',
        'image/webp'
      )
    ),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 15728640),
  content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (submission_id, photo_id),
  CONSTRAINT product_submission_photos_seq_unique
    UNIQUE (submission_id, seq),
  CONSTRAINT product_submission_photos_sha_unique
    UNIQUE (submission_id, content_sha256),
  CONSTRAINT product_submission_photos_owner_fkey
    FOREIGN KEY (submission_id, user_id)
    REFERENCES public.product_submissions(id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT product_submission_photos_object_path_check CHECK (
    object_path = user_id::text || '/' || submission_id::text || '/'
      || photo_id::text
  )
);

CREATE UNIQUE INDEX idx_product_submission_photo_path
  ON public.product_submission_photos (object_path);

-- DROP TABLE discarded the legacy RLS state and owner policy; the rebuilt
-- table must re-enable both or GRANT SELECT would expose every user's
-- manifest to any authenticated caller.
ALTER TABLE public.product_submission_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_photos FORCE ROW LEVEL SECURITY;
CREATE POLICY "product_submission_photos_select_own"
  ON public.product_submission_photos
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- The manifest-close trigger function survived (plpgsql, no column refs
-- beyond submission_id/user_id); reattach it to the rebuilt table.
CREATE TRIGGER product_submission_photo_pending
  AFTER INSERT ON public.product_submission_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_product_submission_photo_pending();

-- ---------------------------------------------------------------------------
-- 5. Durable submission push queue. Written in-transaction by
--    review_product_submission; drained (SELECT/UPDATE) by the review Edge
--    Function under EdgeRuntime.waitUntil. Zero policies: service_role and
--    the SECURITY DEFINER owner are the only actors.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_push_deliveries (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_status public.product_submission_review_status NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error text
    CHECK (last_error IS NULL OR char_length(last_error) <= 500)
);

CREATE INDEX idx_product_submission_push_pending
  ON public.product_submission_push_deliveries (created_at)
  WHERE sent_at IS NULL;

ALTER TABLE public.product_submission_push_deliveries
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_push_deliveries
  FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_push_deliveries
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, UPDATE ON TABLE public.product_submission_push_deliveries
  TO service_role;

-- ---------------------------------------------------------------------------
-- 6. Evidence coverage v2. A missing_product submission must photograph the
--    front identity, the Supplement Facts panel, and the complete ingredient
--    disclosure; one photo may satisfy several categories.
--    label_mismatch keeps its legacy contract (details row required, photos
--    optional) — enforced in finalize below, not here.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_has_required_evidence(
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
    SELECT count(DISTINCT category) = 3
    FROM public.product_submission_photos AS photo,
         unnest(photo.categories) AS category
    WHERE photo.submission_id = p_submission_id
      AND photo.user_id = p_user_id
      AND category IN (
        'front_identity',
        'supplement_facts',
        'ingredient_disclosure'
      )
  );
$$;

CREATE FUNCTION public.list_product_submission_objects_for_user(
  p_user_id uuid
)
RETURNS TABLE (object_path text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT photo.object_path
  FROM public.product_submission_photos AS photo
  WHERE photo.user_id = p_user_id
  ORDER BY photo.object_path;
$$;

-- ---------------------------------------------------------------------------
-- 7. create_product_submission v2. Signature changes (cue param rename), so
--    the old function is dropped by exact signature and recreated.
-- ---------------------------------------------------------------------------

DROP FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
);

CREATE FUNCTION public.create_product_submission(
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
  photo jsonb;
  detail_keys text[];
  category_values public.label_mismatch_category[];
  photo_count integer;
  photo_id_value uuid;
  photo_seq_value integer;
  photo_categories public.product_submission_evidence_category[];
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
  photo_count := jsonb_array_length(p_photos);

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
     OR persisted.review_status <> 'submitted' THEN
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
       OR photo_seq_value NOT BETWEEN 1 AND 8 THEN
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
      content_sha256
    ) VALUES (
      p_submission_id,
      caller_id,
      photo_id_value,
      photo_seq_value,
      photo_categories,
      caller_id::text || '/' || p_submission_id::text || '/'
        || photo_id_value::text,
      photo->>'content_type',
      (photo->>'byte_size')::bigint,
      photo->>'content_sha256'
    )
    ON CONFLICT (submission_id, photo_id) DO NOTHING;
  END LOOP;

  IF (
    SELECT count(*)
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = caller_id
  ) <> photo_count
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_photos) AS expected_photo(value)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS persisted_photo
      WHERE persisted_photo.submission_id = p_submission_id
        AND persisted_photo.user_id = caller_id
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

  -- Sequence numbers must be exactly 1..N with no holes.
  IF photo_count > 0 AND (
    SELECT count(DISTINCT persisted_photo.seq) <> photo_count
        OR min(persisted_photo.seq) <> 1
        OR max(persisted_photo.seq) <> photo_count
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = caller_id
  ) THEN
    RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
  END IF;

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

-- ---------------------------------------------------------------------------
-- 8. finalize_product_submission: unified evidence rule for missing_product;
--    label_mismatch contract unchanged; storage cross-check unchanged.
-- ---------------------------------------------------------------------------

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
      submitted_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id
    AND upload_state = 'pending';
  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. record_product_submission_extraction: hash map keyed by photo_id.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_product_submission_extraction(
  p_submission_id uuid,
  p_recorded_by uuid,
  p_schema_version text,
  p_provider text,
  p_model text,
  p_prompt_version text,
  p_input_image_hashes jsonb,
  p_draft_payload jsonb,
  p_field_provenance jsonb,
  p_confidence numeric DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  next_version integer;
  submission public.product_submissions%ROWTYPE;
BEGIN
  IF p_recorded_by IS NULL THEN
    RAISE EXCEPTION 'reviewer identity required' USING ERRCODE = '22023';
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
    confidence
  ) VALUES (
    p_submission_id,
    p_recorded_by,
    next_version,
    btrim(p_schema_version),
    btrim(p_provider),
    btrim(p_model),
    btrim(p_prompt_version),
    p_input_image_hashes,
    p_draft_payload,
    p_field_provenance,
    p_confidence
  );
  RETURN next_version;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. review_product_submission v2: resolution contract + durable push row.
-- ---------------------------------------------------------------------------

DROP FUNCTION public.review_product_submission(
  uuid,
  uuid,
  public.product_submission_review_status,
  text,
  text,
  jsonb,
  text,
  text,
  uuid
);

CREATE FUNCTION public.review_product_submission(
  p_submission_id uuid,
  p_reviewer_id uuid,
  p_to_status public.product_submission_review_status,
  p_review_notes text DEFAULT NULL,
  p_approved_schema_version text DEFAULT NULL,
  p_approved_payload jsonb DEFAULT NULL,
  p_approved_payload_canonical text DEFAULT NULL,
  p_payload_sha256 text DEFAULT NULL,
  p_duplicate_of uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_detail text DEFAULT NULL,
  p_resolved_dsld_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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

  -- Resolution field parsing and sanitization (control chars stripped;
  -- consumer copy renders resolution_detail verbatim).
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

  -- Status-conditional resolution requirements.
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
  ELSE  -- duplicate
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
          AND target.normalized_upc = submission.normalized_upc
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
    IF submission.kind = 'label_mismatch' THEN
      SELECT 'label_mismatch:' || mismatch.dsld_id
        INTO review_target_key
      FROM public.product_submission_mismatch_details AS mismatch
      WHERE mismatch.submission_id = p_submission_id;
    ELSE
      review_target_key := 'missing_product:' || submission.normalized_upc;
    END IF;
    IF NULLIF(review_target_key, '') IS NULL THEN
      RAISE EXCEPTION 'review target identity is unavailable'
        USING ERRCODE = '55000';
    END IF;

    -- Serialize approvals for one catalog identity. The partial uniqueness
    -- spans a typed detail table, so an advisory transaction lock provides
    -- the database-level race boundary that a pre-insert SELECT alone cannot.
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(review_target_key, 0)
    );
    IF EXISTS (
      SELECT 1
      FROM public.product_submissions AS other
      LEFT JOIN public.product_submission_mismatch_details AS other_mismatch
        ON other_mismatch.submission_id = other.id
      WHERE other.id <> p_submission_id
        AND other.review_status = 'approved'
        AND other.promoted_at IS NULL
        AND (
          CASE other.kind
            WHEN 'label_mismatch' THEN
              'label_mismatch:' || other_mismatch.dsld_id
            ELSE 'missing_product:' || other.normalized_upc
          END
        ) = review_target_key
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

  -- Durable push-delivery record: committed with the transition so the
  -- Edge Function's post-response send can never lose the event.
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
$$;

-- ---------------------------------------------------------------------------
-- 11. mark_product_submission_promoted v2: stamps resolved_dsld_id and
--     cascades promotion to duplicate submissions.
-- ---------------------------------------------------------------------------

DROP FUNCTION public.mark_product_submission_promoted(uuid, text);

CREATE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid,
  p_catalog_version text,
  p_resolved_dsld_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  catalog_version_value text := btrim(coalesce(p_catalog_version, ''));
  resolved_dsld_value text := btrim(coalesce(p_resolved_dsld_id, ''));
  target_promoted boolean := false;
BEGIN
  IF catalog_version_value = '' THEN
    RAISE EXCEPTION 'catalog version required' USING ERRCODE = '22023';
  END IF;
  IF resolved_dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid resolved product id' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.id = p_submission_id
      AND submission.promoted_catalog_version IS NOT NULL
      AND (
        submission.promoted_catalog_version <> catalog_version_value
        OR submission.resolved_dsld_id IS DISTINCT FROM resolved_dsld_value
      )
  ) THEN
    RAISE EXCEPTION 'submission already promoted with a different catalog identity'
      USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.id = p_submission_id
      AND submission.promoted_catalog_version = catalog_version_value
      AND submission.resolved_dsld_id = resolved_dsld_value
  ) THEN
    target_promoted := true;
  ELSE
    UPDATE public.product_submissions
    SET promoted_catalog_version = catalog_version_value,
        promoted_at = now(),
        resolved_dsld_id = resolved_dsld_value
    WHERE id = p_submission_id
      AND review_status = 'approved'
      AND upload_state = 'ready'
      AND promoted_catalog_version IS NULL;
    target_promoted := FOUND;
  END IF;

  -- Cascade to duplicates of the promoted target so their submitters see
  -- the released product instead of a permanent "on the way". Runs on the
  -- idempotent path too, completing any partial earlier run.
  IF target_promoted THEN
    UPDATE public.product_submissions
    SET resolved_dsld_id = coalesce(resolved_dsld_id, resolved_dsld_value),
        promoted_catalog_version = catalog_version_value,
        promoted_at = now()
    WHERE duplicate_of = p_submission_id
      AND review_status = 'duplicate'
      AND promoted_catalog_version IS NULL;
  END IF;

  RETURN target_promoted;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Grants for every new or signature-changed object.
-- ---------------------------------------------------------------------------

GRANT SELECT ON TABLE public.product_submission_photos TO authenticated;
GRANT SELECT ON TABLE public.product_submission_photos TO service_role;

REVOKE ALL ON FUNCTION
  public.product_submission_has_required_evidence(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) TO authenticated;

REVOKE ALL ON FUNCTION public.finalize_product_submission(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission(uuid)
  TO authenticated;

REVOKE ALL ON FUNCTION public.review_product_submission(
  uuid,
  uuid,
  public.product_submission_review_status,
  text,
  text,
  jsonb,
  text,
  text,
  uuid,
  text,
  text,
  text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
  uuid,
  uuid,
  public.product_submission_review_status,
  text,
  text,
  jsonb,
  text,
  text,
  uuid,
  text,
  text,
  text
) TO service_role;

REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb,
  numeric
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_extraction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb,
  numeric
) TO service_role;

REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(
  uuid,
  text,
  text
)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_product_submission_promoted(
  uuid,
  text,
  text
)
  TO service_role;

REVOKE ALL ON FUNCTION
  public.list_product_submission_objects_for_user(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 13. Recreate the four storage policies with predicates identical to the
--     legacy migration (paths now end in photo_id, which changes no policy
--     text: they match on object_path equality, not slot names).
-- ---------------------------------------------------------------------------

CREATE POLICY "product_submission_objects_select_own"
  ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'product-submission-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      WHERE photo.object_path = name
        AND photo.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "product_submission_objects_insert_own"
  ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-submission-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      JOIN public.product_submissions AS submission
        ON submission.id = photo.submission_id
       AND submission.user_id = photo.user_id
      WHERE photo.object_path = name
        AND photo.user_id = (SELECT auth.uid())
        AND submission.upload_state = 'pending'
    )
  );

CREATE POLICY "product_submission_objects_update_own"
  ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'product-submission-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      JOIN public.product_submissions AS submission
        ON submission.id = photo.submission_id
       AND submission.user_id = photo.user_id
      WHERE photo.object_path = name
        AND photo.user_id = (SELECT auth.uid())
        AND submission.upload_state = 'pending'
    )
  )
  WITH CHECK (
    bucket_id = 'product-submission-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      JOIN public.product_submissions AS submission
        ON submission.id = photo.submission_id
       AND submission.user_id = photo.user_id
      WHERE photo.object_path = name
        AND photo.user_id = (SELECT auth.uid())
        AND submission.upload_state = 'pending'
    )
  );

CREATE POLICY "product_submission_objects_delete_own"
  ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-submission-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      JOIN public.product_submissions AS submission
        ON submission.id = photo.submission_id
       AND submission.user_id = photo.user_id
      WHERE photo.object_path = name
        AND photo.user_id = (SELECT auth.uid())
        AND submission.upload_state = 'pending'
    )
  );

-- =============================================================================
-- Unified, private product-submission evidence pipeline
-- =============================================================================
-- One append-only user submission spine serves both catalog-label mismatch
-- reports and missing-product evidence. The app can submit evidence; only the
-- service-held review boundary can change editorial state or publish data.
--
-- The preceding 20260719 migration may already exist in a deployed database.
-- This migration therefore copies any legacy rows before retiring that schema.
-- Legacy Storage objects cannot be moved safely with SQL (Supabase Storage must
-- be mutated through its API), so deployment fails closed if any are present.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TYPE public.product_submission_kind AS ENUM (
  'label_mismatch',
  'missing_product'
);

CREATE TYPE public.product_submission_upload_state AS ENUM (
  'pending',
  'ready',
  'cleaning'
);

CREATE TYPE public.product_submission_review_status AS ENUM (
  'submitted',
  'under_review',
  'approved',
  'rejected',
  'duplicate'
);

CREATE TYPE public.product_submission_photo_slot AS ENUM (
  'front',
  'supplement_facts',
  'other_ingredients'
);

CREATE TABLE public.product_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind public.product_submission_kind NOT NULL,
  normalized_upc text
    CHECK (
      normalized_upc IS NULL
      OR normalized_upc ~ '^[0-9]{8,14}$'
    ),
  upload_state public.product_submission_upload_state
    NOT NULL DEFAULT 'pending',
  review_status public.product_submission_review_status
    NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  promoted_catalog_version text
    CHECK (
      promoted_catalog_version IS NULL
      OR btrim(promoted_catalog_version) <> ''
    ),
  promoted_at timestamptz,
  duplicate_of uuid REFERENCES public.product_submissions(id),
  cleanup_claimed_at timestamptz,
  evidence_purged_at timestamptz,
  CONSTRAINT product_submissions_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT product_submissions_missing_upc_required CHECK (
    kind <> 'missing_product' OR normalized_upc IS NOT NULL
  ),
  CONSTRAINT product_submissions_review_fields_consistent CHECK (
    (
      review_status = 'submitted'
      AND reviewed_at IS NULL
      AND reviewed_by IS NULL
    )
    OR (
      review_status <> 'submitted'
      AND reviewed_at IS NOT NULL
      AND reviewed_by IS NOT NULL
    )
  ),
  CONSTRAINT product_submissions_duplicate_consistent CHECK (
    (review_status = 'duplicate') = (duplicate_of IS NOT NULL)
  ),
  CONSTRAINT product_submissions_promotion_consistent CHECK (
    (
      promoted_catalog_version IS NULL
      AND promoted_at IS NULL
    )
    OR (
      review_status = 'approved'
      AND promoted_catalog_version IS NOT NULL
      AND promoted_at IS NOT NULL
    )
  ),
  CONSTRAINT product_submissions_cleanup_consistent CHECK (
    upload_state <> 'cleaning' OR cleanup_claimed_at IS NOT NULL
  )
);

CREATE TABLE public.product_submission_mismatch_details (
  submission_id uuid PRIMARY KEY
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dsld_id text NOT NULL CHECK (btrim(dsld_id) <> ''),
  source_record_id text
    CHECK (source_record_id IS NULL OR btrim(source_record_id) <> ''),
  catalog_source_version text
    CHECK (
      catalog_source_version IS NULL
      OR btrim(catalog_source_version) <> ''
    ),
  formula_fingerprint text
    CHECK (
      formula_fingerprint IS NULL
      OR formula_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  mismatch_categories public.label_mismatch_category[] NOT NULL
    CHECK (cardinality(mismatch_categories) BETWEEN 1 AND 8)
    CHECK (array_position(mismatch_categories, NULL) IS NULL),
  CONSTRAINT product_submission_mismatch_owner_fkey
    FOREIGN KEY (submission_id, user_id)
    REFERENCES public.product_submissions(id, user_id)
    ON DELETE CASCADE
);

CREATE TABLE public.product_submission_missing_details (
  submission_id uuid PRIMARY KEY
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  other_ingredients_not_present boolean NOT NULL DEFAULT false,
  CONSTRAINT product_submission_missing_owner_fkey
    FOREIGN KEY (submission_id, user_id)
    REFERENCES public.product_submissions(id, user_id)
    ON DELETE CASCADE
);

CREATE TABLE public.product_submission_photos (
  submission_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_slot public.product_submission_photo_slot NOT NULL,
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
  content_sha256 text NOT NULL
    CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (submission_id, photo_slot),
  CONSTRAINT product_submission_photos_owner_fkey
    FOREIGN KEY (submission_id, user_id)
    REFERENCES public.product_submissions(id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT product_submission_photos_object_path_check
    CHECK (
      object_path =
        user_id::text || '/' || submission_id::text || '/' || photo_slot::text
    )
);

-- AI output remains an attributable draft. Human-approved canonical label JSON
-- is stored separately below and is the only artifact the pipeline may ingest.
CREATE TABLE public.product_submission_extractions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version > 0),
  schema_version text NOT NULL CHECK (btrim(schema_version) <> ''),
  provider text NOT NULL CHECK (btrim(provider) <> ''),
  model text NOT NULL CHECK (btrim(model) <> ''),
  prompt_version text NOT NULL CHECK (btrim(prompt_version) <> ''),
  input_image_hashes jsonb NOT NULL
    CHECK (
      jsonb_typeof(input_image_hashes) = 'object'
      AND input_image_hashes <> '{}'::jsonb
    ),
  draft_payload jsonb NOT NULL CHECK (jsonb_typeof(draft_payload) = 'object'),
  field_provenance jsonb NOT NULL
    CHECK (jsonb_typeof(field_provenance) = 'object'),
  confidence numeric CHECK (confidence BETWEEN 0 AND 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submission_id, version)
);

CREATE TABLE public.product_submission_approved_labels (
  submission_id uuid PRIMARY KEY
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  schema_version text NOT NULL CHECK (btrim(schema_version) <> ''),
  approved_payload jsonb NOT NULL
    CHECK (jsonb_typeof(approved_payload) = 'object'),
  approved_payload_canonical text NOT NULL
    CHECK (
      octet_length(approved_payload_canonical) BETWEEN 2 AND 524288
      AND approved_payload_canonical::jsonb = approved_payload
    ),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  reviewer_id uuid NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.product_submission_review_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  from_status public.product_submission_review_status NOT NULL,
  to_status public.product_submission_review_status NOT NULL,
  reviewer_id uuid NOT NULL,
  review_notes text
    CHECK (
      review_notes IS NULL
      OR (
        btrim(review_notes) <> ''
        AND char_length(review_notes) <= 2000
      )
    ),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_submissions_user_created
  ON public.product_submissions (user_id, created_at DESC, id DESC);
CREATE INDEX idx_product_submissions_review_queue
  ON public.product_submissions (
    upload_state,
    review_status,
    submitted_at,
    id
  );
CREATE INDEX idx_product_submissions_upc
  ON public.product_submissions (normalized_upc)
  WHERE normalized_upc IS NOT NULL;
CREATE UNIQUE INDEX idx_product_submissions_user_open_upc
  ON public.product_submissions (user_id, kind, normalized_upc)
  WHERE normalized_upc IS NOT NULL
    AND upload_state = 'ready'
    AND review_status IN ('submitted', 'under_review', 'approved');
CREATE UNIQUE INDEX idx_product_submission_photo_path
  ON public.product_submission_photos (object_path);
CREATE INDEX idx_product_submission_review_events_submission
  ON public.product_submission_review_events (submission_id, created_at);

-- A user cannot create a detail row for the wrong submission kind. These
-- triggers run even when a privileged migration or future server code writes.
CREATE OR REPLACE FUNCTION public.enforce_product_submission_detail_kind()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  expected_kind public.product_submission_kind;
  actual_kind public.product_submission_kind;
BEGIN
  expected_kind := TG_ARGV[0]::public.product_submission_kind;
  SELECT submission.kind
    INTO actual_kind
  FROM public.product_submissions AS submission
  WHERE submission.id = NEW.submission_id
    AND submission.user_id = NEW.user_id
  FOR UPDATE;

  IF NOT FOUND OR actual_kind <> expected_kind THEN
    RAISE EXCEPTION 'submission detail kind mismatch'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER product_submission_mismatch_kind
  BEFORE INSERT OR UPDATE
  ON public.product_submission_mismatch_details
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_product_submission_detail_kind(
    'label_mismatch'
  );

CREATE TRIGGER product_submission_missing_kind
  BEFORE INSERT OR UPDATE
  ON public.product_submission_missing_details
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_product_submission_detail_kind(
    'missing_product'
  );

CREATE OR REPLACE FUNCTION public.enforce_product_submission_photo_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  parent_upload_state public.product_submission_upload_state;
BEGIN
  SELECT submission.upload_state
    INTO parent_upload_state
  FROM public.product_submissions AS submission
  WHERE submission.id = NEW.submission_id
    AND submission.user_id = NEW.user_id
  FOR UPDATE;

  IF NOT FOUND OR parent_upload_state <> 'pending' THEN
    RAISE EXCEPTION 'photo manifest is closed' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER product_submission_photo_pending
  AFTER INSERT ON public.product_submission_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_product_submission_photo_pending();

-- Returns true only when a missing-product submission has the two mandatory
-- label faces and either an Other Ingredients face or an explicit assertion
-- that the product label has no Other Ingredients panel.
CREATE OR REPLACE FUNCTION public.product_submission_has_required_missing_evidence(
  p_submission_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    (
      SELECT count(DISTINCT photo.photo_slot) = 2
      FROM public.product_submission_photos AS photo
      WHERE photo.submission_id = p_submission_id
        AND photo.user_id = p_user_id
        AND photo.photo_slot IN ('front', 'supplement_facts')
    )
    AND EXISTS (
      SELECT 1
      FROM public.product_submission_missing_details AS missing
      WHERE missing.submission_id = p_submission_id
        AND missing.user_id = p_user_id
        AND (
          missing.other_ingredients_not_present
          OR EXISTS (
            SELECT 1
            FROM public.product_submission_photos AS other_photo
            WHERE other_photo.submission_id = p_submission_id
              AND other_photo.user_id = p_user_id
              AND other_photo.photo_slot = 'other_ingredients'
          )
        )
    );
$$;

-- GTIN-8, UPC-A/GTIN-12, EAN-13, and GTIN-14 share the same mod-10
-- check-digit algorithm. Rejecting a bad check digit prevents a scanner typo
-- from becoming a second product identity.
CREATE OR REPLACE FUNCTION public.is_valid_product_submission_gtin(
  p_value text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
DECLARE
  sum_value integer := 0;
  position integer;
  digit integer;
  body_length integer := char_length(p_value) - 1;
BEGIN
  IF p_value !~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$' THEN
    RETURN false;
  END IF;
  FOR position IN 1..body_length LOOP
    digit := substr(p_value, body_length - position + 1, 1)::integer;
    sum_value := sum_value + digit * CASE
      WHEN position % 2 = 1 THEN 3
      ELSE 1
    END;
  END LOOP;
  RETURN ((10 - (sum_value % 10)) % 10)
    = right(p_value, 1)::integer;
END;
$$;

-- One transactional, idempotent write boundary prevents an envelope without
-- its typed detail or photo manifest. Unknown JSON keys and altered retries
-- fail closed.
CREATE OR REPLACE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_other_ingredients_not_present boolean DEFAULT false,
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
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission id required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_photos) <> 'array' OR jsonb_array_length(p_photos) > 3 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[^0-9]',
    '',
    'g'
  ), '');
  IF p_kind = 'missing_product'
     AND normalized_upc_value IS NOT NULL
     AND NOT public.is_valid_product_submission_gtin(normalized_upc_value) THEN
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
    normalized_upc
  ) VALUES (
    p_submission_id,
    caller_id,
    p_kind,
    normalized_upc_value
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
      user_id,
      other_ingredients_not_present
    ) VALUES (
      p_submission_id,
      caller_id,
      p_other_ingredients_not_present
    )
    ON CONFLICT (submission_id) DO NOTHING;
    IF NOT EXISTS (
      SELECT 1
      FROM public.product_submission_missing_details AS detail
      WHERE detail.submission_id = p_submission_id
        AND detail.user_id = caller_id
        AND detail.other_ingredients_not_present
          = p_other_ingredients_not_present
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
            'content_sha256',
            'content_type',
            'photo_slot'
          ]::text[] THEN
      RAISE EXCEPTION 'invalid photo manifest entry'
        USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.product_submission_photos (
      submission_id,
      user_id,
      photo_slot,
      object_path,
      content_type,
      byte_size,
      content_sha256
    ) VALUES (
      p_submission_id,
      caller_id,
      (photo->>'photo_slot')::public.product_submission_photo_slot,
      caller_id::text || '/' || p_submission_id::text || '/'
        || (photo->>'photo_slot'),
      photo->>'content_type',
      (photo->>'byte_size')::bigint,
      photo->>'content_sha256'
    )
    ON CONFLICT (submission_id, photo_slot) DO NOTHING;
  END LOOP;

  IF (
    SELECT count(*)
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = caller_id
  ) <> jsonb_array_length(p_photos)
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_photos) AS expected_photo(value)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS persisted_photo
      WHERE persisted_photo.submission_id = p_submission_id
        AND persisted_photo.user_id = caller_id
        AND persisted_photo.photo_slot =
          (expected_photo.value->>'photo_slot')
            ::public.product_submission_photo_slot
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

  RETURN true;
END;
$$;

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
     AND NOT public.product_submission_has_required_missing_evidence(
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

CREATE OR REPLACE FUNCTION public.record_product_submission_extraction(
  p_submission_id uuid,
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
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'service role required' USING ERRCODE = '42501';
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
        photo.photo_slot::text,
        photo.content_sha256
        ORDER BY photo.photo_slot::text
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

-- Transactional reviewer mutation. AI drafts can be recorded separately but
-- cannot call this function and cannot produce an approved label.
CREATE OR REPLACE FUNCTION public.review_product_submission(
  p_submission_id uuid,
  p_reviewer_id uuid,
  p_to_status public.product_submission_review_status,
  p_review_notes text DEFAULT NULL,
  p_approved_schema_version text DEFAULT NULL,
  p_approved_payload jsonb DEFAULT NULL,
  p_approved_payload_canonical text DEFAULT NULL,
  p_payload_sha256 text DEFAULT NULL,
  p_duplicate_of uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  transition_allowed boolean;
BEGIN
  IF auth.role() <> 'service_role' OR p_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'service role required' USING ERRCODE = '42501';
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
  IF (p_to_status = 'duplicate') <> (p_duplicate_of IS NOT NULL) THEN
    RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_duplicate_of = p_submission_id THEN
    RAISE EXCEPTION 'submission cannot duplicate itself'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' THEN
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
    review_notes
  ) VALUES (
    p_submission_id,
    submission.review_status,
    p_to_status,
    p_reviewer_id,
    NULLIF(btrim(p_review_notes), '')
  );

  UPDATE public.product_submissions
  SET review_status = p_to_status,
      reviewed_at = now(),
      reviewed_by = p_reviewer_id,
      duplicate_of = p_duplicate_of
  WHERE id = p_submission_id;
  RETURN true;
END;
$$;

-- The pipeline reads only human-approved, unpromoted canonical payloads.
-- User identity and private object paths never cross this boundary.
CREATE OR REPLACE FUNCTION public.export_approved_product_submissions(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  submission_id uuid,
  kind public.product_submission_kind,
  normalized_upc text,
  target_dsld_id text,
  schema_version text,
  approved_payload_canonical text,
  payload_sha256 text,
  reviewer_id uuid,
  approved_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    submission.id,
    submission.kind,
    submission.normalized_upc,
    mismatch.dsld_id,
    approved.schema_version,
    approved.approved_payload_canonical,
    approved.payload_sha256,
    approved.reviewer_id,
    approved.approved_at
  FROM public.product_submissions AS submission
  JOIN public.product_submission_approved_labels AS approved
    ON approved.submission_id = submission.id
  LEFT JOIN public.product_submission_mismatch_details AS mismatch
    ON mismatch.submission_id = submission.id
  WHERE auth.role() = 'service_role'
    AND submission.upload_state = 'ready'
    AND submission.review_status = 'approved'
    AND submission.promoted_at IS NULL
  ORDER BY approved.approved_at, submission.id
  LIMIT greatest(0, least(p_limit, 500));
$$;

CREATE OR REPLACE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid,
  p_catalog_version text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.role() <> 'service_role'
     OR NULLIF(btrim(p_catalog_version), '') IS NULL THEN
    RAISE EXCEPTION 'service role and catalog version required'
      USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.id = p_submission_id
      AND submission.promoted_catalog_version IS NOT NULL
      AND submission.promoted_catalog_version <> btrim(p_catalog_version)
  ) THEN
    RAISE EXCEPTION 'submission already promoted in a different catalog'
      USING ERRCODE = '23505';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.id = p_submission_id
      AND submission.promoted_catalog_version = btrim(p_catalog_version)
  ) THEN
    RETURN true;
  END IF;
  UPDATE public.product_submissions
  SET promoted_catalog_version = btrim(p_catalog_version),
      promoted_at = now()
  WHERE id = p_submission_id
    AND review_status = 'approved'
    AND upload_state = 'ready'
    AND promoted_catalog_version IS NULL;
  RETURN FOUND;
END;
$$;

-- Service-only cleanup manifests. The caller must delete objects through the
-- Storage API before completing the database delete.
CREATE OR REPLACE FUNCTION public.claim_product_submission_cleanup(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (submission_id uuid, object_paths text[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'service role required' USING ERRCODE = '42501';
  END IF;
  IF p_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid cleanup limit' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
  WITH candidates AS (
    SELECT submission.id
    FROM public.product_submissions AS submission
    WHERE (
      submission.upload_state IN ('pending', 'cleaning')
      AND submission.created_at < now() - interval '24 hours'
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    ) OR (
      submission.review_status IN ('rejected', 'duplicate')
      AND submission.reviewed_at < now() - interval '90 days'
      AND submission.evidence_purged_at IS NULL
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    ) OR (
      submission.promoted_at < now() - interval '90 days'
      AND submission.evidence_purged_at IS NULL
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    )
    ORDER BY submission.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  ), claimed AS (
    UPDATE public.product_submissions AS submission
    SET upload_state = CASE
          WHEN submission.upload_state IN ('pending', 'cleaning')
            THEN 'cleaning'::public.product_submission_upload_state
          ELSE submission.upload_state
        END,
        cleanup_claimed_at = now()
    FROM candidates
    WHERE submission.id = candidates.id
    RETURNING submission.id
  )
  SELECT claimed.id,
         coalesce(array_agg(photo.object_path)
           FILTER (WHERE photo.object_path IS NOT NULL), ARRAY[]::text[])
  FROM claimed
  LEFT JOIN public.product_submission_photos AS photo
    ON photo.submission_id = claimed.id
  GROUP BY claimed.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_product_submission_cleanup(
  p_submission_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  purged_retained_count integer;
  deleted_pending_count integer;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'service role required' USING ERRCODE = '42501';
  END IF;
  -- Review/publication provenance is durable. Retention removes only the
  -- private photo manifest after the Storage worker confirms object deletion.
  DELETE FROM public.product_submission_photos AS photo
  USING public.product_submissions AS submission
  WHERE photo.submission_id = submission.id
    AND submission.id = ANY(p_submission_ids)
    AND submission.cleanup_claimed_at IS NOT NULL
    AND submission.upload_state = 'ready'
    AND (
      submission.review_status IN ('rejected', 'duplicate')
      OR submission.promoted_at IS NOT NULL
    );

  UPDATE public.product_submissions
  SET evidence_purged_at = now(),
      cleanup_claimed_at = NULL
  WHERE id = ANY(p_submission_ids)
    AND cleanup_claimed_at IS NOT NULL
    AND upload_state = 'ready'
    AND evidence_purged_at IS NULL
    AND (
      review_status IN ('rejected', 'duplicate')
      OR promoted_at IS NOT NULL
    );
  GET DIAGNOSTICS purged_retained_count = ROW_COUNT;

  -- An abandoned, never-finalized draft has no review or publication record to
  -- preserve, so the parent can be removed after its private objects are gone.
  DELETE FROM public.product_submissions AS submission
  WHERE submission.id = ANY(p_submission_ids)
    AND submission.upload_state = 'cleaning'
    AND submission.review_status = 'submitted'
    AND submission.cleanup_claimed_at IS NOT NULL;
  GET DIAGNOSTICS deleted_pending_count = ROW_COUNT;

  RETURN purged_retained_count + deleted_pending_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_product_submission_objects_for_user(
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
  WHERE auth.role() = 'service_role'
    AND photo.user_id = p_user_id
  ORDER BY photo.object_path;
$$;

-- Migrate the legacy mismatch envelope before retiring it. Old objects are
-- required to be absent because Storage object moves must use the Storage API.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = 'label-mismatch-report-photos'
  ) OR EXISTS (
    SELECT 1
    FROM public.label_mismatch_report_photos
  ) THEN
    RAISE EXCEPTION
      'legacy label-mismatch photos require Storage API migration first';
  END IF;
END;
$$;

INSERT INTO public.product_submissions (
  id,
  user_id,
  kind,
  normalized_upc,
  upload_state,
  review_status,
  created_at,
  submitted_at,
  reviewed_at,
  reviewed_by
)
SELECT
  legacy.id,
  legacy.user_id,
  'label_mismatch',
  NULLIF(regexp_replace(coalesce(legacy.upc, ''), '[^0-9]', '', 'g'), ''),
  CASE
    WHEN legacy.upload_state = 'ready' THEN 'ready'
    ELSE 'pending'
  END::public.product_submission_upload_state,
  -- Legacy rows did not record reviewer identity. Re-queue them as submitted
  -- instead of fabricating provenance for an in-progress/final decision.
  'submitted'::public.product_submission_review_status,
  legacy.submitted_at,
  CASE WHEN legacy.upload_state = 'ready' THEN legacy.submitted_at END,
  NULL,
  NULL
FROM public.label_mismatch_reports AS legacy;

INSERT INTO public.product_submission_mismatch_details (
  submission_id,
  user_id,
  dsld_id,
  source_record_id,
  catalog_source_version,
  formula_fingerprint,
  mismatch_categories
)
SELECT
  legacy.id,
  legacy.user_id,
  legacy.dsld_id,
  legacy.source_record_id,
  legacy.catalog_source_version,
  legacy.formula_fingerprint,
  legacy.mismatch_categories
FROM public.label_mismatch_reports AS legacy;

-- Retire every legacy database and Storage policy before dropping the tables.
DROP POLICY IF EXISTS "label_mismatch_objects_select_own" ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_update_own" ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_reviewer_select"
  ON storage.objects;

DROP TABLE public.label_mismatch_report_photos;
DROP TABLE public.label_mismatch_reports;
DROP FUNCTION IF EXISTS public.finalize_label_mismatch_report(uuid);
DROP FUNCTION IF EXISTS public.enforce_label_mismatch_photo_pending();
DROP FUNCTION IF EXISTS public.enforce_label_mismatch_owner_immutable();
DROP TYPE public.label_mismatch_photo_slot;
DROP TYPE public.label_mismatch_upload_state;
DROP TYPE public.label_mismatch_report_status;
DELETE FROM storage.buckets WHERE id = 'label-mismatch-report-photos';

-- Preserve the closed mismatch-category vocabulary because it is the typed
-- detail contract. Everything else now uses product_submission_* names.

ALTER TABLE public.product_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submissions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_mismatch_details
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_mismatch_details
  FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_missing_details
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_missing_details
  FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_photos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extractions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extractions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_approved_labels
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_approved_labels
  FORCE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_review_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_review_events FORCE ROW LEVEL SECURITY;

CREATE POLICY "product_submissions_select_own"
  ON public.product_submissions
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "product_submission_mismatch_select_own"
  ON public.product_submission_mismatch_details
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "product_submission_missing_select_own"
  ON public.product_submission_missing_details
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "product_submission_photos_select_own"
  ON public.product_submission_photos
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

REVOKE ALL ON TABLE public.product_submissions
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.product_submission_mismatch_details
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.product_submission_missing_details
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.product_submission_photos
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.product_submission_extractions
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.product_submission_approved_labels
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.product_submission_review_events
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.product_submissions TO authenticated;
GRANT SELECT ON TABLE public.product_submission_mismatch_details
  TO authenticated;
GRANT SELECT ON TABLE public.product_submission_missing_details
  TO authenticated;
GRANT SELECT ON TABLE public.product_submission_photos TO authenticated;
GRANT SELECT, UPDATE, DELETE ON TABLE public.product_submissions
  TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.product_submission_mismatch_details TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.product_submission_missing_details TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.product_submission_photos TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.product_submission_extractions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.product_submission_approved_labels TO service_role;
GRANT SELECT, INSERT
  ON TABLE public.product_submission_review_events TO service_role;
GRANT USAGE, SELECT
  ON SEQUENCE public.product_submission_review_events_id_seq TO service_role;

REVOKE ALL ON TYPE public.product_submission_kind
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TYPE public.product_submission_upload_state
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TYPE public.product_submission_review_status
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TYPE public.product_submission_photo_slot
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_kind
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_upload_state
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_review_status
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.product_submission_photo_slot
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.enforce_product_submission_detail_kind()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_product_submission_photo_pending()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION
  public.product_submission_has_required_missing_evidence(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_valid_product_submission_gtin(text)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.finalize_product_submission(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission(uuid)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.review_product_submission(
  uuid,
  uuid,
  public.product_submission_review_status,
  text,
  text,
  jsonb,
  text,
  text,
  uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
  uuid,
  uuid,
  public.product_submission_review_status,
  text,
  text,
  jsonb,
  text,
  text,
  uuid
) TO service_role;
REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb,
  numeric
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_product_submission_extraction(
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
REVOKE ALL ON FUNCTION public.export_approved_product_submissions(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.export_approved_product_submissions(integer)
  TO service_role;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_product_submission_promoted(uuid, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.claim_product_submission_cleanup(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_cleanup(integer)
  TO service_role;
REVOKE ALL ON FUNCTION public.complete_product_submission_cleanup(uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_product_submission_cleanup(uuid[])
  TO service_role;
REVOKE ALL ON FUNCTION
  public.list_product_submission_objects_for_user(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.list_product_submission_objects_for_user(uuid)
  TO service_role;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) VALUES (
  'product-submission-photos',
  'product-submission-photos',
  false,
  15728640,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

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

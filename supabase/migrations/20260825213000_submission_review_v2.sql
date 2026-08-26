-- Human-only submission review and immutable local-index match history.
--
-- The Edge allowlist remains an early rejection boundary. This migration is
-- the authoritative database boundary: reviewer identity comes only from the
-- caller JWT, membership is operator-managed, and automation roles cannot
-- execute the approval transition.

CREATE TABLE public.product_submission_reviewers (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.product_submission_reviewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_reviewers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_reviewers
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TYPE public.product_submission_match_outcome AS ENUM (
  'catalog_match',
  'dsld_match',
  'identity_ambiguous',
  'no_match_verified',
  'not_this_product'
);

CREATE TABLE public.product_submission_match_checks (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  outcome public.product_submission_match_outcome NOT NULL,
  canonical_gtin14 text NOT NULL CHECK (canonical_gtin14 ~ '^[0-9]{14}$'),
  index_built_at timestamptz NOT NULL,
  matched_dsld_id text CHECK (
    matched_dsld_id IS NULL
    OR matched_dsld_id ~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'
  ),
  candidate_dsld_ids text[] NOT NULL DEFAULT '{}',
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_submission_match_check_shape CHECK (
    CASE outcome
      WHEN 'catalog_match' THEN
        matched_dsld_id IS NOT NULL
        AND cardinality(candidate_dsld_ids) = 0
        AND reason IS NULL
      WHEN 'dsld_match' THEN
        matched_dsld_id IS NOT NULL
        AND cardinality(candidate_dsld_ids) = 0
        AND reason IS NULL
      WHEN 'identity_ambiguous' THEN
        matched_dsld_id IS NULL
        AND cardinality(candidate_dsld_ids) >= 2
        AND reason IS NULL
      WHEN 'no_match_verified' THEN
        matched_dsld_id IS NULL
        AND cardinality(candidate_dsld_ids) = 0
        AND reason IS NULL
      WHEN 'not_this_product' THEN
        matched_dsld_id IS NOT NULL
        AND cardinality(candidate_dsld_ids) = 0
        AND reason IS NOT NULL
    END
  )
);

CREATE INDEX idx_product_submission_match_checks_latest
  ON public.product_submission_match_checks (
    submission_id,
    created_at DESC,
    id DESC
  );

ALTER TABLE public.product_submission_match_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_match_checks FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_match_checks
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_submission_match_checks TO service_role;

ALTER TABLE public.product_submission_extractions
  ADD COLUMN usage jsonb CHECK (usage IS NULL OR jsonb_typeof(usage) = 'object');

CREATE TYPE public.product_submission_image_rights AS ENUM (
  'user_evidence_crop',
  'operator_photo',
  'manufacturer_provided',
  'licensed'
);

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) VALUES (
  'product-submission-reviewer-images',
  'product-submission-reviewer-images',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
) ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE public.product_submission_reviewer_images (
  object_id uuid PRIMARY KEY,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  object_path text NOT NULL UNIQUE,
  source_rights public.product_submission_image_rights NOT NULL,
  source_photo_id uuid,
  rights_attested_at timestamptz,
  content_type text CHECK (
    content_type IS NULL
    OR content_type IN ('image/jpeg', 'image/png', 'image/webp')
  ),
  byte_size bigint CHECK (byte_size IS NULL OR byte_size BETWEEN 1 AND 10485760),
  content_sha256 text CHECK (
    content_sha256 IS NULL OR content_sha256 ~ '^[0-9a-f]{64}$'
  ),
  finalized_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_submission_reviewer_image_path CHECK (
    object_path = reviewer_id::text || '/' || submission_id::text || '/'
      || object_id::text
  ),
  CONSTRAINT product_submission_reviewer_image_rights CHECK (
    (source_rights = 'user_evidence_crop' AND rights_attested_at IS NULL
      AND source_photo_id IS NOT NULL)
    OR (source_rights <> 'user_evidence_crop' AND rights_attested_at IS NOT NULL
      AND source_photo_id IS NULL)
  ),
  CONSTRAINT product_submission_reviewer_image_finalized CHECK (
    (finalized_at IS NULL AND content_type IS NULL
      AND byte_size IS NULL AND content_sha256 IS NULL)
    OR (finalized_at IS NOT NULL AND content_type IS NOT NULL
      AND byte_size IS NOT NULL AND content_sha256 IS NOT NULL)
  )
);

ALTER TABLE public.product_submission_reviewer_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_reviewer_images FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_reviewer_images
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_submission_reviewer_images TO service_role;

ALTER TABLE public.product_submission_approved_labels
  ADD COLUMN approved_product_image_photo_id uuid,
  ADD COLUMN approved_product_image_reviewer_object_id uuid,
  ADD CONSTRAINT product_submission_approved_image_singular CHECK (
    num_nonnulls(
      approved_product_image_photo_id,
      approved_product_image_reviewer_object_id
    ) <= 1
  );

CREATE FUNCTION public.create_product_submission_reviewer_image(
  p_submission_id uuid,
  p_object_id uuid,
  p_source_rights public.product_submission_image_rights,
  p_rights_attested boolean,
  p_source_photo_id uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  object_path text;
  persisted public.product_submission_reviewer_images%ROWTYPE;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.upload_state <> 'ready'
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  IF (p_source_rights = 'user_evidence_crop' AND p_rights_attested)
     OR (p_source_rights <> 'user_evidence_crop' AND NOT p_rights_attested) THEN
    RAISE EXCEPTION 'image rights attestation mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_source_rights = 'user_evidence_crop' AND NOT EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.photo_id = p_source_photo_id
      AND 'front_identity' = ANY(photo.categories)
  ) THEN
    RAISE EXCEPTION 'front source photo required for crop'
      USING ERRCODE = '22023';
  END IF;
  IF p_source_rights <> 'user_evidence_crop' AND p_source_photo_id IS NOT NULL THEN
    RAISE EXCEPTION 'source photo not allowed for replacement image'
      USING ERRCODE = '22023';
  END IF;
  object_path := reviewer_id::text || '/' || p_submission_id::text || '/'
    || p_object_id::text;

  INSERT INTO public.product_submission_reviewer_images (
    object_id,
    submission_id,
    reviewer_id,
    object_path,
    source_rights,
    source_photo_id,
    rights_attested_at
  ) VALUES (
    p_object_id,
    p_submission_id,
    reviewer_id,
    object_path,
    p_source_rights,
    p_source_photo_id,
    CASE WHEN p_rights_attested THEN now() END
  ) ON CONFLICT (object_id) DO NOTHING;

  SELECT image.* INTO persisted
  FROM public.product_submission_reviewer_images AS image
  WHERE image.object_id = p_object_id;
  IF NOT FOUND
     OR persisted.submission_id <> p_submission_id
     OR persisted.reviewer_id <> reviewer_id
     OR persisted.object_path <> object_path
     OR persisted.source_rights <> p_source_rights
     OR persisted.source_photo_id IS DISTINCT FROM p_source_photo_id
     OR (persisted.rights_attested_at IS NOT NULL) <> p_rights_attested THEN
    RAISE EXCEPTION 'reviewer image replay conflict' USING ERRCODE = '23505';
  END IF;
  RETURN object_path;
END;
$$;

CREATE FUNCTION public.finalize_product_submission_reviewer_image(
  p_submission_id uuid,
  p_object_id uuid,
  p_content_type text,
  p_byte_size bigint,
  p_content_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  expected_path text;
BEGIN
  SELECT image.object_path INTO expected_path
  FROM public.product_submission_reviewer_images AS image
  WHERE image.object_id = p_object_id
    AND image.submission_id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'reviewer image manifest required' USING ERRCODE = '55000';
  END IF;
  IF p_content_type NOT IN ('image/jpeg', 'image/png', 'image/webp')
     OR p_byte_size NOT BETWEEN 1 AND 10485760
     OR p_content_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid reviewer image bytes' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects AS object
    WHERE object.bucket_id = 'product-submission-reviewer-images'
      AND object.name = expected_path
      AND coalesce((object.metadata->>'size')::bigint, -1) = p_byte_size
  ) THEN
    RAISE EXCEPTION 'reviewer image storage object mismatch'
      USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submission_reviewer_images
  SET content_type = p_content_type,
      byte_size = p_byte_size,
      content_sha256 = p_content_sha256,
      finalized_at = now()
  WHERE object_id = p_object_id;
  RETURN true;
END;
$$;

CREATE FUNCTION public.record_product_submission_match_check(
  p_submission_id uuid,
  p_outcome public.product_submission_match_outcome,
  p_canonical_gtin14 text,
  p_index_built_at timestamptz,
  p_matched_dsld_id text DEFAULT NULL,
  p_candidate_dsld_ids text[] DEFAULT '{}',
  p_reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  canonical_gtin14 text := btrim(coalesce(p_canonical_gtin14, ''));
  matched_dsld_id text := NULLIF(btrim(coalesce(p_matched_dsld_id, '')), '');
  candidate_dsld_ids text[] := coalesce(p_candidate_dsld_ids, '{}');
  reason text := NULLIF(btrim(regexp_replace(
    coalesce(p_reason, ''),
    '[\x00-\x1F\x7F]',
    '',
    'g'
  )), '');
  match_check_id bigint;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;

  IF NOT FOUND
     OR submission.kind <> 'missing_product'
     OR submission.upload_state <> 'ready'
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open missing-product submission required'
      USING ERRCODE = '55000';
  END IF;

  IF canonical_gtin14 !~ '^[0-9]{14}$'
     OR NOT public.is_valid_product_submission_gtin(canonical_gtin14)
     OR canonical_gtin14 <> lpad(submission.normalized_upc, 14, '0') THEN
    RAISE EXCEPTION 'exact canonical GTIN-14 required'
      USING ERRCODE = '22023';
  END IF;
  IF p_index_built_at IS NULL
     OR p_index_built_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'invalid index built-at' USING ERRCODE = '22023';
  END IF;
  IF p_outcome = 'no_match_verified'
     AND p_index_built_at < now() - interval '60 days' THEN
    RAISE EXCEPTION 'identity index is stale' USING ERRCODE = '22023';
  END IF;
  IF matched_dsld_id IS NOT NULL
     AND matched_dsld_id !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid matched product id' USING ERRCODE = '22023';
  END IF;
  IF cardinality(candidate_dsld_ids) > 100
     OR EXISTS (
       SELECT 1
       FROM unnest(candidate_dsld_ids) AS candidate_id
       WHERE candidate_id !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$'
     )
     OR cardinality(candidate_dsld_ids) <> (
       SELECT count(DISTINCT candidate_id)
       FROM unnest(candidate_dsld_ids) AS candidate_id
     ) THEN
    RAISE EXCEPTION 'invalid candidate product ids' USING ERRCODE = '22023';
  END IF;
  IF reason IS NOT NULL AND char_length(reason) > 1000 THEN
    RAISE EXCEPTION 'match reason too long' USING ERRCODE = '22023';
  END IF;

  IF p_outcome IN ('catalog_match', 'dsld_match') AND NOT (
    matched_dsld_id IS NOT NULL
    AND cardinality(candidate_dsld_ids) = 0
    AND reason IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid exact-match evidence' USING ERRCODE = '22023';
  ELSIF p_outcome = 'identity_ambiguous' AND NOT (
    matched_dsld_id IS NULL
    AND cardinality(candidate_dsld_ids) >= 2
    AND reason IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid ambiguous-match evidence' USING ERRCODE = '22023';
  ELSIF p_outcome = 'no_match_verified' AND NOT (
    matched_dsld_id IS NULL
    AND cardinality(candidate_dsld_ids) = 0
    AND reason IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid no-match evidence' USING ERRCODE = '22023';
  ELSIF p_outcome = 'not_this_product' AND NOT (
    matched_dsld_id IS NOT NULL
    AND cardinality(candidate_dsld_ids) = 0
    AND reason IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'invalid wrong-product override' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.product_submission_match_checks (
    submission_id,
    reviewer_id,
    outcome,
    canonical_gtin14,
    index_built_at,
    matched_dsld_id,
    candidate_dsld_ids,
    reason
  ) VALUES (
    p_submission_id,
    reviewer_id,
    p_outcome,
    canonical_gtin14,
    p_index_built_at,
    matched_dsld_id,
    candidate_dsld_ids,
    reason
  ) RETURNING id INTO match_check_id;

  RETURN match_check_id;
END;
$$;

-- Preserve the reviewed transition implementation behind an inaccessible
-- internal name. The only API-visible wrapper derives identity from auth.uid.
ALTER FUNCTION public.review_product_submission(
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
) RENAME TO review_product_submission_human_internal;

REVOKE ALL ON FUNCTION public.review_product_submission_human_internal(
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

CREATE FUNCTION public.review_product_submission(
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
  p_product_image_reviewer_object_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  latest_match public.product_submission_match_checks%ROWTYPE;
  transitioned boolean;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
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

  IF p_to_status = 'approved' AND submission.kind = 'missing_product' THEN
    SELECT match_check.*
      INTO latest_match
    FROM public.product_submission_match_checks AS match_check
    WHERE match_check.submission_id = p_submission_id
    ORDER BY match_check.created_at DESC, match_check.id DESC
    LIMIT 1;
    IF NOT FOUND
       OR latest_match.outcome <> 'no_match_verified'
       OR latest_match.index_built_at < now() - interval '60 days'
       OR latest_match.index_built_at > now() + interval '5 minutes'
       OR latest_match.canonical_gtin14 <> lpad(submission.normalized_upc, 14, '0') THEN
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
        AND image.reviewer_id = reviewer_id
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

  transitioned := public.review_product_submission_human_internal(
    p_submission_id,
    reviewer_id,
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
          p_product_image_reviewer_object_id
    WHERE submission_id = p_submission_id;
  END IF;
  RETURN transitioned;
END;
$$;

DROP FUNCTION public.claim_product_submission_cleanup(integer);

CREATE FUNCTION public.claim_product_submission_cleanup(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  submission_id uuid,
  evidence_object_paths text[],
  reviewer_object_paths text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
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
  SELECT
    claimed.id,
    ARRAY(
      SELECT photo.object_path
      FROM public.product_submission_photos AS photo
      WHERE photo.submission_id = claimed.id
      ORDER BY photo.object_path
    ),
    ARRAY(
      SELECT image.object_path
      FROM public.product_submission_reviewer_images AS image
      WHERE image.submission_id = claimed.id
      ORDER BY image.object_path
    )
  FROM claimed;
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

  DELETE FROM public.product_submission_reviewer_images AS image
  USING public.product_submissions AS submission
  WHERE image.submission_id = submission.id
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

  DELETE FROM public.product_submissions AS submission
  WHERE submission.id = ANY(p_submission_ids)
    AND submission.upload_state = 'cleaning'
    AND submission.review_status = 'submitted'
    AND submission.cleanup_claimed_at IS NOT NULL;
  GET DIAGNOSTICS deleted_pending_count = ROW_COUNT;

  RETURN purged_retained_count + deleted_pending_count;
END;
$$;

CREATE FUNCTION public.get_approved_product_submission_image(
  p_submission_id uuid
)
RETURNS TABLE (
  bucket_id text,
  object_path text,
  content_type text,
  content_sha256 text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    'product-submission-photos'::text,
    photo.object_path,
    photo.content_type,
    photo.content_sha256
  FROM public.product_submissions AS submission
  JOIN public.product_submission_approved_labels AS approved
    ON approved.submission_id = submission.id
  JOIN public.product_submission_photos AS photo
    ON photo.submission_id = submission.id
   AND photo.photo_id = approved.approved_product_image_photo_id
  WHERE submission.id = p_submission_id
    AND submission.kind = 'missing_product'
    AND submission.review_status = 'approved'
    AND submission.promoted_at IS NULL
  UNION ALL
  SELECT
    'product-submission-reviewer-images'::text,
    image.object_path,
    image.content_type,
    image.content_sha256
  FROM public.product_submissions AS submission
  JOIN public.product_submission_approved_labels AS approved
    ON approved.submission_id = submission.id
  JOIN public.product_submission_reviewer_images AS image
    ON image.submission_id = submission.id
   AND image.object_id = approved.approved_product_image_reviewer_object_id
  WHERE submission.id = p_submission_id
    AND submission.kind = 'missing_product'
    AND submission.review_status = 'approved'
    AND submission.promoted_at IS NULL;
$$;

REVOKE ALL ON FUNCTION public.record_product_submission_match_check(
  uuid,
  public.product_submission_match_outcome,
  text,
  timestamptz,
  text,
  text[],
  text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_match_check(
  uuid,
  public.product_submission_match_outcome,
  text,
  timestamptz,
  text,
  text[],
  text
) TO authenticated;

REVOKE ALL ON FUNCTION public.create_product_submission_reviewer_image(
  uuid,
  uuid,
  public.product_submission_image_rights,
  boolean,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission_reviewer_image(
  uuid,
  uuid,
  public.product_submission_image_rights,
  boolean,
  uuid
) TO authenticated;

REVOKE ALL ON FUNCTION public.finalize_product_submission_reviewer_image(
  uuid,
  uuid,
  text,
  bigint,
  text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission_reviewer_image(
  uuid,
  uuid,
  text,
  bigint,
  text
) TO service_role;

REVOKE ALL ON FUNCTION public.review_product_submission(
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
  text,
  uuid,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
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
  text,
  uuid,
  uuid
) TO authenticated;

REVOKE ALL ON FUNCTION public.claim_product_submission_cleanup(integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_cleanup(integer)
  TO service_role;

REVOKE ALL ON FUNCTION public.get_approved_product_submission_image(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_approved_product_submission_image(uuid)
  TO service_role;

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
  p_resolved_dsld_id text DEFAULT NULL
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
  END IF;

  RETURN public.review_product_submission_human_internal(
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
END;
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
  text
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
  text
) TO authenticated;

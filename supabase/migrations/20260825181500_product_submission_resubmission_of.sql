-- Add explicit lineage for user retries of rejected product submissions.
--
-- The existing six-argument create function is retained as a locked-down
-- implementation detail so its mature manifest/replay checks stay single-
-- sourced. The public wrapper is the only callable create boundary and adds
-- fail-closed lineage validation before delegating to that implementation.

ALTER TABLE public.product_submissions
  ADD COLUMN resubmission_of uuid
    REFERENCES public.product_submissions(id) ON DELETE SET NULL,
  ADD CONSTRAINT product_submissions_resubmission_not_self CHECK (
    resubmission_of IS NULL OR resubmission_of <> id
  );

CREATE INDEX idx_product_submissions_resubmission_of
  ON public.product_submissions (resubmission_of)
  WHERE resubmission_of IS NOT NULL;

ALTER FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) RENAME TO create_product_submission_v2_internal;

REVOKE ALL ON FUNCTION public.create_product_submission_v2_internal(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_resubmission_of uuid DEFAULT NULL
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
        'other'
      )
      AND target.kind = p_kind
      AND target.normalized_upc IS NOT DISTINCT FROM normalized_upc_value
    FOR SHARE;

    IF NOT FOUND THEN
      -- One message deliberately covers missing, wrong-owner, wrong-state,
      -- wrong-kind, and wrong-identity parents without revealing which.
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

  -- Pin lineage into the idempotent replay identity. The row lock prevents an
  -- already-created submission id from being rebound to another rejection.
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
    SET resubmission_of = p_resubmission_of
    WHERE submission.id = p_submission_id
      AND submission.user_id = caller_id
      AND (
        submission.resubmission_of IS NULL
        OR submission.resubmission_of IS NOT DISTINCT FROM p_resubmission_of
      );
    GET DIAGNOSTICS persisted_count = ROW_COUNT;
    IF persisted_count <> 1 THEN
      RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
    END IF;
  END IF;

  RETURN result_value;
END;
$$;

REVOKE ALL ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb,
  uuid
) TO authenticated;

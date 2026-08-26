-- Keep PL/pgSQL variables distinct from table-column names. The original
-- wrapper used `reviewer_id` for both, so PostgreSQL rejected approvals with
-- `column reference "reviewer_id" is ambiguous` before the human-only gate
-- could complete.
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
  p_product_image_reviewer_object_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  latest_match public.product_submission_match_checks%ROWTYPE;
  transitioned boolean;
BEGIN
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
        AND image.reviewer_id = v_reviewer_id
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
          p_product_image_reviewer_object_id
    WHERE submission_id = p_submission_id;
  END IF;
  RETURN transitioned;
END;
$$;

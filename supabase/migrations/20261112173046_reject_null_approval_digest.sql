-- Reject SQL NULL before any state change; preserve existing authorization and valid-input behavior.
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
     OR p_expected_payload_sha256 IS NULL
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

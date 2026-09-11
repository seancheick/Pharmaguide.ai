-- Reviewer-requested retakes reach the owner.
--
-- The revision machinery (request, open, add, finalize) has existed since
-- 20260909013000, but nothing could use it end to end: a reviewer could not
-- say which panel needed a new photo, the owner was never told, and the owner
-- could not read which photos the current revision holds, so the app could not
-- keep the good ones. This adds exactly those three things. Opening, adding
-- and finalizing a revision are unchanged.

-- 1. Which panels the reviewer needs again. It belongs to the request on
--    `evidence_requested_revision`; a corrected request on the same revision
--    replaces it, and a request on a later revision starts over.
ALTER TABLE public.product_submissions
  ADD COLUMN evidence_request_panels public.product_submission_evidence_category[]
    CHECK (
      evidence_request_panels IS NULL
      OR cardinality(evidence_request_panels) BETWEEN 1 AND 6
    );

-- 2. The request names panels and tells the owner once per revision. The
--    delivery row is the same durable queue review decisions use; its copy is
--    generic, so the app reads what changed when it opens.
DROP FUNCTION public.request_product_submission_evidence(uuid, text, integer, text);
CREATE FUNCTION public.request_product_submission_evidence(
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
     OR submission.promoted_at IS NOT NULL
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
REVOKE ALL ON FUNCTION public.request_product_submission_evidence(uuid, text, text[], integer, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_product_submission_evidence(uuid, text, text[], integer, text)
  TO authenticated;

-- 3. The owner reads which of its photos each revision holds, so a retake can
--    keep the photos the reviewer did not ask for. Membership and state only:
--    request keys, consent and frozen manifests stay server-side.
CREATE POLICY product_submission_evidence_revisions_select_own
  ON public.product_submission_evidence_revisions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.id = submission_id
      AND submission.user_id = (SELECT auth.uid())
  ));
GRANT SELECT (submission_id, revision, photo_ids, ready_at, abandoned_at)
  ON public.product_submission_evidence_revisions TO authenticated;

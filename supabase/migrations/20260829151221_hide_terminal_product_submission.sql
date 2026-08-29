-- User-facing contribution history can hide a terminal failed outcome without
-- deleting the immutable submission, its private evidence, or review events.
-- The audit remains available to the clinical/operator boundary.

ALTER TABLE public.product_submissions
  ADD COLUMN dismissed_at timestamptz,
  ADD CONSTRAINT product_submissions_dismissed_terminal CHECK (
    dismissed_at IS NULL
    OR (
      upload_state = 'ready'
      AND review_status IN ('rejected', 'duplicate')
    )
  );

CREATE FUNCTION public.hide_product_submission(p_submission_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  candidate public.product_submissions%ROWTYPE;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT submission.*
  INTO candidate
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
  FOR UPDATE;

  IF NOT FOUND OR candidate.user_id <> caller_id THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = 'P0002';
  END IF;

  IF candidate.upload_state <> 'ready'
     OR candidate.review_status NOT IN ('rejected', 'duplicate') THEN
    RAISE EXCEPTION 'only failed terminal submissions can be hidden'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.product_submissions
  SET dismissed_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hide_product_submission(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.hide_product_submission(uuid)
  TO authenticated;

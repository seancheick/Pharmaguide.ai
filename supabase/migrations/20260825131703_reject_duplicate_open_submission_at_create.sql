-- Refuse a duplicate-barcode submission when it is CREATED, not when it
-- finalizes. The uniqueness index only guards upload_state = 'ready', so
-- a second submission for the same barcode sailed through create and all
-- photo uploads, then died at finalize — leaving an orphaned pending row
-- and a "retry says it already exists" loop after the user had done all
-- the work. The message carries the index name verbatim because the app
-- maps that substring to its actionable conflict copy.

CREATE FUNCTION public.reject_duplicate_open_submission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.normalized_upc IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.product_submissions AS existing
    WHERE existing.user_id = NEW.user_id
      AND existing.kind = NEW.kind
      AND existing.normalized_upc = NEW.normalized_upc
      AND existing.upload_state = 'ready'
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

CREATE TRIGGER product_submissions_reject_duplicate_open
  BEFORE INSERT ON public.product_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_duplicate_open_submission();

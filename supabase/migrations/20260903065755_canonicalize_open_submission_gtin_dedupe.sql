-- Treat equivalent GTIN widths as one product identity. A UPC-A may be
-- reported by scanners as either 12 digits or as a zero-prefixed EAN-13;
-- both normalize to the same GTIN-14 comparison key.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    WHERE submission.normalized_upc IS NOT NULL
      AND submission.promoted_at IS NULL
      AND submission.upload_state = 'ready'
      AND submission.review_status IN ('submitted', 'under_review', 'approved')
    GROUP BY
      submission.user_id,
      submission.kind,
      lpad(submission.normalized_upc, 14, '0')
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'canonical open-submission duplicates must be resolved before migration'
      USING ERRCODE = '23505';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_duplicate_open_submission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.normalized_upc IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.product_submissions AS existing
    WHERE existing.id <> NEW.id
      AND existing.user_id = NEW.user_id
      AND existing.kind = NEW.kind
      AND lpad(existing.normalized_upc, 14, '0') = lpad(NEW.normalized_upc, 14, '0')
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

DROP INDEX public.idx_product_submissions_user_open_upc;
CREATE UNIQUE INDEX idx_product_submissions_user_open_upc
  ON public.product_submissions (user_id, kind, (lpad(normalized_upc, 14, '0')))
  WHERE normalized_upc IS NOT NULL
    AND promoted_at IS NULL
    AND upload_state = 'ready'
    AND review_status IN ('submitted', 'under_review', 'approved');

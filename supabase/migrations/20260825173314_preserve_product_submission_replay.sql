-- The create RPC is intentionally idempotent: retrying the same immutable
-- submission id must succeed after an ambiguous network response. The
-- create-time duplicate guard still rejects a different submission for the
-- same open barcode, but must not mistake the row being replayed for a
-- duplicate of itself.

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

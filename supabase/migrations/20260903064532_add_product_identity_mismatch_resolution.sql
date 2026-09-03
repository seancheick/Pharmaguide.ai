-- A reviewer-confirmed mismatch between the scanned barcode and submitted
-- label photos is distinct from image quality and from catalog duplication.
-- Keep this enum addition in its own transaction: PostgreSQL must commit a
-- new enum value before later functions can safely reference it.

ALTER TYPE public.product_submission_resolution_code
  ADD VALUE IF NOT EXISTS 'product_identity_mismatch';

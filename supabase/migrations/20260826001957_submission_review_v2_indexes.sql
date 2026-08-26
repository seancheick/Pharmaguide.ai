-- Cover the reviewer and cleanup lookup paths introduced by review v2.
-- The primary/unique indexes do not lead with these foreign-key columns.

CREATE INDEX idx_product_submission_match_checks_reviewer
  ON public.product_submission_match_checks (reviewer_id);

CREATE INDEX idx_product_submission_reviewer_images_submission
  ON public.product_submission_reviewer_images (submission_id);

CREATE INDEX idx_product_submission_reviewer_images_reviewer
  ON public.product_submission_reviewer_images (reviewer_id);

-- Match the pipeline's existing assessment_incomplete share disposition.
-- Preserve immutable snapshots, server-only access and blocked-product guards.
ALTER TABLE public.public_share_snapshots
  DROP CONSTRAINT IF EXISTS share_disposition_value;
ALTER TABLE public.public_share_snapshots
  ADD CONSTRAINT share_disposition_value
  CHECK (catalog_disposition IN ('scored', 'not_scored', 'blocked', 'assessment_incomplete'));

ALTER TABLE public.public_share_snapshots
  DROP CONSTRAINT IF EXISTS share_disposition_score;
ALTER TABLE public.public_share_snapshots
  ADD CONSTRAINT share_disposition_score CHECK (
    (catalog_disposition = 'scored' AND quality_score IS NOT NULL AND quality_tier IS NOT NULL)
    OR
    (catalog_disposition IN ('not_scored', 'blocked', 'assessment_incomplete') AND quality_score IS NULL AND quality_tier IS NULL)
  );

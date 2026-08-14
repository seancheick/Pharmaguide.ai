-- Harden the already-deployed public-share table. Public links remain readable
-- through the website server, which uses the service role and selects one
-- validated short code. PostgREST browser roles receive no table access.

ALTER TABLE public.public_share_snapshots
  ADD COLUMN IF NOT EXISTS catalog_disposition text;

-- Legacy rows did not carry a safety disposition. Preserve scored rows and
-- classify null-score rows conservatively as not_scored; the table was empty
-- when this migration was authored, but this update keeps replay idempotent.
UPDATE public.public_share_snapshots
SET catalog_disposition = CASE
  WHEN quality_score IS NOT NULL THEN 'scored'
  ELSE 'not_scored'
END
WHERE catalog_disposition IS NULL;

ALTER TABLE public.public_share_snapshots
  ALTER COLUMN catalog_disposition SET NOT NULL;

-- Every new share is resolved from a specific immutable release. The table
-- was empty when this migration was authored, so there are no undated legacy
-- snapshots to preserve.
ALTER TABLE public.public_share_snapshots
  ALTER COLUMN catalog_version SET NOT NULL;

ALTER TABLE public.public_share_snapshots
  DROP CONSTRAINT IF EXISTS share_disposition_value;
ALTER TABLE public.public_share_snapshots
  ADD CONSTRAINT share_disposition_value
  CHECK (catalog_disposition IN ('scored', 'not_scored', 'blocked'));

ALTER TABLE public.public_share_snapshots
  DROP CONSTRAINT IF EXISTS share_disposition_score;
ALTER TABLE public.public_share_snapshots
  ADD CONSTRAINT share_disposition_score CHECK (
    (catalog_disposition = 'scored' AND quality_score IS NOT NULL AND quality_tier IS NOT NULL)
    OR
    (catalog_disposition IN ('not_scored', 'blocked') AND quality_score IS NULL AND quality_tier IS NULL)
  );

ALTER TABLE public.public_share_snapshots
  DROP CONSTRAINT IF EXISTS share_blocked_no_highlights;
ALTER TABLE public.public_share_snapshots
  ADD CONSTRAINT share_blocked_no_highlights CHECK (
    catalog_disposition != 'blocked' OR cardinality(highlights) = 0
  );

DROP POLICY IF EXISTS share_snapshots_public_read
  ON public.public_share_snapshots;
REVOKE ALL ON public.public_share_snapshots FROM PUBLIC;
REVOKE ALL ON public.public_share_snapshots FROM anon;
REVOKE ALL ON public.public_share_snapshots FROM authenticated;
GRANT SELECT, INSERT ON public.public_share_snapshots TO service_role;

COMMENT ON TABLE public.public_share_snapshots IS
  'Immutable anonymous product snapshots. Read and written only by the PharmaGuide website service role; no user linkage or public PostgREST access.';

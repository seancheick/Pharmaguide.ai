-- =============================================================================
-- Public share snapshots — the table behind pharmaguide.io/s/{code}
-- =============================================================================
-- Tapping Share on a product in the app POSTs an allowlisted payload to
-- pharmaguide.io/api/share, which mints a short code and writes exactly one row
-- here. The website's /s/{code} route renders that row.
--
-- WHY A SNAPSHOT AND NOT A CATALOG API:
-- The website has no product data — the catalog is a bundled SQLite file on the
-- device and a storage blob for the pipeline. Publishing 180k products to the
-- web to serve a share link would create a second source of truth for scores
-- that immediately drifts from the app. A snapshot instead stores only what the
-- sharer actually saw, stamped with the catalog version they saw it in, so the
-- public page can date the check honestly rather than silently diverging from a
-- score that has since been recomputed.
--
-- PRIVACY: there is deliberately NO user_id, device id, or profile column. A
-- share must never be linkable to the person who created it, and personal-fit
-- results cannot enter this table because the columns to hold them do not
-- exist. This mirrors the boundary ShareService already enforces in Dart.
--
-- Applied to project omayamxacvacrnvdvzhr on 2026-08-13. Recorded here because
-- the app repo version-controls this project's schema; the table is written by
-- the website but owned by the same database.

CREATE TABLE IF NOT EXISTS public.public_share_snapshots (
  code             text        PRIMARY KEY,
  dsld_id          text        NOT NULL,
  product_name     text        NOT NULL,
  brand_name       text,
  -- Null when the product is blocked or not scored. The app gates this and the
  -- website validates it, and the CHECK below makes a fabricated score
  -- impossible even if a future caller forgets: score and tier must both be
  -- present or both absent.
  quality_score    smallint,
  quality_tier     text,
  score_confidence text,
  -- Objectively checkable label facts only (third-party tested, organic,
  -- non-GMO...). Scoring-derived reasons are deliberately excluded until the
  -- ingredient-form citation gap closes: 117 of 271 forms rated "excellent"
  -- (bio_score >= 12) currently carry no evidence reference, and a card that
  -- travels to strangers turns an internal heuristic into a public claim.
  highlights       text[]      NOT NULL DEFAULT '{}',
  catalog_version  text,
  created_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT share_code_format     CHECK (code ~ '^[a-hjkmnp-tv-z2-9]{8}$'),
  CONSTRAINT share_score_range     CHECK (quality_score IS NULL
                                          OR (quality_score >= 0 AND quality_score <= 100)),
  CONSTRAINT share_score_tier_pair CHECK ((quality_score IS NULL) = (quality_tier IS NULL)),
  CONSTRAINT share_highlights_cap  CHECK (array_length(highlights, 1) IS NULL
                                          OR array_length(highlights, 1) <= 3),
  CONSTRAINT share_name_len        CHECK (char_length(product_name) BETWEEN 1 AND 200),
  CONSTRAINT share_brand_len       CHECK (brand_name IS NULL OR char_length(brand_name) <= 200)
);

COMMENT ON TABLE public.public_share_snapshots IS
  'Immutable, anonymous snapshots backing pharmaguide.io/s/{code}. Written only by the website API with the service role; readable by anyone with the code. No user linkage by design.';

CREATE INDEX IF NOT EXISTS public_share_snapshots_created_at_idx
  ON public.public_share_snapshots (created_at DESC);

ALTER TABLE public.public_share_snapshots ENABLE ROW LEVEL SECURITY;

-- Anyone holding a code may read that row. The code IS the capability: 8 chars
-- from a 30-symbol alphabet (~6.6e11 space), unguessable in practice, and the
-- row carries no personal data even if guessed.
DROP POLICY IF EXISTS share_snapshots_public_read ON public.public_share_snapshots;
CREATE POLICY share_snapshots_public_read
  ON public.public_share_snapshots
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- RLS decides WHICH ROWS a role may see; a table-level GRANT decides whether
-- the role may touch the relation at all. A table created by raw SQL does not
-- inherit the grants Supabase applies to dashboard-created tables, so without
-- this the read policy is enforced against a role that cannot reach the table
-- and PostgREST answers 42501 "permission denied" — which reads like a bad API
-- key and is not one.
--
-- SELECT only, deliberately. There is no INSERT grant and no INSERT policy for
-- anon, so the website's service-role write path stays the single door into
-- this table, behind its rate limiter and payload allowlist.
GRANT SELECT ON public.public_share_snapshots TO anon, authenticated;

-- =============================================================================
-- Sprint 5a — user_stacks sync table
-- =============================================================================
-- Apply via: supabase db push (or `supabase migration up`)
--
-- Design notes:
-- - One row per supplement in a signed-in user's stack. Guest users stay
--   local-only; nothing ever leaves their device.
-- - The primary key `id` is a client-generated string (dsldId + microseconds
--   timestamp). Clients are authoritative for id assignment — server never
--   issues ids. This is an offline-first, local-first design.
-- - `type` is constrained to 'supplement'. Medications (type='medication')
--   are PHI and MUST NEVER reach this table. The Flutter client filters
--   medication rows at the query level (StackSyncQueue.dirtyRows) AND the
--   INSERT/UPDATE RLS policies reject them here as a belt-and-suspenders
--   second line of defense.
-- - Soft delete via `deleted_at`. Rows are never hard-deleted so multi-device
--   visibility continues to work — when device A deletes a row, device B
--   pulls the tombstone and hides the row locally.
-- - LWW conflict resolution: `client_updated_at` is compared on upsert. The
--   `server_updated_at` is set by a BEFORE trigger and is what clients
--   compare against for pull sync (not implemented in Sprint 5a — push-only).
-- =============================================================================
-- ⚠️ LEGACY SNAPSHOT — do not apply this file as a fresh bootstrap.
-- It records the original, untracked Sprint 5a shape. The deployed
-- user_stacks was actually built by an earlier untracked migration + remote migration
-- `20260415204654 add_missing_user_stacks_columns` (renamed timing→frequency,
-- added type/name/ingredient_keys, made dsld_id nullable), a different lineage
-- than this snapshot. Its historical differences include:
--   * live has extra nullable cols `supply_count`, `source_device_id` (the
--     client never reads or writes them);
--   * live uses `updated_at` + trigger `user_stacks_updated_at` (→ set_updated_at)
--     instead of this file's `server_updated_at` + trg_user_stacks_server_updated_at.
-- The current authority is explicit and disjoint:
--   * Flutter migration 20260710210013 owns user_stacks, user_usage,
--     pending_products, and increment_usage.
--   * dsld_clean owns export_manifest, catalog_releases, rotate_manifest, and
--     the database-wide default client-access baseline.
-- The medication-PHI backstops are restored by
-- 20260614_user_stacks_phi_backstops.sql, then hardened by the current
-- app-data authority migration. Do not use this snapshot to infer live shape.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_stacks (
  id                 text PRIMARY KEY,
  user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Hard-constrained to supplements. Medications are PHI-local-only.
  type               text NOT NULL DEFAULT 'supplement'
                     CHECK (type = 'supplement'),

  name               text NOT NULL,
  dsld_id            text,
  ingredient_keys    text,   -- JSON-encoded array of canonical ingredient ids
  dosage             text,
  frequency          text,

  -- Timestamps
  added_at           timestamptz NOT NULL DEFAULT now(),
  client_updated_at  timestamptz NOT NULL,
  deleted_at         timestamptz,              -- NULL = active, set = tombstone
  server_updated_at  timestamptz NOT NULL DEFAULT now(),

  -- Ensure (user_id, id) unique as well as id alone. Defends against
  -- accidental id collisions across users.
  CONSTRAINT user_stacks_user_id_id_unique UNIQUE (user_id, id)
);

-- Index for the most common query: "give me all active rows for user X"
CREATE INDEX IF NOT EXISTS idx_user_stacks_user_active
  ON public.user_stacks (user_id)
  WHERE deleted_at IS NULL;

-- Index for pull-sync queries: "what changed since timestamp T for user X"
CREATE INDEX IF NOT EXISTS idx_user_stacks_user_updated
  ON public.user_stacks (user_id, server_updated_at DESC);

-- =============================================================================
-- server_updated_at trigger — always set to NOW on any write
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_user_stacks_server_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.server_updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_stacks_server_updated_at ON public.user_stacks;
CREATE TRIGGER trg_user_stacks_server_updated_at
  BEFORE INSERT OR UPDATE ON public.user_stacks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_user_stacks_server_updated_at();

-- =============================================================================
-- Row Level Security
-- =============================================================================
-- All policies are user-scoped — signed-in users only see/edit their own rows.
-- The `type = 'supplement'` check on INSERT/UPDATE is the second line of
-- defense against medication PHI leakage.

ALTER TABLE public.user_stacks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_can_read_own_stack"
  ON public.user_stacks;
CREATE POLICY "users_can_read_own_stack"
  ON public.user_stacks
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "users_can_insert_own_supplements"
  ON public.user_stacks;
CREATE POLICY "users_can_insert_own_supplements"
  ON public.user_stacks
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND type = 'supplement'
  );

DROP POLICY IF EXISTS "users_can_update_own_supplements"
  ON public.user_stacks;
CREATE POLICY "users_can_update_own_supplements"
  ON public.user_stacks
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND type = 'supplement'
  );

DROP POLICY IF EXISTS "users_can_delete_own_stack"
  ON public.user_stacks;
CREATE POLICY "users_can_delete_own_stack"
  ON public.user_stacks
  FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================================
-- Grants — anon has NO access; authenticated role has RLS-gated CRUD
-- =============================================================================

REVOKE ALL ON public.user_stacks FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_stacks TO authenticated;

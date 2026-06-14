-- =============================================================================
-- 2026-06-14 — user_stacks PHI safety backstops (schema drift repair)
-- =============================================================================
-- Root cause: SCHEMA DRIFT. The live `user_stacks` table was missing the
-- server-side guards the source migration (20260411_user_stacks.sql) mandates
-- to keep medication PHI out of the cloud. Audit of the deployed table found:
--
--   * NO  CHECK (type = 'supplement')            — column-level guard absent
--   * `type` column was NULLABLE, no DEFAULT     — drifted from source
--   * NO  UNIQUE (user_id, id)                   — cross-user id-collision guard
--   * RLS was a single catch-all `FOR ALL` policy with USING (auth.uid() =
--     user_id) and NO `WITH CHECK` — so an authenticated user could INSERT/
--     UPDATE a row with type='medication' for their own id and the DB would
--     accept it. Only the client-side filter (StackSyncQueue.dirtyRows) stood
--     between medication PHI and the cloud.
--
-- Safety rule (non-negotiable, CLAUDE.md): medication rows must NEVER sync.
-- This migration restores the 2nd + 3rd lines of defense (column CHECK + RLS
-- WITH CHECK) so the guarantee no longer depends on the client alone.
--
-- Idempotent and safe on a 0-row table. The granular policies are strictly
-- tighter than the catch-all they replace: legitimate supplement sync is
-- unaffected; only non-supplement writes are newly rejected.
--
-- Apply via: supabase db push   (or paste into the Supabase SQL editor)
-- =============================================================================

-- 1. `type` column — NOT NULL DEFAULT 'supplement' + CHECK (type = 'supplement')
DO $$
BEGIN
  -- Backfill any NULLs (none expected) so SET NOT NULL succeeds.
  UPDATE public.user_stacks SET type = 'supplement' WHERE type IS NULL;

  ALTER TABLE public.user_stacks ALTER COLUMN type SET DEFAULT 'supplement';
  ALTER TABLE public.user_stacks ALTER COLUMN type SET NOT NULL;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname  = 'user_stacks_type_supplement_check'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_type_supplement_check CHECK (type = 'supplement');
  END IF;
END $$;

-- 2. UNIQUE (user_id, id) — defends against cross-user id collision.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname  = 'user_stacks_user_id_id_unique'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_user_id_id_unique UNIQUE (user_id, id);
  END IF;
END $$;

-- 3. RLS — replace the catch-all policy with the source migration's granular
--    set. INSERT/UPDATE enforce type='supplement' as the server-side backstop.
ALTER TABLE public.user_stacks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own stacks"            ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_read_own_stack"           ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_insert_own_supplements"   ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_update_own_supplements"   ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_delete_own_stack"         ON public.user_stacks;

CREATE POLICY "users_can_read_own_stack"
  ON public.user_stacks
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "users_can_insert_own_supplements"
  ON public.user_stacks
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND type = 'supplement'
  );

CREATE POLICY "users_can_update_own_supplements"
  ON public.user_stacks
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND type = 'supplement'
  );

CREATE POLICY "users_can_delete_own_stack"
  ON public.user_stacks
  FOR DELETE
  USING (auth.uid() = user_id);

-- 4. Grants — anon has NO access; authenticated role has RLS-gated CRUD.
REVOKE ALL ON public.user_stacks FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_stacks TO authenticated;

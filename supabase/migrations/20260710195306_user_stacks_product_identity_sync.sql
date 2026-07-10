-- =============================================================================
-- user_stacks product identity sync contract
-- =============================================================================
-- The client generates an entry id for local history, but a user can have one
-- current state per DSLD product. The old live-only partial unique index
-- enforced that active-state invariant without being an upsert target, while
-- Flutter upserted only on `id`; replacing a local row therefore raised 23505.
--
-- This migration makes `(user_id, dsld_id)` the canonical, ordinary UNIQUE
-- constraint used by the client. A tombstone is the current product state, not
-- additional history: client_updated_at selects the latest state before this
-- constraint is added. No foreign keys reference this table (verified before
-- migration), so obsolete remote history rows can be consolidated safely.
-- =============================================================================

-- Preserve exactly the newest state for each product. `updated_at` and `id`
-- only break ties, so a later delete remains a delete and a later re-add
-- remains active.
WITH ranked AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY user_id, dsld_id
      ORDER BY
        client_updated_at DESC,
        COALESCE(
          (to_jsonb(user_stacks) ->> 'updated_at')::timestamptz,
          (to_jsonb(user_stacks) ->> 'server_updated_at')::timestamptz
        ) DESC NULLS LAST,
        id DESC
    ) AS row_number
  FROM public.user_stacks
)
DELETE FROM public.user_stacks AS stack
USING ranked
WHERE stack.ctid = ranked.ctid
  AND ranked.row_number > 1;

-- Every synced supplement originates from the catalog and therefore has a
-- DSLD identity. Enforcing it makes the upsert key total rather than nullable.
ALTER TABLE public.user_stacks
  ALTER COLUMN dsld_id SET NOT NULL;

-- Add the full constraint before removing the old partial index so there is no
-- window where two active rows for the same user/product can be inserted.
ALTER TABLE public.user_stacks
  ADD CONSTRAINT user_stacks_user_dsld_unique UNIQUE (user_id, dsld_id);

DROP INDEX IF EXISTS public.idx_user_stacks_user_dsld_active;

-- LWW is based on client_updated_at, not request arrival order. The existing
-- `user_stacks_updated_at` trigger runs before this `zz_` trigger; returning
-- OLD restores the complete prior row, including updated_at, for stale writes.
-- Entry id breaks a same-instant tie deterministically, matching the initial
-- consolidation query above.
CREATE OR REPLACE FUNCTION public.keep_newest_user_stack_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.client_updated_at < OLD.client_updated_at
     OR (
       NEW.client_updated_at = OLD.client_updated_at
       AND NEW.id < OLD.id
     ) THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zz_user_stacks_keep_newest_state
  ON public.user_stacks;
CREATE TRIGGER zz_user_stacks_keep_newest_state
  BEFORE UPDATE ON public.user_stacks
  FOR EACH ROW
  EXECUTE FUNCTION public.keep_newest_user_stack_state();

-- =============================================================================
-- 2026-06-14 — user_stacks.id type repair (schema drift fix)
-- =============================================================================
-- Symptom (runtime): every stack push failed with
--   22P02 invalid input syntax for type uuid: "1000_1778959783820629"
-- and the dirty row retried forever on each auth/connectivity/add trigger.
--
-- Root cause: SCHEMA DRIFT. The source-of-truth migration
-- (20260411_user_stacks.sql) defines `id text PRIMARY KEY` — the offline-first,
-- client-authoritative id design (id = "<dsldId>_<microseconds>", generated in
-- lib/features/stack/providers/active_stack_provider.dart `_newId`). The client
-- upserts that text id with `onConflict: 'id'`. The DEPLOYED table, however,
-- had `id` typed as `uuid`, so it rejected every real client id.
--
-- This migration realigns the live column to the documented contract. It is
-- idempotent and a no-op on any environment already on `text` (e.g. fresh
-- deploys from 20260411, which create the column as text to begin with).
--
-- uuid -> text is a lossless widening cast; existing uuid values become their
-- canonical text representation. The PRIMARY KEY and the
-- user_stacks_user_id_id_unique (user_id, id) constraint remain valid across
-- the type change.
--
-- Apply via: supabase db push   (or paste into the Supabase SQL editor)
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name  = 'user_stacks'
      AND column_name = 'id'
      AND data_type   = 'uuid'
  ) THEN
    ALTER TABLE public.user_stacks
      ALTER COLUMN id TYPE text USING id::text;
  END IF;
END $$;

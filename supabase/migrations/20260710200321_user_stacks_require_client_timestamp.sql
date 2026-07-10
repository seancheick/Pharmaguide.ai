-- =============================================================================
-- Require a client ordering timestamp for every synced stack product state.
-- =============================================================================
-- `keep_newest_user_stack_state` compares client_updated_at to enforce
-- deterministic last-write-wins. Null timestamps would bypass that ordering,
-- so reject malformed legacy state rather than silently accepting it.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.user_stacks
    WHERE client_updated_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'user_stacks contains rows without client_updated_at; remediate before enabling LWW';
  END IF;

  ALTER TABLE public.user_stacks
    ALTER COLUMN client_updated_at SET NOT NULL;
END$$;

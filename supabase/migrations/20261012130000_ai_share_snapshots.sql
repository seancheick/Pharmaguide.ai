-- =============================================================================
-- AI connector Phase 2 (ADR-009): consented, encrypted, expiring stack snapshots
-- =============================================================================
-- The one scoped exception to "medications never reach Supabase". The phone
-- renders the scoped brief the user previewed and sends it to the
-- ai-share-snapshot edge function with the app's own session. The function
-- encrypts it with AES-256-GCM under a key from its secrets
-- (AI_SHARE_SNAPSHOT_KEY_V<key_version>) and stores only the ciphertext here.
-- mcp-personal decrypts it for the one connection it is bound to.
--
-- By design there is NO plaintext payload column. Encrypted at rest;
-- PharmaGuide's server can decrypt while the share is live; not end-to-end.
-- supabase/tests/ai_connector/snapshots_pre_request.sql pins the column list.
--
-- Lifetime: at most one row per connection (a re-share replaces it). The row
-- goes when the connection or the user is deleted (cascade), and the purge
-- below removes expired rows and rows of connections that are no longer
-- active.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).

-- The composite foreign key below needs (connection_id, user_id) unique on
-- ai_connections; connection_id alone is already the primary key.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'ai_connections_connection_user_unique') THEN
    ALTER TABLE public.ai_connections
      ADD CONSTRAINT ai_connections_connection_user_unique UNIQUE (connection_id, user_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.ai_share_snapshots (
  snapshot_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id uuid NOT NULL REFERENCES public.ai_connections(connection_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  format text NOT NULL CHECK (format = 'pharmaguide-brief-markdown/v1'),
  scope jsonb NOT NULL CHECK (jsonb_typeof(scope) = 'object'),
  stack_revision text CHECK (stack_revision IS NULL OR char_length(stack_revision) <= 128),
  ciphertext bytea NOT NULL,
  nonce bytea NOT NULL,
  key_version smallint NOT NULL CHECK (key_version > 0),
  generated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  CONSTRAINT ai_share_snapshots_one_per_connection UNIQUE (connection_id),
  -- The snapshot's owner is always the connection's owner.
  CONSTRAINT ai_share_snapshots_owner_matches_connection
    FOREIGN KEY (connection_id, user_id)
    REFERENCES public.ai_connections (connection_id, user_id) ON DELETE CASCADE,
  CONSTRAINT ai_share_snapshots_expiry_after_generation CHECK (expires_at > generated_at)
);

COMMENT ON TABLE public.ai_share_snapshots IS
  'ADR-009 Phase 2: one consented, AES-256-GCM encrypted share per ai_connections '
  'row. No plaintext payload column by design; written by ai-share-snapshot, read '
  'by mcp-personal (get_my_stack_snapshot), both with the service role.';
COMMENT ON COLUMN public.ai_share_snapshots.key_version IS
  'Selects the function secret AI_SHARE_SNAPSHOT_KEY_V<key_version>.';

CREATE INDEX IF NOT EXISTS ai_share_snapshots_expires_at
  ON public.ai_share_snapshots (expires_at);
CREATE INDEX IF NOT EXISTS ai_share_snapshots_user
  ON public.ai_share_snapshots (user_id);

-- Service role only. No permissive policy exists, and S1's restrictive policy
-- is kept as defense in depth in case a grant is ever added by mistake.
ALTER TABLE public.ai_share_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_share_snapshots FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.ai_share_snapshots TO service_role;

DROP POLICY IF EXISTS ai_connector_no_oauth_client ON public.ai_share_snapshots;
CREATE POLICY ai_connector_no_oauth_client ON public.ai_share_snapshots
  AS RESTRICTIVE FOR ALL
  USING ((SELECT auth.jwt() ->> 'client_id') IS NULL)
  WITH CHECK ((SELECT auth.jwt() ->> 'client_id') IS NULL);

-- Expiry sweep. mcp-personal already refuses an expired snapshot or a lapsed
-- connection on every call; this removes the ciphertext as well.
CREATE OR REPLACE FUNCTION public.purge_expired_ai_share_snapshots()
RETURNS TABLE (snapshots_deleted integer, connections_expired integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_expired integer;
  v_deleted integer;
BEGIN
  UPDATE public.ai_connections
     SET status = 'expired'
   WHERE status = 'active' AND expires_at <= now();
  GET DIAGNOSTICS v_expired = ROW_COUNT;

  DELETE FROM public.ai_share_snapshots s
   WHERE s.expires_at <= now()
      OR NOT EXISTS (
        SELECT 1 FROM public.ai_connections c
         WHERE c.connection_id = s.connection_id AND c.status = 'active'
      );
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN QUERY SELECT v_deleted, v_expired;
END
$$;
REVOKE ALL ON FUNCTION public.purge_expired_ai_share_snapshots() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_ai_share_snapshots() TO service_role;

-- Every 15 minutes where pg_cron is installed (it is on the hosted project:
-- 20260918160000_admin_submission_notification_outbox.sql). Without pg_cron,
-- run it manually or from any scheduler with the service role:
--   SELECT * FROM public.purge_expired_ai_share_snapshots();
-- (PostgREST: POST /rest/v1/rpc/purge_expired_ai_share_snapshots).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'purge-expired-ai-share-snapshots',
      '*/15 * * * *',
      'SELECT public.purge_expired_ai_share_snapshots()'
    );
  END IF;
END $$;

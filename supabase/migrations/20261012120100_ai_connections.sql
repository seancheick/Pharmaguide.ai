-- =============================================================================
-- AI connector S10, S7, S5: one row per approved assistant connection
-- =============================================================================
-- An `ai_connections` row is written by the website consent route
-- (PharmaGuide Website src/app/api/ai-connections/route.ts, service role) when
-- the user approves an assistant. Every personal MCP tool call resolves its
-- verified OAuth token to exactly one row and requires status = 'active',
-- expires_at in the future and the tool's category in `scope`. A valid token
-- therefore never implies access on its own: Disconnect and expiry take effect
-- on the next call even while the access token is still unexpired.
--
-- `session_id` is bound by the MCP server on the connection's first call (the
-- Auth session does not exist yet when the user approves). Afterwards only
-- that session's tokens resolve to the row.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).

CREATE TABLE IF NOT EXISTS public.ai_connections (
  connection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id text NOT NULL CHECK (btrim(client_id) <> '' AND char_length(client_id) <= 255),
  session_id text CHECK (session_id IS NULL OR (btrim(session_id) <> '' AND char_length(session_id) <= 255)),
  scope jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(scope) = 'object'),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- NOT NULL so a connection can never be open-ended; the gate fails closed.
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT ai_connections_expiry_after_creation CHECK (expires_at > created_at),
  CONSTRAINT ai_connections_revoked_has_time CHECK (status <> 'revoked' OR revoked_at IS NOT NULL)
);

COMMENT ON TABLE public.ai_connections IS
  'One approved AI assistant connection (S10). scope.categories lists what the '
  'connection may read, e.g. {"categories": ["supplements"]}; an empty scope '
  'grants nothing. Written by the website consent route; read by mcp-personal.';

-- One live connection per (user, assistant): resolving by (user_id, client_id)
-- can never be ambiguous. A new approval supersedes the previous row first.
CREATE UNIQUE INDEX IF NOT EXISTS ai_connections_one_active_per_client
  ON public.ai_connections (user_id, client_id)
  WHERE status = 'active';
-- A session belongs to at most one connection.
CREATE UNIQUE INDEX IF NOT EXISTS ai_connections_session_unique
  ON public.ai_connections (session_id)
  WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ai_connections_user_client_created
  ON public.ai_connections (user_id, client_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.mcp_access_log (
  id bigserial PRIMARY KEY,
  connection_id uuid NOT NULL REFERENCES public.ai_connections(connection_id) ON DELETE CASCADE,
  tool text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);

-- By design this table has no payload, argument, result or name column. It
-- records which connection called which tool and when (S7). Adding a content
-- column would turn an audit log into a health-data store;
-- supabase/functions/mcp-personal/access_log_test.ts pins the column list.
COMMENT ON TABLE public.mcp_access_log IS
  'S7 audit: connection, tool name and time only. No payload columns by design.';

CREATE INDEX IF NOT EXISTS mcp_access_log_connection_at
  ON public.mcp_access_log (connection_id, at DESC);

ALTER TABLE public.ai_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mcp_access_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.ai_connections, public.mcp_access_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.mcp_access_log_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_connections, public.mcp_access_log TO authenticated;
GRANT ALL ON public.ai_connections, public.mcp_access_log TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.mcp_access_log_id_seq TO service_role;

-- Owners read their own connections and log rows from an app or website
-- session. Writes happen only through the service role (consent route,
-- Disconnect route, mcp-personal).
DROP POLICY IF EXISTS ai_connections_select_own ON public.ai_connections;
CREATE POLICY ai_connections_select_own ON public.ai_connections
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS mcp_access_log_select_own ON public.mcp_access_log;
CREATE POLICY mcp_access_log_select_own ON public.mcp_access_log
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.ai_connections c
    WHERE c.connection_id = mcp_access_log.connection_id
      AND c.user_id = (SELECT auth.uid())
  ));

-- S1 applies here too: an assistant's own token cannot list connections.
DROP POLICY IF EXISTS ai_connector_no_oauth_client ON public.ai_connections;
CREATE POLICY ai_connector_no_oauth_client ON public.ai_connections
  AS RESTRICTIVE FOR ALL
  USING ((SELECT auth.jwt() ->> 'client_id') IS NULL)
  WITH CHECK ((SELECT auth.jwt() ->> 'client_id') IS NULL);

DROP POLICY IF EXISTS ai_connector_no_oauth_client ON public.mcp_access_log;
CREATE POLICY ai_connector_no_oauth_client ON public.mcp_access_log
  AS RESTRICTIVE FOR ALL
  USING ((SELECT auth.jwt() ->> 'client_id') IS NULL)
  WITH CHECK ((SELECT auth.jwt() ->> 'client_id') IS NULL);

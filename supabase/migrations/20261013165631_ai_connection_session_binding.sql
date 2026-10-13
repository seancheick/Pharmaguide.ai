-- Enforce the existing ai_connections session owner using Auth's original
-- session creation time, which token refresh does not change. This function
-- is an internal service-role RPC; no app/assistant may invoke it directly.
-- Auth source: internal/models/sessions.go (CreatedAt, OAuthClientID, NotAfter).
CREATE OR REPLACE FUNCTION public.bind_ai_connection_session(
  p_connection_id uuid, p_session_id text
) RETURNS SETOF public.ai_connections
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
  UPDATE public.ai_connections AS c
  SET session_id = p_session_id
  FROM auth.sessions AS s
  WHERE c.connection_id = p_connection_id
    AND (c.session_id IS NULL OR c.session_id = p_session_id)
    AND c.status = 'active' AND c.revoked_at IS NULL
    AND c.expires_at > statement_timestamp()
    AND s.id::text = p_session_id
    AND s.user_id = c.user_id
    AND s.oauth_client_id::text = c.client_id
    AND s.created_at >= c.created_at
    AND (s.not_after IS NULL OR s.not_after > statement_timestamp())
  RETURNING c.*;
$$;
REVOKE ALL ON FUNCTION public.bind_ai_connection_session(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_ai_connection_session(uuid,text) TO service_role;
COMMENT ON FUNCTION public.bind_ai_connection_session(uuid,text) IS
  'Internal S10 connection binding and live Auth-session validation; service_role only.';

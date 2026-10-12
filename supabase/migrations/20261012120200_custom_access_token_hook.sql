-- =============================================================================
-- AI connector S2: bind OAuth access tokens to the personal MCP resource
-- =============================================================================
-- Supabase Auth ignores the OAuth `resource` parameter and always issues
-- aud = "authenticated" (supabase/auth#2610, open). A token minted for any other
-- MCP resource on this authorization server would otherwise be accepted by the
-- personal MCP server. This Custom Access Token Hook stamps `aud` with the
-- personal MCP URL for OAuth client tokens only (those carrying `client_id`),
-- and mcp-personal requires exactly that audience.
--
-- App and website sessions carry no `client_id`; their claims pass through
-- unchanged.
--
-- Sean, after applying:
--   1. UPDATE public.ai_connector_config SET value = '<personal MCP URL>'
--      WHERE key = 'personal_mcp_audience';
--      The URL is the function's public URL, e.g.
--      https://<project-ref>.supabase.co/functions/v1/mcp-personal, and must
--      equal the MCP_PERSONAL_RESOURCE_URL secret of the function.
--   2. Dashboard: Authentication -> Hooks -> Customize Access Token (JWT)
--      Claims -> Postgres -> public.custom_access_token_hook -> Enable.
-- Until step 1 the seeded value is an unroutable placeholder, so a token the
-- hook stamps is rejected by mcp-personal (fail closed). If the row is missing
-- or blank, the hook refuses to issue the OAuth token at all.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).
-- Hook contract: https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook

CREATE TABLE IF NOT EXISTS public.ai_connector_config (
  key text PRIMARY KEY CHECK (btrim(key) <> ''),
  value text NOT NULL
);

COMMENT ON TABLE public.ai_connector_config IS
  'Server-only AI connector settings. personal_mcp_audience: the aud the '
  'custom access token hook stamps on OAuth client tokens.';

INSERT INTO public.ai_connector_config (key, value)
VALUES ('personal_mcp_audience', 'https://set-personal-mcp-url.invalid/functions/v1/mcp-personal')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.ai_connector_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_connector_config FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.ai_connector_config TO service_role;
GRANT SELECT ON public.ai_connector_config TO supabase_auth_admin;

DROP POLICY IF EXISTS ai_connector_config_auth_admin_read ON public.ai_connector_config;
CREATE POLICY ai_connector_config_auth_admin_read ON public.ai_connector_config
  AS PERMISSIVE FOR SELECT TO supabase_auth_admin
  USING (true);

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  claims jsonb := event -> 'claims';
  audience text;
BEGIN
  IF claims IS NULL OR (claims ->> 'client_id') IS NULL THEN
    RETURN event;
  END IF;

  SELECT btrim(value) INTO audience
  FROM public.ai_connector_config
  WHERE key = 'personal_mcp_audience';

  IF audience IS NULL OR audience = '' THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'http_code', 500,
      'message', 'The AI connector audience is not configured.'));
  END IF;

  RETURN jsonb_set(event, '{claims,aud}', to_jsonb(audience));
END
$$;

GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC, anon, authenticated;

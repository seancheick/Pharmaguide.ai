-- ADR-009 S2 containment. Stamping a personal audience cannot prove the
-- resource originally requested from this issuer. Until that prerequisite
-- is implemented and verified, refuse third-party issuance and refresh.
-- Normal app / website sessions have no client_id and remain unchanged.
-- This replaces the hook in place; it does not solve resource binding.
-- Requires the existing Auth custom-access-token hook to remain enabled.
-- https://supabase.com/docs/guides/auth/auth-hooks#error-handling
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  IF (event -> 'claims' ->> 'client_id') IS NOT NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Personal AI connections are unavailable until OAuth resource binding is verified.'));
  END IF;
  RETURN event;
END
$$;

COMMENT ON FUNCTION public.custom_access_token_hook(jsonb) IS
  'S2 containment: refuses third-party OAuth issuance and refresh until requested-resource binding is verified; ordinary app sessions pass through unchanged.';

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC, anon, authenticated;

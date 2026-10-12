-- =============================================================================
-- AI connector S1, project-wide: PostgREST refuses an AI assistant's token
-- before any query runs
-- =============================================================================
-- An OAuth access token from Supabase Auth's OAuth server carries the user's
-- full database session plus a `client_id` claim. The restrictive policies in
-- 20261012120000 hide user rows from it, and seven app RPCs refuse it, but 23
-- other SECURITY DEFINER functions that `authenticated` can run (reviewer and
-- worker RPCs, increment_usage, ...) have no per-function guard, and any new
-- function or view would need one too.
--
-- PostgREST runs `pgrst.db_pre_request` after it has switched to the request
-- role and set the verified claims, and before the request's own query, for
-- every table, view, RPC and GraphQL request. One function therefore covers
-- the whole Data API. It reuses the existing guard
-- (public.reject_oauth_client_request, auth.jwt() ->> 'client_id'), so there
-- is one owner of the check. App sessions, the anon key and the service role
-- carry no `client_id` and pass unchanged.
--
-- The restrictive RLS policies and per-RPC guards stay as defense in depth
-- (Storage, Realtime and direct database connections do not run this hook).
--
-- If another pre-request function is ever needed, call it from this one:
-- PostgREST accepts exactly one.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).
-- Test: supabase/tests/ai_connector/snapshots_pre_request.sql.

CREATE OR REPLACE FUNCTION public.pgrst_reject_ai_assistant_tokens()
RETURNS void
LANGUAGE plpgsql
STABLE
-- Definer: the request roles may not run reject_oauth_client_request directly.
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.reject_oauth_client_request();
END
$$;

COMMENT ON FUNCTION public.pgrst_reject_ai_assistant_tokens() IS
  'S1: PostgREST db_pre_request. Raises insufficient_privilege (42501) when the '
  'request claims carry client_id (an AI assistant OAuth token).';

-- PostgREST calls it as the request role.
REVOKE ALL ON FUNCTION public.pgrst_reject_ai_assistant_tokens() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pgrst_reject_ai_assistant_tokens()
  TO anon, authenticated, service_role;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.pgrst_reject_ai_assistant_tokens';
NOTIFY pgrst, 'reload config';

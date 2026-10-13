-- AI connector SQL suite, part 2: Phase 2 snapshots (S1, S5) and the
-- project-wide PostgREST pre-request guard (S1). Runs after
-- restrictive_rls.sql, which creates the aic helpers and seeds two users.
-- Every check raises on failure, and psql stops on the first error.

-- What PostgREST does per request with pgrst.db_pre_request set: switch to the
-- request role with the verified claims, run the pre-request function, then
-- the query. A raise in the pre-request ends the request before any query.
CREATE FUNCTION aic.postgrest_request(p_user uuid, p_client_id text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  PERFORM aic.act_as(p_user, p_client_id);
  PERFORM public.pgrst_reject_ai_assistant_tokens();
  EXECUTE p_sql;
END $$;

-- 1. The pre-request guard is installed for every PostgREST request.
DO $$ BEGIN
  PERFORM aic.assert(EXISTS (
    SELECT 1 FROM pg_db_role_setting s
    WHERE s.setrole = 'authenticator'::regrole AND s.setdatabase = 0
      AND 'pgrst.db_pre_request=public.pgrst_reject_ai_assistant_tokens' = ANY (s.setconfig)
  ), 'authenticator runs pgrst_reject_ai_assistant_tokens before every request');
  PERFORM aic.assert((SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
    FROM pg_proc p WHERE p.oid = 'public.pgrst_reject_ai_assistant_tokens()'::regprocedure),
    'pre-request guard is SECURITY DEFINER with a pinned search_path');
  PERFORM aic.assert(has_function_privilege('anon', 'public.pgrst_reject_ai_assistant_tokens()', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.pgrst_reject_ai_assistant_tokens()', 'EXECUTE')
    AND has_function_privilege('service_role', 'public.pgrst_reject_ai_assistant_tokens()', 'EXECUTE'),
    'every PostgREST request role can run the pre-request guard');
END $$;

-- 2. It raises insufficient_privilege for a client_id claim and passes
--    without one (app session, anon key, service role, no claims at all).
DO $$
DECLARE
  caught boolean := false;
BEGIN
  PERFORM aic.act_as(aic.user_id(1), 'client-claude');
  BEGIN
    PERFORM public.pgrst_reject_ai_assistant_tokens();
  EXCEPTION WHEN insufficient_privilege THEN caught := true;
  END;
  PERFORM aic.assert(caught, 'pre-request guard refuses an AI assistant token');
  PERFORM aic.act_as(aic.user_id(1), NULL);
  PERFORM public.pgrst_reject_ai_assistant_tokens();
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
  PERFORM public.pgrst_reject_ai_assistant_tokens();
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('role', 'service_role', true);
  PERFORM public.pgrst_reject_ai_assistant_tokens();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
  PERFORM public.pgrst_reject_ai_assistant_tokens();
END $$;
RESET role;

-- 3. increment_usage, one of the privileged functions with no per-function
--    guard, is unreachable through PostgREST with an assistant token, and
--    still serves the app session.
DO $$
DECLARE
  caught boolean := false;
  before_row text;
BEGIN
  SELECT u::text INTO before_row FROM public.user_usage u WHERE user_id = aic.user_id(1);
  BEGIN
    PERFORM aic.postgrest_request(aic.user_id(1), 'client-claude',
      format('SELECT public.increment_usage(%L::uuid, %L)', aic.user_id(1), 'scan'));
  EXCEPTION WHEN insufficient_privilege THEN caught := true;
  END;
  PERFORM set_config('role', 'supabase_admin', true);
  PERFORM aic.assert(caught, 'increment_usage refused for an AI assistant token');
  PERFORM aic.assert((SELECT u::text FROM public.user_usage u WHERE user_id = aic.user_id(1)) = before_row,
    'assistant token changed no usage row');
  PERFORM aic.postgrest_request(aic.user_id(1), NULL,
    format('SELECT public.increment_usage(%L::uuid, %L)', aic.user_id(1), 'scan'));
  PERFORM set_config('role', 'supabase_admin', true);
  PERFORM aic.assert((SELECT u::text FROM public.user_usage u WHERE user_id = aic.user_id(1)) <> before_row,
    'app session still increments usage');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;
RESET role;

-- 4. ai_share_snapshots: no plaintext column, service role only, restrictive.
DO $$ BEGIN
  PERFORM aic.assert(
    (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'ai_share_snapshots')
    = ARRAY['snapshot_id', 'connection_id', 'user_id', 'format', 'scope', 'stack_revision',
            'ciphertext', 'nonce', 'key_version', 'generated_at', 'expires_at'],
    'ai_share_snapshots has exactly the encrypted columns (no plaintext payload)');
  PERFORM aic.assert((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ai_share_snapshots'::regclass),
    'RLS enabled on ai_share_snapshots');
  PERFORM aic.assert(NOT has_table_privilege('authenticated', 'public.ai_share_snapshots', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.ai_share_snapshots', 'INSERT')
    AND NOT has_table_privilege('anon', 'public.ai_share_snapshots', 'SELECT'),
    'app and anon roles cannot touch snapshots');
  PERFORM aic.assert(has_table_privilege('service_role', 'public.ai_share_snapshots', 'SELECT')
    AND has_table_privilege('service_role', 'public.ai_share_snapshots', 'INSERT'),
    'service role reads and writes snapshots');
  PERFORM aic.assert(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'ai_share_snapshots' AND policyname = 'ai_connector_no_oauth_client'
    AND permissive = 'RESTRICTIVE' AND cmd = 'ALL'), 'restrictive client_id policy on ai_share_snapshots');
  PERFORM aic.assert(NOT has_function_privilege('authenticated', 'public.purge_expired_ai_share_snapshots()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.purge_expired_ai_share_snapshots()', 'EXECUTE'),
    'only the service role and cron run the purge');
  PERFORM aic.assert((SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
    FROM pg_proc p WHERE p.oid = 'public.purge_expired_ai_share_snapshots()'::regprocedure),
    'purge is SECURITY DEFINER with a pinned search_path');
END $$;

-- 5. One snapshot per connection; the owner must match the connection's user.
DO $$ BEGIN
  INSERT INTO public.ai_share_snapshots (connection_id, user_id, format, scope, ciphertext, nonce, key_version, expires_at)
  VALUES ('10000000-0000-0000-0000-000000000001', aic.user_id(1), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now() + interval '1 day');
  BEGIN
    INSERT INTO public.ai_share_snapshots (connection_id, user_id, format, scope, ciphertext, nonce, key_version, expires_at)
    VALUES ('10000000-0000-0000-0000-000000000001', aic.user_id(1), 'pharmaguide-brief-markdown/v1', '{}',
            '\x01', '\x01', 1, now() + interval '1 day');
    RAISE EXCEPTION 'FAIL: second snapshot for one connection';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.ai_share_snapshots (connection_id, user_id, format, scope, ciphertext, nonce, key_version, expires_at)
    VALUES ('10000000-0000-0000-0000-000000000002', aic.user_id(1), 'pharmaguide-brief-markdown/v1', '{}',
            '\x01', '\x01', 1, now() + interval '1 day');
    RAISE EXCEPTION 'FAIL: snapshot owned by a user other than the connection''s';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;

-- 6. S5: deleting a connection (Disconnect purge, delete-account's explicit
--    ai_connections delete) or the auth user removes its snapshot.
DO $$ BEGIN
  INSERT INTO public.ai_share_snapshots (connection_id, user_id, format, scope, ciphertext, nonce, key_version, expires_at)
  VALUES ('10000000-0000-0000-0000-000000000001', aic.user_id(1), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now() + interval '1 day'),
         ('10000000-0000-0000-0000-000000000002', aic.user_id(2), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now() + interval '1 day');
  DELETE FROM public.ai_connections WHERE user_id = aic.user_id(1);
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.ai_share_snapshots WHERE user_id = aic.user_id(1)),
    'deleting the connection deletes its snapshot');
  DELETE FROM auth.users WHERE id = aic.user_id(2);
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.ai_share_snapshots), 'deleting the user deletes its snapshot');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;

-- 7. The purge deletes expired snapshots and snapshots of connections that
--    are no longer active, marks lapsed connections expired, and leaves live
--    ones alone.
DO $$
DECLARE
  purged record;
BEGIN
  INSERT INTO auth.users (id) VALUES (aic.user_id(3));
  INSERT INTO public.ai_connections (connection_id, user_id, client_id, scope, created_at, expires_at)
  VALUES ('10000000-0000-0000-0000-000000000003', aic.user_id(3), 'client-chatgpt', '{}',
          now() - interval '2 days', now() - interval '1 day');
  INSERT INTO public.ai_share_snapshots (connection_id, user_id, format, scope, ciphertext, nonce, key_version,
                                         generated_at, expires_at)
  VALUES ('10000000-0000-0000-0000-000000000001', aic.user_id(1), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now() - interval '2 days', now() - interval '1 minute'),
         ('10000000-0000-0000-0000-000000000002', aic.user_id(2), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now(), now() + interval '1 day'),
         ('10000000-0000-0000-0000-000000000003', aic.user_id(3), 'pharmaguide-brief-markdown/v1', '{}',
          '\x00', '\x00', 1, now() - interval '2 days', now() + interval '1 day');
  SELECT * INTO purged FROM public.purge_expired_ai_share_snapshots();
  PERFORM aic.assert(purged.snapshots_deleted = 2 AND purged.connections_expired = 1,
    'purge reports two snapshots and one connection, got ' || purged::text);
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.ai_share_snapshots WHERE user_id = aic.user_id(1)),
    'expired snapshot deleted');
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.ai_share_snapshots WHERE user_id = aic.user_id(3)),
    'snapshot of a lapsed connection deleted');
  PERFORM aic.assert(EXISTS (SELECT 1 FROM public.ai_share_snapshots WHERE user_id = aic.user_id(2)),
    'live snapshot kept');
  PERFORM aic.assert((SELECT status FROM public.ai_connections
    WHERE connection_id = '10000000-0000-0000-0000-000000000003') = 'expired', 'lapsed connection marked expired');
  PERFORM aic.assert((SELECT count(*) FROM public.ai_connections WHERE status = 'active') = 2,
    'live connections untouched');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;

-- 8. S3/S4 display fields on ai_connections: nullable, non-blank, <= 200.
DO $$ BEGIN
  UPDATE public.ai_connections SET client_name = 'Claude', callback_host = 'claude.ai'
  WHERE connection_id = '10000000-0000-0000-0000-000000000001';
  PERFORM aic.assert((SELECT client_name = 'Claude' AND callback_host = 'claude.ai' FROM public.ai_connections
    WHERE connection_id = '10000000-0000-0000-0000-000000000001'), 'display fields stored');
  BEGIN
    UPDATE public.ai_connections SET client_name = repeat('x', 201)
    WHERE connection_id = '10000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL: client_name over 200 characters';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.ai_connections SET callback_host = ' '
    WHERE connection_id = '10000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL: blank callback_host';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM aic.assert((SELECT client_name IS NULL AND callback_host IS NULL FROM public.ai_connections
    WHERE connection_id = '10000000-0000-0000-0000-000000000002'), 'older rows stay null');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;

SELECT 'AI connector snapshot and pre-request tests passed.' AS result;

SELECT aic.assert(to_regprocedure('public.bind_ai_connection_session(uuid,text)') IS NOT NULL,
  'authoritative session binding RPC exists');

DO $$
DECLARE
  c uuid := '50000000-0000-0000-0000-000000000001';
  s uuid := '60000000-0000-0000-0000-000000000001';
  client uuid := '70000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM aic.assert(NOT has_function_privilege('anon', 'public.bind_ai_connection_session(uuid,text)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.bind_ai_connection_session(uuid,text)', 'EXECUTE')
    AND has_function_privilege('service_role', 'public.bind_ai_connection_session(uuid,text)', 'EXECUTE'),
    'session binding RPC is service-only');
  INSERT INTO public.ai_connections(connection_id,user_id,client_id,created_at,expires_at)
    VALUES(c,aic.user_id(1),client::text,now()-interval '1 minute',now()+interval '1 day');
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'missing session denied');
  INSERT INTO auth.sessions(id,user_id,oauth_client_id,created_at)
    VALUES(s,aic.user_id(1),client,now()-interval '1 minute'-interval '1 microsecond');
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'older session denied even within consent second');
  UPDATE auth.sessions SET created_at=now(),user_id=aic.user_id(2) WHERE id=s;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'wrong user denied');
  UPDATE auth.sessions SET user_id=aic.user_id(1),oauth_client_id=NULL WHERE id=s;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'app session denied');
  UPDATE auth.sessions SET oauth_client_id='70000000-0000-0000-0000-000000000002' WHERE id=s;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'wrong OAuth client denied');
  UPDATE auth.sessions SET oauth_client_id=client,not_after=now()-interval '1 second' WHERE id=s;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'ended session denied');
  UPDATE auth.sessions SET not_after=NULL WHERE id=s;
  PERFORM set_config('role','service_role',true);
  PERFORM aic.assert(EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text) WHERE session_id=s::text), 'current session binds using service role');
  PERFORM aic.assert(EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'bound session validates again after token refresh');
  PERFORM set_config('role','supabase_admin',true);
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,'60000000-0000-0000-0000-000000000002')), 'another session cannot take bound grant');
  DELETE FROM auth.sessions WHERE id=s;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'Auth-revoked bound session immediately denied');
  INSERT INTO auth.sessions(id,user_id,oauth_client_id,created_at) VALUES(s,aic.user_id(1),client,now());
  UPDATE public.ai_connections SET revoked_at=now() WHERE connection_id=c;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'revoked_at denies even if active status');
  UPDATE public.ai_connections SET revoked_at=NULL,expires_at=now()-interval '1 second' WHERE connection_id=c;
  PERFORM aic.assert(NOT EXISTS(SELECT 1 FROM public.bind_ai_connection_session(c,s::text)), 'expired connection denied');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE='Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;
RESET role;

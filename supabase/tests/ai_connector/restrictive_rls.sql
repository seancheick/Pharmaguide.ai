-- AI connector SQL suite (S1, S2, S5, S7, S10). Runs after the full migration
-- chain in a disposable database; see scripts/test_ai_connector_rls.sh.
-- Every check raises on failure, and psql stops on the first error.
CREATE SCHEMA aic;
GRANT USAGE ON SCHEMA aic TO PUBLIC;

CREATE FUNCTION aic.assert(p_value boolean, p_message text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF p_value IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', p_message; END IF;
END $$;

-- What PostgREST does per request: a local role plus the verified claims.
CREATE FUNCTION aic.act_as(p_user uuid, p_client_id text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  PERFORM set_config('request.jwt.claims', (jsonb_build_object(
    'sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')
    || CASE WHEN p_client_id IS NULL THEN '{}'::jsonb
            ELSE jsonb_build_object('client_id', p_client_id) END)::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE FUNCTION aic.user_id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE
AS $$ SELECT ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;

INSERT INTO auth.users (id) VALUES (aic.user_id(1)), (aic.user_id(2));

-- One owned row per user in the tables simple enough to seed directly.
INSERT INTO public.user_stacks (id, user_id, name, dsld_id, client_updated_at)
VALUES ('stack-a', aic.user_id(1), 'Magnesium Glycinate', '1001', now()),
       ('stack-b', aic.user_id(2), 'Fish Oil', '2002', now());
INSERT INTO public.user_usage (user_id) VALUES (aic.user_id(1)), (aic.user_id(2));
INSERT INTO storage.objects (bucket_id, name, owner_id)
VALUES ('product-submission-photos', aic.user_id(1) || '/a.jpg', aic.user_id(1)::text);
INSERT INTO public.ai_connections (connection_id, user_id, client_id, scope, expires_at)
VALUES ('10000000-0000-0000-0000-000000000001', aic.user_id(1), 'client-claude',
        '{"categories": ["supplements"]}', now() + interval '1 day'),
       ('10000000-0000-0000-0000-000000000002', aic.user_id(2), 'client-claude',
        '{"categories": ["supplements"]}', now() + interval '1 day');
INSERT INTO public.mcp_access_log (connection_id, tool)
VALUES ('10000000-0000-0000-0000-000000000001', 'get_my_supplements');

-- 1. Behaviour: the same user reads their own rows without client_id and
--    nothing with it, and cannot write with it.
BEGIN;
SELECT aic.act_as(aic.user_id(1), NULL);
SELECT aic.assert((SELECT count(*) FROM public.user_stacks) = 1, 'app session reads own stack row');
SELECT aic.assert((SELECT count(*) FROM public.user_usage) = 1, 'app session reads own usage row');
SELECT aic.assert((SELECT count(*) FROM public.ai_connections) = 1, 'app session reads own connection only');
SELECT aic.assert((SELECT count(*) FROM public.mcp_access_log) = 1, 'app session reads own log row');
ROLLBACK;

BEGIN;
SELECT aic.act_as(aic.user_id(1), 'client-claude');
SELECT aic.assert((SELECT count(*) FROM public.user_stacks) = 0, 'OAuth token reads no stack rows');
SELECT aic.assert((SELECT count(*) FROM public.user_usage) = 0, 'OAuth token reads no usage rows');
SELECT aic.assert((SELECT count(*) FROM public.ai_connections) = 0, 'OAuth token reads no connections');
SELECT aic.assert((SELECT count(*) FROM public.mcp_access_log) = 0, 'OAuth token reads no log rows');
ROLLBACK;

DO $$ BEGIN
  PERFORM aic.act_as(aic.user_id(1), 'client-claude');
  BEGIN
    INSERT INTO public.user_stacks (id, user_id, name, dsld_id, client_updated_at)
    VALUES ('stack-oauth', aic.user_id(1), 'Injected', '3003', now());
    RAISE EXCEPTION 'FAIL: OAuth token inserted a stack row';
  EXCEPTION WHEN insufficient_privilege THEN NULL; -- RLS WITH CHECK violation
  END;
  BEGIN
    UPDATE public.user_stacks SET name = 'Renamed' WHERE id = 'stack-a';
    PERFORM aic.assert(NOT FOUND, 'OAuth token updated no stack row');
  END;
END $$;
RESET role;

-- Storage: a temporary owner-read policy proves the restrictive policy, not the
-- absence of a permissive one, is what hides the object.
BEGIN;
CREATE POLICY aic_owner_read ON storage.objects FOR SELECT TO authenticated
  USING (owner_id = (SELECT auth.uid())::text);
SELECT aic.act_as(aic.user_id(1), NULL);
SELECT aic.assert((SELECT count(*) FROM storage.objects) = 1, 'app session reads own object');
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","client_id":"client-claude"}', true);
SELECT aic.assert((SELECT count(*) FROM storage.objects) = 0, 'OAuth token reads no storage objects');
ROLLBACK;

-- 2. Structure: every user-owned table and storage.objects carries the
--    restrictive policy for all commands.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'public.user_stacks', 'public.user_usage',
    'public.device_push_tokens',
    'public.product_submissions',
    'public.product_submission_mismatch_details', 'public.product_submission_missing_details',
    'public.product_submission_photos', 'public.product_submission_evidence_revisions',
    'public.product_contribution_ledger', 'public.ai_connections', 'public.mcp_access_log',
    'storage.objects'
  ] LOOP
    PERFORM aic.assert(EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname || '.' || tablename = t
        AND policyname = 'ai_connector_no_oauth_client'
        AND permissive = 'RESTRICTIVE' AND cmd = 'ALL'
        AND qual LIKE '%client_id%' AND with_check LIKE '%client_id%'
    ), 'restrictive client_id policy on ' || t);
  END LOOP;
END $$;

-- 3. Coverage: any public table a signed-in user can reach through a
--    permissive policy must carry the restrictive policy, unless it holds only
--    public data. A new user-owned table without it fails here.
DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(DISTINCT p.tablename, ', ') INTO missing
  FROM pg_policies p
  WHERE p.schemaname = 'public'
    AND p.permissive = 'PERMISSIVE'
    AND (p.roles && ARRAY['authenticated', 'public']::name[])
    AND p.tablename NOT IN (
      'safety_alert_releases',   -- public alert-release metadata, readable by anon
      'public_share_snapshots',  -- public product-share snapshots, keyed by code
      'export_manifest',        -- public catalog distribution metadata
      'catalog_releases'        -- public catalog distribution metadata
    )
    AND NOT EXISTS (
      SELECT 1 FROM pg_policies r
      WHERE r.schemaname = 'public' AND r.tablename = p.tablename
        AND r.policyname = 'ai_connector_no_oauth_client' AND r.permissive = 'RESTRICTIVE'
    );
  PERFORM aic.assert(missing IS NULL, 'tables reachable without the S1 policy: ' || coalesce(missing, ''));
END $$;

-- 4. The app's SECURITY DEFINER RPCs refuse an OAuth token before doing
--    anything, and still run for an app session.
DO $$
DECLARE
  fn record;
  call text;
  caught boolean;
BEGIN
  FOR fn IN
    SELECT p.oid, p.proname, p.proisstrict, p.prosrc, p.pronargs
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'create_product_submission', 'finalize_product_submission', 'hide_product_submission',
      'get_product_submission_intake', 'add_product_submission_evidence',
      'set_product_submission_display_name', 'open_product_submission_evidence_revision',
      'request_product_submission_evidence', 'create_product_submission_reviewer_evidence_revision')
  LOOP
    PERFORM aic.assert(fn.prosrc LIKE '%PERFORM public.reject_oauth_client_request();%',
      fn.proname || ' keeps the S1 guard');
    PERFORM aic.assert(NOT fn.proisstrict, fn.proname || ' is not STRICT (NULL args would skip the guard)');
    call := format('SELECT public.%I(%s)', fn.proname,
      (SELECT string_agg('NULL', ', ') FROM generate_series(1, fn.pronargs)));
    caught := false;
    BEGIN
      PERFORM aic.act_as(aic.user_id(1), 'client-claude');
      EXECUTE call;
    EXCEPTION WHEN insufficient_privilege THEN
      caught := SQLERRM = 'AI assistant connections cannot call this function';
    END;
    PERFORM aic.assert(caught, fn.proname || ' refuses an OAuth client token');
    -- An app session passes the guard and fails later on its own checks.
    BEGIN
      PERFORM aic.act_as(aic.user_id(1), NULL);
      EXECUTE call;
    EXCEPTION WHEN others THEN
      PERFORM aic.assert(SQLERRM <> 'AI assistant connections cannot call this function',
        fn.proname || ' still serves app sessions');
    END;
  END LOOP;
  -- Internal guarded helpers may be added without becoming new API endpoints.
  -- Pin the public mobile signatures actually exercised above, not a global
  -- count of function bodies containing the guard text.
  PERFORM aic.assert((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'create_product_submission', 'finalize_product_submission', 'hide_product_submission',
      'get_product_submission_intake', 'add_product_submission_evidence',
      'set_product_submission_display_name', 'open_product_submission_evidence_revision',
      'request_product_submission_evidence', 'create_product_submission_reviewer_evidence_revision')) = 9,
    'all nine guarded mobile signatures remain present without ambiguous overloads');
END $$;
RESET role;

-- 5. S2 containment: until the issuer proves original requested-resource
--    binding, refuse third-party issuance and refresh regardless of audience.
--    Ordinary app / website sessions pass through unchanged.
DO $$
DECLARE
  app_event jsonb := '{"user_id":"u","claims":{"aud":"authenticated","sub":"u","role":"authenticated"}}';
  oauth_event jsonb := '{"user_id":"u","claims":{"aud":"authenticated","sub":"u","role":"authenticated","client_id":"c"}}';
  event jsonb;
  result jsonb;
  audience jsonb;
  method text;
BEGIN
  UPDATE public.ai_connector_config SET value = 'https://ref.supabase.co/functions/v1/mcp-personal'
  WHERE key = 'personal_mcp_audience';
  PERFORM set_config('role', 'supabase_auth_admin', true);
  FOREACH method IN ARRAY ARRAY['password', 'oauth', 'token_refresh'] LOOP
    event := app_event || jsonb_build_object('authentication_method', method);
    PERFORM aic.assert(public.custom_access_token_hook(event) = event,
      'ordinary app session unchanged: ' || method);
  END LOOP;
  FOREACH method IN ARRAY ARRAY['oauth_provider/authorization_code', 'token_refresh'] LOOP
    FOR audience IN SELECT value FROM jsonb_array_elements(
      '["authenticated", "https://ref.supabase.co/functions/v1/mcp-personal", "https://attacker.invalid/mcp", ["authenticated", "https://ref.supabase.co/functions/v1/mcp-personal"], null]'::jsonb
    ) LOOP
      event := jsonb_set(oauth_event, '{claims,aud}', audience)
        || jsonb_build_object('authentication_method', method);
      result := public.custom_access_token_hook(event);
      PERFORM aic.assert(result #>> '{error,http_code}' = '403'
        AND result #>> '{error,message}' = 'Personal AI connections are temporarily unavailable.'
        AND NOT (result ? 'claims'),
        'OAuth token refused regardless of audience: ' || method || ' ' || audience::text);
    END LOOP;
  END LOOP;
  PERFORM set_config('role', 'supabase_admin', true);
  UPDATE public.ai_connector_config SET value = ' ' WHERE key = 'personal_mcp_audience';
  PERFORM set_config('role', 'supabase_auth_admin', true);
  result := public.custom_access_token_hook(oauth_event);
  PERFORM aic.assert(result #>> '{error,http_code}' = '403', 'blank config cannot permit OAuth issuance');
  PERFORM set_config('role', 'supabase_admin', true);
  PERFORM aic.assert(NOT has_function_privilege('authenticated', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
    'authenticated cannot run the hook');
  PERFORM aic.assert(NOT has_function_privilege('anon', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
    'anon cannot run the hook');
  PERFORM aic.assert(NOT has_table_privilege('authenticated', 'public.ai_connector_config', 'SELECT'),
    'authenticated cannot read the connector config');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;
RESET role;

-- 6. S10 schema: writes only through the service role; one active connection
--    per (user, assistant); never open-ended.
DO $$ BEGIN
  PERFORM aic.assert(NOT has_table_privilege('authenticated', 'public.ai_connections', 'INSERT'),
    'authenticated cannot insert connections');
  PERFORM aic.assert(NOT has_table_privilege('authenticated', 'public.mcp_access_log', 'INSERT'),
    'authenticated cannot insert log rows');
  BEGIN
    INSERT INTO public.ai_connections (user_id, client_id, expires_at)
    VALUES (aic.user_id(1), 'client-claude', now() + interval '1 day');
    RAISE EXCEPTION 'FAIL: second active connection for the same assistant';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.ai_connections (user_id, client_id, expires_at, status)
    VALUES (aic.user_id(1), 'client-other', NULL, 'active');
    RAISE EXCEPTION 'FAIL: connection without expiry';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM aic.assert(
    (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'mcp_access_log')
    = ARRAY['id', 'connection_id', 'tool', 'at'], 'mcp_access_log has no payload column');
END $$;

-- 7. S5: deleting the auth user purges connections and their log rows.
DO $$ BEGIN
  DELETE FROM auth.users WHERE id = aic.user_id(1);
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.ai_connections WHERE user_id = aic.user_id(1)),
    'connections purged with the user');
  PERFORM aic.assert(NOT EXISTS (SELECT 1 FROM public.mcp_access_log
    WHERE connection_id = '10000000-0000-0000-0000-000000000001'), 'log rows purged with the user');
  PERFORM aic.assert(EXISTS (SELECT 1 FROM public.ai_connections WHERE user_id = aic.user_id(2)),
    'other users untouched');
  RAISE EXCEPTION 'aic rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
END $$;



-- New reviewer RPCs delegate authorization through the existing reviewer owner.
-- An OAuth token belonging to an actual reviewer must still fail at the OAuth
-- fence, not merely because an unrelated test user lacks reviewer membership.
BEGIN;
INSERT INTO public.product_submission_reviewers(user_id) VALUES(aic.user_id(1)) ON CONFLICT DO NOTHING;
DO $$
DECLARE fn record; caught boolean; call text; seen integer := 0;
BEGIN
  FOR fn IN SELECT p.proname,p.pronargs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('prepare_product_submission_approval_payload','save_product_submission_reviewer_draft','reopen_product_submission_approval','correct_product_submission_barcode')
  LOOP
    seen := seen + 1;
    call := format('SELECT public.%I(%s)',fn.proname,(SELECT string_agg('NULL',',') FROM generate_series(1,fn.pronargs)));
    caught := false;
    BEGIN
      PERFORM aic.act_as(aic.user_id(1),'client-claude');
      EXECUTE call;
    EXCEPTION WHEN insufficient_privilege THEN
      caught := SQLERRM='AI assistant connections cannot call this function';
    WHEN others THEN
      caught := false;
    END;
    PERFORM aic.assert(caught,fn.proname || ' refuses an OAuth reviewer before touching private review state');
  END LOOP;
  PERFORM aic.assert(seen=4,'new and corrected reviewer signatures are all covered');
END $$;
ROLLBACK;
RESET role;

SELECT 'AI connector SQL tests passed.' AS result;

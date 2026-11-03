-- Backend security suite (A6): identities, seed rows and the runners.
-- Runs after the full deployment stream in a disposable database; see
-- scripts/test_backend_security.sh. A check raises to fail.
CREATE SCHEMA sec;
GRANT USAGE ON SCHEMA sec TO PUBLIC;
-- Filled from lib/ by app_reads.py, so these reads can't drift from the app.
CREATE TABLE sec.app_reads(parent_table text NOT NULL, table_name text NOT NULL, embedded_fk text, columns text NOT NULL);
CREATE TABLE sec.check_results(name text PRIMARY KEY, result text NOT NULL);
CREATE TABLE sec.mutation_results(name text PRIMARY KEY, check_name text NOT NULL, result text NOT NULL);

CREATE FUNCTION sec.uid(p_who text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_who
    WHEN 'A' THEN 'a0000000-0000-4000-8000-000000000001'
    WHEN 'B' THEN 'b0000000-0000-4000-8000-000000000002'
    WHEN 'R' THEN 'c0000000-0000-4000-8000-000000000003'
    WHEN 'W' THEN 'd0000000-0000-4000-8000-000000000004'
  END::uuid $$;
CREATE FUNCTION sec.submission() RETURNS uuid LANGUAGE sql IMMUTABLE
  AS $$ SELECT 'a1000000-0000-4000-8000-000000000001'::uuid $$;
CREATE FUNCTION sec.session(p_who text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_who
    WHEN 'A' THEN 'a2000000-0000-4000-8000-000000000001'
    WHEN 'A2' THEN 'a3000000-0000-4000-8000-000000000001'
    WHEN 'B' THEN 'b2000000-0000-4000-8000-000000000002'
  END::uuid $$;

-- What PostgREST does per request: a local role plus the verified claims.
-- 'anon', a user letter, or 'oauth:A' for an AI assistant's token for user A.
CREATE FUNCTION sec.act(p_as text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE who text := replace(p_as, 'oauth:', ''); claims jsonb;
BEGIN
  IF p_as = 'anon' THEN
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('role', 'anon', true);
    RETURN;
  END IF;
  claims := jsonb_build_object('sub', sec.uid(who), 'role', 'authenticated', 'aud', 'authenticated',
    'is_anonymous', false, 'session_id', sec.session(who));
  IF p_as LIKE 'oauth:%' THEN
    claims := claims || jsonb_build_object('client_id', 'a6-assistant');
  END IF;
  PERFORM set_config('request.jwt.claims', claims::text, true);
  PERFORM set_config('request.jwt.claim.sub', sec.uid(who)::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

-- Runs one statement as an identity and always rolls it back. Returns
-- 'rows:<n>' when the statement ran, 'denied:<sqlstate>' when it raised.
CREATE FUNCTION sec.try(p_as text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n bigint; outcome text;
BEGIN
  BEGIN
    PERFORM sec.act(p_as);
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    outcome := 'rows:' || n;
    RAISE EXCEPTION 'rollback' USING ERRCODE = 'SEC01';
  EXCEPTION WHEN SQLSTATE 'SEC01' THEN RETURN outcome;
  WHEN others THEN RETURN 'denied:' || SQLSTATE;
  END;
END $$;

CREATE FUNCTION sec.expect(p_as text, p_sql text, p_outcome text, p_why text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual text := sec.try(p_as, p_sql);
BEGIN
  IF actual IS DISTINCT FROM p_outcome THEN
    RAISE EXCEPTION 'FAIL: % (as %): expected %, got %', p_why, p_as, p_outcome, actual;
  END IF;
END $$;

-- A call to any function with typed NULL arguments.
CREATE FUNCTION sec.null_call(p_proc regprocedure) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format('SELECT %I.%I(%s)', p.pronamespace::regnamespace, p.proname,
    coalesce((SELECT string_agg(format('NULL::%s', t::regtype), ',' ORDER BY ord)
      FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY AS a(t, ord)), ''))
  FROM pg_proc p WHERE p.oid = p_proc $$;

-- Rewrites a function's real source. Raises when the pattern is not there, so
-- a mutation can never silently test nothing after the function changes.
CREATE FUNCTION sec.mutate_fn(p_proc regprocedure, p_pattern text, p_replacement text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE before text := pg_get_functiondef(p_proc); after text;
BEGIN
  after := regexp_replace(before, p_pattern, p_replacement, 'g');
  IF after = before THEN RAISE EXCEPTION 'mutation pattern not found in %: %', p_proc, p_pattern; END IF;
  EXECUTE after;
END $$;

-- mutate_fn for every overload of a name; each must contain the pattern.
CREATE FUNCTION sec.mutate(p_name text, p_pattern text, p_replacement text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE f regprocedure; n integer := 0;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public' AND p.proname = p_name LOOP
    PERFORM sec.mutate_fn(f, p_pattern, p_replacement);
    n := n + 1;
  END LOOP;
  IF n = 0 THEN RAISE EXCEPTION 'no function named %', p_name; END IF;
END $$;

-- A role without EXECUTE, proved by the catalog and by a real call. A call to a
-- short overload is ambiguous (42725) before privileges are checked, so for
-- those the catalog answer is the proof.
CREATE FUNCTION sec.expect_refused(p_as text, p_role text, p_proc regprocedure, p_why text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE got text;
BEGIN
  IF has_function_privilege(p_role, p_proc, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: % can run %', p_role, p_proc;
  END IF;
  got := sec.try(p_as, sec.null_call(p_proc));
  IF got NOT IN ('denied:42501', 'denied:42725') THEN
    RAISE EXCEPTION 'FAIL: % (as %): expected a refusal, got %', p_why, p_as, got;
  END IF;
END $$;

CREATE FUNCTION sec.run_checks() RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  FOR c IN SELECT p.oid::regproc::text AS fn, p.proname::text AS name FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'sec' AND p.proname LIKE 'check\_%' ORDER BY p.proname LOOP
    BEGIN
      EXECUTE format('SELECT %s()', c.fn);
      INSERT INTO sec.check_results VALUES (c.name, 'PASS');
    EXCEPTION WHEN others THEN
      INSERT INTO sec.check_results VALUES (c.name, 'FAILED: ' || SQLERRM);
    END;
  END LOOP;
END $$;

-- Each entry removes one protection, then its check must fail as named. The rollback
-- restores the protection before the next entry.
CREATE TABLE sec.mutations(name text PRIMARY KEY, check_name text NOT NULL, ddl text NOT NULL, fails_on text NOT NULL);
-- Removing a protection counts only if its check fails on the assertion that
-- guards it. Any other error means the check broke, and proves nothing.
CREATE FUNCTION sec.mutation_outcome(p_error text, p_fails_on text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN starts_with(p_error, 'FAIL: ' || p_fails_on) THEN 'caught: ' ELSE 'WRONG FAILURE: ' END || left(p_error, 150)
$$;
CREATE FUNCTION sec.run_mutations() RETURNS void LANGUAGE plpgsql AS $$
DECLARE m record; outcome text;
BEGIN
  FOR m IN SELECT * FROM sec.mutations ORDER BY name LOOP
    outcome := NULL;
    BEGIN
      BEGIN
        EXECUTE m.ddl;
      EXCEPTION WHEN others THEN
        outcome := 'MUTATION DID NOT APPLY: ' || SQLERRM;
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'SEC02';
      END;
      BEGIN
        EXECUTE format('SELECT sec.%I()', m.check_name);
        outcome := 'NOT CAUGHT';
      EXCEPTION WHEN others THEN
        outcome := sec.mutation_outcome(SQLERRM, m.fails_on);
      END;
      RAISE EXCEPTION 'rollback' USING ERRCODE = 'SEC02';
    EXCEPTION WHEN SQLSTATE 'SEC02' THEN
      INSERT INTO sec.mutation_results VALUES (m.name, m.check_name, outcome);
    END;
  END LOOP;
END $$;

CREATE FUNCTION sec.require_all_passed() RETURNS void LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  SELECT string_agg(name || ': ' || result, E'\n') INTO bad FROM sec.check_results WHERE result <> 'PASS';
  IF bad IS NOT NULL THEN RAISE EXCEPTION E'failed checks:\n%', bad; END IF;
  SELECT string_agg(name || ': ' || result, E'\n') INTO bad FROM sec.mutation_results WHERE result NOT LIKE 'caught:%';
  IF bad IS NOT NULL THEN RAISE EXCEPTION E'mutations not caught:\n%', bad; END IF;
  -- A protection with no mutation is an untested claim.
  SELECT string_agg(p.proname, ', ') INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'sec' AND p.proname LIKE 'check\_%'
      AND NOT EXISTS (SELECT 1 FROM sec.mutations m WHERE m.check_name = p.proname);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'checks with no mutation: %', bad; END IF;
END $$;

-- Identities.
INSERT INTO auth.users(id) SELECT sec.uid(w) FROM unnest(ARRAY['A','B','R','W']) w;
INSERT INTO auth.sessions(id, user_id, created_at) VALUES
  (sec.session('A'), sec.uid('A'), now()), (sec.session('A2'), sec.uid('A'), now()),
  (sec.session('B'), sec.uid('B'), now());
INSERT INTO public.product_submission_reviewers(user_id) VALUES (sec.uid('R'));
INSERT INTO public.product_submission_extraction_workers(user_id, label) VALUES (sec.uid('W'), 'sec worker');
INSERT INTO public.product_submission_consent_versions(version, kind, purposes, copy_sha256, effective_from)
SELECT 'sec.consent.v1', kind, ARRAY['private_review', 'ai_label_draft'], repeat('f', 64), '2020-01-01'
FROM unnest(enum_range(NULL::public.product_submission_kind)) kind;

-- Seed rows that belong to user A. A's submission goes through the real RPC.
INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at)
VALUES ('sec-stack-a', sec.uid('A'), 'Fish oil', '1001', now());
INSERT INTO public.user_usage(user_id, scans_today, ai_messages_today, reset_day_utc)
VALUES (sec.uid('A'), 1, 0, (now() AT TIME ZONE 'UTC')::date);
INSERT INTO public.device_push_tokens(user_id, fcm_token, platform) VALUES (sec.uid('A'), 'sec-token-a', 'ios');
INSERT INTO public.ai_connections(connection_id, user_id, client_id, expires_at)
VALUES ('a4000000-0000-4000-8000-000000000001', sec.uid('A'), 'sec-client', now() + interval '1 day');
INSERT INTO public.mcp_access_log(connection_id, tool)
VALUES ('a4000000-0000-4000-8000-000000000001', 'get_my_supplements');
INSERT INTO public.ai_share_snapshots(connection_id, user_id, format, scope, ciphertext, nonce, key_version, expires_at)
VALUES ('a4000000-0000-4000-8000-000000000001', sec.uid('A'), 'pharmaguide-brief-markdown/v1', '{}', '\x00', '\x00', 1, now() + interval '1 hour');
DO $$ BEGIN
  PERFORM sec.act('A');
  PERFORM public.create_product_submission(
    sec.submission(), 'missing_product', '012345678905', NULL, false,
    jsonb_build_array(jsonb_build_object(
      'photo_id', 'a5000000-0000-4000-8000-000000000001', 'seq', 1,
      'categories', jsonb_build_array('front_identity', 'supplement_facts', 'ingredient_disclosure', 'barcode'),
      'content_type', 'image/jpeg', 'byte_size', 100, 'content_sha256', repeat('a', 64))),
    NULL, 'sec.consent.v1', NULL);
  PERFORM set_config('role', 'none', true);
END $$;
INSERT INTO storage.objects(bucket_id, name, owner_id, metadata)
SELECT 'product-submission-photos', object_path, user_id::text, '{}' FROM public.product_submission_photos
WHERE submission_id = sec.submission();
-- A pairing code A's browser is showing, for the other-user check.
SELECT public.start_ai_connection_pairing(sec.uid('A'), sec.session('A'), 'sec-auth', 'sec-pair-client',
  'Verified assistant', 'https://chatgpt.com/callback', encode(extensions.digest('ABCDEFGHJKLM', 'sha256'), 'hex'));
-- Rows the submission flow cannot produce from one fixture. The mismatch detail
-- belongs to another kind of submission, and only its owner column matters here.
INSERT INTO public.product_contribution_ledger(user_id, submission_id, event, points, catalog_version)
VALUES (sec.uid('A'), sec.submission(), 'earned_catalog_added', 1, 'sec-v1');
ALTER TABLE public.product_submission_mismatch_details DISABLE TRIGGER product_submission_mismatch_kind;
INSERT INTO public.product_submission_mismatch_details(submission_id, user_id, dsld_id, mismatch_categories)
VALUES (sec.submission(), sec.uid('A'), '1001', (enum_range(NULL::public.label_mismatch_category))[1:1]);
ALTER TABLE public.product_submission_mismatch_details ENABLE TRIGGER product_submission_mismatch_kind;

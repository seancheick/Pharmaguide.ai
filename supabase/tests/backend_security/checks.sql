-- Every check raises to fail, and sec.mutations (mutations.sql) proves each one
-- fails when its protection is removed. Rows belong to user A; B is another
-- signed-in user. Each "other user" check also proves A can see the row, so a
-- zero-row result can never pass only because nothing was seeded.

-- The tables anyone may read, because the app needs them before sign-in.
CREATE FUNCTION sec.public_read_tables() RETURNS text[] LANGUAGE sql IMMUTABLE
  AS $$ SELECT ARRAY['catalog_releases','export_manifest','safety_alert_releases'] $$;
-- Rows A owns and may read. Everything here is checked against B and anon.
CREATE FUNCTION sec.owned_tables() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['user_stacks','user_usage','ai_connections','mcp_access_log','product_contribution_ledger',
    'product_submissions','product_submission_photos','product_submission_missing_details',
    'product_submission_mismatch_details','product_submission_evidence_revisions'] $$;
-- Every other public table is server-side: no API role may touch it directly.
CREATE FUNCTION sec.client_visible_tables() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT sec.public_read_tables() || sec.owned_tables() $$;

CREATE FUNCTION sec.reviewer_rpcs() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
  'assert_product_submission_fully_verified','correct_product_submission_barcode',
  'create_product_submission_reviewer_evidence_revision','create_product_submission_reviewer_image',
  'get_product_submission_evidence','get_product_submission_extractions',
  'get_product_submission_identity_candidates','load_product_submission_reviewer_draft',
  'prepare_product_submission_approval_payload','product_submission_reviewer_batch_state',
  'record_product_submission_extraction','record_product_submission_match_check',
  'reopen_product_submission_approval','request_product_submission_evidence',
  'review_product_submission','save_product_submission_reviewer_draft',
  'set_product_submission_field_verification','set_product_submission_review_image'] $$;
CREATE FUNCTION sec.worker_rpcs() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
  'claim_product_submission_extraction_jobs','complete_product_submission_extraction_job',
  'heartbeat_product_submission_extraction_job','product_submission_extraction_attempt_outcome',
  'product_submission_extraction_budget_state','reserve_product_submission_extraction_budget'] $$;

CREATE FUNCTION sec.definers() RETURNS TABLE(proc regprocedure, name text, returns_trigger boolean)
LANGUAGE sql STABLE AS $$
  SELECT p.oid::regprocedure, p.proname::text, p.prorettype = 'trigger'::regtype
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prosecdef $$;

-- === Whole-schema rules ===

CREATE FUNCTION sec.check_rls_on_every_public_table() RETURNS void LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: RLS is off on %', bad; END IF;
END $$;

-- The list of definer functions, who may run them and their search_path are
-- pinned. A new function or grant fails here until its audit row is written.
CREATE FUNCTION sec.check_definer_exposure_matches_audit() RETURNS void LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  WITH live AS (
    SELECT p.proname::text || '/' || p.pronargs::text AS key,
      coalesce((SELECT string_agg(DISTINCT CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END, ',')
        FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE a.privilege_type = 'EXECUTE' AND a.grantee <> p.proowner), '') AS exec_by
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef AND p.proname <> 'rls_auto_enable'
  ), diff AS (
    SELECT coalesce(l.key, e.key) AS key, l.exec_by AS actual, e.exec_by AS audited
    FROM live l FULL JOIN sec.definer_exposure e USING (key)
    WHERE l.exec_by IS DISTINCT FROM e.exec_by
  )
  SELECT string_agg(format('%s audited=[%s] actual=[%s]', key, audited, actual), '; ') INTO bad FROM diff;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: definer exposure differs from docs/security/SECURITY_DEFINER_AUDIT.md: %', bad;
  END IF;
END $$;

CREATE FUNCTION sec.check_definers_pin_search_path() RETURNS void LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search\_path=%');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: definer without a pinned search_path: %', bad; END IF;
END $$;

-- === Anonymous ===

CREATE FUNCTION sec.check_anon_has_no_private_table_access() RETURNS void LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
      AND NOT c.relname = ANY(sec.public_read_tables())
      AND has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: anon holds a privilege on %', bad; END IF;
  SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
      AND NOT c.relname = ANY(sec.public_read_tables())
      AND has_table_privilege('anon', c.oid, 'DELETE, TRUNCATE');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: anon can delete from %', bad; END IF;
END $$;

CREATE FUNCTION sec.check_anon_reads_no_personal_rows() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY sec.owned_tables() || ARRAY['ai_share_snapshots','device_push_tokens'] LOOP
    PERFORM sec.expect('anon', format('SELECT * FROM public.%I', t), 'denied:42501', 'anon read of ' || t);
  END LOOP;
END $$;

CREATE FUNCTION sec.check_anon_cannot_write() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('anon', $q$INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at)
    VALUES ('x', sec.uid('A'), 'x', '1', now())$q$, 'denied:42501', 'anon insert');
  PERFORM sec.expect('anon', $q$UPDATE public.user_stacks SET name='x'$q$, 'denied:42501', 'anon update');
  PERFORM sec.expect('anon', 'DELETE FROM public.user_stacks', 'denied:42501', 'anon delete');
END $$;

CREATE FUNCTION sec.check_anon_only_reads_public_tables() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY sec.public_read_tables() LOOP
    IF has_table_privilege('anon', format('public.%I', t), 'INSERT, UPDATE, DELETE, TRUNCATE')
       OR has_any_column_privilege('anon', format('public.%I', t), 'INSERT, UPDATE') THEN
      RAISE EXCEPTION 'FAIL: anon can write to %', t;
    END IF;
    IF sec.try('anon', format('SELECT * FROM public.%I', t)) LIKE 'denied:%' THEN
      RAISE EXCEPTION 'FAIL: anon cannot read %, and the app needs it before sign-in', t;
    END IF;
  END LOOP;
END $$;

CREATE FUNCTION sec.check_anon_runs_only_the_request_guard() RETURNS void LANGUAGE plpgsql AS $$
DECLARE d record;
BEGIN
  FOR d IN SELECT * FROM sec.definers() WHERE name <> 'pgrst_reject_ai_assistant_tokens' AND NOT returns_trigger LOOP
    PERFORM sec.expect_refused('anon', 'anon', d.proc, 'anon call of ' || d.name);
  END LOOP;
END $$;

-- === Other users' rows ===

CREATE FUNCTION sec.check_other_user_reads_nothing() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_usage','ai_connections','mcp_access_log','product_contribution_ledger',
    'product_submission_missing_details','product_submission_mismatch_details'] LOOP
    PERFORM sec.expect('A', format('SELECT * FROM public.%I', t), 'rows:1', 'owner read of ' || t);
    PERFORM sec.expect('B', format('SELECT * FROM public.%I', t), 'rows:0', 'other user read of ' || t);
  END LOOP;
  PERFORM sec.expect('A', 'SELECT id, user_id FROM public.product_submissions', 'rows:1', 'owner reads own submission');
  PERFORM sec.expect('B', 'SELECT id, user_id FROM public.product_submissions', 'rows:0', 'other user read of submissions');
  PERFORM sec.expect('A', 'SELECT photo_id, object_path FROM public.product_submission_photos', 'rows:1', 'owner reads own photo row');
  PERFORM sec.expect('B', 'SELECT photo_id, object_path FROM public.product_submission_photos', 'rows:0', 'other user read of photos');
  PERFORM sec.expect('A', 'SELECT revision, photo_ids FROM public.product_submission_evidence_revisions', 'rows:1', 'owner reads own revision');
  PERFORM sec.expect('B', 'SELECT revision, photo_ids FROM public.product_submission_evidence_revisions', 'rows:0', 'other user read of revisions');
END $$;

CREATE FUNCTION sec.check_other_user_cannot_read_stack() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', 'SELECT * FROM public.user_stacks', 'rows:1', 'owner reads own stack');
  PERFORM sec.expect('B', 'SELECT * FROM public.user_stacks', 'rows:0', 'other user read of a stack');
END $$;
CREATE FUNCTION sec.check_other_user_cannot_update_stack() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', $q$UPDATE public.user_stacks SET name='mine' WHERE id='sec-stack-a'$q$, 'rows:1', 'owner updates own stack');
  PERFORM sec.expect('B', $q$UPDATE public.user_stacks SET name='stolen' WHERE id='sec-stack-a'$q$, 'rows:0', 'other user update of a stack');
  -- The app syncs by upsert, and the primary key is id alone.
  PERFORM sec.expect('B', $q$INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at)
    VALUES ('sec-stack-a', sec.uid('B'), 'stolen', '2', now())
    ON CONFLICT (id) DO UPDATE SET name = excluded.name$q$, 'denied:42501', 'other user upsert over a stack');
END $$;
CREATE FUNCTION sec.check_other_user_cannot_delete_stack() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', $q$DELETE FROM public.user_stacks WHERE id='sec-stack-a'$q$, 'rows:1', 'owner deletes own stack');
  PERFORM sec.expect('B', $q$DELETE FROM public.user_stacks WHERE id='sec-stack-a'$q$, 'rows:0', 'other user delete of a stack');
END $$;
CREATE FUNCTION sec.check_other_user_cannot_insert_stack() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('B', $q$INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at)
    VALUES ('sec-b-own', sec.uid('B'), 'x', '2', now())$q$, 'rows:1', 'user inserts own stack row');
  PERFORM sec.expect('B', $q$INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at)
    VALUES ('sec-b-for-a', sec.uid('A'), 'x', '2', now())$q$, 'denied:42501', 'insert into another user stack');
END $$;
CREATE FUNCTION sec.check_owner_cannot_give_stack_row_away() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', $q$UPDATE public.user_stacks SET user_id=sec.uid('B') WHERE id='sec-stack-a'$q$, 'denied:42501', 'moving a row to another user');
END $$;

-- Medication rows never sync. Two independent layers, each checked alone:
-- the column CHECK fires even for a role that skips RLS, and the policy fires
-- first for an API caller (RLS checks run before constraints).
CREATE FUNCTION sec.check_medication_refused_by_constraint() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at, type)
    VALUES ('sec-med-admin', sec.uid('A'), 'Warfarin', '1', now(), 'medication');
  EXCEPTION WHEN check_violation THEN RETURN;
  END;
  RAISE EXCEPTION 'FAIL: a medication row was stored past the column CHECK';
END $$;
CREATE FUNCTION sec.check_medication_refused_on_insert_by_policy() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', $q$INSERT INTO public.user_stacks(id, user_id, name, dsld_id, client_updated_at, type)
    VALUES ('sec-med', sec.uid('A'), 'Warfarin', '1', now(), 'medication')$q$, 'denied:42501', 'medication insert');
END $$;
CREATE FUNCTION sec.check_medication_refused_on_update_by_policy() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', $q$UPDATE public.user_stacks SET type='medication' WHERE id='sec-stack-a'$q$, 'denied:42501', 'medication update');
END $$;

CREATE FUNCTION sec.check_read_only_tables_refuse_client_writes() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY sec.client_visible_tables() LOOP
    CONTINUE WHEN t = 'user_stacks';
    IF has_table_privilege('authenticated', format('public.%I', t), 'INSERT, UPDATE, DELETE, TRUNCATE')
       OR has_any_column_privilege('authenticated', format('public.%I', t), 'INSERT, UPDATE') THEN
      RAISE EXCEPTION 'FAIL: signed-in users can write to %', t;
    END IF;
    PERFORM sec.expect('A', format('DELETE FROM public.%I', t), 'denied:42501', 'client delete from ' || t);
  END LOOP;
END $$;

CREATE FUNCTION sec.check_server_tables_closed_to_clients() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t record;
BEGIN
  FOR t IN SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND NOT c.relname = ANY(sec.client_visible_tables()) LOOP
    IF has_any_column_privilege('authenticated', t.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
       OR has_table_privilege('authenticated', t.oid, 'DELETE, TRUNCATE') THEN
      RAISE EXCEPTION 'FAIL: signed-in users hold a privilege on %', t.relname;
    END IF;
    PERFORM sec.expect('A', format('SELECT 1 FROM public.%I', t.relname), 'denied:42501', 'client read of ' || t.relname);
  END LOOP;
END $$;

-- === RPCs against another user's rows ===

CREATE FUNCTION sec.check_owner_rpcs_refuse_other_user() RETURNS void LANGUAGE plpgsql AS $$
DECLARE s text := quote_literal(sec.submission()) || '::uuid';
BEGIN
  PERFORM sec.expect('B', format($q$SELECT public.add_product_submission_evidence(%s, 2, '[{}]')$q$, s), 'denied:42501', 'add evidence to another user submission');
  PERFORM sec.expect('B', format('SELECT public.finalize_product_submission(%s, 1)', s), 'denied:42501', 'finalize another user submission');
  PERFORM sec.expect('B', format('SELECT public.hide_product_submission(%s)', s), 'denied:P0002', 'hide another user submission');
  PERFORM sec.expect('B', format($q$SELECT public.set_product_submission_display_name(%s, 'x')$q$, s), 'denied:42501', 'rename another user submission');
  PERFORM sec.expect('B', format($q$SELECT public.open_product_submission_evidence_revision(%s, 1, gen_random_uuid(), '{}', 'sec.consent.v1', NULL)$q$, s), 'denied:42501', 'open a revision on another user submission');
  PERFORM sec.expect('B', format($q$SELECT public.create_product_submission(%s, 'missing_product', '012345678905', NULL, false,
    jsonb_build_array(jsonb_build_object('photo_id','b5000000-0000-4000-8000-000000000001','seq',1,
      'categories',jsonb_build_array('front_identity','supplement_facts','ingredient_disclosure','barcode'),
      'content_type','image/jpeg','byte_size',100,'content_sha256',repeat('b',64))),
    NULL, 'sec.consent.v1', NULL)$q$, s), 'denied:23505', 'replaying another user submission id');
  -- The intake lookup answers from the caller's rows only.
  IF (SELECT sec.intake_action('B')) <> 'start_new' OR (SELECT sec.intake_action('A')) = 'start_new' THEN
    RAISE EXCEPTION 'FAIL: intake answered from another user''s submission';
  END IF;
END $$;
CREATE FUNCTION sec.intake_action(p_as text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE a text;
BEGIN
  BEGIN
    PERFORM sec.act(p_as);
    a := public.get_product_submission_intake('missing_product', '012345678905', NULL)->>'action';
    RAISE EXCEPTION 'rollback' USING ERRCODE = 'SEC01';
  EXCEPTION WHEN SQLSTATE 'SEC01' THEN RETURN a;
  END;
END $$;

CREATE FUNCTION sec.check_usage_counter_refuses_other_user() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('B', $q$SELECT public.increment_usage(sec.uid('B'), 'scan')$q$, 'rows:1', 'own usage counter');
  PERFORM sec.expect('B', $q$SELECT public.increment_usage(sec.uid('A'), 'scan')$q$, 'denied:P0001', 'another user usage counter');
END $$;

CREATE FUNCTION sec.check_pairing_refuses_other_user() RETURNS void LANGUAGE plpgsql AS $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['preview_ai_connection_pairing','approve_ai_connection_pairing','cancel_my_ai_connection_pairing'] LOOP
    IF sec.pairing_answer('B', f) <> '{"error": "pairing_unavailable"}' THEN
      RAISE EXCEPTION 'FAIL: % answered for another user''s code: %', f, sec.pairing_answer('B', f);
    END IF;
  END LOOP;
  -- Positive control: A's other live session can read A's own code.
  IF sec.pairing_answer('A2', 'preview_ai_connection_pairing') NOT LIKE '%Verified assistant%' THEN
    RAISE EXCEPTION 'FAIL: owner cannot preview own code (fixture broken): %', sec.pairing_answer('A2', 'preview_ai_connection_pairing');
  END IF;
END $$;
CREATE FUNCTION sec.pairing_answer(p_as text, p_function text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE answer text;
BEGIN
  BEGIN
    PERFORM sec.act(CASE WHEN p_as = 'A2' THEN 'A' ELSE p_as END);
    IF p_as = 'A2' THEN
      PERFORM set_config('request.jwt.claims', (auth.jwt() || jsonb_build_object('session_id', sec.session('A2')))::text, true);
    END IF;
    EXECUTE format($q$SELECT public.%I('ABCDEFGHJKLM')::text$q$, p_function) INTO answer;
    RAISE EXCEPTION 'rollback' USING ERRCODE = 'SEC01';
  EXCEPTION WHEN SQLSTATE 'SEC01' THEN RETURN answer;
  END;
END $$;

CREATE FUNCTION sec.check_reviewer_rpcs_refuse_non_reviewers() RETURNS void LANGUAGE plpgsql AS $$
DECLARE d record; n integer := 0;
BEGIN
  FOR d IN SELECT * FROM sec.definers() WHERE name = ANY(sec.reviewer_rpcs()) LOOP
    PERFORM sec.expect('A', sec.null_call(d.proc), 'denied:42501', 'non-reviewer call of ' || d.name);
    n := n + 1;
  END LOOP;
  IF n <> cardinality(sec.reviewer_rpcs()) THEN RAISE EXCEPTION 'FAIL: reviewer RPC list out of date: % found', n; END IF;
END $$;

CREATE FUNCTION sec.check_worker_rpcs_refuse_non_workers() RETURNS void LANGUAGE plpgsql AS $$
DECLARE d record; n integer := 0;
BEGIN
  FOR d IN SELECT * FROM sec.definers() WHERE name = ANY(sec.worker_rpcs()) LOOP
    PERFORM sec.expect('A', sec.null_call(d.proc), 'denied:42501', 'non-worker call of ' || d.name);
    PERFORM sec.expect('R', sec.null_call(d.proc), 'denied:42501', 'reviewer call of worker RPC ' || d.name);
    n := n + 1;
  END LOOP;
  IF n <> cardinality(sec.worker_rpcs()) THEN RAISE EXCEPTION 'FAIL: worker RPC list out of date: % found', n; END IF;
END $$;

-- Every definer the audit keeps away from signed-in users, called for real.
CREATE FUNCTION sec.check_server_only_rpcs_refuse_signed_in_users() RETURNS void LANGUAGE plpgsql AS $$
DECLARE d record; n integer := 0;
BEGIN
  FOR d IN SELECT x.proc, x.name FROM sec.definers() x
      JOIN pg_proc p ON p.oid = x.proc::oid
      JOIN sec.definer_exposure e ON e.key = p.proname::text || '/' || p.pronargs::text
      WHERE e.exec_by NOT LIKE '%authenticated%' AND NOT x.returns_trigger LOOP
    PERFORM sec.expect_refused('A', 'authenticated', d.proc, 'signed-in call of ' || d.name);
    n := n + 1;
  END LOOP;
  IF n < 50 THEN RAISE EXCEPTION 'FAIL: only % server-only functions were called', n; END IF;
END $$;

-- === Storage ===

CREATE FUNCTION sec.check_storage_other_user_cannot_read() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('A', 'SELECT * FROM storage.objects', 'rows:1', 'owner reads own object');
  PERFORM sec.expect('B', 'SELECT * FROM storage.objects', 'rows:0', 'other user read of a photo');
  PERFORM sec.expect('anon', 'SELECT * FROM storage.objects', 'rows:0', 'anon read of a photo');
END $$;
CREATE FUNCTION sec.check_storage_other_user_cannot_write() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('B', $q$INSERT INTO storage.objects(bucket_id, name, owner_id, metadata)
    VALUES ('product-submission-photos', sec.uid('A')::text || '/x', sec.uid('B')::text, '{}')$q$, 'denied:42501', 'upload into another user folder');
  PERFORM sec.expect('B', $q$UPDATE storage.objects SET metadata='{"x":1}'$q$, 'rows:0', 'other user update of a photo');
  PERFORM sec.expect('B', 'DELETE FROM storage.objects', 'rows:0', 'other user delete of a photo');
END $$;
CREATE FUNCTION sec.check_storage_owner_writes_only_pending_paths() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- A's manifested, still-pending path is writable; a path A never declared is not.
  PERFORM sec.expect('A', 'UPDATE storage.objects SET metadata=''{"x":1}''', 'rows:1', 'owner updates own pending upload');
  PERFORM sec.expect('A', $q$INSERT INTO storage.objects(bucket_id, name, owner_id, metadata)
    VALUES ('product-submission-photos', sec.uid('A')::text || '/undeclared', sec.uid('A')::text, '{}')$q$, 'denied:42501', 'upload to an undeclared path');
END $$;

-- === AI assistant tokens (a real user id with a client_id claim) ===

CREATE FUNCTION sec.check_assistant_token_reads_no_owned_rows() RETURNS void LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_stacks','user_usage','ai_connections','mcp_access_log'] LOOP
    PERFORM sec.expect('oauth:A', format('SELECT * FROM public.%I', t), 'rows:0', 'assistant token read of ' || t);
  END LOOP;
  PERFORM sec.expect('oauth:A', 'SELECT id FROM public.product_submissions', 'rows:0', 'assistant token read of submissions');
  PERFORM sec.expect('oauth:A', 'SELECT * FROM storage.objects', 'rows:0', 'assistant token read of photos');
END $$;
CREATE FUNCTION sec.check_assistant_token_stopped_at_every_request() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM sec.expect('oauth:A', 'SELECT public.pgrst_reject_ai_assistant_tokens()', 'denied:42501', 'request guard');
  PERFORM sec.expect('A', 'SELECT public.pgrst_reject_ai_assistant_tokens()', 'rows:1', 'request guard lets the app through');
  PERFORM sec.expect('anon', 'SELECT public.pgrst_reject_ai_assistant_tokens()', 'rows:1', 'request guard lets anon through');
END $$;

-- === Staff identifiers (finding F2) ===

-- A submitter sees their own receipt, not which staff account acted on it or
-- the cleanup worker's claim.
CREATE FUNCTION sec.staff_columns() RETURNS text[] LANGUAGE sql IMMUTABLE
  AS $$ SELECT ARRAY['reviewed_by','evidence_requested_by','cleanup_claim_token','cleanup_claimed_at'] $$;
CREATE FUNCTION sec.check_submitter_cannot_read_staff_columns() RETURNS void LANGUAGE plpgsql AS $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY sec.staff_columns() LOOP
    PERFORM sec.expect('A', format('SELECT %I FROM public.product_submissions', c), 'denied:42501', 'submitter read of ' || c);
  END LOOP;
  PERFORM sec.expect('A', 'SELECT uploader_id FROM public.product_submission_photos', 'denied:42501', 'submitter read of uploader_id');
END $$;

-- Every read in the app's source, run as a signed-in user. A column added to a
-- Dart select list without a grant fails here.
CREATE FUNCTION sec.check_app_reads_keep_working() RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; t text; got text; sql text; keys record;
BEGIN
  FOREACH t IN ARRAY ARRAY['product_submissions','product_submission_photos',
      'product_submission_evidence_revisions','product_submission_mismatch_details'] LOOP
    IF NOT EXISTS (SELECT 1 FROM sec.app_reads a WHERE a.table_name = t) THEN
      RAISE EXCEPTION 'FAIL: the app read extractor loaded no read of %', t;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM sec.app_reads ORDER BY embedded_fk NULLS FIRST, table_name, columns LOOP
    sql := format('SELECT %s FROM public.%I', r.columns, r.table_name);
    IF r.embedded_fk IS NOT NULL THEN
      -- PostgREST joins an embed through this named foreign key.
      SELECT (SELECT string_agg(format('child.%I = parent.%I', a.attname, b.attname), ' AND ')
          FROM unnest(c.conkey, c.confkey) AS k(child, parent)
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.child
          JOIN pg_attribute b ON b.attrelid = c.confrelid AND b.attnum = k.parent) AS join_on INTO keys
      FROM pg_constraint c
      WHERE c.conname = r.embedded_fk AND c.contype = 'f'
        AND c.conrelid = format('public.%I', r.table_name)::regclass
        AND c.confrelid = format('public.%I', r.parent_table)::regclass;
      IF keys.join_on IS NULL THEN
        RAISE EXCEPTION 'FAIL: app embed has no relationship: %', r.embedded_fk;
      END IF;
      sql := format('SELECT %s FROM public.%I AS parent JOIN public.%I AS child ON %s',
        (SELECT string_agg('child.' || quote_ident(c), ',') FROM unnest(string_to_array(r.columns, ',')) c),
        r.parent_table, r.table_name, keys.join_on);
    END IF;
    got := sec.try('A', sql);
    IF got NOT LIKE 'rows:%' OR (got = 'rows:0' AND r.table_name = ANY(sec.owned_tables())) THEN
      RAISE EXCEPTION 'FAIL: app read of % (as A): columns [%] got %', r.table_name, r.columns, got;
    END IF;
  END LOOP;
END $$;

-- The suite's own proof rests on this, so it is held to the same rule.
CREATE FUNCTION sec.check_mutation_judge_is_strict() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF sec.mutation_outcome('syntax error at or near "x"', 'some assertion') LIKE 'caught:%'
     OR sec.mutation_outcome('FAIL: another assertion', 'some assertion') LIKE 'caught:%' THEN
    RAISE EXCEPTION 'FAIL: the mutation judge accepted an unrelated error';
  END IF;
  IF sec.mutation_outcome('FAIL: some assertion (as A)', 'some assertion') NOT LIKE 'caught:%' THEN
    RAISE EXCEPTION 'FAIL: the mutation judge refused the named assertion';
  END IF;
END $$;

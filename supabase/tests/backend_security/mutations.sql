-- Each row removes one protection for one rollback, and its check must fail on
-- the assertion named last in the row. Any other failure does not count.
-- Gate patterns are the real source text: sec.mutate raises if it has changed.
INSERT INTO sec.mutations(name, check_name, ddl, fails_on) VALUES
('rls off: user_stacks', 'check_rls_on_every_public_table', 'ALTER TABLE public.user_stacks DISABLE ROW LEVEL SECURITY',
  $f$RLS is off on user_stacks$f$),
('rls off: ai_share_snapshots', 'check_rls_on_every_public_table', 'ALTER TABLE public.ai_share_snapshots DISABLE ROW LEVEL SECURITY',
  $f$RLS is off on ai_share_snapshots$f$),

('definer: new function exposed', 'check_definer_exposure_matches_audit',
  'CREATE FUNCTION public.sec_new_definer() RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '''' AS ''SELECT 1''',
  $f$definer exposure differs from docs/security/SECURITY_DEFINER_AUDIT.md: sec_new_definer/0 audited=[] actual=[$f$),
('definer: granted to anon', 'check_definer_exposure_matches_audit', 'GRANT EXECUTE ON FUNCTION public.hide_product_submission(uuid) TO anon',
  $f$definer exposure differs from docs/security/SECURITY_DEFINER_AUDIT.md: hide_product_submission/1 audited=[authenticated] actual=[$f$),
('definer: granted to PUBLIC', 'check_definer_exposure_matches_audit', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO PUBLIC',
  $f$definer exposure differs from docs/security/SECURITY_DEFINER_AUDIT.md: list_product_submission_objects_for_user/1 audited=[service_role] actual=[PUBLIC$f$),
('definer: grant dropped', 'check_definer_exposure_matches_audit', 'REVOKE EXECUTE ON FUNCTION public.hide_product_submission(uuid) FROM authenticated',
  $f$definer exposure differs from docs/security/SECURITY_DEFINER_AUDIT.md: hide_product_submission/1 audited=[authenticated] actual=[$f$),
('definer: search_path unpinned', 'check_definers_pin_search_path', 'ALTER FUNCTION public.hide_product_submission(uuid) RESET search_path',
  $f$definer without a pinned search_path: hide_product_submission$f$),

('anon granted stacks', 'check_anon_has_no_private_table_access', 'GRANT SELECT ON public.user_stacks TO anon',
  $f$anon holds a privilege on user_stacks$f$),
('anon granted one column', 'check_anon_has_no_private_table_access', 'GRANT SELECT (id) ON public.product_submissions TO anon',
  $f$anon holds a privilege on product_submissions$f$),
('anon granted delete', 'check_anon_has_no_private_table_access', 'GRANT DELETE ON public.device_push_tokens TO anon',
  $f$anon can delete from device_push_tokens$f$),
('anon reads stacks', 'check_anon_reads_no_personal_rows', 'GRANT SELECT ON public.user_stacks TO anon',
  $f$anon read of user_stacks (as anon)$f$),
('anon reads snapshots', 'check_anon_reads_no_personal_rows', 'GRANT SELECT ON public.ai_share_snapshots TO anon',
  $f$anon read of ai_share_snapshots (as anon)$f$),
-- No policy admits anon, so an insert needs a grant and a policy before it lands.
('anon inserts', 'check_anon_cannot_write', 'GRANT INSERT ON public.user_stacks TO anon; CREATE POLICY sec_open ON public.user_stacks FOR INSERT TO anon WITH CHECK (true)',
  $f$anon insert (as anon)$f$),
('anon updates', 'check_anon_cannot_write', 'GRANT UPDATE ON public.user_stacks TO anon',
  $f$anon update (as anon)$f$),
('anon deletes', 'check_anon_cannot_write', 'GRANT DELETE ON public.user_stacks TO anon',
  $f$anon delete (as anon)$f$),
('anon writes catalog', 'check_anon_only_reads_public_tables', 'GRANT INSERT ON public.catalog_releases TO anon',
  $f$anon can write to catalog_releases$f$),
('anon updates alert column', 'check_anon_only_reads_public_tables', 'GRANT UPDATE (is_current) ON public.safety_alert_releases TO anon',
  $f$anon can write to safety_alert_releases$f$),
('anon loses catalog read', 'check_anon_only_reads_public_tables', 'REVOKE SELECT ON public.export_manifest FROM anon',
  $f$anon cannot read export_manifest, and the app needs it before sign-in$f$),
('anon runs owner RPC', 'check_anon_runs_only_the_request_guard', 'GRANT EXECUTE ON FUNCTION public.hide_product_submission(uuid) TO anon',
  $f$anon can run hide_product_submission(uuid)$f$),
('anon runs server RPC', 'check_anon_runs_only_the_request_guard', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO anon',
  $f$anon can run list_product_submission_objects_for_user(uuid)$f$),

('stack read policy open', 'check_other_user_cannot_read_stack', 'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true)',
  $f$other user read of a stack (as B)$f$),
-- UPDATE and DELETE also filter through the SELECT policy, so both must open.
('stack update policies open', 'check_other_user_cannot_update_stack',
  'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_update_own_supplements ON public.user_stacks USING (true) WITH CHECK (true)',
  $f$other user update of a stack (as B)$f$),
('stack delete policies open', 'check_other_user_cannot_delete_stack',
  'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_delete_own_stack ON public.user_stacks USING (true)',
  $f$other user delete of a stack (as B)$f$),
('stack insert owner clause gone', 'check_other_user_cannot_insert_stack', $$ALTER POLICY users_can_insert_own_supplements ON public.user_stacks WITH CHECK (type = 'supplement')$$,
  $f$insert into another user stack (as B)$f$),
-- The new row must also pass the SELECT policy, so both clauses must go.
('stack update owner clause gone', 'check_owner_cannot_give_stack_row_away',
  $$ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_update_own_supplements ON public.user_stacks WITH CHECK (type = 'supplement')$$,
  $f$moving a row to another user (as A)$f$),
('medication column checks dropped', 'check_medication_refused_by_constraint',
  'ALTER TABLE public.user_stacks DROP CONSTRAINT user_stacks_type_check, DROP CONSTRAINT user_stacks_type_supplement_check',
  $f$a medication row was stored past the column CHECK$f$),
('medication insert clause gone', 'check_medication_refused_on_insert_by_policy', 'ALTER POLICY users_can_insert_own_supplements ON public.user_stacks WITH CHECK ((SELECT auth.uid()) = user_id)',
  $f$medication insert (as A)$f$),
('medication update clause gone', 'check_medication_refused_on_update_by_policy', 'ALTER POLICY users_can_update_own_supplements ON public.user_stacks WITH CHECK ((SELECT auth.uid()) = user_id)',
  $f$medication update (as A)$f$),

('open: user_usage', 'check_other_user_reads_nothing', 'ALTER POLICY "Users read own usage" ON public.user_usage USING (true)',
  $f$other user read of user_usage (as B)$f$),
('open: ai_connections', 'check_other_user_reads_nothing', 'ALTER POLICY ai_connections_select_own ON public.ai_connections USING (true)',
  $f$other user read of ai_connections (as B)$f$),
('open: mcp_access_log', 'check_other_user_reads_nothing', 'ALTER POLICY mcp_access_log_select_own ON public.mcp_access_log USING (true)',
  $f$other user read of mcp_access_log (as B)$f$),
('open: ledger', 'check_other_user_reads_nothing', 'ALTER POLICY product_contribution_ledger_select_own ON public.product_contribution_ledger USING (true)',
  $f$other user read of product_contribution_ledger (as B)$f$),
('open: submissions', 'check_other_user_reads_nothing', 'ALTER POLICY product_submissions_select_own ON public.product_submissions USING (true)',
  $f$other user read of submissions (as B)$f$),
('open: photos', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_photos_select_own ON public.product_submission_photos USING (true)',
  $f$other user read of photos (as B)$f$),
('open: revisions', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_evidence_revisions_select_own ON public.product_submission_evidence_revisions USING (true)',
  $f$other user read of revisions (as B)$f$),
('open: missing details', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_missing_select_own ON public.product_submission_missing_details USING (true)',
  $f$other user read of product_submission_missing_details (as B)$f$),
('open: mismatch details', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_mismatch_select_own ON public.product_submission_mismatch_details USING (true)',
  $f$other user read of product_submission_mismatch_details (as B)$f$),

('clients write submissions', 'check_read_only_tables_refuse_client_writes', 'GRANT DELETE ON public.product_submissions TO authenticated',
  $f$signed-in users can write to product_submissions$f$),
('clients write catalog', 'check_read_only_tables_refuse_client_writes', 'GRANT INSERT ON public.catalog_releases TO authenticated',
  $f$signed-in users can write to catalog_releases$f$),
('clients update one column', 'check_read_only_tables_refuse_client_writes', 'GRANT UPDATE (display_name) ON public.product_submissions TO authenticated',
  $f$signed-in users can write to product_submissions$f$),
('clients read snapshots', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.ai_share_snapshots TO authenticated',
  $f$signed-in users hold a privilege on ai_share_snapshots$f$),
('clients read push tokens', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.device_push_tokens TO authenticated',
  $f$signed-in users hold a privilege on device_push_tokens$f$),
('clients read reviewers', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.product_submission_reviewers TO authenticated',
  $f$signed-in users hold a privilege on product_submission_reviewers$f$),
('clients insert pairings', 'check_server_tables_closed_to_clients', 'GRANT INSERT ON public.ai_connection_pairings TO authenticated',
  $f$signed-in users hold a privilege on ai_connection_pairings$f$),

('owner gate gone: add evidence', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('add_product_submission_evidence', 'AND candidate\.user_id = caller_id', '')$$,
  $f$add evidence to another user submission (as B)$f$),
('owner gate gone: finalize', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('finalize_product_submission', 'AND candidate\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND photo\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND mismatch\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND user_id = caller_id', '')$$,
  $f$finalize another user submission (as B)$f$),
('owner gate gone: hide', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('hide_product_submission', 'candidate\.user_id <> caller_id', 'false'); SELECT sec.mutate('hide_product_submission', 'AND user_id = caller_id', '')$$,
  $f$hide another user submission (as B)$f$),
('owner gate gone: rename', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('set_product_submission_display_name', 'AND user_id = auth\.uid\(\)', '')$$,
  $f$rename another user submission (as B)$f$),
('owner gate gone: open revision', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('open_product_submission_evidence_revision', 'AND candidate\.user_id = caller_id', '')$$,
  $f$open a revision on another user submission (as B)$f$),
('owner gate gone: create replay', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('create_product_submission_v2_internal', 'OR persisted\.user_id <> caller_id', '')$$,
  $f$replaying another user submission id (as B)$f$),
('owner gate gone: intake', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('get_product_submission_intake', 'submission\.user_id = caller_id', 'true')$$,
  $f$intake answered from another user's submission$f$),
('usage gate gone', 'check_usage_counter_refuses_other_user', $$SELECT sec.mutate('increment_usage', 'p_user_id IS DISTINCT FROM auth\.uid\(\)', 'false')$$,
  $f$another user usage counter (as B)$f$),
-- A pairing is scoped twice: the row lookup and the browser session's owner.
('pairing gates gone', 'check_pairing_refuses_other_user', $$SELECT sec.mutate('ai_pairing_phone', 'WHERE user_id=u\s+AND code_hash', 'WHERE code_hash'); SELECT sec.mutate('ai_pairing_phone', 'OR NOT public\.ai_pairing_live_session\(u,r\.browser_session_id::text\)', '')$$,
  $f$preview_ai_connection_pairing answered for another user's code$f$),

-- A helper gate guards every RPC in its list, so its check fails on the first
-- one by name. That RPC then refuses for a different reason, past the gate.
('reviewer helper gate gone', 'check_reviewer_rpcs_refuse_non_reviewers', $$SELECT sec.mutate('assert_product_submission_reviewer', 'reviewer IS NULL OR NOT EXISTS\(.*?\) THEN', 'false THEN')$$,
  $f$non-reviewer call of assert_product_submission_fully_verified (as A)$f$),
('worker helper gate gone', 'check_worker_rpcs_refuse_non_workers', $$SELECT sec.mutate('product_submission_extraction_worker_id', 'worker_id IS NULL OR NOT EXISTS \(.*?\) THEN', 'false THEN')$$,
  $f$non-worker call of claim_product_submission_extraction_jobs (as A)$f$),
('server RPC granted: list objects', 'check_server_only_rpcs_refuse_signed_in_users', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO authenticated',
  $f$authenticated can run list_product_submission_objects_for_user(uuid)$f$),

('photo read policy open', 'check_storage_other_user_cannot_read', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true)',
  $f$other user read of a photo (as B)$f$),
('photo read open to anon', 'check_storage_other_user_cannot_read', 'CREATE POLICY sec_open ON storage.objects FOR SELECT TO anon USING (true)',
  $f$anon read of a photo (as anon)$f$),
('photo worker lease gate gone', 'check_storage_other_user_cannot_read', $$CREATE OR REPLACE FUNCTION public.product_submission_worker_may_read_object(p_name text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS 'SELECT true'$$,
  $f$other user read of a photo (as B)$f$),
('photo upload owner clause gone', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_insert_own ON storage.objects WITH CHECK (true)',
  $f$upload into another user folder (as B)$f$),
('photo update policies open', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true); ALTER POLICY product_submission_objects_update_own ON storage.objects USING (true) WITH CHECK (true)',
  $f$other user update of a photo (as B)$f$),
('photo delete policies open', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true); ALTER POLICY product_submission_objects_delete_own ON storage.objects USING (true)',
  $f$other user delete of a photo (as B)$f$),
('photo path check gone', 'check_storage_owner_writes_only_pending_paths', $$ALTER POLICY product_submission_objects_insert_own ON storage.objects WITH CHECK (bucket_id = 'product-submission-photos' AND owner_id = (SELECT auth.uid())::text)$$,
  $f$upload to an undeclared path (as A)$f$),

('assistant filter off: stacks', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.user_stacks',
  $f$assistant token read of user_stacks (as oauth:A)$f$),
('assistant filter off: usage', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.user_usage',
  $f$assistant token read of user_usage (as oauth:A)$f$),
('assistant filter off: connections', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.ai_connections',
  $f$assistant token read of ai_connections (as oauth:A)$f$),
-- The log and photo policies look through a second filtered table.
('assistant filter off: access log', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.mcp_access_log; DROP POLICY ai_connector_no_oauth_client ON public.ai_connections',
  $f$assistant token read of mcp_access_log (as oauth:A)$f$),
('assistant filter off: submissions', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.product_submissions',
  $f$assistant token read of submissions (as oauth:A)$f$),
('assistant filter off: photos', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON storage.objects; DROP POLICY ai_connector_no_oauth_client ON public.product_submission_photos',
  $f$assistant token read of photos (as oauth:A)$f$),
('assistant request guard emptied', 'check_assistant_token_stopped_at_every_request', $$SELECT sec.mutate('reject_oauth_client_request', '\(auth\.jwt\(\) ->> ''client_id''\) IS NOT NULL', 'false')$$,
  $f$request guard (as oauth:A)$f$),

('staff columns regranted', 'check_submitter_cannot_read_staff_columns', 'GRANT SELECT ON public.product_submissions TO authenticated',
  $f$submitter read of reviewed_by (as A)$f$),
('uploader column regranted', 'check_submitter_cannot_read_staff_columns', 'GRANT SELECT (uploader_id) ON public.product_submission_photos TO authenticated',
  $f$submitter read of uploader_id (as A)$f$),
-- The revisions policy reads this table, so that read fails first.
('app read broken: submissions', 'check_app_reads_keep_working', 'REVOKE SELECT ON public.product_submissions FROM authenticated',
  $f$app read of product_submission_evidence_revisions (as A)$f$),
('app read broken: photos', 'check_app_reads_keep_working', 'REVOKE SELECT (object_path) ON public.product_submission_photos FROM authenticated',
  $f$app read of product_submission_photos (as A)$f$);

-- Every gated RPC on its own: its gate call is taken out, and the same refusal
-- check must fail. The inline form is taken out too where a function has one.
INSERT INTO sec.mutations(name, check_name, ddl, fails_on)
SELECT 'reviewer gate gone: ' || f, 'check_reviewer_rpcs_refuse_non_reviewers',
  format($$SELECT sec.ungate_reviewer(%L)$$, f)
    -- This one delegates to a function that checks the reviewer again.
    || CASE WHEN f = 'review_product_submission' THEN $$; SELECT sec.ungate_reviewer('review_product_submission_unchecked')$$ ELSE '' END,
  'non-reviewer call of ' || f || ' (as A)'
FROM unnest(sec.reviewer_rpcs()) f;
INSERT INTO sec.mutations(name, check_name, ddl, fails_on)
SELECT 'worker gate gone: ' || f, 'check_worker_rpcs_refuse_non_workers',
  format($$SELECT sec.mutate(%L, 'public\.product_submission_extraction_worker_id\(\)', 'auth.uid()')$$, f)
    -- This one then also refuses a caller with no receipt of their own.
    || CASE WHEN f = 'product_submission_extraction_attempt_outcome' THEN format(
      $$; SELECT sec.mutate(%L, 'IF NOT FOUND THEN\s+RAISE EXCEPTION ''extraction attempt access required'' USING ERRCODE=''42501'';\s+END IF;', '')$$, f)
      ELSE '' END,
  'non-worker call of ' || f || ' (as A)'
FROM unnest(sec.worker_rpcs()) f;

-- Each hidden column alone: a grant back must fail on that column.
INSERT INTO sec.mutations(name, check_name, ddl, fails_on)
SELECT 'staff column regranted: ' || c, 'check_submitter_cannot_read_staff_columns',
  format('GRANT SELECT (%I) ON public.product_submissions TO authenticated', c),
  'submitter read of ' || c || ' (as A)'
FROM unnest(sec.staff_columns()) c;

INSERT INTO sec.mutations(name, check_name, ddl, fails_on) VALUES
-- A Dart select list naming a column with no grant, as the extractor would load it.
('app read drifts: column without a grant', 'check_app_reads_keep_working',
  $$INSERT INTO sec.app_reads(parent_table, table_name, columns) VALUES ('product_submissions', 'product_submissions', 'id,reviewed_by')$$,
  'app read of product_submissions (as A)'),
('app read broken: embedded join', 'check_app_reads_keep_working',
  'REVOKE SELECT ON public.product_submission_mismatch_details FROM authenticated',
  'app read of product_submission_mismatch_details (as A)'),
('app read broken: embed relationship gone', 'check_app_reads_keep_working',
  'ALTER TABLE public.product_submission_mismatch_details DROP CONSTRAINT product_submission_mismatch_details_submission_id_fkey',
  'app embed has no relationship: product_submission_mismatch_details_submission_id_fkey'),
('app read broken: submission column', 'check_app_reads_keep_working',
  'REVOKE SELECT (display_name) ON public.product_submissions FROM authenticated',
  'app read of product_submissions (as A)'),
('app reads not loaded', 'check_app_reads_keep_working', 'DELETE FROM sec.app_reads', 'the app read extractor loaded no read of'),
('mutation judge accepts any error', 'check_mutation_judge_is_strict',
  $$CREATE OR REPLACE FUNCTION sec.mutation_outcome(p_error text, p_fails_on text) RETURNS text LANGUAGE sql IMMUTABLE AS 'SELECT ''caught: '' || p_error'$$,
  'the mutation judge accepted an unrelated error');

CREATE FUNCTION sec.ungate_reviewer(p_name text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE f regprocedure; changed boolean := false; before text; after text;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public' AND p.proname = p_name LOOP
    before := pg_get_functiondef(f);
    after := regexp_replace(before, 'public\.assert_product_submission_reviewer\(\)', 'auth.uid()', 'g');
    -- The inline form: the reviewer table now lists whoever is calling.
    after := regexp_replace(after, 'public\.product_submission_reviewers', '(SELECT auth.uid() AS user_id)', 'g');
    IF after <> before THEN EXECUTE after; changed := true; END IF;
  END LOOP;
  IF NOT changed THEN RAISE EXCEPTION 'no reviewer gate found in %', p_name; END IF;
END $$;

INSERT INTO sec.mutations VALUES
('NULL usage guard gone', 'check_usage_type_required', $$SELECT sec.mutate('increment_usage', 'p_type IS NULL OR ', '')$$, 'NULL usage type (as B)'),
('NULL approval digest guard gone', 'check_reopen_digest_required', $$SELECT sec.mutate('reopen_product_submission_approval', 'OR p_expected_payload_sha256 IS NULL\s+', '')$$, 'NULL approval digest (as R)');

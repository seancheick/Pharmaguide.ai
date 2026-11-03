-- Each row removes one protection for one rollback, and its check must fail.
-- Gate patterns are the real source text: sec.mutate raises if it has changed.
INSERT INTO sec.mutations(name, check_name, ddl) VALUES
('rls off: user_stacks', 'check_rls_on_every_public_table', 'ALTER TABLE public.user_stacks DISABLE ROW LEVEL SECURITY'),
('rls off: ai_share_snapshots', 'check_rls_on_every_public_table', 'ALTER TABLE public.ai_share_snapshots DISABLE ROW LEVEL SECURITY'),

('definer: new function exposed', 'check_definer_exposure_matches_audit',
  'CREATE FUNCTION public.sec_new_definer() RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '''' AS ''SELECT 1'''),
('definer: granted to anon', 'check_definer_exposure_matches_audit', 'GRANT EXECUTE ON FUNCTION public.hide_product_submission(uuid) TO anon'),
('definer: granted to PUBLIC', 'check_definer_exposure_matches_audit', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO PUBLIC'),
('definer: grant dropped', 'check_definer_exposure_matches_audit', 'REVOKE EXECUTE ON FUNCTION public.hide_product_submission(uuid) FROM authenticated'),
('definer: search_path unpinned', 'check_definers_pin_search_path', 'ALTER FUNCTION public.hide_product_submission(uuid) RESET search_path'),

('anon granted stacks', 'check_anon_has_no_private_table_access', 'GRANT SELECT ON public.user_stacks TO anon'),
('anon granted one column', 'check_anon_has_no_private_table_access', 'GRANT SELECT (id) ON public.product_submissions TO anon'),
('anon granted delete', 'check_anon_has_no_private_table_access', 'GRANT DELETE ON public.device_push_tokens TO anon'),
('anon reads stacks', 'check_anon_reads_no_personal_rows', 'GRANT SELECT ON public.user_stacks TO anon'),
('anon reads snapshots', 'check_anon_reads_no_personal_rows', 'GRANT SELECT ON public.ai_share_snapshots TO anon'),
-- No policy admits anon, so an insert needs a grant and a policy before it lands.
('anon inserts', 'check_anon_cannot_write', 'GRANT INSERT ON public.user_stacks TO anon; CREATE POLICY sec_open ON public.user_stacks FOR INSERT TO anon WITH CHECK (true)'),
('anon updates', 'check_anon_cannot_write', 'GRANT UPDATE ON public.user_stacks TO anon'),
('anon deletes', 'check_anon_cannot_write', 'GRANT DELETE ON public.user_stacks TO anon'),
('anon runs owner RPC', 'check_anon_runs_only_the_request_guard', 'GRANT EXECUTE ON FUNCTION public.hide_product_submission(uuid) TO anon'),
('anon runs server RPC', 'check_anon_runs_only_the_request_guard', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO anon'),

('stack read policy open', 'check_other_user_cannot_read_stack', 'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true)'),
-- UPDATE and DELETE also filter through the SELECT policy, so both must open.
('stack update policies open', 'check_other_user_cannot_update_stack',
  'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_update_own_supplements ON public.user_stacks USING (true) WITH CHECK (true)'),
('stack delete policies open', 'check_other_user_cannot_delete_stack',
  'ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_delete_own_stack ON public.user_stacks USING (true)'),
('stack insert owner clause gone', 'check_other_user_cannot_insert_stack', $$ALTER POLICY users_can_insert_own_supplements ON public.user_stacks WITH CHECK (type = 'supplement')$$),
-- The new row must also pass the SELECT policy, so both clauses must go.
('stack update owner clause gone', 'check_owner_cannot_give_stack_row_away',
  $$ALTER POLICY users_can_read_own_stack ON public.user_stacks USING (true); ALTER POLICY users_can_update_own_supplements ON public.user_stacks WITH CHECK (type = 'supplement')$$),
('medication column checks dropped', 'check_medication_refused_by_constraint',
  'ALTER TABLE public.user_stacks DROP CONSTRAINT user_stacks_type_check, DROP CONSTRAINT user_stacks_type_supplement_check'),
('medication insert clause gone', 'check_medication_refused_on_insert_by_policy', 'ALTER POLICY users_can_insert_own_supplements ON public.user_stacks WITH CHECK ((SELECT auth.uid()) = user_id)'),
('medication update clause gone', 'check_medication_refused_on_update_by_policy', 'ALTER POLICY users_can_update_own_supplements ON public.user_stacks WITH CHECK ((SELECT auth.uid()) = user_id)'),

('open: user_usage', 'check_other_user_reads_nothing', 'ALTER POLICY "Users read own usage" ON public.user_usage USING (true)'),
('open: ai_connections', 'check_other_user_reads_nothing', 'ALTER POLICY ai_connections_select_own ON public.ai_connections USING (true)'),
('open: mcp_access_log', 'check_other_user_reads_nothing', 'ALTER POLICY mcp_access_log_select_own ON public.mcp_access_log USING (true)'),
('open: ledger', 'check_other_user_reads_nothing', 'ALTER POLICY product_contribution_ledger_select_own ON public.product_contribution_ledger USING (true)'),
('open: submissions', 'check_other_user_reads_nothing', 'ALTER POLICY product_submissions_select_own ON public.product_submissions USING (true)'),
('open: photos', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_photos_select_own ON public.product_submission_photos USING (true)'),
('open: revisions', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_evidence_revisions_select_own ON public.product_submission_evidence_revisions USING (true)'),
('open: missing details', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_missing_select_own ON public.product_submission_missing_details USING (true)'),
('open: mismatch details', 'check_other_user_reads_nothing', 'ALTER POLICY product_submission_mismatch_select_own ON public.product_submission_mismatch_details USING (true)'),

('clients write submissions', 'check_read_only_tables_refuse_client_writes', 'GRANT DELETE ON public.product_submissions TO authenticated'),
('clients write catalog', 'check_read_only_tables_refuse_client_writes', 'GRANT INSERT ON public.catalog_releases TO authenticated'),
('clients update one column', 'check_read_only_tables_refuse_client_writes', 'GRANT UPDATE (display_name) ON public.product_submissions TO authenticated'),
('clients read snapshots', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.ai_share_snapshots TO authenticated'),
('clients read push tokens', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.device_push_tokens TO authenticated'),
('clients read reviewers', 'check_server_tables_closed_to_clients', 'GRANT SELECT ON public.product_submission_reviewers TO authenticated'),
('clients insert pairings', 'check_server_tables_closed_to_clients', 'GRANT INSERT ON public.ai_connection_pairings TO authenticated'),

('owner gate gone: add evidence', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('add_product_submission_evidence', 'AND candidate\.user_id = caller_id', '')$$),
('owner gate gone: finalize', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('finalize_product_submission', 'AND candidate\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND photo\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND mismatch\.user_id = caller_id', ''); SELECT sec.mutate('finalize_product_submission', 'AND user_id = caller_id', '')$$),
('owner gate gone: hide', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('hide_product_submission', 'candidate\.user_id <> caller_id', 'false'); SELECT sec.mutate('hide_product_submission', 'AND user_id = caller_id', '')$$),
('owner gate gone: rename', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('set_product_submission_display_name', 'AND user_id = auth\.uid\(\)', '')$$),
('owner gate gone: open revision', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('open_product_submission_evidence_revision', 'AND candidate\.user_id = caller_id', '')$$),
('owner gate gone: create replay', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('create_product_submission_v2_internal', 'OR persisted\.user_id <> caller_id', '')$$),
('owner gate gone: intake', 'check_owner_rpcs_refuse_other_user', $$SELECT sec.mutate('get_product_submission_intake', 'submission\.user_id = caller_id', 'true')$$),
('usage gate gone', 'check_usage_counter_refuses_other_user', $$SELECT sec.mutate('increment_usage', 'p_user_id IS DISTINCT FROM auth\.uid\(\)', 'false')$$),
-- A pairing is scoped twice: the row lookup and the browser session's owner.
('pairing gates gone', 'check_pairing_refuses_other_user', $$SELECT sec.mutate('ai_pairing_phone', 'WHERE user_id=u\s+AND code_hash', 'WHERE code_hash'); SELECT sec.mutate('ai_pairing_phone', 'OR NOT public\.ai_pairing_live_session\(u,r\.browser_session_id::text\)', '')$$),

('reviewer helper gate gone', 'check_reviewer_rpcs_refuse_non_reviewers', $$SELECT sec.mutate('assert_product_submission_reviewer', 'reviewer IS NULL OR NOT EXISTS\(.*?\) THEN', 'false THEN')$$),
('worker helper gate gone', 'check_worker_rpcs_refuse_non_workers', $$SELECT sec.mutate('product_submission_extraction_worker_id', 'worker_id IS NULL OR NOT EXISTS \(.*?\) THEN', 'false THEN')$$),
('server RPC granted: list objects', 'check_server_only_rpcs_refuse_signed_in_users', 'GRANT EXECUTE ON FUNCTION public.list_product_submission_objects_for_user(uuid) TO authenticated'),

('photo read policy open', 'check_storage_other_user_cannot_read', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true)'),
('photo read open to anon', 'check_storage_other_user_cannot_read', 'CREATE POLICY sec_open ON storage.objects FOR SELECT TO anon USING (true)'),
('photo worker lease gate gone', 'check_storage_other_user_cannot_read', $$CREATE OR REPLACE FUNCTION public.product_submission_worker_may_read_object(p_name text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS 'SELECT true'$$),
('photo upload owner clause gone', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_insert_own ON storage.objects WITH CHECK (true)'),
('photo update policies open', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true); ALTER POLICY product_submission_objects_update_own ON storage.objects USING (true) WITH CHECK (true)'),
('photo delete policies open', 'check_storage_other_user_cannot_write', 'ALTER POLICY product_submission_objects_select_own ON storage.objects USING (true); ALTER POLICY product_submission_objects_delete_own ON storage.objects USING (true)'),
('photo path check gone', 'check_storage_owner_writes_only_pending_paths', $$ALTER POLICY product_submission_objects_insert_own ON storage.objects WITH CHECK (bucket_id = 'product-submission-photos' AND owner_id = (SELECT auth.uid())::text)$$),

('assistant filter off: stacks', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.user_stacks'),
('assistant filter off: usage', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.user_usage'),
('assistant filter off: connections', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.ai_connections'),
-- The log and photo policies look through a second filtered table.
('assistant filter off: access log', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.mcp_access_log; DROP POLICY ai_connector_no_oauth_client ON public.ai_connections'),
('assistant filter off: submissions', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON public.product_submissions'),
('assistant filter off: photos', 'check_assistant_token_reads_no_owned_rows', 'DROP POLICY ai_connector_no_oauth_client ON storage.objects; DROP POLICY ai_connector_no_oauth_client ON public.product_submission_photos'),
('assistant request guard emptied', 'check_assistant_token_stopped_at_every_request', $$SELECT sec.mutate('reject_oauth_client_request', '\(auth\.jwt\(\) ->> ''client_id''\) IS NOT NULL', 'false')$$),

('staff columns regranted', 'check_submitter_cannot_read_staff_columns', 'GRANT SELECT ON public.product_submissions TO authenticated'),
('uploader column regranted', 'check_submitter_cannot_read_staff_columns', 'GRANT SELECT (uploader_id) ON public.product_submission_photos TO authenticated'),
('app read broken: submissions', 'check_app_reads_keep_working', 'REVOKE SELECT ON public.product_submissions FROM authenticated'),
('app read broken: photos', 'check_app_reads_keep_working', 'REVOKE SELECT (object_path) ON public.product_submission_photos FROM authenticated');

-- Every gated RPC on its own: its gate call is taken out, and the same refusal
-- check must fail. The inline form is taken out too where a function has one.
INSERT INTO sec.mutations(name, check_name, ddl)
SELECT 'reviewer gate gone: ' || f, 'check_reviewer_rpcs_refuse_non_reviewers',
  format($$SELECT sec.ungate_reviewer(%L)$$, f)
    -- This one delegates to a function that checks the reviewer again.
    || CASE WHEN f = 'review_product_submission' THEN $$; SELECT sec.ungate_reviewer('review_product_submission_unchecked')$$ ELSE '' END
FROM unnest(sec.reviewer_rpcs()) f;
INSERT INTO sec.mutations(name, check_name, ddl)
SELECT 'worker gate gone: ' || f, 'check_worker_rpcs_refuse_non_workers',
  format($$SELECT sec.mutate(%L, 'public\.product_submission_extraction_worker_id\(\)', 'auth.uid()')$$, f)
    -- This one then also refuses a caller with no receipt of their own.
    || CASE WHEN f = 'product_submission_extraction_attempt_outcome' THEN format(
      $$; SELECT sec.mutate(%L, 'IF NOT FOUND THEN\s+RAISE EXCEPTION ''extraction attempt access required'' USING ERRCODE=''42501'';\s+END IF;', '')$$, f)
      ELSE '' END
FROM unnest(sec.worker_rpcs()) f;

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

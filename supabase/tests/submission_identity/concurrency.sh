# Sourced by scripts/test_submission_identity.sh inside its disposable DB.
# Hold the first real transaction open, then observe the second session wait
# on the database lock. Wall-clock timing alone is not the correctness check.
wait_for_event() {
  local application_name="$1" event_name="$2"
  for attempt in {1..50}; do
    if [[ "$(psql_test -Atqc "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '$application_name' AND wait_event = '$event_name')")" == t ]]; then
      return 0
    fi
    sleep 0.02
  done
  return 1
}

test_logs="$(mktemp -d)"
approval_first="$(psql_test -Atqc "SELECT fixture.seed(1, '4006381333931', 'under_review', NULL)")"
approval_second="$(psql_test -Atqc "SELECT fixture.seed(2, '04006381333931', 'under_review', NULL)")"
psql_test -q -c "SET application_name = 'fixture_approval_first'; BEGIN; SELECT fixture.approve('$approval_first'); SELECT pg_sleep(3); COMMIT;" > "$test_logs/approval-first.log" 2>&1 &
approval_first_pid=$!
wait_for_event fixture_approval_first PgSleep
psql_test -q -c "SET application_name = 'fixture_approval_second'; SELECT fixture.approve('$approval_second');" > "$test_logs/approval-second.log" 2>&1 &
approval_second_pid=$!
approval_waited=false
if wait_for_event fixture_approval_second advisory; then approval_waited=true; fi
wait "$approval_first_pid"
approval_second_status=0
wait "$approval_second_pid" || approval_second_status=$?
psql_test -q -c "SELECT fixture.test('concurrent approvals share canonical advisory lock', 'SELECT fixture.assert($approval_waited AND $approval_second_status <> 0 AND (SELECT count(*) = 1 FROM public.product_submissions WHERE id IN (''$approval_first'',''$approval_second'') AND review_status = ''approved''), ''equivalent width approvals must serialize and only one can commit'')')"

finalize_first="$(psql_test -Atqc "SELECT fixture.seed(4, '012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending')")"
finalize_second="$(psql_test -Atqc "SELECT fixture.seed(4, '0012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending')")"
psql_test -q -c "SET application_name = 'fixture_finalize_first'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004'; BEGIN; SELECT public.finalize_product_submission('$finalize_first'); SELECT pg_sleep(3); COMMIT;" > "$test_logs/finalize-first.log" 2>&1 &
finalize_first_pid=$!
wait_for_event fixture_finalize_first PgSleep
psql_test -q -c "SET application_name = 'fixture_finalize_second'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004'; SELECT public.finalize_product_submission('$finalize_second');" > "$test_logs/finalize-second.log" 2>&1 &
finalize_second_pid=$!
finalize_waited=false
if wait_for_event fixture_finalize_second transactionid; then finalize_waited=true; fi
wait "$finalize_first_pid"
finalize_second_status=0
wait "$finalize_second_pid" || finalize_second_status=$?
psql_test -q -c "SELECT fixture.test('concurrent finalize preserves one ready receipt', 'SELECT fixture.assert($finalize_waited AND $finalize_second_status <> 0 AND (SELECT count(*) = 1 FROM public.product_submissions WHERE id IN (''$finalize_first'',''$finalize_second'') AND upload_state = ''ready''), ''canonical unique index must allow only one finalization'')')"

lineage_target="$(psql_test -Atqc "SELECT fixture.seed(5, '96385074')")"
replayed_id="$(psql_test -Atqc 'SELECT gen_random_uuid()')"
psql_test -q -c "SET application_name = 'fixture_create_first'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005'; BEGIN; SELECT public.create_product_submission('$replayed_id', 'missing_product', '96385074', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1'); SELECT pg_sleep(3); COMMIT;" > "$test_logs/create-first.log" 2>&1 &
create_first_pid=$!
wait_for_event fixture_create_first PgSleep
psql_test -q -c "SET application_name = 'fixture_create_second'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005'; SELECT public.create_product_submission('$replayed_id', 'missing_product', '96385074', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => '$lineage_target');" > "$test_logs/create-second.log" 2>&1 &
create_second_pid=$!
create_waited=false
if wait_for_event fixture_create_second advisory; then create_waited=true; fi
wait "$create_first_pid"
create_second_status=0
wait "$create_second_pid" || create_second_status=$?
psql_test -q -c "SELECT fixture.test('concurrent same UUID create cannot rewrite initial null lineage', 'SELECT fixture.assert($create_waited AND $create_second_status <> 0 AND (SELECT resubmission_of IS NULL FROM public.product_submissions WHERE id = ''$replayed_id''), ''same UUID first-create races must preserve original immutable lineage'')')"

identical_id="$(psql_test -Atqc 'SELECT gen_random_uuid()')"
identical_call="SELECT public.create_product_submission('$identical_id', 'missing_product', '96385074', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => '$lineage_target');"
psql_test -q -c "SET application_name = 'fixture_identical_first'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005'; BEGIN; $identical_call SELECT pg_sleep(3); COMMIT;" > "$test_logs/identical-first.log" 2>&1 &
identical_first_pid=$!
wait_for_event fixture_identical_first PgSleep
psql_test -q -c "SET application_name = 'fixture_identical_second'; SET ROLE authenticated; SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005'; $identical_call" > "$test_logs/identical-second.log" 2>&1 &
identical_second_pid=$!
identical_waited=false
if wait_for_event fixture_identical_second advisory; then identical_waited=true; fi
wait "$identical_first_pid"
identical_second_status=0
wait "$identical_second_pid" || identical_second_status=$?
psql_test -q -c "SELECT fixture.test('concurrent identical UUID replay succeeds with one immutable receipt', 'SELECT fixture.assert($identical_waited AND $identical_second_status = 0 AND (SELECT count(*) = 1 AND bool_and(resubmission_of = ''$lineage_target'') FROM public.product_submissions WHERE id = ''$identical_id'') AND (SELECT count(*) = 1 FROM public.product_submission_photos WHERE submission_id = ''$identical_id''), ''identical create retries must both succeed without duplicating or changing evidence'')')"
storage_pending="$(psql_test -Atqc "SELECT fixture.seed(1, '012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending')")"
psql_test -q -c "SET application_name='fixture_storage_writer'; SET ROLE authenticated; SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001'; BEGIN; UPDATE storage.objects SET user_metadata=jsonb_build_object('content_sha256',repeat('b',64)) WHERE name='00000000-0000-0000-0000-000000000001/$storage_pending/10000000-0000-0000-0000-000000000001'; SELECT pg_sleep(3); COMMIT;" > "$test_logs/storage-writer.log" 2>&1 &
storage_writer_pid=$!
wait_for_event fixture_storage_writer PgSleep
psql_test -q -c "SET application_name='fixture_storage_finalize'; SET ROLE authenticated; SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001'; SELECT fixture.assert(NOT public.finalize_product_submission('$storage_pending',1),'changed pending bytes must prevent finalization');" > "$test_logs/storage-finalize.log" 2>&1 &
storage_finalize_pid=$!
storage_waited=false
if wait_for_event fixture_storage_finalize transactionid; then storage_waited=true; fi
wait "$storage_writer_pid"
storage_finalize_status=0
wait "$storage_finalize_pid" || storage_finalize_status=$?
psql_test -q -c "SELECT fixture.test('in-flight Storage mutation serializes with manifest finalization', 'SELECT fixture.assert($storage_waited AND $storage_finalize_status=0 AND (SELECT upload_state=''pending'' FROM public.product_submissions WHERE id=''$storage_pending''), ''no mutable upload may commit after a ready manifest freeze'')')"

if [[ "$approval_waited" != true || "$finalize_waited" != true || "$create_waited" != true || "$identical_waited" != true || "$storage_waited" != true ]]; then
  echo "Concurrency diagnostics: $test_logs"
else
  rm "$test_logs/approval-first.log" "$test_logs/approval-second.log" "$test_logs/finalize-first.log" "$test_logs/finalize-second.log" "$test_logs/create-first.log" "$test_logs/create-second.log" "$test_logs/identical-first.log" "$test_logs/identical-second.log"
  rm "$test_logs/storage-writer.log" "$test_logs/storage-finalize.log"
  rmdir "$test_logs"
fi

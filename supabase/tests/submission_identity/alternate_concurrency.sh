# Two real sessions exercise both orderings. Receipt snapshots and immutable
# approvals are checked after blocking, not inferred from elapsed time.
alt_unrelated_id="$(psql_test -Atqc "SELECT fixture.seed(3,'036000291452','under_review',NULL)")"
psql_test -q -c "SELECT fixture.approve('$alt_unrelated_id')" >/dev/null
alt_unrelated_json="$(psql_test -Atqc "SELECT jsonb_build_array(jsonb_build_object('submission_id',submission_id,'approval_revision',approval_revision,'payload_sha256',payload_sha256)) FROM public.product_submission_approved_labels WHERE submission_id='$alt_unrelated_id'")"
for alt_list_kind in empty unrelated; do
 if [[ "$alt_list_kind" == empty ]]; then alt_release_list='[]'; else alt_release_list="$alt_unrelated_json"; fi
alt_logs="$(mktemp -d)"
alt_approve_id="$(psql_test -Atqc "SELECT fixture.seed_alternate(1,'Race Approval $alt_list_kind','Race Label')")"
psql_test -q -c "INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('race-approval-first-$alt_list_kind','98765431','Race Label','Race Approval $alt_list_kind')" >/dev/null
psql_test -q -c "SET application_name='fixture_alt_approve'; BEGIN; SELECT set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false); SELECT fixture.approve_alternate('$alt_approve_id'); SELECT pg_sleep(2); COMMIT;" > "$alt_logs/approve.log" 2>&1 &
alt_pid=$!
wait_for_event fixture_alt_approve PgSleep
psql_test -q -c "SET application_name='fixture_alt_activate'; SELECT public.rotate_manifest_with_submission_approvals('race-approval-first-$alt_list_kind','p','s','1',1,'hash',now(),'1.0.0','$alt_release_list');" > "$alt_logs/activate.log" 2>&1 &
alt_activation_pid=$!
alt_waited=false
if wait_for_event fixture_alt_activate advisory; then alt_waited=true; fi
wait "$alt_pid"
alt_activation_status=0
wait "$alt_activation_pid" || alt_activation_status=$?
psql_test -q -c "SELECT fixture.test('alternate approval first fences $alt_list_kind-list activation', 'SELECT fixture.assert($alt_waited AND $alt_activation_status <> 0 AND (SELECT count(*)=1 FROM public.product_submission_approved_labels WHERE submission_id=''$alt_approve_id'') AND NOT EXISTS(SELECT 1 FROM public.export_manifest WHERE db_version=''race-approval-first-$alt_list_kind''), ''activation waits then refuses; immutable approval stays intact'')')" >/dev/null

alt_late_id="$(psql_test -Atqc "SELECT fixture.seed_alternate(2,'Race Catalog $alt_list_kind','Race Other')")"
psql_test -q -c "INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('race-catalog-first-$alt_list_kind','98765432','Race Other','Race Catalog $alt_list_kind')" >/dev/null
psql_test -q -c "SET application_name='fixture_alt_catalog_first'; BEGIN; SELECT public.rotate_manifest_with_submission_approvals('race-catalog-first-$alt_list_kind','p','s','1',1,'hash',now(),'1.0.0','$alt_release_list'); SELECT pg_sleep(2); COMMIT;" > "$alt_logs/catalog-first.log" 2>&1 &
alt_catalog_pid=$!
wait_for_event fixture_alt_catalog_first PgSleep
psql_test -q -c "SET application_name='fixture_alt_late_approve'; SELECT set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false); SELECT fixture.approve_alternate('$alt_late_id');" > "$alt_logs/late-approve.log" 2>&1 &
alt_late_pid=$!
alt_late_waited=false
if wait_for_event fixture_alt_late_approve advisory; then alt_late_waited=true; fi
wait "$alt_catalog_pid"
alt_late_status=0
wait "$alt_late_pid" || alt_late_status=$?
psql_test -q -c "SELECT fixture.test('alternate activation first invalidates waiting approval $alt_list_kind', 'SELECT fixture.assert($alt_late_waited AND $alt_late_status <> 0 AND NOT EXISTS(SELECT 1 FROM public.product_submission_approved_labels WHERE submission_id=''$alt_late_id''), ''approval waits and refuses changed full catalog conflict set'')')" >/dev/null
if [[ "$alt_waited" == true && "$alt_late_waited" == true ]]; then
 rm "$alt_logs/approve.log" "$alt_logs/activate.log" "$alt_logs/catalog-first.log" "$alt_logs/late-approve.log"
 rmdir "$alt_logs"
else
 echo "Alternate concurrency diagnostics: $alt_logs"
fi

done

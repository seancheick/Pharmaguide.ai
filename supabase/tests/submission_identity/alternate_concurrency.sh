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

# Label identity edits use the same global-before-row lock order as approval.
alt_draft_logs="$(mktemp -d)"
alt_draft_id="$(psql_test -Atqc "SELECT fixture.seed_alternate(2,'Draft Fence','Draft Label')")"
psql_test -q -c "SET application_name='fixture_alt_draft_approval'; BEGIN; SELECT set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false); SELECT fixture.approve_alternate('$alt_draft_id'); SELECT pg_sleep(2); COMMIT;" > "$alt_draft_logs/approval.log" 2>&1 &
alt_draft_approval_pid=$!
wait_for_event fixture_alt_draft_approval PgSleep
psql_test -q -c "SET application_name='fixture_alt_draft_edit'; SELECT set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false); SELECT public.save_product_submission_reviewer_draft('$alt_draft_id',1,fixture.manifest_hash('$alt_draft_id'),jsonb_build_object('brandName','Changed','fullName','Changed'),'{\"brandName\":\"Changed\",\"fullName\":\"Changed\"}',repeat('e',64));" > "$alt_draft_logs/edit.log" 2>&1 &
alt_draft_edit_pid=$!
alt_draft_waited=false
if wait_for_event fixture_alt_draft_edit advisory; then alt_draft_waited=true; fi
wait "$alt_draft_approval_pid"
alt_draft_status=0
wait "$alt_draft_edit_pid" || alt_draft_status=$?
psql_test -q -c "SELECT fixture.test('reviewed label edits acquire identity fence before row locks', 'SELECT fixture.assert($alt_draft_waited AND $alt_draft_status <> 0 AND (SELECT approved_payload#>>''{label,brandName}''=''Draft Fence'' FROM public.product_submission_approved_labels WHERE submission_id=''$alt_draft_id''), ''late draft edit waits on global identity fence and cannot change approved identity'')')" >/dev/null
if [[ "$alt_draft_waited" == true ]]; then rm "$alt_draft_logs/approval.log" "$alt_draft_logs/edit.log"; rmdir "$alt_draft_logs"; else echo "Draft fence diagnostics: $alt_draft_logs"; fi

# A selected target cannot be deleted while its approval commits.
alt_delete_logs="$(mktemp -d)"
psql_test -q -c "INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('delete-race-catalog','901','Deletion Label','Deletion Fence'); SELECT public.rotate_manifest_with_submission_approvals('delete-race-catalog','p','s','1',1,'hash',now());" >/dev/null
alt_delete_id="$(psql_test -Atqc "SELECT fixture.seed_catalog_alternate(1,'901','Deletion Fence','Deletion Label')")"
psql_test -q -c "SET application_name='fixture_alt_target_approval'; BEGIN; SELECT fixture.approve_catalog_alternate('$alt_delete_id','901'); SELECT pg_sleep(2); COMMIT;" > "$alt_delete_logs/approval.log" 2>&1 &
alt_target_approval_pid=$!
wait_for_event fixture_alt_target_approval PgSleep
psql_test -q -c "SET application_name='fixture_alt_target_delete'; DELETE FROM public.catalog_search WHERE catalog_version='delete-race-catalog' AND dsld_id='901';" > "$alt_delete_logs/delete.log" 2>&1 &
alt_target_delete_pid=$!
alt_delete_waited=false
if wait_for_event fixture_alt_target_delete advisory; then alt_delete_waited=true; fi
wait "$alt_target_approval_pid"
alt_delete_status=0
wait "$alt_target_delete_pid" || alt_delete_status=$?
psql_test -q -c "SELECT fixture.test('selected catalog deletion waits and refuses after concurrent approval', 'SELECT fixture.assert($alt_delete_waited AND $alt_delete_status <> 0 AND EXISTS(SELECT 1 FROM public.catalog_search WHERE catalog_version=''delete-race-catalog'' AND dsld_id=''901'') AND EXISTS(SELECT 1 FROM public.product_submission_approved_labels WHERE submission_id=''$alt_delete_id''), ''deletion shares global fence and cannot remove a selected approved target'')')" >/dev/null
if [[ "$alt_delete_waited" == true ]]; then rm "$alt_delete_logs/approval.log" "$alt_delete_logs/delete.log"; rmdir "$alt_delete_logs"; else echo "Target deletion diagnostics: $alt_delete_logs"; fi

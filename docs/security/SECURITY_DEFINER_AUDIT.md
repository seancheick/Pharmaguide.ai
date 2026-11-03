# SECURITY DEFINER audit

Hardening item A6. One row for each of the 130 `SECURITY DEFINER` functions in the live database on
2026-11-03: 124 in `public`, and 6 owned by the provider (`pgbouncer` 1, `storage` 3, `vault` 2).

Sources: the Supabase security advisor and a live catalog read, both read-only, plus a replay of the
shared migration stream. The replay matches live on `search_path` and `EXECUTE` for all 123 `public`
functions it holds. Source differs only in comments in `promote_catalog_release` and
`rotate_manifest`. Table privileges for `anon` and `authenticated` hash the same on both (40
relations). The "reached from" column comes from a text search of `lib/`, `supabase/functions/`, the
website and `pipeline/scripts`, so it can miss a dynamically built name.

The advisor still reports 39 warnings, 1 for anon and 38 for signed-in users. They cover 38 functions,
because the request guard is counted twice. That number is the part an API caller can reach, not the
size of the audit, and the same 38 remain after this work. Each one stays exposed on purpose: the
shipped app, the reviewer function, the extraction worker client or a storage policy calls it, or it
is the request guard. Only `increment_usage` has no caller today (see below).

Rows in the first table were classified by reading each function body. Service-role and owner-only
rows were classified from the catalog, the tables they touch and their callers, not line by line. No
API caller can reach them, and the suite calls each one as a signed-in user and requires a refusal.

## Findings, ranked by what could really leak

| # | Finding | Who could see what | Status |
|---|---|---|---|
| F1 | `review-product-submissions` did not refuse AI assistant tokens | An assistant token issued to a **reviewer's** account passes the user check, then the function reads with the admin client, so the PostgREST request guard never sees those reads: submission rows and signed links to pending reviewer evidence. The reviewer table lists one account. Not proved against production, since that needs a real assistant token | Fixed in this PR, with a test. **Needs an edge function deploy** |
| F2 | Submitters could read staff columns on their own rows | `reviewed_by`, `evidence_requested_by`, `cleanup_claim_token`, `cleanup_claimed_at`, and `uploader_id` on photos. This reveals a reviewer's account id. The claim token is usable only by service-role functions | Fixed by migration `20261103120000`, with a test. **Needs applying to production** |
| F3 | The hourly `notify-new-product-submissions` cron job holds its shared secret as plain text in `cron.job` | Not in the repo and not readable by API roles. Project admins can read it, and `pg_net` logs may hold it | **Sean's decision:** rotate it and move it to Vault |

None of these is a medication or profile leak. Live, `user_stacks` holds 30 rows and none is a
non-supplement. Column checks and row policies refuse a medication row, and both layers are tested.

Hygiene items, no leak:

- `increment_usage`, `promote_catalog_release` and `rotate_manifest` set `search_path` to
  `public, pg_catalog` rather than empty. Not exploitable, because no API role can create objects in
  `public`.
- `increment_usage` has no caller in the app, the functions or the pipeline scripts. It is owned by
  the pipeline schema. A removal candidate in that repo.
- `rotate_manifest` and the 15-argument `review_product_submission_unchecked` look dead.
- `user_stacks` has its primary key on `id` alone. A collision with another user's id is refused and
  tested, and it reveals only that the id exists.
- `rls_auto_enable` is in production and not in the repo stream. It came from the dashboard.
- The 23 `rls_enabled_no_policy` advisor notes are server-only tables. Closed to clients is intended,
  and tested.

## How this stays true

`scripts/test_backend_security.sh` replays the stream and runs `supabase/tests/backend_security/`. It
checks anonymous callers, other users' rows, writes, gated functions, storage and assistant tokens,
then removes each protection once and fails unless its check notices. A new definer function or a
changed grant fails the run until `definer_exposure_pin.sql` and this page are updated together. CI
runs it on every code change.

## Reachable by the app, a worker or anon (38)

| Function | Who can execute | Caller gate | Input checks | `search_path` | Reached from | What could leak or change |
|---|---|---|---|---|---|---|
| `add_product_submission_evidence/3` | signed-in | Owner: filters on `auth.uid()` | Typed; 6 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Adds photos to someone else's pending submission. |
| `approve_ai_connection_pairing/1` | signed-in | Owner and live session: `ai_pairing_phone`, code hash scoped to `auth.uid()` | Code length and alphabet checked in `ai_pairing_phone`; rate limited | `""` | app `ai_connections_repository.dart` | Connects an AI assistant to the account. The highest-impact write here, since it grants a read of the health summary the user consents to share. |
| `assert_product_submission_fully_verified/2` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 2 refusal(s), e.g. "this label was not the one reviewed" | `""` | 2 other definer function(s) | Whether a draft is fully verified. A yes or no about one submission. |
| `cancel_my_ai_connection_pairing/1` | signed-in | Owner and live session: `ai_pairing_phone`, code hash scoped to `auth.uid()` | Code length and alphabet checked in `ai_pairing_phone`; rate limited | `""` | app `ai_connections_repository.dart` | Cancels someone else's pending connection. |
| `claim_product_submission_extraction_jobs/1` | signed-in | Worker role: `product_submission_extraction_worker_id()` | Typed; 2 refusal(s), e.g. "invalid claim limit" | `""` | pipeline `queue_client.py` | Hands out jobs with photo paths for any submission in the queue. |
| `complete_product_submission_extraction_job/14` | signed-in | Worker role: `product_submission_extraction_worker_id()` plus fencing token | Typed; 6 refusal(s), e.g. "invalid extraction outcome" | `""` | pipeline `queue_client.py` | Writes an AI draft and spends budget. |
| `correct_product_submission_barcode/5` | signed-in | Reviewer role: `assert_product_submission_reviewer()` and inline | Typed; 6 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Changes any submission's barcode and clears its verifications. |
| `create_product_submission/9` | signed-in | Owner: filters on `auth.uid()`; replay of another user's id conflicts | Typed; 11 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Creates the caller's own row. Another user's id is refused. |
| `create_product_submission_reviewer_evidence_revision/5` | signed-in | Reviewer role: inline check of `product_submission_reviewers` | Typed; 7 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Adds reviewer photos to any submission. |
| `create_product_submission_reviewer_image/7` | signed-in | Reviewer role: inline check of `product_submission_reviewers` | Typed; 3 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Returns a reviewer image path for any submission. |
| `finalize_product_submission/2` | signed-in | Owner: filters on `auth.uid()` | Typed; 3 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Submits someone else's pending evidence. |
| `get_product_submission_evidence/1` | signed-in | Reviewer role: inline check of `product_submission_reviewers` | Typed; 2 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Any submitter's photo paths and label identifiers. The most sensitive reviewer read. |
| `get_product_submission_extractions/2` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed arguments | `""` | edge `review-product-submissions` | AI label drafts for any submission. |
| `get_product_submission_identity_candidates/1` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed arguments | `""` | edge `review-product-submissions` | Catalog matches and approved labels for any submission. |
| `get_product_submission_intake/3` | signed-in | Owner: filters on `auth.uid()` | Typed; 4 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Whether the caller already reported this barcode. Answers only from the caller's rows. |
| `heartbeat_product_submission_extraction_job/2` | signed-in | Worker role: `product_submission_extraction_worker_id()` plus fencing token | Typed; 1 refusal(s), e.g. "extraction lease is not held" | `""` | pipeline `queue_client.py` | Extends a lease. No data returned beyond a timestamp. |
| `hide_product_submission/1` | signed-in | Owner: filters on `auth.uid()` | Typed; 3 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Hides a row from someone else's history. |
| `increment_usage/2` | signed-in, service role | `p_user_id` must equal `auth.uid()` | Typed; 2 refusal(s), e.g. "Unauthorized: cannot increment usage for another user" | `public, pg_catalog` | none found | Raises another user's usage counter. No caller found in the app, functions or pipeline scripts. |
| `load_product_submission_reviewer_draft/1` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed arguments | `""` | edge `review-product-submissions` | A reviewer's draft and image rows. |
| `open_product_submission_evidence_revision/6` | signed-in | Owner: filters on `auth.uid()` | Typed; 12 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Opens a retake on someone else's submission. |
| `pgrst_reject_ai_assistant_tokens/0` | anon, signed-in, service role | None by design: it runs before every API request | Typed arguments | `""` | `pgrst.db_pre_request` on every API request | Nothing. It returns void or refuses an assistant token. This is the single anon-callable definer, and the advisor warning on it is expected. |
| `prepare_product_submission_approval_payload/4` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 3 refusal(s), e.g. "matched catalog target is not active" | `""` | edge `review-product-submissions`, 1 other definer function(s) | Canonical approval payload built from a draft. |
| `preview_ai_connection_pairing/1` | signed-in | Owner and live session: `ai_pairing_phone`, code hash scoped to `auth.uid()` | Code length and alphabet checked in `ai_pairing_phone`; rate limited | `""` | app `ai_connections_repository.dart` | Assistant name and callback host for a pending code. |
| `product_submission_extraction_attempt_outcome/2` | signed-in | Worker role: `product_submission_extraction_worker_id()` plus own receipt | Typed; 1 refusal(s), e.g. "extraction attempt access required" | `""` | pipeline `queue_client.py` | Outcome of the caller's own attempt. |
| `product_submission_extraction_budget_state/0` | signed-in | Worker role: `product_submission_extraction_worker_id()` | Typed arguments | `""` | pipeline `queue_client.py` | Budget totals. No user data. |
| `product_submission_photo_uploadable/1` | signed-in | Filters on `auth.uid()` | Typed arguments | `""` | storage row policy | A yes or no about the caller's own pending path. Used by the storage policy. |
| `product_submission_reviewer_batch_state/1` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 1 refusal(s), e.g. "too many submissions requested" | `""` | edge `review-product-submissions` | Review state for a list of submission ids. |
| `product_submission_worker_may_read_object/1` | signed-in | Requires a live lease held by `auth.uid()` | Typed arguments | `""` | storage row policy | A yes or no about a path. Used by the storage policy. |
| `record_product_submission_extraction/11` | signed-in | Reviewer role: inline check of `product_submission_reviewers` | Typed; 1 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Writes an AI draft against any submission. |
| `record_product_submission_match_check/13` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 8 refusal(s), e.g. "open missing-product submission required" | `""` | edge `review-product-submissions` | Writes a catalog match decision. |
| `reopen_product_submission_approval/4` | signed-in | Reviewer role: `assert_product_submission_reviewer()` and inline | Typed; 8 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Reopens an approved label. An integrity risk, no read. |
| `request_product_submission_evidence/5` | signed-in | Reviewer role: inline check of `product_submission_reviewers` | Typed; 6 refusal(s), e.g. "reviewer access required" | `""` | edge `review-product-submissions` | Sends a retake request and push to any submitter. |
| `reserve_product_submission_extraction_budget/2` | signed-in | Worker role: `product_submission_extraction_worker_id()` plus fencing token | Typed; 2 refusal(s), e.g. "extraction is disabled" | `""` | pipeline `queue_client.py` | Spends budget. No user data. |
| `review_product_submission/17` | signed-in | Reviewer role: `assert_product_submission_reviewer()`, again in `_unchecked` | Typed; 1 refusal(s), e.g. "this label was not the one reviewed" | `""` | edge `review-product-submissions` | Approves or rejects any submission, which feeds the catalog. |
| `save_product_submission_reviewer_draft/6` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 3 refusal(s), e.g. "label payload object required" | `""` | edge `review-product-submissions` | Overwrites a reviewer draft. |
| `set_product_submission_display_name/2` | signed-in | Owner: filters on `auth.uid()` | Typed; 3 refusal(s), e.g. "authentication required" | `""` | app `product_submission_service.dart` | Renames a row in someone else's history. |
| `set_product_submission_field_verification/5` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 3 refusal(s), e.g. "save the reviewed label before attesting to a field" | `""` | edge `review-product-submissions` | Marks draft fields as verified. |
| `set_product_submission_review_image/5` | signed-in | Reviewer role: `assert_product_submission_reviewer()` | Typed; 5 refusal(s), e.g. "editable missing product required" | `""` | edge `review-product-submissions` | Chooses the image shown for an approved product. |

## Service role only (31)

| Function | Who can execute | Caller gate | Input checks | `search_path` | Reached from | What could leak or change |
|---|---|---|---|---|---|---|
| `ai_connection_pairing_status/3` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Pairing status for a user and session, read by the website. A holder of that key already has full access, so this adds no exposure. |
| `assert_product_submission_approval_revision/3` | service role | Service role key only | Typed; 1 refusal(s), e.g. "approval changed" | `""` | pipeline `product_submission_import.py`, 5 other definer function(s) | A yes or no about an approval revision, read by the pipeline import. A holder of that key already has full access, so this adds no exposure. |
| `begin_ai_connection_revocation/2` | service role | Service role key only | Typed arguments | `""` | edge `delete-account`, website `api/ai-connections/route.ts`, 2 other definer function(s) | Starts revoking a user's AI connections. A holder of that key already has full access, so this adds no exposure. |
| `bind_ai_connection_session/2` | service role | Service role key only | Typed arguments | `""` | edge `mcp-personal` | Binds an assistant session to a connection. A holder of that key already has full access, so this adds no exposure. |
| `cancel_ai_connection_pairing/3` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Cancels a pairing and purges its snapshots. A holder of that key already has full access, so this adds no exposure. |
| `claim_admin_submission_notifications/1` | service role | Service role key only | Typed; 1 refusal(s), e.g. "invalid notification claim limit" | `""` | edge `notify-new-product-submissions` | Queued submission rows for the admin alert email. A holder of that key already has full access, so this adds no exposure. |
| `claim_product_submission_cleanup/1` | service role | Service role key only | Typed; 1 refusal(s), e.g. "invalid cleanup limit" | `""` | edge `cleanup-product-submissions` | Object paths for expired evidence, plus the cleanup claim token. A holder of that key already has full access, so this adds no exposure. |
| `claim_safety_alert_push_delivery/4` | service role | Service role key only | Typed arguments | `""` | edge `dispatch-safety-alert-release` | Claims a push delivery. Catalog safety data only. A holder of that key already has full access, so this adds no exposure. |
| `complete_ai_connection_pairing/5` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts`, 3 other definer function(s) | Creates the AI connection. A holder of that key already has full access, so this adds no exposure. |
| `complete_product_submission_cleanup/2` | service role | Service role key only | Typed; 2 refusal(s), e.g. "invalid cleanup claims" | `""` | edge `cleanup-product-submissions` | Marks evidence purged. A holder of that key already has full access, so this adds no exposure. |
| `complete_safety_alert_push_delivery/3` | service role | Service role key only | Typed arguments | `""` | edge `dispatch-safety-alert-release` | Records a push result. A holder of that key already has full access, so this adds no exposure. |
| `export_approved_product_submissions/3` | service role | Service role key only | Typed arguments | `""` | pipeline `product_submission_import.py` | Approved labels, for the pipeline import. A holder of that key already has full access, so this adds no exposure. |
| `finalize_product_submission_reviewer_evidence_revision/3` | service role | Service role key only | Typed; 5 refusal(s), e.g. "current correction evidence required" | `""` | edge `review-product-submissions` | Freezes reviewer evidence after upload. A holder of that key already has full access, so this adds no exposure. |
| `finalize_product_submission_reviewer_image/5` | service role | Service role key only | Typed; 4 refusal(s), e.g. "reviewer image requires current evidence" | `""` | edge `review-product-submissions` | Marks a reviewer image ready. A holder of that key already has full access, so this adds no exposure. |
| `finish_ai_connection_revocation/3` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Finishes a revocation. A holder of that key already has full access, so this adds no exposure. |
| `get_approved_product_submission_image/3` | service role | Service role key only | Typed arguments | `""` | pipeline `product_submission_import.py` | Image path for an approved label. A holder of that key already has full access, so this adds no exposure. |
| `get_product_submission_reviewer_evidence_revision/2` | service role | Service role key only | Typed; 1 refusal(s), e.g. "current reviewer evidence required" | `""` | edge `review-product-submissions` | Reviewer evidence paths for a revision. A holder of that key already has full access, so this adds no exposure. |
| `list_product_submission_objects_for_user/1` | service role | Service role key only | Typed arguments | `""` | edge `delete-account` | Every photo path a user owns, used by account deletion. Sensitive if ever granted wider; pinned and tested. A holder of that key already has full access, so this adds no exposure. |
| `mark_product_submission_promoted/5` | service role | Service role key only | Typed; 6 refusal(s), e.g. "catalog version required" | `""` | pipeline `product_submission_import.py`, 1 other definer function(s) | Marks a submission promoted and awards points. A holder of that key already has full access, so this adds no exposure. |
| `preview_workos_ai_pairing/2` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Pairing preview, for the website. A holder of that key already has full access, so this adds no exposure. |
| `product_submission_has_required_evidence/2` | service role | Service role key only | Typed arguments | `""` | 4 other definer function(s) | A yes or no about required photos. A holder of that key already has full access, so this adds no exposure. |
| `promote_catalog_release/1` | service role | Service role key only | Typed; 4 refusal(s), e.g. "promote_catalog_release is restricted to service_role" | `public, pg_catalog` | pipeline `sync_to_supabase.py` | Promotes a catalog release. Integrity, no personal data. A holder of that key already has full access, so this adds no exposure. |
| `promote_safety_alert_release/1` | service role | Service role key only | Typed; 1 refusal(s), e.g. "unknown safety alert release" | `""` | pipeline `sync_safety_alerts.py` | Promotes a safety alert release. Integrity, no personal data. A holder of that key already has full access, so this adds no exposure. |
| `purge_expired_ai_share_snapshots/0` | service role | Service role key only | Typed arguments | `""` | none found | Deletes expired snapshots. Returns counts. A holder of that key already has full access, so this adds no exposure. |
| `read_ai_connection_generation/1` | service role | Service role key only | Typed arguments | `""` | edge `mcp-personal`, 3 other definer function(s) | A generation counter. A holder of that key already has full access, so this adds no exposure. |
| `record_admin_submission_notification_result/4` | service role | Service role key only | Typed arguments | `""` | edge `notify-new-product-submissions` | Records an alert result. A holder of that key already has full access, so this adds no exposure. |
| `register_workos_ai_pairing/8` | service role | Service role key only | Typed arguments | `""` | edge `mcp-personal` | Registers a pairing for an assistant. A holder of that key already has full access, so this adds no exposure. |
| `release_safety_alert_push_delivery/4` | service role | Service role key only | Typed arguments | `""` | edge `dispatch-safety-alert-release` | Releases a delivery claim. A holder of that key already has full access, so this adds no exposure. |
| `revoke_ai_connection_pairings/2` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Revokes pairings. A holder of that key already has full access, so this adds no exposure. |
| `rotate_manifest_with_submission_approvals/9` | service role | Service role key only | Typed; 6 refusal(s), e.g. "product_count cannot be negative" | `""` | pipeline `supabase_client.py` | Publishes a catalog manifest. Integrity, no personal data. A holder of that key already has full access, so this adds no exposure. |
| `start_ai_connection_pairing/7` | service role | Service role key only | Typed arguments | `""` | website `api/ai-connections/route.ts` | Starts a pairing and returns its status. A holder of that key already has full access, so this adds no exposure. |

## No API role can call these (38)

| Function | Who can execute | Caller gate | Input checks | `search_path` | Reached from | What could leak or change |
|---|---|---|---|---|---|---|
| `ai_pairing_budget/2` | owner only | No API role can call it | Typed arguments | `""` | 3 other definer function(s) | Reached only through a gated function. Touches ai_connection_pairing_limits. |
| `ai_pairing_live_session/2` | owner only | No API role can call it | Typed arguments | `""` | 4 other definer function(s) | Reached only through a gated function. Touches auth.sessions. |
| `ai_pairing_lock/1` | owner only | No API role can call it | Typed arguments | `""` | 13 other definer function(s) | Reached only through a gated function. Touches no table. |
| `ai_pairing_phone/2` | owner only | No API role can call it | Typed arguments | `""` | 3 other definer function(s) | Reached only through a gated function. Touches ai_connection_pairings. |
| `ai_revoke_connection_local/2` | owner only | No API role can call it | Typed arguments | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ai_connection_pairings, ai_connections, ai_share_snapshots, mcp_access_log. |
| `assert_product_submission_approval/1` | owner only | No API role can call it | Typed arguments | `""` | none found | Reached only through a gated function. Touches ps_approved_labels, pss. |
| `assert_product_submission_catalog_identity/0` | owner only | No API role can call it | Typed; 3 refusal(s), e.g. "reviewed catalog target is not active during activation" | `""` | 4 other definer function(s) | Reached only through a gated function. Touches ps_approved_labels, ps_match_checks, pss. |
| `assert_product_submission_evidence/3` | owner only | No API role can call it | Typed; 2 refusal(s), e.g. "ready evidence required" | `""` | 10 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, pss. |
| `assert_product_submission_reviewer/0` | owner only | No API role can call it | Typed; 1 refusal(s), e.g. "reviewer access required" | `""` | 13 other definer function(s) | Reached only through a gated function. Touches ps_reviewers. |
| `award_product_contribution_points_internal/1` | owner only | No API role can call it | Typed arguments | `""` | 1 other definer function(s) | Reached only through a gated function. Touches product_contribution_ledger, pss. |
| `create_product_submission_reviewer_image_internal/5` | owner only | No API role can call it | Typed; 6 refusal(s), e.g. "reviewer access required" | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_photos, ps_reviewer_images, ps_reviewers, pss. |
| `create_product_submission_v2_internal/7` | owner only | No API role can call it | Typed; 14 refusal(s), e.g. "authentication required" | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, ps_mismatch_details, ps_missing_details, pss. |
| `finalize_product_submission_reviewer_image_internal/5` | owner only | No API role can call it | Typed; 3 refusal(s), e.g. "reviewer image manifest required" | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_reviewer_images, storage.objects. |
| `get_approved_product_submission_image/1` | owner only | No API role can call it | Typed arguments | `""` | pipeline `product_submission_import.py` | Older overload kept owner-only. Reached only through a gated function. Touches ps_approved_labels, pss. |
| `get_approved_product_submission_image_internal/1` | owner only | No API role can call it | Typed arguments | `""` | none found | Reached only through a gated function. Touches ps_approved_labels, ps_photos, ps_reviewer_images, pss. |
| `insert_product_submission_photos_internal/4` | owner only | No API role can call it | Typed; 11 refusal(s), e.g. "invalid photo manifest" | `""` | 3 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, ps_photos. |
| `mark_product_submission_promoted/3` | owner only | No API role can call it | Typed arguments | `""` | pipeline `product_submission_import.py`, 1 other definer function(s) | Older overload kept owner-only. Reached only through a gated function. Touches ps_approved_labels, pss. |
| `mark_product_submission_promoted_internal/3` | owner only | No API role can call it | Typed; 3 refusal(s), e.g. "catalog version required" | `""` | none found | Reached only through a gated function. Touches pss. |
| `product_submission_approval_catalog_ids/2` | owner only | No API role can call it | Typed arguments | `""` | 2 other definer function(s) | Reached only through a gated function. Touches pss. |
| `product_submission_catalog_target_is_live/1` | owner only | No API role can call it | Typed arguments | `""` | 5 other definer function(s) | Reached only through a gated function. Touches catalog_search, export_manifest. |
| `product_submission_evidence_manifest/2` | owner only | No API role can call it | Typed arguments | `""` | 4 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, ps_photos. |
| `product_submission_evidence_object_paths/2` | owner only | No API role can call it | Typed arguments | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, ps_photos. |
| `product_submission_evidence_records/2` | owner only | No API role can call it | Typed arguments | `""` | 6 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions. |
| `product_submission_evidence_records_without_identifier/2` | owner only | No API role can call it | Typed arguments | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_evidence_revisions, ps_photos. |
| `product_submission_extraction_allowance/0` | owner only | No API role can call it | Typed arguments | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ps_extraction_budget, ps_extraction_settings. |
| `product_submission_extraction_job_key/3` | owner only | No API role can call it | Typed arguments | `""` | none found | Reached only through a gated function. Touches ps_evidence_revisions. |
| `product_submission_extraction_worker_id/0` | owner only | No API role can call it | Typed; 1 refusal(s), e.g. "extraction worker access required" | `""` | 6 other definer function(s) | Reached only through a gated function. Touches ps_extraction_workers. |
| `product_submission_identity_check/1` | owner only | No API role can call it | Typed; 1 refusal(s), e.g. "submission not found" | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ps_identity_conflicts, ps_match_checks, ps_reviewer_drafts, pss. |
| `product_submission_identity_conflicts/2` | owner only | No API role can call it | Typed arguments | `""` | 6 other definer function(s) | Reached only through a gated function. Touches catalog_search, export_manifest, ps_approved_labels, ps_reviewer_drafts. |
| `product_submission_label_duplicate_is_verified/3` | owner only | No API role can call it | Typed arguments | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_approved_labels, ps_identity_conflicts, ps_match_checks, ps_reviewer_drafts. |
| `product_submission_review_target_key/1` | owner only | No API role can call it | Typed arguments | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ps_mismatch_details, ps_reviewer_drafts, pss. |
| `product_submission_reviewer_state_internal/2` | owner only | No API role can call it | Typed; 1 refusal(s), e.g. "submission not found" | `""` | 4 other definer function(s) | Reached only through a gated function. Touches ps_barcode_corrections, ps_evidence_revisions, ps_field_verifications, ps_reviewer_drafts. |
| `record_product_submission_extraction_internal/13` | owner only | No API role can call it | Typed; 11 refusal(s), e.g. "extraction actor required" | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ps_extractions, pss. |
| `record_product_submission_match_check_internal/7` | owner only | No API role can call it | Typed; 12 refusal(s), e.g. "reviewer access required" | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_match_checks, ps_reviewers, pss. |
| `review_product_submission_human_internal/12` | owner only | No API role can call it | Typed; 27 refusal(s), e.g. "reviewer identity required" | `""` | 2 other definer function(s) | Reached only through a gated function. Touches ps_approved_labels, ps_evidence_revisions, ps_identity_conflicts, ps_match_checks. |
| `review_product_submission_unchecked/15` | owner only | No API role can call it | Typed; 11 refusal(s), e.g. "reviewer access required" | `""` | 1 other definer function(s) | Older overload. Any short positional call to it is ambiguous with the 17-argument one. Dead-code candidate, no leak. |
| `review_product_submission_unchecked/17` | owner only | No API role can call it | Typed; 13 refusal(s), e.g. "reviewer access required" | `""` | 1 other definer function(s) | Reached only through a gated function. Touches ps_approved_labels, ps_evidence_revisions, ps_photos, ps_reviewer_images. |
| `rotate_manifest/8` | owner only | No API role can call it | Typed; 2 refusal(s), e.g. "rotate_manifest is restricted to service_role" | `public, pg_catalog` | none found | Unreachable in practice: owner-only, with a service-role guard inside. Only a comment in the pipeline mentions it. |

## Trigger functions (16)

| Function | Who can execute | Caller gate | Input checks | `search_path` | Reached from | What could leak or change |
|---|---|---|---|---|---|---|
| `advance_product_submission_approval_revision/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `ai_share_snapshot_live_connection/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `default_product_submission_photo_uploader/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `enforce_approved_submission_identity_evidence/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `enforce_product_submission_detail_kind/0` | service role | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `enforce_product_submission_photo_pending/0` | service role | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `fence_product_submission_catalog_identity/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `inherit_product_submission_revision_identifier/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `preserve_product_submission_catalog_metadata/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `prevent_product_submission_object_reuse/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `project_submission_history_name/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `protect_product_submission_approval_revision/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `protect_product_submission_approved_parent/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `record_extraction_attempt_receipt/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `revalidate_product_submission_catalog_identity/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |
| `stamp_product_submission_approval_revision/0` | owner only | None needed: Postgres refuses a direct call | No caller input | `""` | table trigger | Nothing directly. It acts only on the row being written. |

## Live-only and provider-owned (7)

| Function | Who can execute | Caller gate | Input checks | `search_path` | Reached from | What could leak or change |
|---|---|---|---|---|---|---|
| `public.rls_auto_enable/0` (live only) | service role (`anon` and signed-in: false, live) | Event trigger: cannot be called directly | No caller input | `pg_catalog` | Supabase dashboard event trigger; not in the repo stream | Nothing. It turns RLS on for new tables. |
| `pgbouncer.get_auth/1` | owner only | Provider owned | Provider owned | `""` | Supabase connection pooler | Password hashes if ever exposed. Not callable by any API role, and the schema is not exposed. |
| `storage.protect_active_lifecycle_states/0` | owner only | Provider owned | No caller input | `pg_catalog` | Supabase Storage | Nothing reachable. |
| `storage.reconcile_lifecycle_state/2` | service role | Provider owned | Provider owned | `pg_catalog` | Supabase Storage | Storage bookkeeping. Service role only. |
| `storage.wake_lifecycle_state/0` | owner only | Provider owned | No caller input | `pg_catalog` | Supabase Storage | Nothing reachable. |
| `vault.create_secret/4` | service role | Provider owned | Provider owned | `""` | Supabase Vault; no repo caller today | Writes a secret. Service role only. |
| `vault.update_secret/5` | service role | Provider owned | Provider owned | `""` | Supabase Vault; no repo caller today | Overwrites a secret. Service role only. |

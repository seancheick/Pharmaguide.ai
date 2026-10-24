#!/usr/bin/env bash
# Applies every tracked migration, in order, to a disposable local Docker
# Postgres and runs the AI connector SQL suite (S1 restrictive RLS and RPC
# guards, S2 token hook, S5 cascades, S7/S10 schema). No URL, linked project,
# credentials, or remote database is accepted. Pattern: test_submission_identity.sh.
set -euo pipefail
if [[ $# -ne 0 ]]; then
  echo 'Usage: test_ai_connector_rls.sh' >&2
  exit 2
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
if ! command -v "$docker_bin" >/dev/null 2>&1; then
  docker_bin=/Applications/Docker.app/Contents/Resources/bin/docker
  # Docker Desktop resolves its credential helper through PATH.
  export PATH="$(dirname "$docker_bin"):$PATH"
fi
test_container="pharmaguide-ai-connector-test-$$-$RANDOM"
cleanup() { "$docker_bin" rm --force "$test_container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$docker_bin" run --detach --name "$test_container" \
  -p 127.0.0.1::5432 \
  -e POSTGRES_PASSWORD=disposable-fixture-only \
  docker.io/supabase/postgres:17.6.1.132@sha256:e09e93a61ed1560caf4be79c9eb29401875bea74b12aec4657cb08bf34ea3a13 >/dev/null
ready=false
for attempt in {1..80}; do
  if "$docker_bin" exec "$test_container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.25
done
if [[ "$ready" != true ]]; then
  echo 'Disposable Postgres did not become ready.' >&2
  exit 1
fi
psql_test() { "$docker_bin" exec -i "$test_container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"; }
# The image finishes its init scripts after first accepting connections.
for attempt in {1..40}; do
  if psql_test -q -c 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 0.25
done
psql_test -q < "$repo_dir/supabase/tests/ai_connector/bootstrap.sql"
for migration in "$repo_dir"/supabase/migrations/*.sql; do
  psql_test -q < "$migration" >/dev/null
done
psql_test -q < "$repo_dir/supabase/tests/ai_connector/restrictive_rls.sql"
psql_test -q < "$repo_dir/supabase/tests/ai_connector/snapshots_pre_request.sql"
psql_test -q < "$repo_dir/supabase/tests/ai_connector/phone_pairing.sql"
# Hold the completion transaction open after it consumes the challenge. A
# second independent connection must wait and then see the committed consume.
psql_test -q <<'SQL' &
SET application_name='aic-pair-complete-race';
BEGIN;
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'race','pair-client','https://chatgpt.com/callback') ? 'connection_id','first concurrent completion');
SELECT pg_sleep(2);
COMMIT;
SQL
pair_race_pid=$!
pair_race_ready=false
for attempt in {1..40}; do
  if [[ "$(psql_test -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='aic-pair-complete-race' AND wait_event='PgSleep'")" == 1 ]]; then
    pair_race_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$pair_race_ready" != true ]]; then
  wait "$pair_race_pid"
  echo 'Pairing concurrency fixture failed to overlap.' >&2
  exit 1
fi
psql_test -q <<'SQL'
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'race','pair-client','https://chatgpt.com/callback') ? 'error','concurrent replay blocked');
SELECT aic.assert((SELECT count(*)=1 FROM public.ai_connections WHERE client_id='pair-client' AND status='active'),'one active connection after concurrent completion');
SQL
wait "$pair_race_pid"
# A disconnect holds the identical lock while a delayed completion arrives.
psql_test -q <<'SQL'
SELECT aic.assert(aic.pair_start('disconnect-race','KLMNPQRSTUVW') ? 'expires_at','disconnect race fixture');
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.approve_ai_connection_pairing('KLMNPQRSTUVW')->>'approved'='true','disconnect race phone approval');
COMMIT;
SQL
psql_test -q <<'SQL' &
SET application_name='aic-pair-disconnect-race';
BEGIN;
SELECT public.revoke_ai_connection_pairings(aic.user_id(1),'pair-client');
SELECT pg_sleep(2);
COMMIT;
SQL
pair_race_pid=$!
pair_race_ready=false
for attempt in {1..40}; do
  if [[ "$(psql_test -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='aic-pair-disconnect-race' AND wait_event='PgSleep'")" == 1 ]]; then
    pair_race_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$pair_race_ready" != true ]]; then
  wait "$pair_race_pid"
  echo 'Pairing disconnect fixture failed to overlap.' >&2
  exit 1
fi
psql_test -q <<'SQL'
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'disconnect-race','pair-client','https://chatgpt.com/callback') ? 'error','delayed complete cannot revive disconnected approval');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='pair-client' AND status='active'),'disconnect race leaves no active connection');
SQL
wait "$pair_race_pid"
# UserInfo can finish after Disconnect. Its captured generation must not
# register a new pending row after provider revocation clears the barrier.
workos_generation="$(psql_test -Atq -c "SELECT public.read_ai_connection_generation(aic.user_id(1))")"
psql_test -q <<'SQL' &
SET application_name='aic-workos-disconnect-race';
BEGIN;
SELECT aic.assert(public.begin_ai_connection_revocation(aic.user_id(1),'workos-race') ? 'generation','WorkOS disconnect starts');
SELECT pg_sleep(2);
COMMIT;
SQL
pair_race_pid=$!
pair_race_ready=false
for attempt in {1..40}; do
  if [[ "$(psql_test -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='aic-workos-disconnect-race' AND wait_event='PgSleep'")" == 1 ]]; then
    pair_race_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$pair_race_ready" != true ]]; then
  wait "$pair_race_pid"
  echo 'WorkOS disconnect fixture failed to overlap.' >&2
  exit 1
fi
psql_test -q -v old_generation="$workos_generation" <<'SQL'
SELECT aic.assert(aic.work_register('delayed-userinfo','workos-race',1,'https://fixture.authkit.app',:old_generation) ? 'error','in-flight UserInfo denied after concurrent disconnect');
SELECT aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'workos-race',public.read_ai_connection_generation(aic.user_id(1)))->>'finished'='true','provider completion clears barrier');
SELECT aic.assert(aic.work_register('delayed-userinfo','workos-race',1,'https://fixture.authkit.app',:old_generation) ? 'error','stale generation denied even after provider finished');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connection_pairings WHERE consent_id='delayed-userinfo'),'no stale registration persisted');
SQL
wait "$pair_race_pid"
# Cancellation owns the same lock as completion; an already-approved phone
# challenge must not create authority after Deny persists the provider barrier.
psql_test -q <<'SQL'
SELECT aic.work_register('deny-race-sid','deny-race-client')->>'authorization_id' AS deny_auth \gset
SELECT aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),:'deny_auth','deny-race-client','Verified WorkOS Codex','https://chatgpt.com/callback',encode(extensions.digest('QRSTUVWXYZA2','sha256'),'hex')) ? 'expires_at','Deny race setup');
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.approve_ai_connection_pairing('QRSTUVWXYZA2')->>'approved'='true','Deny race phone approval');
COMMIT;
SQL
psql_test -q <<'SQL' &
SET application_name='aic-workos-deny-race';
BEGIN;
SELECT aic.assert(public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),(SELECT authorization_id FROM public.ai_connection_pairings WHERE consent_id='deny-race-sid')) ? 'revocation_generation','Deny starts barrier atomically');
SELECT pg_sleep(2);
COMMIT;
SQL
pair_race_pid=$!
pair_race_ready=false
for attempt in {1..40}; do
  if [[ "$(psql_test -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='aic-workos-deny-race' AND wait_event='PgSleep'")" == 1 ]]; then
    pair_race_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$pair_race_ready" != true ]]; then
  wait "$pair_race_pid"
  echo 'WorkOS Deny fixture failed to overlap.' >&2
  exit 1
fi
psql_test -q <<'SQL'
DO $$ DECLARE cid uuid; BEGIN
 SELECT connection_id INTO cid FROM public.ai_connections WHERE client_id='deny-race-client';
 PERFORM aic.assert(cid IS NOT NULL,'phone already created connection before concurrent denial');
 BEGIN
  INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
  VALUES(cid,aic.user_id(1),'pharmaguide-brief-markdown/v1','{}','\x00','\x00',1,now()+interval '1 hour');
  RAISE EXCEPTION 'FAIL: concurrent upload defeated revocation purge';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid),'concurrent late upload stays purged');
END $$;
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),(SELECT authorization_id FROM public.ai_connection_pairings WHERE consent_id='deny-race-sid'),'deny-race-client','https://chatgpt.com/callback') ? 'error','concurrent completion cannot defeat Deny');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='deny-race-client' AND status='active'),'Deny race leaves no active authority');
SELECT public.finish_ai_connection_revocation(aic.user_id(1),'deny-race-client',public.read_ai_connection_generation(aic.user_id(1)));
SQL
wait "$pair_race_pid"
# The actual upload uses ON CONFLICT UPDATE. Exercise its existing-row branch
# first, then let Disconnect wait for that write and purge the committed result.
psql_test -q <<'SQL'
INSERT INTO public.ai_connections(user_id,client_id,expires_at)
VALUES(aic.user_id(1),'snapshot-upsert-race',now()+interval '1 day');
INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
SELECT connection_id,user_id,'pharmaguide-brief-markdown/v1','{}','\x00','\x00',1,now()+interval '1 hour'
FROM public.ai_connections WHERE client_id='snapshot-upsert-race';
SQL
psql_test -q <<'SQL' &
SET application_name='aic-snapshot-upsert-race';
BEGIN;
INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
SELECT connection_id,user_id,'pharmaguide-brief-markdown/v1','{}','\x02','\x00',1,now()+interval '1 hour'
FROM public.ai_connections WHERE client_id='snapshot-upsert-race'
ON CONFLICT(connection_id) DO UPDATE SET ciphertext=excluded.ciphertext;
SELECT aic.assert((SELECT encode(s.ciphertext,'hex')='02' FROM public.ai_share_snapshots s JOIN public.ai_connections c USING(connection_id) WHERE c.client_id='snapshot-upsert-race'),'existing snapshot conflict update exercised');
SELECT pg_sleep(2);
COMMIT;
SQL
pair_race_pid=$!
pair_race_ready=false
for attempt in {1..40}; do
  if [[ "$(psql_test -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='aic-snapshot-upsert-race' AND wait_event='PgSleep'")" == 1 ]]; then
    pair_race_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$pair_race_ready" != true ]]; then
  wait "$pair_race_pid"
  echo 'Snapshot upsert fixture failed to overlap.' >&2
  exit 1
fi
psql_test -q <<'SQL'
SELECT public.revoke_ai_connection_pairings(aic.user_id(1),'snapshot-upsert-race');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_share_snapshots s JOIN public.ai_connections c USING(connection_id) WHERE c.client_id='snapshot-upsert-race'),'disconnect purges overlapping conflict update');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='snapshot-upsert-race' AND status='active'),'upsert cannot preserve revoked authority');
SQL
wait "$pair_race_pid"
echo 'AI connector SQL tests passed.'

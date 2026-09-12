#!/usr/bin/env bash
# Executes the actual submission migration chain in a disposable local Docker
# Postgres. No URL, linked project, credentials, or remote database is accepted.
set -euo pipefail
case "${1:-}" in
  ''|--advisors|--no-concurrency) ;;
  *) echo 'Usage: test_submission_identity.sh [--advisors|--no-concurrency]. The obsolete --baseline mode is retired; tests target the complete migration chain.' >&2; exit 2 ;;
esac
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
if ! command -v "$docker_bin" >/dev/null 2>&1; then
  docker_bin=/Applications/Docker.app/Contents/Resources/bin/docker
fi
test_container="pharmaguide-identity-test-$$-$RANDOM"
cleanup() { "$docker_bin" rm --force "$test_container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$docker_bin" run --detach --name "$test_container" \
  -p 127.0.0.1::5432 \
  -e POSTGRES_PASSWORD=disposable-fixture-only \
  public.ecr.aws/supabase/postgres:17.6.1.132 >/dev/null
for attempt in {1..40}; do
  if "$docker_bin" exec "$test_container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  sleep 0.25
done
psql_test() { "$docker_bin" exec -i "$test_container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_test -q < "$repo_dir/supabase/tests/submission_identity/bootstrap.sql"
# One owner for the chain, shared with the live-stack provisioner.
source "$repo_dir/supabase/tests/submission_identity/chain.sh"
while IFS= read -r chain_file; do
  if [[ "$(basename "$chain_file")" == "20260911120000_product_contribution_ledger.sql" ]]; then
    # Exercise the real migration with historical rows, then roll everything
    # back so the normal suite retains its clean, post-migration fixtures.
    {
      printf '%s\n' 'BEGIN;'
      cat "$repo_dir/supabase/tests/submission_identity/helpers.sql"
      cat "$repo_dir/supabase/tests/submission_identity/ledger_backfill.sql"
      cat "$chain_file"
      printf '%s\n' 'SELECT fixture.check_ledger_backfill();' 'ROLLBACK;'
    } | psql_test -q
  fi
  psql_test -q < "$chain_file"
done < <(submission_migration_chain "$repo_dir")
psql_test -q < "$repo_dir/supabase/tests/submission_identity/helpers.sql"
psql_test -q < "$repo_dir/supabase/tests/submission_identity/identity.sql" >/dev/null
if [[ -f "$repo_dir/supabase/tests/submission_identity/intake.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/intake.sql" >/dev/null
fi
if [[ -f "$repo_dir/supabase/tests/submission_identity/foundations.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/foundations.sql" >/dev/null
fi
if [[ -f "$repo_dir/supabase/tests/submission_identity/extraction_queue.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/extraction_queue.sql" >/dev/null
fi
if [[ -f "$repo_dir/supabase/tests/submission_identity/workstation.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/workstation.sql" >/dev/null
fi
if [[ -f "$repo_dir/supabase/tests/submission_identity/ledger.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/ledger.sql" >/dev/null
fi
if [[ -f "$repo_dir/supabase/tests/submission_identity/retake.sql" ]]; then
  psql_test -q < "$repo_dir/supabase/tests/submission_identity/retake.sql" >/dev/null
fi
psql_test -q < "$repo_dir/supabase/tests/submission_identity/display_names.sql" >/dev/null
psql_test -q < "$repo_dir/supabase/tests/submission_identity/review_pictures.sql" >/dev/null
psql_test -q < "$repo_dir/supabase/tests/submission_identity/read_extractions.sql" >/dev/null
if [[ "${1:-}" != "--no-concurrency" ]]; then
  source "$repo_dir/supabase/tests/submission_identity/concurrency.sh"
fi
psql_test -c 'SELECT name, coalesce(error, '\''PASS'\'') AS result FROM fixture.results ORDER BY name'
psql_test -q -c "SELECT fixture.assert(NOT EXISTS (SELECT 1 FROM fixture.results WHERE error IS NOT NULL), 'submission identity tests failed')"
if [[ "${1:-}" == "--advisors" ]]; then
  # The CLI requires TLS even for an explicit local URL. These throwaway
  # credentials/certificates exist only inside this container.
  test_tls_dir="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$test_tls_dir/server.key" -out "$test_tls_dir/server.crt" -subj /CN=localhost -days 1 >/dev/null 2>&1
  "$docker_bin" cp "$test_tls_dir/server.key" "$test_container:/tmp/fixture-server.key"
  "$docker_bin" cp "$test_tls_dir/server.crt" "$test_container:/tmp/fixture-server.crt"
  "$docker_bin" exec -u root "$test_container" chown postgres:postgres /tmp/fixture-server.key /tmp/fixture-server.crt
  "$docker_bin" exec -u root "$test_container" chmod 600 /tmp/fixture-server.key
  rm "$test_tls_dir/server.key" "$test_tls_dir/server.crt"
  rmdir "$test_tls_dir"
  psql_test -q -c "ALTER SYSTEM SET ssl_cert_file = '/tmp/fixture-server.crt'"
  psql_test -q -c "ALTER SYSTEM SET ssl_key_file = '/tmp/fixture-server.key'"
  psql_test -q -c "ALTER SYSTEM SET ssl = on"
  psql_test -q -c 'SELECT pg_reload_conf()'
  fixture_port="$("$docker_bin" port "$test_container" 5432/tcp)"
  supabase db advisors --db-url "postgresql://postgres:disposable-fixture-only@${fixture_port}/postgres?sslmode=require" \
    --type security --level error --fail-on error
fi
echo 'Submission identity SQL tests passed.'

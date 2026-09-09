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
for migration in \
  20260731144153 20260731144527 20260824172752 20260825172103 \
  20260825173314 20260825181500 20260825213000 20260826001957 \
  20260826100000 20260829151221 20260903064532 20260903064547 20260903065755; do
  for file in "$repo_dir"/supabase/migrations/"$migration"_*.sql; do
    psql_test -q < "$file"
  done
done
psql_test -q < "$repo_dir/supabase/migrations/20260908230736_harden_submission_identity_and_intake.sql"
psql_test -q < "$repo_dir/supabase/tests/submission_identity/legacy_foundations.sql"
psql_test -q < "$repo_dir/supabase/migrations/20260909013000_submission_foundations_consent_revisions_extraction.sql"
psql_test -q < "$repo_dir/supabase/migrations/20260909120000_submission_extraction_queue.sql"
psql_test -q < "$repo_dir/supabase/migrations/20260909180000_submission_extraction_worker_evidence.sql"
psql_test -q < "$repo_dir/supabase/migrations/20260909190858_harden_extraction_attempt_receipts.sql"
psql_test -q < "$repo_dir/supabase/migrations/20260909210000_submission_reviewer_workstation.sql"
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

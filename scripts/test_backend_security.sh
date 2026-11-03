#!/usr/bin/env bash
# Negative access tests for the shared Supabase schema (hardening item A6).
# Replays the assembled deployment stream into a disposable local Docker
# Postgres with production's object owner, runs every check, then removes each
# protection in turn and requires its check to fail. No URL, linked project,
# credentials, or remote database is accepted.
set -euo pipefail
if [[ $# -ne 0 || -z "${PG_MIGRATION_DEPLOYMENT_DIR:-}" ]]; then
  echo 'Usage: PG_MIGRATION_DEPLOYMENT_DIR=<assembled directory> test_backend_security.sh' >&2
  exit 2
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
if ! command -v "$docker_bin" >/dev/null 2>&1; then
  docker_bin=/Applications/Docker.app/Contents/Resources/bin/docker
  export PATH="$(dirname "$docker_bin"):$PATH"
fi
test_container="pharmaguide-backend-security-test-$$-$RANDOM"
cleanup() { "$docker_bin" rm --force "$test_container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$docker_bin" run --detach --name "$test_container" \
  -p 127.0.0.1::5432 \
  -e POSTGRES_PASSWORD=disposable-fixture-only \
  docker.io/supabase/postgres:17.6.1.132@sha256:e09e93a61ed1560caf4be79c9eb29401875bea74b12aec4657cb08bf34ea3a13 >/dev/null
psql_owner() { "$docker_bin" exec -i "$test_container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_admin() { "$docker_bin" exec -i "$test_container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"; }
ready=false
for attempt in {1..240}; do
  # The image accepts connections, then restarts when init ends.
  if "$docker_bin" logs "$test_container" 2>&1 | grep 'init process complete' >/dev/null \
    && psql_admin -q -c 'SELECT 1' >/dev/null 2>&1 \
    && psql_owner -q -c 'SELECT 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.5
done
if [[ "$ready" != true ]]; then
  echo 'Disposable Postgres did not become ready.' >&2
  exit 1
fi
python3 "$repo_dir/scripts/assemble_supabase_migrations.py" --verify "$PG_MIGRATION_DEPLOYMENT_DIR"
psql_admin -q -v pipeline_fixture=false < "$repo_dir/supabase/tests/ai_connector/bootstrap.sql"
psql_admin -q -c 'GRANT USAGE, CREATE ON SCHEMA storage TO postgres; ALTER TABLE storage.objects OWNER TO postgres; ALTER TABLE storage.buckets OWNER TO postgres; GRANT SELECT, UPDATE ON auth.sessions TO postgres; GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO anon, authenticated;'
for prerequisite in "$PG_MIGRATION_DEPLOYMENT_DIR"/replay_prerequisites/*.sql; do
  psql_owner -q < "$prerequisite" >/dev/null
done
for migration in "$PG_MIGRATION_DEPLOYMENT_DIR"/supabase/migrations/*.sql; do
  psql_owner -q < "$migration" >/dev/null
done
suite="$repo_dir/supabase/tests/backend_security"
psql_admin -q < "$suite/harness.sql"
psql_admin -q < "$suite/definer_exposure_pin.sql"
psql_admin -q < "$suite/checks.sql"
psql_admin -q < "$suite/mutations.sql"
psql_admin -At -c 'SELECT sec.run_checks()' >/dev/null
psql_admin -c 'SELECT name, result FROM sec.check_results ORDER BY name'
psql_admin -q -c 'SELECT sec.run_mutations()' >/dev/null
psql_admin -c 'SELECT name, check_name, result FROM sec.mutation_results ORDER BY check_name, name'
psql_admin -q -c 'SELECT sec.require_all_passed()'
audit_page="$repo_dir/docs/security/SECURITY_DEFINER_AUDIT.md"
for key in $(psql_admin -At -c 'SELECT key FROM sec.definer_exposure'); do
  grep -qF "\`$key\`" "$audit_page" || { echo "No audit row for $key" >&2; exit 1; }
done
echo 'Backend security SQL tests passed.'

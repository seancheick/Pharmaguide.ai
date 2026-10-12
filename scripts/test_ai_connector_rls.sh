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
fi
test_container="pharmaguide-ai-connector-test-$$-$RANDOM"
cleanup() { "$docker_bin" rm --force "$test_container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$docker_bin" run --detach --name "$test_container" \
  -p 127.0.0.1::5432 \
  -e POSTGRES_PASSWORD=disposable-fixture-only \
  public.ecr.aws/supabase/postgres:17.6.1.132 >/dev/null
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
echo 'AI connector SQL tests passed.'

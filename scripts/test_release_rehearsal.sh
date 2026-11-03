#!/usr/bin/env bash
# Runs the real publisher and the signed-release migration against a replay of
# production's schema, through a real PostgREST. Only object storage is faked,
# and every URL is loopback. Run it before applying the migration. Not in CI: it
# takes real process kills and a Postgres restart.
#
# Usage: test_release_rehearsal.sh <pipeline repo> [PostgREST tag]
# The pipeline repo must have the signed publisher and the commit named below.
# Its Python environment must have the pipeline's dependencies.
set -uo pipefail
if [[ $# -lt 1 ]]; then
  echo 'Usage: test_release_rehearsal.sh <pipeline repo> [PostgREST tag]' >&2
  exit 2
fi
export PIPELINE_REPO="$(cd "$1" && pwd)"
postgrest_tag="${2:-v14.5}" # What production runs.
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
here="$repo/supabase/tests/release_rehearsal"
migration="$repo/supabase/migrations/20261103130000_signed_release_manifest.sql"
# The last pipeline commit before its schema file declared the signed columns,
# as production has not been given them.
pipeline_before_signing=c8e3ced2ad49b65592c53179adad63128266d052
before_migration=20261103120000
pg=pg-a2-rehearsal
rest=pgrst-a2-rehearsal

base="$(mktemp -d)"
cleanup() { docker rm --force "$pg" "$rest" >/dev/null 2>&1; rm -rf "$base"; }
trap cleanup EXIT
python3 "$repo/scripts/assemble_supabase_migrations.py" --app-ref HEAD \
  --pipeline-repo "$PIPELINE_REPO" --pipeline-ref "$pipeline_before_signing" \
  --through "$before_migration" --output "$base/stream" >/dev/null || exit 9

docker rm --force "$pg" >/dev/null 2>&1
docker run --detach --name "$pg" -p 127.0.0.1:55433:5432 \
  -e POSTGRES_PASSWORD=disposable-fixture-only \
  docker.io/supabase/postgres:17.6.1.132@sha256:e09e93a61ed1560caf4be79c9eb29401875bea74b12aec4657cb08bf34ea3a13 >/dev/null || exit 9
for _ in {1..240}; do
  if docker logs "$pg" 2>&1 | grep 'init process complete' >/dev/null \
    && docker exec "$pg" psql -X -U postgres -d postgres -qc 'SELECT 1' >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
admin() { docker exec -i "$pg" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
owner() { docker exec -i "$pg" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
admin -v pipeline_fixture=false < "$repo/supabase/tests/ai_connector/bootstrap.sql" >/dev/null || exit 9
admin -c 'GRANT USAGE, CREATE ON SCHEMA storage TO postgres; ALTER TABLE storage.objects OWNER TO postgres; ALTER TABLE storage.buckets OWNER TO postgres; GRANT SELECT, UPDATE ON auth.sessions TO postgres;' || exit 9
for f in "$base"/stream/replay_prerequisites/*.sql "$base"/stream/supabase/migrations/*.sql; do
  owner < "$f" >/dev/null || { echo "Replay failed at $f" >&2; exit 9; }
done
admin < "$here/seed.sql" || exit 8

docker rm --force "$rest" >/dev/null 2>&1
docker run -d --name "$rest" -p 127.0.0.1:55434:3000 \
  -e PGRST_DB_URI='postgres://authenticator:disposable-fixture-only@host.docker.internal:55433/postgres' \
  -e PGRST_DB_SCHEMAS=public -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET=disposable-fixture-only-secret-0123456789abcdef \
  -e PGRST_DB_PRE_REQUEST=public.pgrst_reject_ai_assistant_tokens \
  -e PGRST_OPENAPI_MODE=follow-privileges "postgrest/postgrest:$postgrest_tag" >/dev/null || exit 9

cd "$PIPELINE_REPO" || exit 9
PYTHONPATH="$PIPELINE_REPO/scripts:$PIPELINE_REPO/scripts/tests" python3 "$here/rehearse.py" "$migration"

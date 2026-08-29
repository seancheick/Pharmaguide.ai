#!/usr/bin/env bash
set -euo pipefail

# Narrow rollout for the pipeline-consumed storage-inventory RPCs.
#
# This Supabase project intentionally has more than one migration owner, so a
# blanket `db push` refuses on older remote-only pipeline migrations. This
# script applies exactly one reviewed, idempotent SQL file through the linked
# CLI and records exactly its filename version through Supabase's supported
# migration-repair command. It never edits the migration table directly.

readonly VERSION="20260830090000"
readonly EXPECTED_SHA256="df3eedb4d840a95df90873dd91185bce3239e83a97b802adb2da8a42b5534062"
readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MIGRATION="${REPO_DIR}/supabase/migrations/20260830090000_storage_inventory_rpc.sql"

usage() {
  echo "Usage: $0 --check | --execute" >&2
}

file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

require_reviewed_file() {
  if [[ ! -f "$MIGRATION" ]]; then
    echo "[refused] Missing reviewed migration: $MIGRATION" >&2
    exit 2
  fi
  local actual_sha
  actual_sha="$(file_sha256 "$MIGRATION")"
  if [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
    echo "[refused] Migration SHA-256 drift: expected $EXPECTED_SHA256, got $actual_sha" >&2
    exit 2
  fi
}

remote_version_is_applied() {
  supabase migration list --linked 2>/dev/null \
    | grep -Eq "^[[:space:]]*${VERSION}[[:space:]]*\\|[[:space:]]*${VERSION}[[:space:]]*\\|"
}

verify_live_contract() {
  local verification_sql
  verification_sql="$(cat <<'SQL'
do $verify$
declare
  signature text;
begin
  foreach signature in array array[
    'public.pg_storage_inventory_prefix_ok(text)',
    'public.pg_storage_inventory_summary(text)',
    'public.pg_storage_inventory_page(text,text,integer)'
  ] loop
    if to_regprocedure(signature) is null
       or has_function_privilege('anon', signature, 'EXECUTE')
       or has_function_privilege('authenticated', signature, 'EXECUTE')
       or not has_function_privilege('service_role', signature, 'EXECUTE') then
      raise exception
        'storage inventory RPC live-contract verification failed for %',
        signature;
    end if;
  end loop;

  if not public.pg_storage_inventory_prefix_ok('shared/details/sha256')
     or public.pg_storage_inventory_prefix_ok('shared/private') then
    raise exception
      'storage inventory RPC live-contract verification failed for prefix policy';
  end if;

  perform *
  from public.pg_storage_inventory_summary('shared/details/sha256');

  begin
    perform * from public.pg_storage_inventory_summary('shared/private');
    raise exception
      'storage inventory RPC live-contract verification failed: invalid prefix accepted';
  exception
    when sqlstate '22023' then null;
  end;
end
$verify$;
SQL
)"
  supabase db query --linked "$verification_sql"
}

main() {
  if [[ $# -ne 1 ]] || [[ "$1" != "--check" && "$1" != "--execute" ]]; then
    usage
    exit 2
  fi

  cd "$REPO_DIR"
  require_reviewed_file

  if [[ "$1" == "--check" ]]; then
    echo "Reviewed migration SHA-256: $EXPECTED_SHA256"
    supabase migration list --linked
    return 0
  fi

  if remote_version_is_applied; then
    echo "Migration $VERSION is already recorded; verifying the live contract."
    verify_live_contract
    return 0
  fi

  supabase db query --linked --file "$MIGRATION"
  supabase migration repair --status applied 20260830090000 --linked

  if ! remote_version_is_applied; then
    echo "[ERROR] Migration SQL ran, but version $VERSION is not aligned in remote history." >&2
    exit 1
  fi
  verify_live_contract
  supabase migration list --linked
}

main "$@"

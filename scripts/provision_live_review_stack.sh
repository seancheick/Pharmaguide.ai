#!/usr/bin/env bash
# Brings up a disposable local Supabase stack for the reviewer HTTP tests.
#
# Nothing here touches a linked project, a remote database, or production
# credentials: it creates a throwaway project directory, starts the local
# stack, applies the submission migration chain from its single owner, and
# serves the Edge Functions with a reviewer allowlist it just created.
#
# The chain is NOT duplicated here. `supabase db reset` cannot own it while the
# repository still contains duplicate 20260614 prefixes, so both this script
# and the SQL harness read supabase/tests/submission_identity/chain.sh.
#
# Usage:  bash scripts/provision_live_review_stack.sh [port]
# Then:   source /tmp/pg-review-stack.env && PG_RUN_LOCAL_REVIEW_TESTS=1 \
#           bash scripts/test.sh fast -k submission_review_live_stack
# Finally: bash scripts/provision_live_review_stack.sh --stop
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_bin="${DOCKER_BIN:-/Applications/Docker.app/Contents/Resources/bin/docker}"
command -v "$docker_bin" >/dev/null 2>&1 || docker_bin=docker
project="pg-review-live"
state_file="/tmp/pg-review-stack.dir"

if [[ "${1:-}" == "--stop" ]]; then
  if [[ -f "$state_file" ]]; then
    work="$(cat "$state_file")"
    (cd "$work" && PATH="$(dirname "$docker_bin"):$PATH" supabase stop --no-backup >/dev/null 2>&1) || true
    rm -rf "$work" "$state_file" /tmp/pg-review-stack.env /tmp/pg-review-functions.env
  fi
  echo 'Disposable review stack stopped and removed.'
  exit 0
fi

api_port="${1:-55531}"
work="$(mktemp -d /tmp/pg-review-live.XXXXXX)"
echo "$work" > "$state_file"
mkdir -p "$work/supabase"
cp -R "$repo_dir/supabase/functions" "$work/supabase/functions"
cat > "$work/supabase/config.toml" <<TOML
project_id = "$project"
[api]
enabled = true
port = $api_port
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
max_rows = 1000
[db]
port = $((api_port + 1))
major_version = 17
[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
[auth.email]
enable_signup = true
enable_confirmations = false
[storage]
enabled = true
[studio]
enabled = false
[analytics]
enabled = false
[functions.cleanup-product-submissions]
verify_jwt = false
TOML

export PATH="$(dirname "$docker_bin"):$PATH"
(cd "$work" && supabase start -x studio,analytics,vector,imgproxy,inbucket,realtime >/dev/null)
db_container="supabase_db_$project"

# A retired fixture table an early migration still references.
"$docker_bin" exec -i "$db_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -c 'CREATE TABLE IF NOT EXISTS public.pending_products (id uuid);' >/dev/null

source "$repo_dir/supabase/tests/submission_identity/chain.sh"
while IFS= read -r chain_file; do
  "$docker_bin" exec -i "$db_container" psql -U supabase_admin -d postgres -q \
    -v ON_ERROR_STOP=1 < "$chain_file" >/dev/null
done < <(submission_migration_chain "$repo_dir")
# PostgREST caches the schema it started with; the chain landed after that.
"$docker_bin" exec -i "$db_container" psql -U postgres -d postgres \
  -tAc "NOTIFY pgrst, 'reload schema';" >/dev/null

url="http://127.0.0.1:$api_port"
status="$(cd "$work" && supabase status -o env)"
publishable="$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' <<<"$status")"
[[ -n "$publishable" ]] || publishable="$(sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p' <<<"$status")"
secret="$(sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p' <<<"$status")"
[[ -n "$secret" ]] || secret="$(sed -n 's/^SECRET_KEY="\(.*\)"$/\1/p' <<<"$status")"

password="integration-only-$RANDOM"
reviewer_email="reviewer-$RANDOM@example.test"
reviewer_id="$(curl -s -X POST "$url/auth/v1/admin/users" \
  -H "apikey: $secret" -H "Authorization: Bearer $secret" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$reviewer_email\",\"password\":\"$password\",\"email_confirm\":true}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
"$docker_bin" exec -i "$db_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -c "INSERT INTO public.product_submission_reviewers(user_id) VALUES ('$reviewer_id') ON CONFLICT DO NOTHING;" >/dev/null

# The function reads its allowlist from the environment at start, so the
# reviewer has to exist before the runtime does.
printf 'PRODUCT_SUBMISSION_REVIEWER_IDS=%s\n' "$reviewer_id" > /tmp/pg-review-functions.env
(cd "$work" && nohup supabase functions serve --env-file /tmp/pg-review-functions.env \
  > /tmp/pg-review-functions.log 2>&1 &)
for _ in $(seq 1 60); do
  grep -q "Serving functions on" /tmp/pg-review-functions.log 2>/dev/null && break
  sleep 1
done

# Keys stay in a file the caller sources; never in the repository.
cat > /tmp/pg-review-stack.env <<ENV
export PG_RUN_LOCAL_REVIEW_TESTS=1
export PG_REVIEW_URL=$url
export PG_LOCAL_PUBLISHABLE_KEY=$publishable
export PG_LOCAL_SECRET_KEY=$secret
export PG_REVIEW_REVIEWER_EMAIL=$reviewer_email
export PG_REVIEW_REVIEWER_PASSWORD=$password
ENV
echo "Disposable review stack ready at $url"
echo "source /tmp/pg-review-stack.env"

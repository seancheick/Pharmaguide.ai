#!/usr/bin/env bash
# The submission migration chain, in order, owned here and nowhere else.
#
# Two runners need it: the disposable SQL harness and the disposable live-stack
# provisioner. A second copy would drift, and the drift would show up as one
# runner testing a schema the other never loads.
#
# `supabase db reset` cannot own this while the repository still contains
# duplicate 20260614 prefixes, so the chain is selected explicitly rather than
# discovered. Adding a submission migration means adding it here.

# Emits one absolute migration path per line. $1 is the repository root.
submission_migration_chain() {
  local repo_dir="$1" migration file
  for migration in \
    20260731144153 20260731144527 20260824172752 20260825172103 \
    20260825173314 20260825181500 20260825213000 20260826001957 \
    20260826100000 20260829151221 20260903064532 20260903064547 20260903065755; do
    for file in "$repo_dir"/supabase/migrations/"$migration"_*.sql; do
      printf '%s\n' "$file"
    done
  done
  printf '%s\n' "$repo_dir/supabase/migrations/20260908230736_harden_submission_identity_and_intake.sql"
  # The legacy backfill fixture belongs between these two and is not a
  # migration; callers that only want migrations skip a non-existent path.
  printf '%s\n' "$repo_dir/supabase/tests/submission_identity/legacy_foundations.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260909013000_submission_foundations_consent_revisions_extraction.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260909120000_submission_extraction_queue.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260909180000_submission_extraction_worker_evidence.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260909190858_harden_extraction_attempt_receipts.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260909210000_submission_reviewer_workstation.sql"
  printf '%s\n' "$repo_dir/supabase/migrations/20260910010000_submission_batch_readiness.sql"
}

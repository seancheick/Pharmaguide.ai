-- The review function's queue list echoes each approved submission's current
-- approval hash, so reopen and reviewer evidence uploads can bind to what was
-- approved. It reads that hash with the service role, which was never granted
-- this table: every approved row failed and took the whole past-review list
-- with it. Grant only the identity columns; approved payloads stay behind the
-- reviewer RPCs and approvals stay immutable.
GRANT SELECT (submission_id, approval_revision, payload_sha256)
  ON TABLE public.product_submission_approved_labels TO service_role;

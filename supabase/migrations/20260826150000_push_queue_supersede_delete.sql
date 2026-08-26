-- The push drain now discards superseded queue rows (older pending
-- deliveries for a submission that has a newer pending status) instead of
-- replaying stale statuses when a backlog drains. Discarding is a DELETE by
-- the edge function's service role, which the v2 grant (select, update)
-- did not cover. review_events remains the durable transition history;
-- queue rows are operational only.

GRANT DELETE ON TABLE public.product_submission_push_deliveries
  TO service_role;

-- One-time repair: rows delivered by the pre-coalescing drain kept the
-- transport failure that preceded their successful retry. last_error
-- describes the CURRENT state; a delivered row must not keep advertising
-- the 401 that once delayed it.
UPDATE public.product_submission_push_deliveries
  SET last_error = NULL
  WHERE sent_at IS NOT NULL
    AND last_error IS NOT NULL;

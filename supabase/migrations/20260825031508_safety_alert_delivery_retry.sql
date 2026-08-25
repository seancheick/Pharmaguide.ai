-- Failed safety-alert sends must stay retryable and auditable. The previous
-- release_safety_alert_push_delivery DELETEd the pending row, so a transient
-- FCM failure (429/5xx) silently discarded the delivery while the dispatcher
-- still reported success. A released row now keeps delivery_state = 'pending',
-- records attempts + last_error, and back-dates claimed_at past the 10-minute
-- stale window so the next dispatch invocation reclaims it immediately.

ALTER TABLE public.safety_alert_push_deliveries
  ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error text;

DROP FUNCTION IF EXISTS public.release_safety_alert_push_delivery(text, integer, uuid);

CREATE FUNCTION public.release_safety_alert_push_delivery(
  p_alert_id text,
  p_revision integer,
  p_device_push_token_id uuid,
  p_error text
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.safety_alert_push_deliveries
  SET attempts = attempts + 1,
      last_error = left(coalesce(nullif(btrim(p_error), ''), 'send failed'), 500),
      claimed_at = now() - interval '10 minutes'
  WHERE alert_id = p_alert_id
    AND revision = p_revision
    AND device_push_token_id = p_device_push_token_id
    AND delivery_state = 'pending';
$$;

REVOKE ALL ON FUNCTION public.release_safety_alert_push_delivery(text, integer, uuid, text)
  FROM PUBLIC, anon, authenticated;

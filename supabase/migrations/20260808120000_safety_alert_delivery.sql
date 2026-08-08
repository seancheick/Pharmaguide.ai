-- =============================================================================
-- Post-purchase safety-alert distribution and private push-token registry
-- =============================================================================
-- Catalog releases remain pipeline-owned. This app-owned lane only publishes a
-- small, independently versioned regulatory-event feed and lets a privileged
-- Edge Function target generic notifications to an already-synced supplement
-- stack. It never stores medications, profile data, or health history.

CREATE TABLE IF NOT EXISTS public.safety_alert_releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_version text NOT NULL UNIQUE CHECK (btrim(feed_version) <> ''),
  feed_path text NOT NULL CHECK (btrim(feed_path) <> ''),
  checksum text NOT NULL CHECK (checksum ~ '^sha256:[0-9a-f]{64}$'),
  manifest jsonb NOT NULL,
  published_at timestamptz NOT NULL DEFAULT now(),
  is_current boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_safety_alert_releases_one_current
  ON public.safety_alert_releases (is_current)
  WHERE is_current;

CREATE TABLE IF NOT EXISTS public.device_push_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token text NOT NULL UNIQUE CHECK (btrim(fcm_token) <> ''),
  platform text NOT NULL CHECK (platform IN ('ios', 'android')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user
  ON public.device_push_tokens (user_id);

-- A notification is an at-least-once transport, so persist successful sends
-- per alert revision and device. A stranded pending claim becomes retryable
-- after ten minutes; a worker that crashes after FCM accepts the message can
-- therefore produce one duplicate, but never an unbounded replay on releases.
CREATE TABLE IF NOT EXISTS public.safety_alert_push_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id text NOT NULL CHECK (btrim(alert_id) <> ''),
  revision integer NOT NULL CHECK (revision >= 1),
  device_push_token_id uuid NOT NULL REFERENCES public.device_push_tokens(id) ON DELETE CASCADE,
  release_id uuid NOT NULL REFERENCES public.safety_alert_releases(id),
  delivery_state text NOT NULL DEFAULT 'pending' CHECK (delivery_state IN ('pending', 'sent')),
  claimed_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  UNIQUE (alert_id, revision, device_push_token_id)
);

ALTER TABLE public.safety_alert_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_alert_releases FORCE ROW LEVEL SECURITY;
ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_push_tokens FORCE ROW LEVEL SECURITY;
ALTER TABLE public.safety_alert_push_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_alert_push_deliveries FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.safety_alert_releases FROM anon, authenticated;
REVOKE ALL ON TABLE public.device_push_tokens FROM anon, authenticated;
REVOKE ALL ON TABLE public.safety_alert_push_deliveries FROM anon, authenticated;
GRANT SELECT ON TABLE public.safety_alert_releases TO anon, authenticated;

DROP POLICY IF EXISTS "safety_alert_releases_read_current"
  ON public.safety_alert_releases;
CREATE POLICY "safety_alert_releases_read_current"
  ON public.safety_alert_releases
  FOR SELECT TO anon, authenticated
  USING (is_current = true);

-- The pipeline inserts the immutable release with its service-role key, then
-- promotes it atomically. The app has no write route to either table.
CREATE OR REPLACE FUNCTION public.promote_safety_alert_release(
  p_release_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.safety_alert_releases
    WHERE id = p_release_id
  ) THEN
    RAISE EXCEPTION 'unknown safety alert release';
  END IF;

  UPDATE public.safety_alert_releases
  SET is_current = false
  WHERE is_current;

  UPDATE public.safety_alert_releases
  SET is_current = true
  WHERE id = p_release_id;
END;
$$;

REVOKE ALL ON FUNCTION public.promote_safety_alert_release(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_safety_alert_push_delivery(
  p_alert_id text,
  p_revision integer,
  p_device_push_token_id uuid,
  p_release_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  claimed_id uuid;
BEGIN
  INSERT INTO public.safety_alert_push_deliveries (
    alert_id, revision, device_push_token_id, release_id
  ) VALUES (
    p_alert_id, p_revision, p_device_push_token_id, p_release_id
  )
  ON CONFLICT (alert_id, revision, device_push_token_id) DO UPDATE
    SET release_id = EXCLUDED.release_id,
        claimed_at = now()
    WHERE public.safety_alert_push_deliveries.delivery_state = 'pending'
      AND public.safety_alert_push_deliveries.claimed_at < now() - interval '10 minutes'
  RETURNING id INTO claimed_id;

  RETURN claimed_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_safety_alert_push_delivery(
  p_alert_id text,
  p_revision integer,
  p_device_push_token_id uuid
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.safety_alert_push_deliveries
  SET delivery_state = 'sent', sent_at = now()
  WHERE alert_id = p_alert_id
    AND revision = p_revision
    AND device_push_token_id = p_device_push_token_id;
$$;

CREATE OR REPLACE FUNCTION public.release_safety_alert_push_delivery(
  p_alert_id text,
  p_revision integer,
  p_device_push_token_id uuid
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM public.safety_alert_push_deliveries
  WHERE alert_id = p_alert_id
    AND revision = p_revision
    AND device_push_token_id = p_device_push_token_id
    AND delivery_state = 'pending';
$$;

REVOKE ALL ON FUNCTION public.claim_safety_alert_push_delivery(text, integer, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_safety_alert_push_delivery(text, integer, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_safety_alert_push_delivery(text, integer, uuid)
  FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- AI connector S3/S4: what the consent showed, kept on the connection
-- =============================================================================
-- The website consent route (PharmaGuide Website
-- src/app/api/ai-connections/route.ts) writes both at approval time:
--   client_name   the name PharmaGuide shows for a pre-registered assistant
--                 (AI_CONNECTOR_TRUSTED_CLIENTS), never the name the client
--                 registered itself
--   callback_host the host of the callback URI the route verified against
--                 the S3 allowlist (claude.ai, chatgpt.com, localhost, ...)
-- The app's share consent card names the assistant and host from these
-- columns. Nullable: rows written before this migration have neither, and
-- readers fall back to a generic label.
--
-- Status: written 2026-10-12, not applied (see supabase/MIGRATION_HISTORY.md).

ALTER TABLE public.ai_connections
  ADD COLUMN IF NOT EXISTS client_name text,
  ADD COLUMN IF NOT EXISTS callback_host text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_connections_client_name_length') THEN
    ALTER TABLE public.ai_connections ADD CONSTRAINT ai_connections_client_name_length
      CHECK (client_name IS NULL OR (btrim(client_name) <> '' AND char_length(client_name) <= 200));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_connections_callback_host_length') THEN
    ALTER TABLE public.ai_connections ADD CONSTRAINT ai_connections_callback_host_length
      CHECK (callback_host IS NULL OR (btrim(callback_host) <> '' AND char_length(callback_host) <= 200));
  END IF;
END $$;

COMMENT ON COLUMN public.ai_connections.client_name IS
  'S4: PharmaGuide''s display name for the pre-registered assistant, written at consent.';
COMMENT ON COLUMN public.ai_connections.callback_host IS
  'S3: host of the allowlisted callback URI verified at consent.';

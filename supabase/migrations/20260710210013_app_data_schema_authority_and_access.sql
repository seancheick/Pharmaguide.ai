-- =============================================================================
-- App data schema authority and least-privilege public access
-- =============================================================================
-- This migration is the executable source of truth for app-owned public data:
-- user_stacks, user_usage, pending_products, and increment_usage. It never
-- defines pipeline-owned catalog-distribution objects. Every mutable user-data
-- invariant is enforced in PostgreSQL so the Flutter client is never the sole
-- authority.

-- Fresh projects receive the full app-owned tables here. Existing projects are
-- reconciled below after their current values are checked, never fabricated.
CREATE TABLE IF NOT EXISTS public.user_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scans_today integer NOT NULL DEFAULT 0 CHECK (scans_today >= 0),
  ai_messages_today integer NOT NULL DEFAULT 0 CHECK (ai_messages_today >= 0),
  reset_day_utc date NOT NULL DEFAULT ((now() AT TIME ZONE 'UTC')::date)
);

CREATE TABLE IF NOT EXISTS public.pending_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  upc text NOT NULL CHECK (btrim(upc) <> ''),
  normalized_upc text,
  product_name text,
  brand text,
  image_url text,
  submitter_note text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'approved', 'rejected', 'duplicate')),
  review_notes text,
  reviewed_at timestamptz,
  reviewed_by text,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_stacks
  ADD COLUMN IF NOT EXISTS supply_count integer,
  ADD COLUMN IF NOT EXISTS source_device_id text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- The initial untracked table used a server_updated_at shadow timestamp. The
-- current contract has one server-maintained updated_at value plus the client
-- timestamp used for deterministic LWW ordering.
DROP TRIGGER IF EXISTS trg_user_stacks_server_updated_at ON public.user_stacks;
DROP FUNCTION IF EXISTS public.set_user_stacks_server_updated_at();
ALTER TABLE public.user_stacks DROP COLUMN IF EXISTS server_updated_at;

-- Fail before tightening any existing data. This prevents a migration from
-- silently selecting a substitute identity, timestamp, or user-facing name.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.user_stacks
    WHERE id IS NULL
       OR btrim(id) = ''
       OR dsld_id IS NULL
       OR btrim(dsld_id) = ''
       OR name IS NULL
       OR btrim(name) = ''
       OR type IS NULL
       OR type <> 'supplement'
       OR client_updated_at IS NULL
       OR added_at IS NULL
       OR updated_at IS NULL
       OR supply_count < 0
  ) THEN
    RAISE EXCEPTION
      'user_stacks contains values that violate the app-data contract; remediate before enforcing constraints';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_usage
    WHERE scans_today IS NULL
       OR ai_messages_today IS NULL
       OR reset_day_utc IS NULL
  ) THEN
    RAISE EXCEPTION
      'user_usage contains nullable counters or reset days; remediate before enforcing constraints';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pending_products
    WHERE upc IS NULL
       OR status IS NULL
       OR submitted_at IS NULL
       OR btrim(upc) = ''
  ) THEN
    RAISE EXCEPTION
      'pending_products contains values that violate the app-data contract; remediate before enforcing constraints';
  END IF;

END
$$;

ALTER TABLE public.user_stacks
  ALTER COLUMN id DROP DEFAULT,
  ALTER COLUMN type SET DEFAULT 'supplement',
  ALTER COLUMN type SET NOT NULL,
  ALTER COLUMN name SET NOT NULL,
  ALTER COLUMN dsld_id SET NOT NULL,
  ALTER COLUMN client_updated_at SET NOT NULL,
  ALTER COLUMN added_at SET NOT NULL,
  ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE public.user_usage
  ALTER COLUMN scans_today SET NOT NULL,
  ALTER COLUMN ai_messages_today SET NOT NULL,
  ALTER COLUMN reset_day_utc SET NOT NULL;

ALTER TABLE public.pending_products
  ALTER COLUMN upc SET NOT NULL,
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN submitted_at SET NOT NULL;

ALTER TABLE public.user_stacks
  DROP CONSTRAINT IF EXISTS user_stacks_user_id_fkey,
  ADD CONSTRAINT user_stacks_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.user_usage
  DROP CONSTRAINT IF EXISTS user_usage_user_id_fkey,
  ADD CONSTRAINT user_usage_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.pending_products
  DROP CONSTRAINT IF EXISTS pending_products_user_id_fkey,
  ADD CONSTRAINT pending_products_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname = 'user_stacks_type_supplement_check'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_type_supplement_check
      CHECK (type = 'supplement');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname = 'user_stacks_dsld_id_nonblank_check'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_dsld_id_nonblank_check
      CHECK (btrim(dsld_id) <> '');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.pending_products'::regclass
      AND conname = 'pending_products_upc_nonblank_check'
  ) THEN
    ALTER TABLE public.pending_products
      ADD CONSTRAINT pending_products_upc_nonblank_check
      CHECK (btrim(upc) <> '');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname = 'user_stacks_name_nonblank_check'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_name_nonblank_check
      CHECK (btrim(name) <> '');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_stacks'::regclass
      AND conname = 'user_stacks_supply_count_nonnegative_check'
  ) THEN
    ALTER TABLE public.user_stacks
      ADD CONSTRAINT user_stacks_supply_count_nonnegative_check
      CHECK (supply_count IS NULL OR supply_count >= 0);
  END IF;

END
$$;

CREATE INDEX IF NOT EXISTS idx_user_stacks_user ON public.user_stacks(user_id);
CREATE INDEX IF NOT EXISTS idx_user_usage_user ON public.user_usage(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_usage_daily
  ON public.user_usage(user_id, reset_day_utc);
CREATE INDEX IF NOT EXISTS idx_pending_products_user
  ON public.pending_products(user_id);
CREATE INDEX IF NOT EXISTS idx_pending_products_status
  ON public.pending_products(status)
  WHERE status = 'pending';
CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_products_user_normalized_upc_pending
  ON public.pending_products(user_id, normalized_upc)
  WHERE status = 'pending' AND normalized_upc IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_stacks_updated_at ON public.user_stacks;
CREATE TRIGGER user_stacks_updated_at
  BEFORE UPDATE ON public.user_stacks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.increment_usage(
  p_user_id uuid,
  p_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_usage public.user_usage%ROWTYPE;
  v_scans integer := 0;
  v_ai integer := 0;
  v_exceeded boolean := false;
  v_scan_limit constant integer := 20;
  v_ai_limit constant integer := 5;
  v_reset_day_utc date := (now() AT TIME ZONE 'UTC')::date;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: cannot increment usage for another user';
  END IF;

  IF p_type NOT IN ('scan', 'ai_message') THEN
    RAISE EXCEPTION 'Invalid usage type: %', p_type;
  END IF;

  INSERT INTO public.user_usage (
    user_id,
    scans_today,
    ai_messages_today,
    reset_day_utc
  ) VALUES (
    p_user_id,
    0,
    0,
    v_reset_day_utc
  ) ON CONFLICT (user_id, reset_day_utc) DO NOTHING;

  SELECT *
  INTO v_usage
  FROM public.user_usage
  WHERE user_id = p_user_id
    AND reset_day_utc = v_reset_day_utc
  FOR UPDATE;

  IF p_type = 'scan' AND v_usage.scans_today >= v_scan_limit THEN
    v_exceeded := true;
  ELSIF p_type = 'ai_message' AND v_usage.ai_messages_today >= v_ai_limit THEN
    v_exceeded := true;
  ELSE
    UPDATE public.user_usage
    SET scans_today = CASE
          WHEN p_type = 'scan' THEN scans_today + 1
          ELSE scans_today
        END,
        ai_messages_today = CASE
          WHEN p_type = 'ai_message' THEN ai_messages_today + 1
          ELSE ai_messages_today
        END
    WHERE id = v_usage.id
    RETURNING scans_today, ai_messages_today
    INTO v_scans, v_ai;
  END IF;

  IF v_exceeded THEN
    v_scans := v_usage.scans_today;
    v_ai := v_usage.ai_messages_today;
  END IF;

  RETURN jsonb_build_object(
    'scans_today', v_scans,
    'ai_messages_today', v_ai,
    'limit_exceeded', v_exceeded,
    'reset_day_utc', v_reset_day_utc
  );
END;
$$;

-- User-owned tables must be unreachable to anon clients even when a future
-- policy is edited incorrectly. Authenticated grants stay no broader than the
-- operation each table actually supports.
ALTER TABLE public.user_stacks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own stacks" ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_read_own_stack" ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_insert_own_supplements" ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_update_own_supplements" ON public.user_stacks;
DROP POLICY IF EXISTS "users_can_delete_own_stack" ON public.user_stacks;
CREATE POLICY "users_can_read_own_stack" ON public.user_stacks
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "users_can_insert_own_supplements" ON public.user_stacks
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND type = 'supplement');
CREATE POLICY "users_can_update_own_supplements" ON public.user_stacks
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id AND type = 'supplement');
CREATE POLICY "users_can_delete_own_stack" ON public.user_stacks
  FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);

ALTER TABLE public.user_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own usage" ON public.user_usage;
CREATE POLICY "Users read own usage" ON public.user_usage
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

ALTER TABLE public.pending_products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own submissions" ON public.pending_products;
DROP POLICY IF EXISTS "Users submit pending products" ON public.pending_products;
CREATE POLICY "Users read own submissions" ON public.pending_products
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users submit pending products" ON public.pending_products
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

REVOKE ALL ON TABLE public.user_stacks FROM anon;
REVOKE ALL ON TABLE public.user_usage FROM anon;
REVOKE ALL ON TABLE public.pending_products FROM anon;
REVOKE ALL ON TABLE public.user_usage FROM authenticated;
REVOKE ALL ON TABLE public.pending_products FROM authenticated;
REVOKE ALL ON TABLE public.user_stacks FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_stacks TO authenticated;
GRANT SELECT ON TABLE public.user_usage TO authenticated;
GRANT SELECT, INSERT ON TABLE public.pending_products TO authenticated;

REVOKE ALL ON FUNCTION public.keep_newest_user_stack_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.increment_usage(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_usage(uuid, text) TO authenticated;

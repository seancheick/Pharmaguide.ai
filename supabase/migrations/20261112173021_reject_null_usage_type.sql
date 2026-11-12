-- Reject SQL NULL before any state change; preserve existing authorization and valid-input behavior.
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

  IF p_type IS NULL OR p_type NOT IN ('scan', 'ai_message') THEN
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

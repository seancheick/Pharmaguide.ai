-- Keep user-authored dose and schedule details on-device.
--
-- `user_stacks` remains a narrow, push-only supplement identity cache. Older
-- beta builds wrote dosage/frequency into this table; current clients no
-- longer send those columns. Keep the nullable columns temporarily so an old
-- client fails safely instead of breaking its entire upsert, but clear every
-- value at the database boundary.

CREATE OR REPLACE FUNCTION public.clear_user_stack_device_only_schedule()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
BEGIN
  NEW.dosage := NULL;
  NEW.frequency := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS aa_user_stacks_clear_device_only_schedule
  ON public.user_stacks;
CREATE TRIGGER aa_user_stacks_clear_device_only_schedule
  BEFORE INSERT OR UPDATE ON public.user_stacks
  FOR EACH ROW
  EXECUTE FUNCTION public.clear_user_stack_device_only_schedule();

-- `zz_user_stacks_keep_newest_state` rejects updates that do not advance the
-- client timestamp. Advance it once for this server-owned privacy cleanup; the
-- new trigger does not change timestamps on future writes.
UPDATE public.user_stacks
SET dosage = NULL,
    frequency = NULL,
    client_updated_at = GREATEST(
      client_updated_at + INTERVAL '1 microsecond',
      clock_timestamp()
    )
WHERE dosage IS NOT NULL OR frequency IS NOT NULL;

REVOKE ALL ON FUNCTION public.clear_user_stack_device_only_schedule()
  FROM PUBLIC, anon, authenticated;

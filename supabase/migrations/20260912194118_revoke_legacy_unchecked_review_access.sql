-- A retired overload survived the catalog-edition rollout with PUBLIC execute.
-- Only the guarded review_product_submission RPC may call these implementations.
-- Cover every overload so a stale signature cannot bypass field attestations.
DO $$
DECLARE implementation regprocedure;
BEGIN
  FOR implementation IN
    SELECT p.oid::regprocedure FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='review_product_submission_unchecked'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', implementation);
  END LOOP;
END $$;

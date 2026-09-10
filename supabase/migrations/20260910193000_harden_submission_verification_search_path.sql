-- Keep the immutable verification-path helper deterministic and independent
-- of caller-controlled search_path resolution.
ALTER FUNCTION public.product_submission_required_verification_paths()
  SET search_path = pg_catalog;

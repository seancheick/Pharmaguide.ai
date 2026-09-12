-- Reviewers read extraction drafts through a reviewer-gated function.
--
-- product_submission_extractions is revoked from PUBLIC, anon, authenticated
-- and service_role: every read and write goes through a SECURITY DEFINER
-- function that names who may do it. The reviewer backend was selecting the
-- table directly with the service key, which is a permission error on every
-- call — and the console asks for one submission's drafts exactly when it
-- refreshes the open submission after a decision. That refresh failed
-- silently, so the panel kept showing the status the decision had already
-- changed, Start review stayed enabled, and pressing it again was refused by
-- the transition rules. Same failure also stopped signed photo URLs from
-- being renewed before they expired.
--
-- Drafts stay filtered to one evidence revision: a draft read off photographs
-- that have since been replaced is not a reading of what is on screen.

CREATE OR REPLACE FUNCTION public.get_product_submission_extractions(
  p_submission_id uuid,
  p_evidence_revision integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  result jsonb;
BEGIN
  PERFORM public.assert_product_submission_reviewer();
  SELECT COALESCE(jsonb_agg(draft ORDER BY draft.version DESC), '[]'::jsonb)
    INTO result
  FROM (
    SELECT
      extraction.version,
      extraction.schema_version,
      extraction.provider,
      extraction.model,
      extraction.prompt_version,
      extraction.draft_payload,
      extraction.confidence,
      extraction.actor_kind,
      extraction.evidence_revision,
      extraction.created_at
    FROM public.product_submission_extractions AS extraction
    WHERE extraction.submission_id = p_submission_id
      AND extraction.evidence_revision = p_evidence_revision
    ORDER BY extraction.version DESC
    LIMIT 5
  ) AS draft;
  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_product_submission_extractions(uuid, integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_product_submission_extractions(uuid, integer)
  TO authenticated;

-- Add spatial evidence to the existing reviewer-only response. No approval changes.
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
      CASE WHEN jsonb_typeof(extraction.usage->'grounding') = 'object'
        THEN jsonb_build_object(
          'schema_version', extraction.usage->'grounding'->'schema_version',
          'rows', extraction.usage->'grounding'->'rows',
          'fields', extraction.usage->'grounding'->'fields',
          'checked', extraction.usage->'grounding'->'checked',
          'grounded', extraction.usage->'grounding'->'grounded',
          'rate', extraction.usage->'grounding'->'rate',
          'region_coordinate_space', extraction.usage->'grounding'->'region_coordinate_space',
          'status', extraction.usage->'grounding'->'status',
          'independence_note', extraction.usage->'grounding'->'independence_note'
        ) ELSE NULL END AS grounding,
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

-- Make the database RPC the single approval authority.
--
-- The Edge Function already checked the reviewer's field attestations, but the
-- public RPC could be called directly by an authenticated reviewer and skip
-- that check. Keep the existing transition implementation private and expose
-- one guarded function with the original signature.

ALTER FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) RENAME TO review_product_submission_unchecked;

REVOKE ALL ON FUNCTION public.review_product_submission_unchecked(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.review_product_submission(
  p_submission_id uuid,
  p_to_status public.product_submission_review_status,
  p_review_notes text DEFAULT NULL,
  p_approved_schema_version text DEFAULT NULL,
  p_approved_payload jsonb DEFAULT NULL,
  p_approved_payload_canonical text DEFAULT NULL,
  p_payload_sha256 text DEFAULT NULL,
  p_duplicate_of uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_detail text DEFAULT NULL,
  p_resolved_dsld_id text DEFAULT NULL,
  p_product_image_photo_id uuid DEFAULT NULL,
  p_product_image_reviewer_object_id uuid DEFAULT NULL,
  p_expected_evidence_revision integer DEFAULT NULL,
  p_evidence_manifest_sha256 text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_to_status = 'approved' THEN
    -- This is the same required-path rule used by single and batch actions.
    -- It runs inside the RPC so a direct authenticated call cannot bypass the
    -- reviewer workstation or manufacture an approval with no attestations.
    PERFORM public.assert_product_submission_fully_verified(
      p_submission_id, p_payload_sha256);
  END IF;

  RETURN public.review_product_submission_unchecked(
    p_submission_id,
    p_to_status,
    p_review_notes,
    p_approved_schema_version,
    p_approved_payload,
    p_approved_payload_canonical,
    p_payload_sha256,
    p_duplicate_of,
    p_resolution_code,
    p_resolution_detail,
    p_resolved_dsld_id,
    p_product_image_photo_id,
    p_product_image_reviewer_object_id,
    p_expected_evidence_revision,
    p_evidence_manifest_sha256
  );
END;
$$;

REVOKE ALL ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) TO authenticated;

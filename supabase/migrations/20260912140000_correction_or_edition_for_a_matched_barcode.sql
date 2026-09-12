-- A barcode that already names a catalog record is not automatically a
-- duplicate.
--
-- The reviewer had two buttons for a catalog hit: mark it a duplicate, which
-- asserts the catalog already holds this label, or say none of these is this
-- product, which asserts the barcode belongs to something else. When the
-- catalog record is the same product carrying a different label — the common
-- case, because manufacturers reformulate and keep the barcode — both are
-- false, and the reviewer is stuck with no honest action.
--
-- There are two truthful outcomes, and they are not interchangeable:
--
--   correction  the catalog record is this label, transcribed wrongly. The
--               record is rewritten in place, keeping its id, so anyone who
--               already has it in a stack keeps the same product.
--
--   edition     the catalog record is a genuinely different formula sold under
--               the same barcode. It is left alone and this label becomes its
--               own product. Nobody's bottle silently changes contents, and
--               the app already asks which bottle a scan means when one
--               barcode resolves to more than one product.
--
-- Neither may be claimed without a recorded catalog match naming that exact
-- record, checked against the evidence on screen.

ALTER TABLE public.product_submissions
  ADD COLUMN IF NOT EXISTS correction_target_dsld_id text,
  ADD COLUMN IF NOT EXISTS edition_of_dsld_id text;

ALTER TABLE public.product_submissions
  DROP CONSTRAINT IF EXISTS product_submissions_catalog_relation_valid;
ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submissions_catalog_relation_valid CHECK (
    num_nonnulls(correction_target_dsld_id, edition_of_dsld_id) <= 1
    AND (
      correction_target_dsld_id IS NULL
      OR (kind = 'missing_product' AND correction_target_dsld_id ~ '^[0-9]{1,30}$')
    )
    AND (
      edition_of_dsld_id IS NULL
      OR (kind = 'missing_product' AND edition_of_dsld_id ~ '^[0-9]{1,30}$')
    )
  );

-- The identity check now answers both questions the gate asks of it, from one
-- freshness rule rather than two copies of it.
CREATE OR REPLACE FUNCTION public.product_submission_identity_check(
  p_submission_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  latest_match public.product_submission_match_checks%ROWTYPE;
  binds_to_this_evidence boolean;
BEGIN
  SELECT * INTO submission FROM public.product_submissions
  WHERE id = p_submission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '55000';
  END IF;

  SELECT match_check.*
    INTO latest_match
  FROM public.product_submission_match_checks AS match_check
  WHERE match_check.submission_id = p_submission_id
  ORDER BY match_check.created_at DESC, match_check.id DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'recorded', false,
      'satisfies_approval', false,
      'catalog_match_live', false
    );
  END IF;

  -- Only a missing-product approval consults this. For other kinds the record
  -- is reported but never gates, so nothing is claimed as satisfied.
  binds_to_this_evidence :=
    submission.kind = 'missing_product'
    AND latest_match.evidence_revision IS NOT DISTINCT FROM
      submission.evidence_revision
    AND latest_match.index_built_at >= now() - interval '60 days'
    AND latest_match.index_built_at <= now() + interval '5 minutes'
    AND latest_match.canonical_gtin14 =
      lpad(submission.normalized_upc, 14, '0');

  RETURN jsonb_build_object(
    'recorded', true,
    'outcome', latest_match.outcome,
    'matched_dsld_id', latest_match.matched_dsld_id,
    'evidence_revision', latest_match.evidence_revision,
    'index_built_at', latest_match.index_built_at,
    'checked_at', latest_match.created_at,
    'satisfies_approval',
      binds_to_this_evidence AND latest_match.outcome = 'no_match_verified',
    'catalog_match_live',
      binds_to_this_evidence AND latest_match.outcome = 'catalog_match'
      AND latest_match.matched_dsld_id IS NOT NULL
  );
END $$;

REVOKE ALL ON FUNCTION public.product_submission_identity_check(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Both entry points take the decision, so a direct authenticated call cannot
-- reach the unchecked path with one and the reviewed path without it.
DROP FUNCTION IF EXISTS public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text, text,
  uuid, text, text, text, uuid, uuid, integer, text);
DROP FUNCTION IF EXISTS public.review_product_submission_unchecked(
  uuid, public.product_submission_review_status, text, text, jsonb, text, text,
  uuid, text, text, text, uuid, uuid, integer, text);

CREATE OR REPLACE FUNCTION "public"."review_product_submission_unchecked"("p_submission_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text", "p_product_image_photo_id" "uuid" DEFAULT NULL::"uuid", "p_product_image_reviewer_object_id" "uuid" DEFAULT NULL::"uuid", "p_expected_evidence_revision" integer DEFAULT NULL::integer, "p_evidence_manifest_sha256" "text" DEFAULT NULL::"text", "p_correction_target_dsld_id" "text" DEFAULT NULL::"text", "p_edition_of_dsld_id" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  identity jsonb;
  transitioned boolean;
BEGIN
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_evidence_revision,p_evidence_manifest_sha256);

  IF p_to_status = 'approved' THEN
    IF p_expected_evidence_revision IS NULL THEN
      RAISE EXCEPTION 'expected evidence revision required'
        USING ERRCODE = '22023';
    END IF;
    IF p_expected_evidence_revision <> submission.evidence_revision THEN
      RAISE EXCEPTION 'evidence revision changed since review'
        USING ERRCODE = '55000';
    END IF;
    SELECT revision.*
      INTO current_revision
    FROM public.product_submission_evidence_revisions AS revision
    WHERE revision.submission_id = p_submission_id
      AND revision.revision = submission.evidence_revision
      AND revision.ready_at IS NOT NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
    END IF;
  ELSIF p_expected_evidence_revision IS NOT NULL
        AND p_expected_evidence_revision <> submission.evidence_revision THEN
    RAISE EXCEPTION 'evidence revision changed since review'
      USING ERRCODE = '55000';
  END IF;

  IF num_nonnulls(p_correction_target_dsld_id, p_edition_of_dsld_id) > 0
     AND NOT (p_to_status = 'approved' AND submission.kind = 'missing_product')
  THEN
    RAISE EXCEPTION 'catalog relation is not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' AND submission.kind = 'missing_product' THEN
    -- Three honest answers, and the reviewer must have recorded one of them.
    -- A barcode nobody else uses is a new product. A barcode that already
    -- names a catalog record is either that record transcribed wrongly, or a
    -- different edition sold under the same barcode — and those are different
    -- decisions with different consequences, so neither is inferred here.
    identity := public.product_submission_identity_check(p_submission_id);
    IF num_nonnulls(p_correction_target_dsld_id, p_edition_of_dsld_id) = 1 THEN
      IF NOT (identity ->> 'catalog_match_live')::boolean
         OR identity ->> 'matched_dsld_id' IS DISTINCT FROM
            coalesce(p_correction_target_dsld_id, p_edition_of_dsld_id) THEN
        RAISE EXCEPTION
          'recorded catalog match must name the catalog record being decided'
          USING ERRCODE = '55000';
      END IF;
    ELSIF NOT (identity ->> 'satisfies_approval')::boolean THEN
      RAISE EXCEPTION 'fresh verified no-match required before approval'
        USING ERRCODE = '55000';
    END IF;
    IF num_nonnulls(
      p_product_image_photo_id,
      p_product_image_reviewer_object_id
    ) <> 1 THEN
      RAISE EXCEPTION 'exactly one approved product image required'
        USING ERRCODE = '22023';
    END IF;
    IF p_product_image_photo_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS photo
      WHERE photo.submission_id = p_submission_id
        AND photo.photo_id = p_product_image_photo_id
        AND photo.photo_id = ANY(current_revision.photo_ids)
        AND 'front_identity' = ANY(photo.categories)
    ) THEN
      RAISE EXCEPTION 'front evidence photo required for product image'
        USING ERRCODE = '22023';
    END IF;
    IF p_product_image_reviewer_object_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_reviewer_images AS image
      WHERE image.submission_id = p_submission_id
        AND image.object_id = p_product_image_reviewer_object_id
        AND image.reviewer_id = v_reviewer_id
        AND image.evidence_revision = submission.evidence_revision
        AND image.finalized_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'finalized reviewer product image required'
        USING ERRCODE = '22023';
    END IF;
  ELSIF p_product_image_photo_id IS NOT NULL
     OR p_product_image_reviewer_object_id IS NOT NULL THEN
    RAISE EXCEPTION 'product image is not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;

  transitioned := public.review_product_submission_human_internal(
    p_submission_id,
    v_reviewer_id,
    p_to_status,
    p_review_notes,
    p_approved_schema_version,
    p_approved_payload,
    p_approved_payload_canonical,
    p_payload_sha256,
    p_duplicate_of,
    p_resolution_code,
    p_resolution_detail,
    p_resolved_dsld_id
  );
  IF transitioned AND p_to_status = 'approved' THEN
    UPDATE public.product_submissions
    SET correction_target_dsld_id = p_correction_target_dsld_id,
        edition_of_dsld_id = p_edition_of_dsld_id
    WHERE id = p_submission_id;
    UPDATE public.product_submission_approved_labels
    SET approved_product_image_photo_id = p_product_image_photo_id,
        approved_product_image_reviewer_object_id =
          p_product_image_reviewer_object_id,
        evidence_revision = current_revision.revision,
        evidence_manifest_sha256 = current_revision.manifest_sha256
    WHERE submission_id = p_submission_id;
  END IF;
  RETURN transitioned;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_product_submission(
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
  p_evidence_manifest_sha256 text DEFAULT NULL,
  p_correction_target_dsld_id text DEFAULT NULL,
  p_edition_of_dsld_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF p_to_status = 'approved' THEN
    -- The same required-path rule used by single and batch actions, inside the
    -- RPC so a direct authenticated call cannot manufacture an approval with
    -- no attestations.
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
    p_evidence_manifest_sha256,
    p_correction_target_dsld_id,
    p_edition_of_dsld_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text, text,
  uuid, text, text, text, uuid, uuid, integer, text, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text, text,
  uuid, text, text, text, uuid, uuid, integer, text, text, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.review_product_submission_unchecked(
  uuid, public.product_submission_review_status, text, text, jsonb, text, text,
  uuid, text, text, text, uuid, uuid, integer, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- The importer reads the decision with the approval it belongs to. The return
-- type grows, so the old shape is dropped rather than replaced in place.
DROP FUNCTION IF EXISTS public.export_approved_product_submissions(
  integer, timestamp with time zone, uuid);
DROP FUNCTION IF EXISTS public.export_approved_product_submissions_internal(
  integer, timestamp with time zone, uuid);

CREATE OR REPLACE FUNCTION public.export_approved_product_submissions_internal(
  p_limit integer DEFAULT 100,
  p_after_approved_at timestamp with time zone DEFAULT NULL,
  p_after_submission_id uuid DEFAULT NULL
)
RETURNS TABLE(
  submission_id uuid, kind public.product_submission_kind, normalized_upc text,
  target_dsld_id text, schema_version text, approved_payload_canonical text,
  payload_sha256 text, reviewer_id uuid, approved_at timestamp with time zone,
  correction_target_dsld_id text, edition_of_dsld_id text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT
    submission.id,
    submission.kind,
    submission.normalized_upc,
    mismatch.dsld_id,
    approved.schema_version,
    approved.approved_payload_canonical,
    approved.payload_sha256,
    approved.reviewer_id,
    approved.approved_at,
    submission.correction_target_dsld_id,
    submission.edition_of_dsld_id
  FROM public.product_submissions AS submission
  JOIN public.product_submission_approved_labels AS approved
    ON approved.submission_id = submission.id
  LEFT JOIN public.product_submission_mismatch_details AS mismatch
    ON mismatch.submission_id = submission.id
  WHERE submission.upload_state = 'ready'
    AND submission.review_status = 'approved'
    AND submission.promoted_at IS NULL
    AND (
      (
        p_after_approved_at IS NULL
        AND p_after_submission_id IS NULL
      )
      OR (
        p_after_approved_at IS NOT NULL
        AND p_after_submission_id IS NOT NULL
        AND (approved.approved_at, submission.id) >
          (p_after_approved_at, p_after_submission_id)
      )
    )
  ORDER BY approved.approved_at, submission.id
  LIMIT greatest(0, least(p_limit, 500));
$$;

CREATE OR REPLACE FUNCTION public.export_approved_product_submissions(
  p_limit integer DEFAULT 100,
  p_after_approved_at timestamp with time zone DEFAULT NULL,
  p_after_submission_id uuid DEFAULT NULL
)
RETURNS TABLE(
  submission_id uuid, kind public.product_submission_kind, normalized_upc text,
  target_dsld_id text, schema_version text, approved_payload_canonical text,
  payload_sha256 text, reviewer_id uuid, approved_at timestamp with time zone,
  correction_target_dsld_id text, edition_of_dsld_id text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE candidate record;
BEGIN
  FOR candidate IN SELECT * FROM
    public.export_approved_product_submissions_internal(
      p_limit, p_after_approved_at, p_after_submission_id) LOOP
    PERFORM public.assert_product_submission_approval(candidate.submission_id);
    RETURN QUERY SELECT candidate.submission_id, candidate.kind,
      candidate.normalized_upc, candidate.target_dsld_id,
      candidate.schema_version, candidate.approved_payload_canonical,
      candidate.payload_sha256, candidate.reviewer_id, candidate.approved_at,
      candidate.correction_target_dsld_id, candidate.edition_of_dsld_id;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.export_approved_product_submissions_internal(
  integer, timestamp with time zone, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.export_approved_product_submissions(
  integer, timestamp with time zone, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_approved_product_submissions(
  integer, timestamp with time zone, uuid)
  TO service_role;

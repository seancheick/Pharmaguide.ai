-- One owner for "has this barcode been verified as new?"
--
-- The approval gate held that rule inline, so the console could not ask the
-- question: it kept the answer in a page variable instead, cleared it every
-- time the barcode lookup ran, and never reloaded it. A reviewer who had
-- already recorded a verified no-match came back to a greyed-out Approve on a
-- submission the database would have accepted, with no way to see why.
--
-- The rule moves into product_submission_identity_check. The gate calls it, so
-- what it enforces cannot drift from what the console shows, and the reviewer
-- state function returns it so a reopened page starts from the record.

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
    RETURN jsonb_build_object('recorded', false, 'satisfies_approval', false);
  END IF;

  RETURN jsonb_build_object(
    'recorded', true,
    'outcome', latest_match.outcome,
    'matched_dsld_id', latest_match.matched_dsld_id,
    'evidence_revision', latest_match.evidence_revision,
    'index_built_at', latest_match.index_built_at,
    'checked_at', latest_match.created_at,
    -- Only a missing-product approval consults this. For other kinds the
    -- answer is reported but never gates, so it is not claimed as satisfied.
    'satisfies_approval',
      submission.kind = 'missing_product'
      AND latest_match.outcome = 'no_match_verified'
      AND latest_match.evidence_revision IS NOT DISTINCT FROM
        submission.evidence_revision
      AND latest_match.index_built_at >= now() - interval '60 days'
      AND latest_match.index_built_at <= now() + interval '5 minutes'
      AND latest_match.canonical_gtin14 =
        lpad(submission.normalized_upc, 14, '0')
  );
END $$;

REVOKE ALL ON FUNCTION public.product_submission_identity_check(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."review_product_submission_unchecked"("p_submission_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text", "p_product_image_photo_id" "uuid" DEFAULT NULL::"uuid", "p_product_image_reviewer_object_id" "uuid" DEFAULT NULL::"uuid", "p_expected_evidence_revision" integer DEFAULT NULL::integer, "p_evidence_manifest_sha256" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
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

  IF p_to_status = 'approved' AND submission.kind = 'missing_product' THEN
    -- The rule itself lives in product_submission_identity_check, so the
    -- console can show the same answer this gate enforces instead of
    -- remembering a click.
    IF NOT (public.product_submission_identity_check(p_submission_id)
            ->> 'satisfies_approval')::boolean THEN
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

CREATE OR REPLACE FUNCTION "public"."product_submission_reviewer_state_internal"("p_submission_id" "uuid", "p_reviewer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  draft public.product_submission_reviewer_drafts%ROWTYPE;
  draft_is_current boolean;
  found_draft boolean;
  -- product_submissions does not carry the manifest hash; the ready revision
  -- row owns it. Read it from there rather than inventing a second copy.
  current_manifest_sha256 text;
BEGIN
  SELECT * INTO submission FROM public.product_submissions
  WHERE id = p_submission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '55000';
  END IF;
  SELECT revision.manifest_sha256 INTO current_manifest_sha256
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = submission.evidence_revision
    AND revision.ready_at IS NOT NULL;
  SELECT * INTO draft FROM public.product_submission_reviewer_drafts
  WHERE submission_id = p_submission_id AND reviewer_id = p_reviewer_id;

  -- A draft written against evidence that has since been retaken is still the
  -- reviewer's work; it is reported as superseded rather than deleted, so the
  -- console can show what was lost instead of pretending it never existed.
  found_draft := draft.submission_id IS NOT NULL;
  draft_is_current := found_draft
    AND current_manifest_sha256 IS NOT NULL
    AND draft.evidence_revision = submission.evidence_revision
    AND draft.evidence_manifest_sha256 = current_manifest_sha256;

  RETURN jsonb_build_object(
    'submission_id', p_submission_id,
    -- The recorded barcode check, so a reopened page shows what was checked
    -- rather than asking for it again. Same answer the approval gate uses.
    'identity_check', public.product_submission_identity_check(p_submission_id),
    'current_evidence_revision', submission.evidence_revision,
    'current_evidence_manifest_sha256', current_manifest_sha256,
    'review_status', submission.review_status,
    'draft', CASE WHEN draft.submission_id IS NULL THEN NULL ELSE
      jsonb_build_object(
        'payload', draft.payload,
        'payload_canonical', draft.payload_canonical,
        'payload_sha256', draft.payload_sha256,
        'evidence_revision', draft.evidence_revision,
        'evidence_manifest_sha256', draft.evidence_manifest_sha256,
        'superseded', NOT draft_is_current,
        'updated_at', draft.updated_at
      ) END,
    'verifications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'field_path', verification.field_path,
        'photo_id', verification.photo_id,
        'payload_sha256', verification.payload_sha256,
        'evidence_revision', verification.evidence_revision,
        -- Live means: attested against exactly this label text and exactly
        -- these photographs. Anything else is history, not authorization.
        'live', draft_is_current
          AND verification.payload_sha256 = draft.payload_sha256
          AND verification.evidence_revision = submission.evidence_revision
          AND verification.evidence_manifest_sha256 = current_manifest_sha256,
        'verified_at', verification.verified_at
      ) ORDER BY verification.field_path)
      FROM public.product_submission_field_verifications AS verification
      WHERE verification.submission_id = p_submission_id
        AND verification.reviewer_id = p_reviewer_id
    ), '[]'::jsonb)
  );
END $$;

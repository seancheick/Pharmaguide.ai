-- One owner for "which catalog record does this approval change?"
--
-- Only one approved-but-unreleased change to a catalog record may wait at a
-- time; two would reach the importer as one product id with two labels, and
-- the import refuses the whole run. The key that enforces this was computed
-- twice inline — once for the approving row, once for every other row — and
-- neither copy knew that a missing-product capture can now correct an
-- existing record. A correction of 178392 keyed itself by barcode while a
-- label report on 178392 keyed itself by record, so both could be approved and
-- the import queue then blocked until someone intervened by hand.
--
-- product_submission_review_target_key is now the only definition, used for
-- both sides of the comparison. A correction contends for the record it
-- rewrites. An edition adds a product beside that record and changes nothing
-- in it, so it contends for its barcode like any new product.

CREATE OR REPLACE FUNCTION public.product_submission_review_target_key(
  p_submission_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT CASE
    WHEN submission.kind = 'label_mismatch' THEN
      'label_mismatch:' || mismatch.dsld_id
    WHEN submission.correction_target_dsld_id IS NOT NULL THEN
      'label_mismatch:' || submission.correction_target_dsld_id
    ELSE
      'missing_product:'
        || public.product_submission_canonical_gtin(submission.normalized_upc)
  END
  FROM public.product_submissions AS submission
  LEFT JOIN public.product_submission_mismatch_details AS mismatch
    ON mismatch.submission_id = submission.id
  WHERE submission.id = p_submission_id;
$$;

REVOKE ALL ON FUNCTION public.product_submission_review_target_key(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."review_product_submission_human_internal"("p_submission_id" "uuid", "p_reviewer_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  submission public.product_submissions%ROWTYPE;
  transition_allowed boolean;
  review_target_key text;
  resolution_code_value public.product_submission_resolution_code;
  resolution_detail_value text;
  resolved_dsld_value text;
BEGIN
  IF p_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'reviewer identity required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;

  transition_allowed := CASE submission.review_status
    WHEN 'submitted' THEN p_to_status IN (
      'under_review',
      'rejected',
      'duplicate'
    )
    WHEN 'under_review' THEN p_to_status IN (
      'approved',
      'rejected',
      'duplicate'
    )
    ELSE false
  END;
  IF NOT transition_allowed THEN
    RAISE EXCEPTION 'invalid review transition' USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(coalesce(p_resolution_code, '')), '') IS NOT NULL THEN
    BEGIN
      resolution_code_value := btrim(p_resolution_code)
        ::public.product_submission_resolution_code;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid resolution code' USING ERRCODE = '22023';
    END;
  END IF;
  resolution_detail_value := NULLIF(btrim(regexp_replace(
    coalesce(p_resolution_detail, ''),
    '[\x00-\x1F\x7F]',
    '',
    'g'
  )), '');
  IF resolution_detail_value IS NOT NULL
     AND char_length(resolution_detail_value) > 280 THEN
    RAISE EXCEPTION 'resolution detail too long' USING ERRCODE = '22023';
  END IF;
  resolved_dsld_value := NULLIF(btrim(coalesce(p_resolved_dsld_id, '')), '');
  IF resolved_dsld_value IS NOT NULL
     AND resolved_dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid resolved product id' USING ERRCODE = '22023';
  END IF;

  IF p_to_status IN ('under_review', 'approved') THEN
    IF resolution_code_value IS NOT NULL
       OR resolution_detail_value IS NOT NULL
       OR resolved_dsld_value IS NOT NULL THEN
      RAISE EXCEPTION 'resolution not allowed for this transition'
        USING ERRCODE = '22023';
    END IF;
    IF p_duplicate_of IS NOT NULL THEN
      RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
    END IF;
  ELSIF p_to_status = 'rejected' THEN
    IF resolution_code_value IS NULL
       OR resolution_code_value NOT IN (
         'photo_quality',
         'missing_panel',
         'label_unreadable',
         'product_identity_mismatch',
         'not_a_supplement',
         'other'
       ) THEN
      RAISE EXCEPTION 'rejection resolution code required'
        USING ERRCODE = '22023';
    END IF;
    IF resolution_code_value = 'other'
       AND resolution_detail_value IS NULL THEN
      RAISE EXCEPTION 'resolution detail required' USING ERRCODE = '22023';
    END IF;
    IF resolved_dsld_value IS NOT NULL OR p_duplicate_of IS NOT NULL THEN
      RAISE EXCEPTION 'resolution not allowed for this transition'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF resolution_code_value IS NULL
       OR resolution_code_value NOT IN (
         'already_in_catalog',
         'duplicate_submission'
       ) THEN
      RAISE EXCEPTION 'duplicate resolution code required'
        USING ERRCODE = '22023';
    END IF;
    IF resolution_code_value = 'already_in_catalog' THEN
      IF resolved_dsld_value IS NULL OR p_duplicate_of IS NOT NULL THEN
        RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF p_duplicate_of IS NULL OR resolved_dsld_value IS NOT NULL THEN
        RAISE EXCEPTION 'duplicate target mismatch' USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  IF p_to_status = 'approved' AND (
    p_approved_schema_version IS DISTINCT FROM 'manual_label_v1'
    OR p_approved_payload IS NULL
    OR jsonb_typeof(p_approved_payload) <> 'object'
    OR p_approved_payload_canonical IS NULL
    OR octet_length(p_approved_payload_canonical) NOT BETWEEN 2 AND 524288
    OR p_approved_payload_canonical::jsonb <> p_approved_payload
    OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
    OR encode(
      extensions.digest(p_approved_payload_canonical, 'sha256'),
      'hex'
    ) <> p_payload_sha256
  ) THEN
    RAISE EXCEPTION 'approved canonical payload required'
      USING ERRCODE = '22023';
  END IF;
  IF p_to_status <> 'approved' AND (
    p_approved_schema_version IS NOT NULL
    OR p_approved_payload IS NOT NULL
    OR p_approved_payload_canonical IS NOT NULL
    OR p_payload_sha256 IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'approved payload not allowed for this transition'
      USING ERRCODE = '22023';
  END IF;
  IF p_duplicate_of = p_submission_id THEN
    RAISE EXCEPTION 'submission cannot duplicate itself'
      USING ERRCODE = '22023';
  END IF;
  IF p_to_status = 'duplicate'
     AND resolution_code_value = 'duplicate_submission'
     AND NOT EXISTS (
    SELECT 1
    FROM public.product_submissions AS target
    LEFT JOIN public.product_submission_mismatch_details AS current_mismatch
      ON current_mismatch.submission_id = submission.id
    LEFT JOIN public.product_submission_mismatch_details AS target_mismatch
      ON target_mismatch.submission_id = target.id
    WHERE target.id = p_duplicate_of
      AND target.upload_state = 'ready'
      AND target.review_status = 'approved'
      AND target.kind = submission.kind
      AND (
        (
          submission.kind = 'missing_product'
          AND public.product_submission_canonical_gtin(target.normalized_upc)
            = public.product_submission_canonical_gtin(submission.normalized_upc)
        )
        OR (
          submission.kind = 'label_mismatch'
          AND target_mismatch.dsld_id = current_mismatch.dsld_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'duplicate target must be an approved matching submission'
      USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'approved' THEN
    review_target_key :=
      public.product_submission_review_target_key(p_submission_id);
    IF NULLIF(review_target_key, '') IS NULL THEN
      RAISE EXCEPTION 'review target identity is unavailable'
        USING ERRCODE = '55000';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(review_target_key, 0)
    );
    IF EXISTS (
      SELECT 1
      FROM public.product_submissions AS other
      WHERE other.id <> p_submission_id
        AND other.review_status = 'approved'
        AND other.promoted_at IS NULL
        AND public.product_submission_review_target_key(other.id)
          = review_target_key
    ) THEN
      RAISE EXCEPTION 'another approved submission awaits promotion'
        USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.product_submission_approved_labels (
      submission_id,
      schema_version,
      approved_payload,
      approved_payload_canonical,
      payload_sha256,
      reviewer_id
    ) VALUES (
      p_submission_id,
      p_approved_schema_version,
      p_approved_payload,
      p_approved_payload_canonical,
      p_payload_sha256,
      p_reviewer_id
    );
  END IF;

  INSERT INTO public.product_submission_review_events (
    submission_id,
    from_status,
    to_status,
    reviewer_id,
    review_notes,
    resolution_code,
    resolved_dsld_id
  ) VALUES (
    p_submission_id,
    submission.review_status,
    p_to_status,
    p_reviewer_id,
    NULLIF(btrim(p_review_notes), ''),
    resolution_code_value,
    resolved_dsld_value
  );

  UPDATE public.product_submissions
  SET review_status = p_to_status,
      reviewed_at = now(),
      reviewed_by = p_reviewer_id,
      duplicate_of = p_duplicate_of,
      resolution_code = resolution_code_value,
      resolution_detail = resolution_detail_value,
      resolved_dsld_id = resolved_dsld_value
  WHERE id = p_submission_id;

  INSERT INTO public.product_submission_push_deliveries (
    submission_id,
    user_id,
    to_status
  ) VALUES (
    p_submission_id,
    submission.user_id,
    p_to_status
  );

  RETURN true;
END;
$_$;


ALTER FUNCTION "public"."review_product_submission_human_internal"("p_submission_id" "uuid", "p_reviewer_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text", "p_approved_schema_version" "text", "p_approved_payload" "jsonb", "p_approved_payload_canonical" "text", "p_payload_sha256" "text", "p_duplicate_of" "uuid", "p_resolution_code" "text", "p_resolution_detail" "text", "p_resolved_dsld_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_product_submission_unchecked"("p_submission_id" "uuid", "p_to_status" "public"."product_submission_review_status", "p_review_notes" "text" DEFAULT NULL::"text", "p_approved_schema_version" "text" DEFAULT NULL::"text", "p_approved_payload" "jsonb" DEFAULT NULL::"jsonb", "p_approved_payload_canonical" "text" DEFAULT NULL::"text", "p_payload_sha256" "text" DEFAULT NULL::"text", "p_duplicate_of" "uuid" DEFAULT NULL::"uuid", "p_resolution_code" "text" DEFAULT NULL::"text", "p_resolution_detail" "text" DEFAULT NULL::"text", "p_resolved_dsld_id" "text" DEFAULT NULL::"text", "p_product_image_photo_id" "uuid" DEFAULT NULL::"uuid", "p_product_image_reviewer_object_id" "uuid" DEFAULT NULL::"uuid", "p_expected_evidence_revision" integer DEFAULT NULL::integer, "p_evidence_manifest_sha256" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  latest_match public.product_submission_match_checks%ROWTYPE;
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
    SELECT match_check.*
      INTO latest_match
    FROM public.product_submission_match_checks AS match_check
    WHERE match_check.submission_id = p_submission_id
    ORDER BY match_check.created_at DESC, match_check.id DESC
    LIMIT 1;
    IF NOT FOUND
       OR latest_match.outcome <> 'no_match_verified'
       OR latest_match.evidence_revision IS DISTINCT FROM submission.evidence_revision
       OR latest_match.index_built_at < now() - interval '60 days'
       OR latest_match.index_built_at > now() + interval '5 minutes'
       OR latest_match.canonical_gtin14 <> lpad(submission.normalized_upc, 14, '0') THEN
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

  IF p_to_status = 'approved' THEN
    -- Recorded before the transition, inside the same transaction: the
    -- transition decides which catalog record this approval contends for, and
    -- a correction contends for the record it rewrites. A refusal below rolls
    -- this back with everything else.
    UPDATE public.product_submissions
    SET correction_target_dsld_id = p_correction_target_dsld_id,
        edition_of_dsld_id = p_edition_of_dsld_id
    WHERE id = p_submission_id;
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

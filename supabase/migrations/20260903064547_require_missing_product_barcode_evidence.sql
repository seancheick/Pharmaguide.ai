-- Bind every missing-product submission to the scanned package with a
-- required barcode photo. The same category gate is used before upload,
-- during finalize, and again before an approved label can be recorded.

CREATE OR REPLACE FUNCTION public.product_submission_has_required_evidence(
  p_submission_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (
    SELECT count(DISTINCT category) = 4
    FROM public.product_submission_photos AS photo,
         unnest(photo.categories) AS category
    WHERE photo.submission_id = p_submission_id
      AND photo.user_id = p_user_id
      AND category IN (
        'front_identity',
        'supplement_facts',
        'ingredient_disclosure',
        'barcode'
      )
  );
$$;

-- Preserve the existing owner-scoped lineage boundary while allowing a user
-- to correct a reviewer-confirmed identity mismatch with fresh evidence.
CREATE OR REPLACE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_resubmission_of uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  target_submission public.product_submissions%ROWTYPE;
  existing_lineage uuid;
  had_existing boolean := false;
  persisted_count integer := 0;
  result_value boolean;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission id required' USING ERRCODE = '22023';
  END IF;
  IF p_resubmission_of = p_submission_id THEN
    RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
  END IF;

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[^0-9]',
    '',
    'g'
  ), '');

  IF p_resubmission_of IS NOT NULL THEN
    SELECT target.*
      INTO target_submission
    FROM public.product_submissions AS target
    WHERE target.id = p_resubmission_of
      AND target.user_id = caller_id
      AND target.review_status = 'rejected'
      AND target.resolution_code IN (
        'photo_quality',
        'missing_panel',
        'label_unreadable',
        'product_identity_mismatch',
        'other'
      )
      AND target.kind = p_kind
      AND target.normalized_upc IS NOT DISTINCT FROM normalized_upc_value
    FOR SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'label_mismatch' AND NOT EXISTS (
      SELECT 1
      FROM public.product_submission_mismatch_details AS target_detail
      WHERE target_detail.submission_id = p_resubmission_of
        AND target_detail.user_id = caller_id
        AND target_detail.dsld_id = btrim(p_mismatch_detail->>'dsld_id')
    ) THEN
      RAISE EXCEPTION 'invalid resubmission lineage' USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT submission.resubmission_of
    INTO existing_lineage
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
    AND submission.user_id = caller_id
  FOR UPDATE;
  had_existing := FOUND;
  IF had_existing
     AND existing_lineage IS DISTINCT FROM p_resubmission_of THEN
    RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
  END IF;

  result_value := public.create_product_submission_v2_internal(
    p_submission_id,
    p_kind,
    p_upc,
    p_mismatch_detail,
    p_no_separate_ingredient_panel,
    p_photos
  );

  IF NOT had_existing THEN
    UPDATE public.product_submissions AS submission
    SET resubmission_of = p_resubmission_of
    WHERE submission.id = p_submission_id
      AND submission.user_id = caller_id
      AND (
        submission.resubmission_of IS NULL
        OR submission.resubmission_of IS NOT DISTINCT FROM p_resubmission_of
      );
    GET DIAGNOSTICS persisted_count = ROW_COUNT;
    IF persisted_count <> 1 THEN
      RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
    END IF;
  END IF;

  RETURN result_value;
END;
$$;

-- Preserve the mature review transaction, adding only the new typed,
-- retakeable rejection code.
CREATE OR REPLACE FUNCTION public.review_product_submission_human_internal(
  p_submission_id uuid,
  p_reviewer_id uuid,
  p_to_status public.product_submission_review_status,
  p_review_notes text DEFAULT NULL,
  p_approved_schema_version text DEFAULT NULL,
  p_approved_payload jsonb DEFAULT NULL,
  p_approved_payload_canonical text DEFAULT NULL,
  p_payload_sha256 text DEFAULT NULL,
  p_duplicate_of uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_detail text DEFAULT NULL,
  p_resolved_dsld_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
          AND target.normalized_upc = submission.normalized_upc
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
    IF submission.kind = 'label_mismatch' THEN
      SELECT 'label_mismatch:' || mismatch.dsld_id
        INTO review_target_key
      FROM public.product_submission_mismatch_details AS mismatch
      WHERE mismatch.submission_id = p_submission_id;
    ELSE
      review_target_key := 'missing_product:' || submission.normalized_upc;
    END IF;
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
      LEFT JOIN public.product_submission_mismatch_details AS other_mismatch
        ON other_mismatch.submission_id = other.id
      WHERE other.id <> p_submission_id
        AND other.review_status = 'approved'
        AND other.promoted_at IS NULL
        AND (
          CASE other.kind
            WHEN 'label_mismatch' THEN
              'label_mismatch:' || other_mismatch.dsld_id
            ELSE 'missing_product:' || other.normalized_upc
          END
        ) = review_target_key
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
$$;

-- Approval backstop for rows submitted before barcode evidence became
-- mandatory. This prevents a legacy ready row from bypassing the new gate.
CREATE OR REPLACE FUNCTION public.enforce_approved_submission_identity_evidence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
BEGIN
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = NEW.submission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '55000';
  END IF;
  IF submission.kind = 'missing_product'
     AND NOT public.product_submission_has_required_evidence(
       submission.id,
       submission.user_id
     ) THEN
    RAISE EXCEPTION 'barcode-bound evidence required before approval'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS approved_submission_identity_evidence
  ON public.product_submission_approved_labels;
CREATE TRIGGER approved_submission_identity_evidence
BEFORE INSERT OR UPDATE ON public.product_submission_approved_labels
FOR EACH ROW
EXECUTE FUNCTION public.enforce_approved_submission_identity_evidence();

REVOKE ALL ON FUNCTION public.enforce_approved_submission_identity_evidence()
  FROM PUBLIC, anon, authenticated, service_role;

-- Audited correction cycle for human-approved product submissions.
-- Approval payloads are append-only revisions; release promotion is fenced to
-- the exact revision and payload hash that the pipeline imported.

ALTER TABLE public.product_submissions
  ADD COLUMN approval_revision integer NOT NULL DEFAULT 0
    CHECK (approval_revision >= 0),
  ADD COLUMN promoted_approval_revision integer NOT NULL DEFAULT 0
    CHECK (promoted_approval_revision >= 0);

ALTER TABLE public.product_submission_approved_labels
  ADD COLUMN approval_revision integer,
  ADD COLUMN target_dsld_id text,
  ADD COLUMN correction_target_dsld_id text,
  ADD COLUMN edition_of_dsld_id text,
  ADD COLUMN promoted_catalog_version text,
  ADD COLUMN promoted_dsld_id text,
  ADD COLUMN promoted_at timestamptz;

UPDATE public.product_submission_approved_labels AS approved
SET approval_revision = 1,
    target_dsld_id = mismatch.dsld_id,
    correction_target_dsld_id = submission.correction_target_dsld_id,
    edition_of_dsld_id = submission.edition_of_dsld_id,
    promoted_catalog_version = submission.promoted_catalog_version,
    promoted_dsld_id = submission.resolved_dsld_id,
    promoted_at = submission.promoted_at
FROM public.product_submissions AS submission
LEFT JOIN public.product_submission_mismatch_details AS mismatch
  ON mismatch.submission_id = submission.id
WHERE submission.id = approved.submission_id;

UPDATE public.product_submissions AS submission
SET approval_revision = 1,
    promoted_approval_revision = CASE
      WHEN submission.promoted_at IS NOT NULL
        OR submission.promoted_catalog_version IS NOT NULL THEN 1
      ELSE 0
    END
WHERE EXISTS (
  SELECT 1 FROM public.product_submission_approved_labels AS approved
  WHERE approved.submission_id = submission.id
);

ALTER TABLE public.product_submission_approved_labels
  ALTER COLUMN approval_revision SET NOT NULL,
  DROP CONSTRAINT product_submission_approved_labels_pkey,
  ADD PRIMARY KEY (submission_id, approval_revision),
  ADD CONSTRAINT product_submission_approval_revision_positive
    CHECK (approval_revision >= 1),
  ADD CONSTRAINT product_submission_approval_catalog_relation_singular
    CHECK (num_nonnulls(correction_target_dsld_id, edition_of_dsld_id) <= 1),
  ADD CONSTRAINT product_submission_approval_promotion_complete CHECK (
    num_nonnulls(promoted_catalog_version, promoted_dsld_id, promoted_at)
      IN (0, 3)
  );

ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submission_promoted_revision_not_future
  CHECK (promoted_approval_revision <= approval_revision);

-- A versioned catalog path is immutable for its entire lifetime, not merely
-- while that version is current. Reject any attempt to reuse historical
-- v<db_version>/ storage paths.
CREATE UNIQUE INDEX export_manifest_db_version_unique
  ON public.export_manifest (db_version);

CREATE FUNCTION public.preserve_product_submission_catalog_metadata()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.promoted_approval_revision > 0
     AND NEW.promoted_approval_revision = OLD.promoted_approval_revision THEN
    NEW.promoted_catalog_version := OLD.promoted_catalog_version;
    NEW.promoted_at := OLD.promoted_at;
    NEW.resolved_dsld_id := coalesce(NEW.resolved_dsld_id, OLD.resolved_dsld_id);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.preserve_product_submission_catalog_metadata()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER product_submission_catalog_metadata_preserved
BEFORE UPDATE ON public.product_submissions
FOR EACH ROW EXECUTE FUNCTION public.preserve_product_submission_catalog_metadata();

-- A promoted catalog row remains live while its next revision is being
-- corrected, so the lifecycle constraints must admit that one audited state.
ALTER TABLE public.product_submissions
  DROP CONSTRAINT product_submissions_promotion_consistent,
  DROP CONSTRAINT product_submissions_resolved_dsld_consistent;
ALTER TABLE public.product_submissions
  ADD CONSTRAINT product_submissions_promotion_consistent CHECK (
    (promoted_catalog_version IS NULL AND promoted_at IS NULL)
    OR (
      review_status IN ('approved', 'duplicate', 'under_review')
      AND promoted_catalog_version IS NOT NULL
      AND promoted_at IS NOT NULL
      AND (
        review_status <> 'under_review'
        OR promoted_approval_revision > 0
      )
    )
  ),
  ADD CONSTRAINT product_submissions_resolved_dsld_consistent CHECK (
    resolved_dsld_id IS NULL
    OR review_status IN ('approved', 'duplicate', 'under_review')
  );

CREATE INDEX idx_product_submission_approvals_current
  ON public.product_submission_approved_labels
  (submission_id, approval_revision DESC);

-- Evidence remains one system. The owner column continues to identify whose
-- submission the private object belongs to; these columns record who supplied
-- the bytes and through which path.
ALTER TABLE public.product_submission_photos
  -- Keep immutable provenance even if the uploader account is later deleted.
  -- This intentionally is not a foreign key: changing this value would also
  -- change the frozen evidence manifest for an approved revision.
  ADD COLUMN uploader_id uuid,
  ADD COLUMN uploader_role text NOT NULL DEFAULT 'submitter'
    CHECK (uploader_role IN ('submitter', 'reviewer'));
UPDATE public.product_submission_photos
SET uploader_id = user_id
WHERE uploader_id IS NULL;

CREATE FUNCTION public.default_product_submission_photo_uploader()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.uploader_id := coalesce(NEW.uploader_id, NEW.user_id);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.default_product_submission_photo_uploader()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER product_submission_photo_uploader_defaulted
BEFORE INSERT ON public.product_submission_photos
FOR EACH ROW EXECUTE FUNCTION public.default_product_submission_photo_uploader();
ALTER TABLE public.product_submission_photos
  ALTER COLUMN uploader_id SET NOT NULL;

-- Keep every already-frozen manifest byte-for-byte. New revisions use v2,
-- whose digest also binds uploader provenance; the record builder selects the
-- correct schema for each immutable evidence revision.
ALTER TABLE public.product_submission_evidence_revisions
  ADD COLUMN manifest_schema_version text;
UPDATE public.product_submission_evidence_revisions
SET manifest_schema_version = 'evidence_manifest_v1';
ALTER TABLE public.product_submission_evidence_revisions
  ALTER COLUMN manifest_schema_version SET DEFAULT 'evidence_manifest_v2',
  ALTER COLUMN manifest_schema_version SET NOT NULL,
  ADD CONSTRAINT product_submission_evidence_manifest_schema_known
    CHECK (manifest_schema_version IN (
      'evidence_manifest_v1', 'evidence_manifest_v2'));

CREATE OR REPLACE FUNCTION public.product_submission_evidence_records(
  p_submission_id uuid,
  p_revision integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(
    CASE revision.manifest_schema_version
      WHEN 'evidence_manifest_v1' THEN jsonb_build_object(
        'photo_id', photo.photo_id,
        'seq', photo.seq,
        'revision', photo.revision,
        'categories', photo.categories,
        'object_path', photo.object_path,
        'content_type', photo.content_type,
        'byte_size', photo.byte_size,
        'content_sha256', photo.content_sha256)
      ELSE jsonb_build_object(
        'photo_id', photo.photo_id,
        'seq', photo.seq,
        'revision', photo.revision,
        'categories', photo.categories,
        'object_path', photo.object_path,
        'content_type', photo.content_type,
        'byte_size', photo.byte_size,
        'content_sha256', photo.content_sha256,
        'uploader_id', photo.uploader_id,
        'uploader_role', photo.uploader_role)
    END ORDER BY photo.photo_id), '[]'::jsonb)
  FROM public.product_submission_evidence_revisions AS revision
  JOIN public.product_submission_photos AS photo
    ON photo.submission_id = revision.submission_id
   AND photo.photo_id = ANY(revision.photo_ids)
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_evidence_records(uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.stamp_product_submission_approval_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE submission public.product_submissions%ROWTYPE;
BEGIN
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = NEW.submission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission required' USING ERRCODE = '23503';
  END IF;
  NEW.approval_revision := submission.approval_revision + 1;
  SELECT mismatch.dsld_id INTO NEW.target_dsld_id
  FROM public.product_submission_mismatch_details AS mismatch
  WHERE mismatch.submission_id = NEW.submission_id;
  NEW.correction_target_dsld_id := submission.correction_target_dsld_id;
  NEW.edition_of_dsld_id := submission.edition_of_dsld_id;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.stamp_product_submission_approval_revision()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER product_submission_approval_revision_stamp
BEFORE INSERT ON public.product_submission_approved_labels
FOR EACH ROW EXECUTE FUNCTION public.stamp_product_submission_approval_revision();

CREATE FUNCTION public.advance_product_submission_approval_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.product_submissions
  SET approval_revision = NEW.approval_revision
  WHERE id = NEW.submission_id
    AND approval_revision = NEW.approval_revision - 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval revision changed' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.advance_product_submission_approval_revision()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER product_submission_approval_revision_advance
AFTER INSERT ON public.product_submission_approved_labels
FOR EACH ROW EXECUTE FUNCTION public.advance_product_submission_approval_revision();

CREATE FUNCTION public.protect_product_submission_approval_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE current_revision integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'approval revisions are immutable' USING ERRCODE = '55000';
  END IF;

  SELECT approval_revision INTO current_revision
  FROM public.product_submissions
  WHERE id = OLD.submission_id;

  -- The existing approval transition writes the chosen image/evidence after
  -- inserting the row in the same transaction. Permit that single fill only.
  IF OLD.approval_revision = current_revision
     AND OLD.evidence_revision IS NULL
     AND NEW.evidence_revision IS NOT NULL
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id, NEW.promoted_catalog_version,
       NEW.promoted_dsld_id, NEW.promoted_at
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id, OLD.promoted_catalog_version,
       OLD.promoted_dsld_id, OLD.promoted_at
     ) THEN
    RETURN NEW;
  END IF;

  -- A promotion stamps an approval once; payload, evidence, identity and
  -- reviewer remain byte-for-byte immutable.
  IF OLD.promoted_at IS NULL
     AND NEW.promoted_at IS NOT NULL
     AND NEW.promoted_catalog_version IS NOT NULL
     AND NEW.promoted_dsld_id IS NOT NULL
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.approved_product_image_photo_id,
       NEW.approved_product_image_reviewer_object_id,
       NEW.evidence_revision, NEW.evidence_manifest_sha256,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.approved_product_image_photo_id,
       OLD.approved_product_image_reviewer_object_id,
       OLD.evidence_revision, OLD.evidence_manifest_sha256,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id
     ) THEN
    RETURN NEW;
  END IF;

  -- The legacy approval function addresses all rows for a submission when it
  -- fills evidence. Older revisions ignore that mechanical update.
  IF OLD.approval_revision < current_revision
     AND ROW(
       NEW.submission_id, NEW.approval_revision, NEW.schema_version,
       NEW.approved_payload, NEW.approved_payload_canonical,
       NEW.payload_sha256, NEW.reviewer_id, NEW.approved_at,
       NEW.target_dsld_id, NEW.correction_target_dsld_id,
       NEW.edition_of_dsld_id, NEW.promoted_catalog_version,
       NEW.promoted_dsld_id, NEW.promoted_at
     ) IS NOT DISTINCT FROM ROW(
       OLD.submission_id, OLD.approval_revision, OLD.schema_version,
       OLD.approved_payload, OLD.approved_payload_canonical,
       OLD.payload_sha256, OLD.reviewer_id, OLD.approved_at,
       OLD.target_dsld_id, OLD.correction_target_dsld_id,
       OLD.edition_of_dsld_id, OLD.promoted_catalog_version,
       OLD.promoted_dsld_id, OLD.promoted_at
     ) THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'approval revisions are immutable' USING ERRCODE = '55000';
END;
$$;
REVOKE ALL ON FUNCTION public.protect_product_submission_approval_revision()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER product_submission_approval_revision_immutable
BEFORE UPDATE OR DELETE ON public.product_submission_approved_labels
FOR EACH ROW EXECUTE FUNCTION public.protect_product_submission_approval_revision();

CREATE FUNCTION public.reopen_product_submission_approval(
  p_submission_id uuid,
  p_expected_approval_revision integer,
  p_expected_payload_sha256 text,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  approved public.product_submission_approved_labels%ROWTYPE;
  reason_value text := NULLIF(btrim(regexp_replace(
    coalesce(p_reason, ''), '[\x00-\x1F\x7F]', '', 'g')), '');
  latest_event public.product_submission_review_events%ROWTYPE;
BEGIN
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF reason_value IS NULL THEN
    RAISE EXCEPTION 'correction reason required' USING ERRCODE = '22023';
  END IF;
  IF char_length(reason_value) > 2000 THEN
    RAISE EXCEPTION 'correction reason too long' USING ERRCODE = '22023';
  END IF;
  IF p_expected_approval_revision IS NULL
     OR p_expected_payload_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'expected approval required' USING ERRCODE = '22023';
  END IF;

  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready'
     OR submission.cleanup_claimed_at IS NOT NULL THEN
    RAISE EXCEPTION 'ready submission required' USING ERRCODE = '55000';
  END IF;
  SELECT candidate.* INTO approved
  FROM public.product_submission_approved_labels AS candidate
  WHERE candidate.submission_id = p_submission_id
    AND candidate.approval_revision = p_expected_approval_revision;
  IF NOT FOUND
     OR submission.approval_revision <> p_expected_approval_revision
     OR approved.payload_sha256 <> p_expected_payload_sha256 THEN
    RAISE EXCEPTION 'approval changed since review' USING ERRCODE = '55000';
  END IF;

  IF submission.review_status = 'under_review' THEN
    SELECT event.* INTO latest_event
    FROM public.product_submission_review_events AS event
    WHERE event.submission_id = p_submission_id
    ORDER BY event.created_at DESC, event.id DESC
    LIMIT 1;
    IF FOUND
       AND latest_event.from_status = 'approved'
       AND latest_event.to_status = 'under_review'
       AND latest_event.reviewer_id = v_reviewer_id
       AND latest_event.review_notes = reason_value THEN
      RETURN true;
    END IF;
    RAISE EXCEPTION 'approval already reopened' USING ERRCODE = '55000';
  END IF;
  IF submission.review_status <> 'approved' THEN
    RAISE EXCEPTION 'approved submission required' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.product_submission_review_events(
    submission_id, from_status, to_status, reviewer_id, review_notes)
  VALUES (p_submission_id, 'approved', 'under_review', v_reviewer_id, reason_value);

  UPDATE public.product_submissions
  SET review_status = 'under_review',
      reviewed_at = now(),
      reviewed_by = v_reviewer_id
  WHERE id = p_submission_id;

  INSERT INTO public.product_submission_reviewer_drafts(
    submission_id, reviewer_id, evidence_revision,
    evidence_manifest_sha256, payload, payload_canonical, payload_sha256,
    product_image
  ) VALUES (
    p_submission_id, v_reviewer_id, approved.evidence_revision,
    approved.evidence_manifest_sha256, approved.approved_payload,
    approved.approved_payload_canonical, approved.payload_sha256,
    CASE
      WHEN approved.approved_product_image_photo_id IS NOT NULL THEN
        jsonb_build_object('kind','photo','id',
          approved.approved_product_image_photo_id,
          'evidence_revision', approved.evidence_revision,
          'manifest', approved.evidence_manifest_sha256)
      WHEN approved.approved_product_image_reviewer_object_id IS NOT NULL THEN
        jsonb_build_object('kind','reviewer','id',
          approved.approved_product_image_reviewer_object_id,
          'evidence_revision', approved.evidence_revision,
          'manifest', approved.evidence_manifest_sha256)
      ELSE NULL
    END
  )
  ON CONFLICT (submission_id, reviewer_id) DO UPDATE SET
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
    payload = EXCLUDED.payload,
    payload_canonical = EXCLUDED.payload_canonical,
    payload_sha256 = EXCLUDED.payload_sha256,
    product_image = EXCLUDED.product_image,
    updated_at = now();

  DELETE FROM public.product_submission_field_verifications
  WHERE submission_id = p_submission_id;

  INSERT INTO public.product_submission_push_deliveries(
    submission_id, user_id, to_status)
  VALUES (p_submission_id, submission.user_id, 'under_review');
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.reopen_product_submission_approval(
  uuid, integer, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reopen_product_submission_approval(
  uuid, integer, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.load_product_submission_reviewer_draft(
  p_submission_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  reviewer uuid:=public.assert_product_submission_reviewer();
  result jsonb; picture jsonb; approved jsonb; current_revision integer;
BEGIN
  result:=public.product_submission_reviewer_state_internal(p_submission_id,reviewer);
  current_revision:=coalesce((result->>'approval_revision')::integer,
    (SELECT approval_revision FROM public.product_submissions WHERE id=p_submission_id));
  SELECT product_image INTO picture FROM public.product_submission_reviewer_drafts
    WHERE submission_id=p_submission_id AND reviewer_id=reviewer;
  IF picture->>'evidence_revision' IS DISTINCT FROM result->>'current_evidence_revision'
    OR picture->>'manifest' IS DISTINCT FROM result->>'current_evidence_manifest_sha256' THEN
    picture:=NULL;
  END IF;
  IF current_revision > 0 THEN
    SELECT jsonb_build_object('approval_revision',approval_revision,
      'approved_payload',approved_payload,'payload_sha256',payload_sha256,
      'approved_at',approved_at,'product_image_photo_id',approved_product_image_photo_id,
      'product_image_reviewer_object_id',approved_product_image_reviewer_object_id)
      INTO approved FROM public.product_submission_approved_labels
      WHERE submission_id=p_submission_id AND approval_revision=current_revision;
  END IF;
  IF result->>'review_status'='approved' THEN
    picture:=CASE WHEN approved->>'product_image_reviewer_object_id' IS NOT NULL THEN
      jsonb_build_object('kind','reviewer','id',approved->>'product_image_reviewer_object_id')
      WHEN approved->>'product_image_photo_id' IS NOT NULL THEN
      jsonb_build_object('kind','photo','id',approved->>'product_image_photo_id') ELSE NULL END;
  END IF;
  RETURN result || jsonb_build_object('approved_label',approved,'product_image',picture,
    'reviewer_images',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'object_id',image.object_id,'object_path',image.object_path))
      FROM public.product_submission_reviewer_images image
      WHERE image.submission_id=p_submission_id
      AND image.evidence_revision=(result->>'current_evidence_revision')::integer
      AND (image.reviewer_id=reviewer OR image.object_id::text=approved->>'product_image_reviewer_object_id')
      AND EXISTS (SELECT 1 FROM storage.objects object WHERE object.bucket_id='product-submission-reviewer-images'
        AND object.name=image.object_path)), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.load_product_submission_reviewer_draft(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.load_product_submission_reviewer_draft(uuid)
  TO authenticated;

CREATE FUNCTION public.create_product_submission_reviewer_evidence_revision(
  p_submission_id uuid,
  p_expected_approval_revision integer,
  p_expected_payload_sha256 text,
  p_request_key uuid,
  p_photos jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  existing public.product_submission_evidence_revisions%ROWTYPE;
  next_revision integer;
  uploads jsonb;
  persisted_manifest jsonb;
BEGIN
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF p_request_key IS NULL THEN
    RAISE EXCEPTION 'request key required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND OR submission.review_status <> 'under_review'
     OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.approval_revision <> p_expected_approval_revision
     OR NOT EXISTS (
       SELECT 1 FROM public.product_submission_approved_labels AS approved
       WHERE approved.submission_id = p_submission_id
         AND approved.approval_revision = p_expected_approval_revision
         AND approved.payload_sha256 = p_expected_payload_sha256
     ) THEN
    RAISE EXCEPTION 'approval changed since review' USING ERRCODE = '55000';
  END IF;

  SELECT revision.* INTO existing
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.request_key = p_request_key;
  IF FOUND THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'photo_id', photo.photo_id,
      'seq', photo.seq,
      'categories', to_jsonb(photo.categories),
      'content_type', photo.content_type,
      'byte_size', photo.byte_size,
      'content_sha256', photo.content_sha256
    ) ORDER BY photo.seq), '[]'::jsonb) INTO persisted_manifest
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = existing.revision
      AND photo.uploader_id = v_reviewer_id
      AND photo.uploader_role = 'reviewer';
    IF persisted_manifest <> p_photos THEN
      RAISE EXCEPTION 'reviewer evidence replay conflict'
        USING ERRCODE = '23505';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'photo_id', photo.photo_id,
      'object_path', photo.object_path
    ) ORDER BY photo.seq), '[]'::jsonb) INTO uploads
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = existing.revision
      AND photo.uploader_id = v_reviewer_id
      AND photo.uploader_role = 'reviewer';
    RETURN jsonb_build_object(
      'evidence_revision', existing.revision,
      'uploads', uploads
    );
  END IF;

  IF submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'replacement evidence upload already pending'
      USING ERRCODE = '55000';
  END IF;

  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_photos) NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  next_revision := submission.evidence_revision + 1;
  INSERT INTO public.product_submission_evidence_revisions(
    submission_id, revision, request_key, opened_by, photo_ids,
    consent_version, consented_at
  ) VALUES (
    p_submission_id, next_revision, p_request_key, v_reviewer_id, '{}'::uuid[],
    submission.consent_version, submission.consented_at
  );
  UPDATE public.product_submissions
  SET evidence_revision = next_revision,
      evidence_revision_opened_at = now(),
      upload_state = 'pending',
      cleanup_claimed_at = NULL,
      cleanup_claim_token = NULL
  WHERE id = p_submission_id;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id, submission.user_id, p_photos, next_revision);
  UPDATE public.product_submission_photos
  SET uploader_id = v_reviewer_id,
      uploader_role = 'reviewer'
  WHERE submission_id = p_submission_id
    AND revision = next_revision;
  DELETE FROM public.product_submission_field_verifications
  WHERE submission_id = p_submission_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'photo_id', photo.photo_id,
    'object_path', photo.object_path
  ) ORDER BY photo.seq), '[]'::jsonb) INTO uploads
  FROM public.product_submission_photos AS photo
  WHERE photo.submission_id = p_submission_id
    AND photo.revision = next_revision;
  RETURN jsonb_build_object(
    'evidence_revision', next_revision,
    'uploads', uploads
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_product_submission_reviewer_evidence_revision(
  uuid, integer, text, uuid, jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission_reviewer_evidence_revision(
  uuid, integer, text, uuid, jsonb) TO authenticated;

CREATE FUNCTION public.get_product_submission_reviewer_evidence_revision(
  p_submission_id uuid,
  p_evidence_revision integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  records jsonb;
BEGIN
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id;
  IF submission.id IS NULL
     OR submission.review_status <> 'under_review'
     OR submission.evidence_revision <> p_evidence_revision
     OR NOT EXISTS (
       SELECT 1 FROM public.product_submission_photos AS photo
       WHERE photo.submission_id = p_submission_id
         AND photo.revision = p_evidence_revision
         AND photo.uploader_role = 'reviewer'
     ) THEN
    RAISE EXCEPTION 'current reviewer evidence required'
      USING ERRCODE = '55000';
  END IF;
  records := public.product_submission_evidence_records(
    p_submission_id, p_evidence_revision);
  RETURN jsonb_build_object(
    'evidence_revision', p_evidence_revision,
    'manifest_sha256', public.product_submission_manifest_sha256(records),
    'evidence_snapshot', '{}'::jsonb,
    'photos', records
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_product_submission_reviewer_evidence_revision(
  uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_submission_reviewer_evidence_revision(
  uuid, integer) TO service_role;

CREATE FUNCTION public.finalize_product_submission_reviewer_evidence_revision(
  p_submission_id uuid,
  p_evidence_revision integer,
  p_manifest_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  v_revision public.product_submission_evidence_revisions%ROWTYPE;
  records jsonb;
  manifest_hash text;
BEGIN
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  SELECT candidate.* INTO v_revision
  FROM public.product_submission_evidence_revisions AS candidate
  WHERE candidate.submission_id = p_submission_id
    AND candidate.revision = p_evidence_revision
  FOR UPDATE;
  IF submission.id IS NULL OR v_revision.submission_id IS NULL
     OR submission.review_status <> 'under_review'
     OR submission.evidence_revision <> p_evidence_revision
     OR v_revision.abandoned_at IS NOT NULL THEN
    RAISE EXCEPTION 'current correction evidence required'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.ready_at IS NOT NULL THEN
    IF v_revision.manifest_sha256 = p_manifest_sha256 THEN RETURN true; END IF;
    RAISE EXCEPTION 'evidence revision already finalized'
      USING ERRCODE = '23505';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    LEFT JOIN storage.objects AS object
      ON object.bucket_id = 'product-submission-photos'
     AND object.name = photo.object_path
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = p_evidence_revision
      AND (
        object.name IS NULL
        OR coalesce((object.metadata->>'size')::bigint, -1) <> photo.byte_size
        OR coalesce(object.metadata->>'mimetype', '') <> photo.content_type
        OR coalesce(object.user_metadata->>'content_sha256', '')
             <> photo.content_sha256
      )
  ) THEN
    RAISE EXCEPTION 'reviewer evidence bytes are incomplete'
      USING ERRCODE = '55000';
  END IF;
  IF NOT public.product_submission_has_required_evidence(
    p_submission_id, submission.user_id) THEN
    RAISE EXCEPTION 'complete replacement evidence required'
      USING ERRCODE = '55000';
  END IF;
  records := public.product_submission_evidence_records(
    p_submission_id, p_evidence_revision);
  manifest_hash := public.product_submission_manifest_sha256(records);
  IF manifest_hash <> p_manifest_sha256 THEN
    RAISE EXCEPTION 'evidence manifest changed' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submission_evidence_revisions
  SET ready_at = now(), manifest = records, manifest_sha256 = manifest_hash
  WHERE submission_id = p_submission_id
    AND revision = p_evidence_revision;
  UPDATE public.product_submissions
  SET upload_state = 'ready',
      evidence_purged_at = NULL,
      evidence_revision_opened_at = NULL,
      evidence_requested_at = NULL,
      evidence_requested_revision = NULL,
      evidence_request_reason = NULL,
      evidence_request_panels = NULL
  WHERE id = p_submission_id;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_product_submission_reviewer_evidence_revision(
  uuid, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission_reviewer_evidence_revision(
  uuid, integer, text) TO service_role;

-- Exact approval assertion used by every release-side read and write.
CREATE FUNCTION public.assert_product_submission_approval_revision(
  p_submission_id uuid,
  p_approval_revision integer,
  p_payload_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.product_submissions AS submission
    JOIN public.product_submission_approved_labels AS approved
      ON approved.submission_id = submission.id
     AND approved.approval_revision = p_approval_revision
    JOIN public.product_submission_evidence_revisions AS revision
      ON revision.submission_id = submission.id
     AND revision.revision = approved.evidence_revision
    WHERE submission.id = p_submission_id
      AND submission.upload_state = 'ready'
      AND (
        submission.review_status = 'approved'
          AND submission.approval_revision = p_approval_revision
        OR submission.promoted_approval_revision = p_approval_revision
          AND approved.promoted_at IS NOT NULL
      )
      AND approved.payload_sha256 = p_payload_sha256
      AND revision.ready_at IS NOT NULL
      AND approved.evidence_manifest_sha256 = revision.manifest_sha256
      AND (
        submission.evidence_purged_at IS NOT NULL
          AND submission.promoted_approval_revision >= p_approval_revision
        OR revision.manifest = public.product_submission_evidence_records(
          submission.id, revision.revision)
      )
  ) THEN
    RAISE EXCEPTION 'approval changed' USING ERRCODE = '55000';
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_product_submission_approval_revision(
  uuid, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_product_submission_approval_revision(
  uuid, integer, text) TO service_role;

CREATE OR REPLACE FUNCTION public.assert_product_submission_approval(
  p_submission_id uuid
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE submission public.product_submissions%ROWTYPE; payload_hash text;
BEGIN
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate WHERE candidate.id=p_submission_id;
  SELECT approved.payload_sha256 INTO payload_hash
  FROM public.product_submission_approved_labels AS approved
  WHERE approved.submission_id=p_submission_id
    AND approved.approval_revision=submission.approval_revision;
  PERFORM public.assert_product_submission_approval_revision(
    p_submission_id, submission.approval_revision, payload_hash);
END;
$$;
REVOKE ALL ON FUNCTION public.assert_product_submission_approval(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION public.export_approved_product_submissions(
  integer, timestamptz, uuid);
DROP FUNCTION public.export_approved_product_submissions_internal(
  integer, timestamptz, uuid);

CREATE FUNCTION public.export_approved_product_submissions(
  p_limit integer DEFAULT 100,
  p_after_approved_at timestamptz DEFAULT NULL,
  p_after_submission_id uuid DEFAULT NULL
)
RETURNS TABLE(
  submission_id uuid,
  approval_revision integer,
  kind public.product_submission_kind,
  normalized_upc text,
  target_dsld_id text,
  schema_version text,
  approved_payload_canonical text,
  payload_sha256 text,
  reviewer_id uuid,
  approved_at timestamptz,
  correction_target_dsld_id text,
  edition_of_dsld_id text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE candidate record;
BEGIN
  FOR candidate IN
    SELECT submission.id AS submission_id,
      approved.approval_revision,
      submission.kind,
      submission.normalized_upc,
      approved.target_dsld_id,
      approved.schema_version,
      approved.approved_payload_canonical,
      approved.payload_sha256,
      approved.reviewer_id,
      approved.approved_at,
      approved.correction_target_dsld_id,
      approved.edition_of_dsld_id
    FROM public.product_submissions AS submission
    JOIN public.product_submission_approved_labels AS approved
      ON approved.submission_id = submission.id
     AND approved.approval_revision = submission.approval_revision
    WHERE submission.upload_state = 'ready'
      AND submission.review_status = 'approved'
      AND submission.approval_revision > submission.promoted_approval_revision
      AND (
        p_after_approved_at IS NULL AND p_after_submission_id IS NULL
        OR p_after_approved_at IS NOT NULL AND p_after_submission_id IS NOT NULL
          AND (approved.approved_at, submission.id) >
            (p_after_approved_at, p_after_submission_id)
      )
    ORDER BY approved.approved_at, submission.id
    LIMIT greatest(0, least(p_limit, 500))
  LOOP
    PERFORM public.assert_product_submission_approval_revision(
      candidate.submission_id, candidate.approval_revision,
      candidate.payload_sha256);
    RETURN QUERY SELECT
      candidate.submission_id,
      candidate.approval_revision,
      candidate.kind,
      candidate.normalized_upc,
      candidate.target_dsld_id,
      candidate.schema_version,
      candidate.approved_payload_canonical,
      candidate.payload_sha256,
      candidate.reviewer_id,
      candidate.approved_at,
      candidate.correction_target_dsld_id,
      candidate.edition_of_dsld_id;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.export_approved_product_submissions(
  integer, timestamptz, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_approved_product_submissions(
  integer, timestamptz, uuid) TO service_role;

DROP FUNCTION public.get_approved_product_submission_image(uuid);
CREATE FUNCTION public.get_approved_product_submission_image(
  p_submission_id uuid,
  p_approval_revision integer,
  p_payload_sha256 text
)
RETURNS TABLE(
  bucket_id text,
  object_path text,
  content_type text,
  content_sha256 text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.assert_product_submission_approval_revision(
    p_submission_id, p_approval_revision, p_payload_sha256);
  RETURN QUERY
  SELECT 'product-submission-photos'::text, photo.object_path,
    photo.content_type, photo.content_sha256
  FROM public.product_submission_approved_labels AS approved
  JOIN public.product_submission_photos AS photo
    ON photo.submission_id = approved.submission_id
   AND photo.photo_id = approved.approved_product_image_photo_id
  WHERE approved.submission_id = p_submission_id
    AND approved.approval_revision = p_approval_revision
  UNION ALL
  SELECT 'product-submission-reviewer-images'::text, image.object_path,
    image.content_type, image.content_sha256
  FROM public.product_submission_approved_labels AS approved
  JOIN public.product_submission_reviewer_images AS image
    ON image.submission_id = approved.submission_id
   AND image.object_id = approved.approved_product_image_reviewer_object_id
  WHERE approved.submission_id = p_submission_id
    AND approved.approval_revision = p_approval_revision;
END;
$$;
REVOKE ALL ON FUNCTION public.get_approved_product_submission_image(
  uuid, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_approved_product_submission_image(
  uuid, integer, text) TO service_role;

-- Revoked compatibility wrapper for old SQL fixtures and no external caller.
CREATE FUNCTION public.get_approved_product_submission_image(p_submission_id uuid)
RETURNS TABLE(bucket_id text, object_path text, content_type text,
  content_sha256 text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE revision integer; payload_hash text;
BEGIN
 SELECT submission.approval_revision, approved.payload_sha256
 INTO revision, payload_hash
 FROM public.product_submissions AS submission
 JOIN public.product_submission_approved_labels AS approved
   ON approved.submission_id=submission.id
  AND approved.approval_revision=submission.approval_revision
 WHERE submission.id=p_submission_id;
 RETURN QUERY SELECT * FROM public.get_approved_product_submission_image(
   p_submission_id,revision,payload_hash);
END $$;
REVOKE ALL ON FUNCTION public.get_approved_product_submission_image(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION public.mark_product_submission_promoted(uuid, text, text);
CREATE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid,
  p_approval_revision integer,
  p_payload_sha256 text,
  p_catalog_version text,
  p_resolved_dsld_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  submission public.product_submissions%ROWTYPE;
  catalog_version_value text := btrim(coalesce(p_catalog_version,''));
  resolved_dsld_value text := btrim(coalesce(p_resolved_dsld_id,''));
BEGIN
  IF catalog_version_value = '' THEN
    RAISE EXCEPTION 'catalog version required' USING ERRCODE='22023';
  END IF;
  IF resolved_dsld_value !~ '^([0-9]{1,30}|PG_SUB_[0-9A-F]{32})$' THEN
    RAISE EXCEPTION 'invalid resolved product id' USING ERRCODE='22023';
  END IF;
  SELECT candidate.* INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id=p_submission_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF submission.promoted_approval_revision = p_approval_revision THEN
    IF EXISTS (
      SELECT 1 FROM public.product_submission_approved_labels AS approved
      WHERE approved.submission_id=p_submission_id
        AND approved.approval_revision=p_approval_revision
        AND approved.payload_sha256=p_payload_sha256
        AND approved.promoted_catalog_version=catalog_version_value
        AND approved.promoted_dsld_id=resolved_dsld_value
    ) THEN RETURN true; END IF;
    IF submission.approval_revision <> p_approval_revision THEN
      RAISE EXCEPTION 'approval changed' USING ERRCODE='55000';
    END IF;
    RAISE EXCEPTION 'approval already promoted differently'
      USING ERRCODE='23505';
  END IF;
  PERFORM public.assert_product_submission_approval_revision(
    p_submission_id,p_approval_revision,p_payload_sha256);
  IF p_approval_revision <= submission.promoted_approval_revision THEN
    RAISE EXCEPTION 'approval revision is older than the promoted revision'
      USING ERRCODE='55000';
  END IF;
  UPDATE public.product_submission_approved_labels
  SET promoted_catalog_version=catalog_version_value,
      promoted_dsld_id=resolved_dsld_value,
      promoted_at=now()
  WHERE submission_id=p_submission_id
    AND approval_revision=p_approval_revision;
  UPDATE public.product_submissions
  SET promoted_approval_revision=p_approval_revision,
      promoted_catalog_version=catalog_version_value,
      promoted_at=now(),
      resolved_dsld_id=resolved_dsld_value
  WHERE id=p_submission_id;
  UPDATE public.product_submissions
  SET resolved_dsld_id=coalesce(resolved_dsld_id,resolved_dsld_value),
      promoted_catalog_version=catalog_version_value,
      promoted_at=now()
  WHERE duplicate_of=p_submission_id
    AND review_status='duplicate'
    AND promoted_catalog_version IS NULL;
  PERFORM public.award_product_contribution_points_internal(p_submission_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(
  uuid, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_product_submission_promoted(
  uuid, integer, text, text, text) TO service_role;

-- Revoked compatibility wrapper. The release client receives no grant and
-- must provide the exact revision/hash signature above.
CREATE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid, p_catalog_version text, p_resolved_dsld_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE revision integer; payload_hash text;
BEGIN
 SELECT submission.approval_revision, approved.payload_sha256
 INTO revision,payload_hash
 FROM public.product_submissions AS submission
 JOIN public.product_submission_approved_labels AS approved
  ON approved.submission_id=submission.id
 AND approved.approval_revision=submission.approval_revision
 WHERE submission.id=p_submission_id;
 RETURN public.mark_product_submission_promoted(
  p_submission_id,revision,payload_hash,p_catalog_version,p_resolved_dsld_id);
END $$;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(uuid,text,text)
  FROM PUBLIC, anon, authenticated, service_role;

-- One activation transaction owns both the public manifest pointer and every
-- submission promotion it proves. Staged storage objects are inert until this
-- function commits; reopen locks the same submission rows, so it orders wholly
-- before or wholly after publication.
CREATE FUNCTION public.rotate_manifest_with_submission_approvals(
  p_db_version text,
  p_pipeline_version text,
  p_scoring_version text,
  p_schema_version text,
  p_product_count integer,
  p_checksum text,
  p_generated_at timestamptz,
  p_min_app_version text DEFAULT '1.0.0',
  p_submission_approvals jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  new_id uuid;
  current_manifest public.export_manifest%ROWTYPE;
  item jsonb;
  sid uuid;
  revision integer;
  payload_hash text;
  resolved_id text;
BEGIN
  IF p_product_count < 0 THEN
    RAISE EXCEPTION 'product_count cannot be negative' USING ERRCODE='22023';
  END IF;
  IF jsonb_typeof(p_submission_approvals) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_submission_approvals) > 500 THEN
    RAISE EXCEPTION 'invalid submission approvals' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_submission_approvals) value
    WHERE jsonb_typeof(value) IS DISTINCT FROM 'object'
      OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(value) key)
        NOT IN (
          ARRAY['approval_revision','payload_sha256','submission_id']::text[],
          ARRAY['approval_revision','payload_sha256','resolved_dsld_id','submission_id']::text[]
        )
  ) THEN
    RAISE EXCEPTION 'invalid submission approval entry' USING ERRCODE='22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_submission_approvals))
     <> (SELECT count(DISTINCT value->>'submission_id')
         FROM jsonb_array_elements(p_submission_approvals) value) THEN
    RAISE EXCEPTION 'duplicate submission approval' USING ERRCODE='22023';
  END IF;

  -- Lock in deterministic order before validating any exact revision.
  PERFORM submission.id
  FROM public.product_submissions AS submission
  WHERE submission.id IN (
    SELECT (value->>'submission_id')::uuid
    FROM jsonb_array_elements(p_submission_approvals) value
  )
  ORDER BY submission.id
  FOR UPDATE;

  FOR item IN SELECT value FROM jsonb_array_elements(p_submission_approvals)
  LOOP
    BEGIN
      sid := (item->>'submission_id')::uuid;
      revision := (item->>'approval_revision')::integer;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid submission approval identity'
        USING ERRCODE='22023';
    END;
    payload_hash := item->>'payload_sha256';
    PERFORM public.assert_product_submission_approval_revision(
      sid, revision, payload_hash);
  END LOOP;

  SELECT manifest.* INTO current_manifest
  FROM public.export_manifest AS manifest
  WHERE manifest.db_version = p_db_version
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION 'catalog version was already used; use a fresh version'
      USING ERRCODE='55000';
  END IF;
  UPDATE public.export_manifest SET is_current=false WHERE is_current;
  INSERT INTO public.export_manifest(
    db_version,pipeline_version,scoring_version,schema_version,
    product_count,checksum,min_app_version,generated_at,is_current
  ) VALUES (
    p_db_version,p_pipeline_version,p_scoring_version,p_schema_version,
    p_product_count,p_checksum,p_min_app_version,p_generated_at,true
  ) RETURNING id INTO new_id;

  FOR item IN SELECT value FROM jsonb_array_elements(p_submission_approvals)
  LOOP
    resolved_id := nullif(item->>'resolved_dsld_id','');
    IF resolved_id IS NOT NULL THEN
      PERFORM public.mark_product_submission_promoted(
        (item->>'submission_id')::uuid,
        (item->>'approval_revision')::integer,
        item->>'payload_sha256',
        p_db_version,
        resolved_id);
    END IF;
  END LOOP;
  RETURN new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rotate_manifest_with_submission_approvals(
  text,text,text,text,integer,text,timestamptz,text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_manifest_with_submission_approvals(
  text,text,text,text,integer,text,timestamptz,text,jsonb)
  TO service_role;
-- The old entry point would bypass exact submission locking.
REVOKE ALL ON FUNCTION public.rotate_manifest(
  text,text,text,text,integer,text,timestamptz,text)
  FROM PUBLIC, anon, authenticated, service_role;

-- Retention may purge historical promoted evidence, but never the evidence a
-- correction is currently using or has approved for the next release.
CREATE OR REPLACE FUNCTION public.claim_product_submission_cleanup(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  submission_id uuid,
  evidence_object_paths text[],
  reviewer_object_paths text[],
  evidence_revision integer,
  claim_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid cleanup limit' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
  WITH candidates AS (
    SELECT submission.id
    FROM public.product_submissions AS submission
    WHERE (
      submission.upload_state IN ('pending', 'cleaning')
      AND CASE
            WHEN submission.evidence_revision > 1
              THEN submission.evidence_revision_opened_at
            ELSE submission.created_at
          END < now() - interval '24 hours'
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    ) OR (
      submission.review_status IN ('rejected', 'duplicate')
      AND submission.reviewed_at < now() - interval '90 days'
      AND submission.evidence_purged_at IS NULL
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    ) OR (
      submission.promoted_at < now() - interval '90 days'
      AND submission.evidence_purged_at IS NULL
      AND submission.review_status <> 'under_review'
      AND submission.approval_revision = submission.promoted_approval_revision
      AND (
        submission.cleanup_claimed_at IS NULL
        OR submission.cleanup_claimed_at < now() - interval '15 minutes'
      )
    )
    ORDER BY submission.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  ), claimed AS (
    UPDATE public.product_submissions AS submission
    SET upload_state = CASE
          WHEN submission.upload_state IN ('pending', 'cleaning')
            THEN 'cleaning'::public.product_submission_upload_state
          ELSE submission.upload_state
        END,
        cleanup_claimed_at = now(),
        cleanup_claim_token = gen_random_uuid()
    FROM candidates
    WHERE submission.id = candidates.id
    RETURNING submission.id, submission.upload_state,
      submission.evidence_revision, submission.cleanup_claim_token
  )
  SELECT
    claimed.id,
    ARRAY(
      SELECT photo.object_path
      FROM public.product_submission_photos AS photo
      WHERE photo.submission_id = claimed.id
        AND (
          claimed.upload_state <> 'cleaning'
          OR claimed.evidence_revision = 1
          OR photo.revision = claimed.evidence_revision
        )
      ORDER BY photo.object_path
    ),
    ARRAY(
      SELECT image.object_path
      FROM public.product_submission_reviewer_images AS image
      WHERE image.submission_id = claimed.id
        AND (claimed.upload_state <> 'cleaning' OR claimed.evidence_revision = 1)
      ORDER BY image.object_path
    ), claimed.evidence_revision, claimed.cleanup_claim_token
  FROM claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_product_submission_cleanup(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_cleanup(integer)
  TO service_role;

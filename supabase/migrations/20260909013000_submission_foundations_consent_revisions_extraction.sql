-- Submission foundations (Batch 1, 2026-09-09):
--   1. consent is recorded server-side at creation, against a registry of
--      recognized consent versions (copy hash and purposes per kind);
--   2. evidence is versioned by immutable revisions with explicit membership —
--      a retake appends photos under a new revision, never rewrites or
--      deletes the originals, and every consumer (finalize, extraction,
--      identity checks, approval, retention) reads the current revision;
--   3. draft recording derives the reviewer from auth.uid() and the DB
--      allowlist (the previous signature trusted a caller-supplied id and was
--      executable by service_role), binds the draft to the revision it read,
--      and carries usage.
-- No existing private image bytes, review events, or approved payloads are
-- changed. Legacy receipts gain revision provenance, never invented consent.

-- ---------------------------------------------------------------------------
-- 1. Consent recorded at creation, against a registry.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_consent_versions (
  version text NOT NULL CHECK (version ~ '^[A-Za-z0-9._-]{1,80}$'),
  kind public.product_submission_kind NOT NULL,
  purposes text[] NOT NULL CHECK (cardinality(purposes) BETWEEN 1 AND 10),
  copy_sha256 text NOT NULL CHECK (copy_sha256 ~ '^[0-9a-f]{64}$'),
  effective_from timestamptz NOT NULL,
  retired_at timestamptz,
  PRIMARY KEY (version, kind)
);
ALTER TABLE public.product_submission_consent_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_consent_versions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_consent_versions
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_submission_consent_versions TO service_role;

-- The pinned app copy (lib/features/contributions/product_submission_consent_copy.dart).
-- copy_sha256 = sha256 of the UTF-8 consent sentence the user accepts; the
-- app's safety-invariant test recomputes it from the Dart constant.
INSERT INTO public.product_submission_consent_versions
  (version, kind, purposes, copy_sha256, effective_from)
VALUES
  ('pharmaguide.submission_consent.2026-08-25.v1', 'missing_product',
   ARRAY['private_review', 'ai_label_draft', 'human_approval', 'front_photo_publication'],
   'e5881d7cb3f7b0606f5dd989689d10caf458ae9819bfba566a26e874414f0558',
   '2026-08-25T00:00:00Z'),
  ('pharmaguide.submission_consent.2026-08-25.v1', 'label_mismatch',
   ARRAY['private_review', 'ai_label_draft', 'human_approval', 'front_photo_publication'],
   '94dcb98d57f6e47e1eae2861f71820720d849bf962acb5a633c3e1194aee6f8e',
   '2026-08-25T00:00:00Z');

ALTER TABLE public.product_submissions
  ADD COLUMN consent_version text
    CHECK (consent_version IS NULL OR consent_version ~ '^[A-Za-z0-9._-]{1,80}$'),
  ADD COLUMN consented_at timestamptz
    CHECK ((consent_version IS NULL) = (consented_at IS NULL)),
  ADD CONSTRAINT product_submissions_consent_version_fkey
    FOREIGN KEY (consent_version, kind)
    REFERENCES public.product_submission_consent_versions(version, kind);

-- ---------------------------------------------------------------------------
-- 2. Evidence revisions with explicit membership.
-- ---------------------------------------------------------------------------

ALTER TABLE public.product_submissions
  ADD COLUMN evidence_revision integer NOT NULL DEFAULT 1
    CHECK (evidence_revision >= 1),
  ADD COLUMN evidence_revision_opened_at timestamptz,
  ADD COLUMN evidence_ready_at timestamptz,
  ADD COLUMN evidence_requested_at timestamptz,
  ADD COLUMN evidence_requested_by uuid,
  ADD COLUMN evidence_requested_revision integer,
  ADD COLUMN evidence_request_reason public.product_submission_resolution_code,
  ADD COLUMN cleanup_claim_token uuid;

-- The revision that introduced each photo. Sequence numbers restart per
-- revision so the eight-photo manifest cap applies to each retake, not to
-- the whole retained history.
ALTER TABLE public.product_submission_photos
  ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision >= 1);
ALTER TABLE public.product_submission_photos
  DROP CONSTRAINT product_submission_photos_seq_unique;
ALTER TABLE public.product_submission_photos
  ADD CONSTRAINT product_submission_photos_seq_unique
    UNIQUE (submission_id, revision, seq);

-- One row per evidence revision. `photo_ids` is the revision's membership:
-- photos explicitly kept from the previous revision plus photos appended
-- under this revision. It is frozen (manifest_sha256) when the revision is
-- finalized and never changes afterwards.
CREATE TABLE public.product_submission_evidence_revisions (
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  revision integer NOT NULL CHECK (revision >= 1),
  request_key uuid NOT NULL,
  opened_by uuid NOT NULL,
  opened_at timestamptz NOT NULL DEFAULT now(),
  photo_ids uuid[] NOT NULL DEFAULT '{}',
  kept_photo_ids uuid[] NOT NULL DEFAULT '{}',
  replaces_revision integer,
  consent_version text,
  consented_at timestamptz,
  manifest jsonb,
  ready_at timestamptz,
  manifest_sha256 text
    CHECK (manifest_sha256 IS NULL OR manifest_sha256 ~ '^[0-9a-f]{64}$'),
  abandoned_at timestamptz,
  PRIMARY KEY (submission_id, revision),
  CONSTRAINT product_submission_evidence_revisions_request_unique
    UNIQUE (submission_id, request_key),
  CONSTRAINT product_submission_evidence_revisions_state_check
    CHECK (ready_at IS NULL OR abandoned_at IS NULL),
  CONSTRAINT product_submission_evidence_revisions_manifest_check
    CHECK ((ready_at IS NULL) = (manifest_sha256 IS NULL))
);
ALTER TABLE public.product_submission_evidence_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_evidence_revisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_evidence_revisions
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_submission_evidence_revisions TO service_role;

ALTER TABLE public.product_submission_extractions
  ADD COLUMN actor_kind text NOT NULL DEFAULT 'reviewer'
    CHECK (actor_kind IN ('reviewer', 'worker')),
  ADD COLUMN evidence_revision integer
    CHECK (evidence_revision IS NULL OR evidence_revision >= 1);

ALTER TABLE public.product_submission_match_checks
  ADD COLUMN evidence_revision integer
    CHECK (evidence_revision IS NULL OR evidence_revision >= 1);

ALTER TABLE public.product_submission_approved_labels
  ADD COLUMN evidence_revision integer
    CHECK (evidence_revision IS NULL OR evidence_revision >= 1),
  ADD COLUMN evidence_manifest_sha256 text
    CHECK (evidence_manifest_sha256 IS NULL OR evidence_manifest_sha256 ~ '^[0-9a-f]{64}$');

-- The canonical manifest of one revision: {photo_id: content_sha256} over
-- its membership. Every consumer below reads evidence through this.
CREATE FUNCTION public.product_submission_evidence_manifest(
  p_submission_id uuid,
  p_revision integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_object_agg(photo.photo_id::text, photo.content_sha256),
    '{}'::jsonb
  )
  FROM public.product_submission_evidence_revisions AS revision
  JOIN public.product_submission_photos AS photo
    ON photo.submission_id = revision.submission_id
   AND photo.photo_id = ANY(revision.photo_ids)
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_evidence_manifest(uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.product_submission_manifest_sha256(p_manifest jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT encode(extensions.digest(convert_to(p_manifest::text, 'UTF8'), 'sha256'), 'hex');
$$;
REVOKE ALL ON FUNCTION public.product_submission_manifest_sha256(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- A role/category or ownership change matters just as much as new bytes.
-- The opaque digest of these full records is passed unchanged by clients.
CREATE FUNCTION public.product_submission_evidence_records(p_submission_id uuid, p_revision integer)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'photo_id', photo.photo_id, 'seq', photo.seq, 'revision', photo.revision,
    'categories', photo.categories, 'object_path', photo.object_path,
    'content_type', photo.content_type, 'byte_size', photo.byte_size,
    'content_sha256', photo.content_sha256
  ) ORDER BY photo.photo_id), '[]'::jsonb)
  FROM public.product_submission_evidence_revisions revision
  JOIN public.product_submission_photos photo ON photo.submission_id = revision.submission_id
    AND photo.photo_id = ANY(revision.photo_ids)
  WHERE revision.submission_id = p_submission_id AND revision.revision = p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_evidence_records(uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_product_submission_evidence(p_submission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE submission public.product_submissions%ROWTYPE; current_evidence public.product_submission_evidence_revisions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.product_submission_reviewers WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO submission FROM public.product_submissions WHERE id = p_submission_id;
  IF NOT FOUND OR submission.upload_state <> 'ready' THEN
    RAISE EXCEPTION 'ready evidence required' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO current_evidence FROM public.product_submission_evidence_revisions
    WHERE submission_id = p_submission_id AND revision = submission.evidence_revision;
  RETURN jsonb_build_object('evidence_revision', submission.evidence_revision,
    'manifest_sha256', current_evidence.manifest_sha256,
    'evidence_snapshot', public.product_submission_evidence_manifest(p_submission_id, submission.evidence_revision),
    'photos', public.product_submission_evidence_records(p_submission_id, submission.evidence_revision));
END;
$$;

-- App upload privileges apply only to newly introduced photos of the open
-- revision. Retained evidence is never editable during a subsequent retake.
CREATE FUNCTION public.product_submission_photo_uploadable(p_path text)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Hold authorization until the Storage metadata transaction commits.
  -- Finalize/cleanup take UPDATE on this same parent, so a pending upload
  -- cannot commit a metadata replacement after the manifest was frozen.
  PERFORM submission.id FROM public.product_submission_photos photo
    JOIN public.product_submissions submission ON submission.id=photo.submission_id
    JOIN public.product_submission_evidence_revisions revision ON revision.submission_id=submission.id
      AND revision.revision=submission.evidence_revision
    WHERE photo.object_path=p_path AND photo.user_id=auth.uid() AND submission.user_id=auth.uid()
      AND photo.revision=submission.evidence_revision AND photo.photo_id=ANY(revision.photo_ids)
      AND submission.upload_state='pending' AND revision.ready_at IS NULL AND revision.abandoned_at IS NULL
    FOR SHARE OF submission;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.product_submission_photo_uploadable(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_photo_uploadable(text) TO authenticated;
ALTER POLICY product_submission_objects_insert_own ON storage.objects
  WITH CHECK(bucket_id='product-submission-photos' AND owner_id=(SELECT auth.uid())::text
    AND public.product_submission_photo_uploadable(name));
ALTER POLICY product_submission_objects_update_own ON storage.objects
  USING(bucket_id='product-submission-photos' AND owner_id=(SELECT auth.uid())::text
    AND public.product_submission_photo_uploadable(name))
  WITH CHECK(bucket_id='product-submission-photos' AND owner_id=(SELECT auth.uid())::text
    AND public.product_submission_photo_uploadable(name));
ALTER POLICY product_submission_objects_delete_own ON storage.objects
  USING(bucket_id='product-submission-photos' AND owner_id=(SELECT auth.uid())::text
    AND public.product_submission_photo_uploadable(name));
REVOKE ALL ON FUNCTION public.get_product_submission_evidence(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_product_submission_evidence(uuid) TO authenticated;

-- Every existing submission is revision 1 with its existing photos as the
-- membership; finalized ones are recorded ready with their manifest frozen.
INSERT INTO public.product_submission_evidence_revisions (
  submission_id, revision, request_key, opened_by, opened_at, photo_ids
)
SELECT
  submission.id,
  1,
  gen_random_uuid(),
  submission.user_id,
  submission.created_at,
  coalesce(
    (SELECT array_agg(photo.photo_id ORDER BY photo.seq)
     FROM public.product_submission_photos AS photo
     WHERE photo.submission_id = submission.id),
    '{}'::uuid[]
  )
FROM public.product_submissions AS submission;

UPDATE public.product_submission_evidence_revisions AS revision
SET ready_at = coalesce(submission.submitted_at, submission.created_at),
    manifest = public.product_submission_evidence_records(submission.id, 1),
    manifest_sha256 = public.product_submission_manifest_sha256(
      public.product_submission_evidence_records(submission.id, 1)
    )
FROM public.product_submissions AS submission
WHERE submission.id = revision.submission_id
  AND revision.revision = 1
  AND submission.upload_state = 'ready';

UPDATE public.product_submission_match_checks AS match_check
SET evidence_revision = 1
WHERE match_check.evidence_revision IS NULL;

-- Existing approved receipts refer to their original immutable revision. This
-- records provenance only; it does not invent historical consent or extraction.
UPDATE public.product_submission_approved_labels approved
SET evidence_revision=1, evidence_manifest_sha256=revision.manifest_sha256
FROM public.product_submission_evidence_revisions revision
WHERE approved.submission_id=revision.submission_id AND revision.revision=1;

-- Identity checks are bound to the evidence they were made against.
CREATE FUNCTION public.stamp_product_submission_match_check_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  SELECT evidence_revision INTO NEW.evidence_revision FROM public.product_submissions
  WHERE id = NEW.submission_id AND upload_state = 'ready';
  IF NEW.evidence_revision IS NULL THEN
    RAISE EXCEPTION 'match check evidence revision required' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER product_submission_match_check_revision
  BEFORE INSERT ON public.product_submission_match_checks
  FOR EACH ROW EXECUTE FUNCTION public.stamp_product_submission_match_check_revision();

-- All mutation callers lock the parent and compare the snapshot the human
-- actually read. Lower-level legacy implementations are private, not RPCs.
CREATE FUNCTION public.assert_product_submission_evidence(
  p_submission_id uuid, p_revision integer, p_manifest_sha256 text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE submission public.product_submissions%ROWTYPE;
BEGIN
  SELECT * INTO submission FROM public.product_submissions WHERE id = p_submission_id FOR UPDATE;
  IF NOT FOUND OR submission.upload_state <> 'ready' OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.evidence_purged_at IS NOT NULL THEN
    RAISE EXCEPTION 'ready evidence required' USING ERRCODE = '55000';
  END IF;
  IF p_revision IS DISTINCT FROM submission.evidence_revision OR p_manifest_sha256 IS NULL
    OR NOT EXISTS(SELECT 1 FROM public.product_submission_evidence_revisions revision
      WHERE revision.submission_id = p_submission_id AND revision.revision = p_revision
        AND revision.ready_at IS NOT NULL AND revision.manifest_sha256 = p_manifest_sha256
        AND revision.manifest = public.product_submission_evidence_records(p_submission_id,p_revision)) THEN
    RAISE EXCEPTION 'evidence revision or manifest changed since review' USING ERRCODE = '55000';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_product_submission_evidence(uuid,integer,text)
  FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text)
  RENAME TO record_product_submission_match_check_internal;
REVOKE ALL ON FUNCTION public.record_product_submission_match_check_internal(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text)
  FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.record_product_submission_match_check(
  p_submission_id uuid, p_outcome public.product_submission_match_outcome, p_canonical_gtin14 text,
  p_index_built_at timestamptz, p_matched_dsld_id text DEFAULT NULL,
  p_candidate_dsld_ids text[] DEFAULT '{}', p_reason text DEFAULT NULL,
  p_expected_evidence_revision integer DEFAULT NULL, p_evidence_manifest_sha256 text DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.product_submission_reviewers WHERE user_id=auth.uid()) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE='42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_evidence_revision,p_evidence_manifest_sha256);
  RETURN public.record_product_submission_match_check_internal(p_submission_id,p_outcome,p_canonical_gtin14,
    p_index_built_at,p_matched_dsld_id,p_candidate_dsld_ids,p_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text,integer,text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_match_check(uuid,public.product_submission_match_outcome,text,timestamptz,text,text[],text,integer,text) TO authenticated;

ALTER TABLE public.product_submission_reviewer_images ADD COLUMN evidence_revision integer;
UPDATE public.product_submission_reviewer_images SET evidence_revision = 1;
ALTER FUNCTION public.create_product_submission_reviewer_image(uuid,uuid,public.product_submission_image_rights,boolean,uuid)
  RENAME TO create_product_submission_reviewer_image_internal;
REVOKE ALL ON FUNCTION public.create_product_submission_reviewer_image_internal(uuid,uuid,public.product_submission_image_rights,boolean,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.create_product_submission_reviewer_image(
  p_submission_id uuid, p_object_id uuid, p_source_rights public.product_submission_image_rights,
  p_rights_attested boolean, p_source_photo_id uuid DEFAULT NULL,
  p_expected_evidence_revision integer DEFAULT NULL, p_evidence_manifest_sha256 text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result text;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.product_submission_reviewers WHERE user_id=auth.uid()) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE='42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_evidence_revision,p_evidence_manifest_sha256);
  IF p_source_photo_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.product_submission_evidence_revisions
    WHERE submission_id=p_submission_id AND revision=p_expected_evidence_revision AND p_source_photo_id=ANY(photo_ids)) THEN
    RAISE EXCEPTION 'current source photo required for crop' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM public.product_submission_reviewer_images WHERE object_id=p_object_id
    AND evidence_revision IS DISTINCT FROM p_expected_evidence_revision) THEN
    RAISE EXCEPTION 'reviewer image replay conflict' USING ERRCODE='23505';
  END IF;
  result := public.create_product_submission_reviewer_image_internal(p_submission_id,p_object_id,p_source_rights,p_rights_attested,p_source_photo_id);
  UPDATE public.product_submission_reviewer_images SET evidence_revision=p_expected_evidence_revision WHERE object_id=p_object_id;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_product_submission_reviewer_image(uuid,uuid,public.product_submission_image_rights,boolean,uuid,integer,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission_reviewer_image(uuid,uuid,public.product_submission_image_rights,boolean,uuid,integer,text) TO authenticated;

ALTER FUNCTION public.finalize_product_submission_reviewer_image(uuid,uuid,text,bigint,text)
  RENAME TO finalize_product_submission_reviewer_image_internal;
REVOKE ALL ON FUNCTION public.finalize_product_submission_reviewer_image_internal(uuid,uuid,text,bigint,text)
  FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.finalize_product_submission_reviewer_image(
  p_submission_id uuid,p_object_id uuid,p_content_type text,p_byte_size bigint,p_content_sha256 text
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE submission public.product_submissions%ROWTYPE; image public.product_submission_reviewer_images%ROWTYPE;
BEGIN
  SELECT * INTO submission FROM public.product_submissions WHERE id=p_submission_id FOR UPDATE;
  SELECT * INTO image FROM public.product_submission_reviewer_images
    WHERE submission_id=p_submission_id AND object_id=p_object_id FOR UPDATE;
  IF image.object_id IS NULL OR image.evidence_revision IS DISTINCT FROM submission.evidence_revision
     OR submission.upload_state <> 'ready' OR submission.evidence_purged_at IS NOT NULL
     OR submission.cleanup_claimed_at IS NOT NULL THEN
    RAISE EXCEPTION 'reviewer image requires current evidence' USING ERRCODE='55000';
  END IF;
  IF p_content_type IS NULL OR p_byte_size IS NULL OR p_content_sha256 IS NULL THEN
    RAISE EXCEPTION 'invalid reviewer image bytes' USING ERRCODE='22023';
  END IF;
  IF image.finalized_at IS NOT NULL THEN
    IF image.content_type IS DISTINCT FROM p_content_type OR image.byte_size IS DISTINCT FROM p_byte_size
       OR image.content_sha256 IS DISTINCT FROM p_content_sha256 THEN
      RAISE EXCEPTION 'reviewer image already finalized' USING ERRCODE='23505';
    END IF;
    RETURN true;
  END IF;
  IF submission.review_status NOT IN ('submitted','under_review') THEN
    RAISE EXCEPTION 'open submission required' USING ERRCODE='55000';
  END IF;
  RETURN public.finalize_product_submission_reviewer_image_internal(p_submission_id,p_object_id,p_content_type,p_byte_size,p_content_sha256);
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_product_submission_reviewer_image(uuid,uuid,text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission_reviewer_image(uuid,uuid,text,bigint,text) TO service_role;

-- Release consumers keep their existing API shape, but cannot export or
-- promote a label approved against a different evidence revision.
CREATE FUNCTION public.assert_product_submission_approval(p_submission_id uuid)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.product_submissions submission
    JOIN public.product_submission_approved_labels approved ON approved.submission_id=submission.id
    JOIN public.product_submission_evidence_revisions revision ON revision.submission_id=submission.id
      AND revision.revision=submission.evidence_revision
    WHERE submission.id=p_submission_id AND submission.upload_state='ready' AND submission.review_status='approved'
      AND approved.evidence_revision=revision.revision AND revision.ready_at IS NOT NULL
      AND approved.evidence_manifest_sha256=revision.manifest_sha256
      AND (submission.evidence_purged_at IS NOT NULL AND submission.promoted_at IS NOT NULL
        OR revision.manifest=public.product_submission_evidence_records(submission.id,revision.revision))) THEN
    RAISE EXCEPTION 'approval evidence changed' USING ERRCODE='55000';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_product_submission_approval(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Cleanup workers may outlive their lease. A completed cleanup therefore
-- retires object addresses permanently: a late worker can only delete an
-- already-retired object, never newly uploaded bytes at a recycled address.
-- This stores addresses only, not private bytes or label content.
CREATE TABLE public.product_submission_retired_objects (
  bucket_id text NOT NULL CHECK(bucket_id IN ('product-submission-photos','product-submission-reviewer-images')),
  object_path text NOT NULL,
  PRIMARY KEY(bucket_id,object_path)
);
ALTER TABLE public.product_submission_retired_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_retired_objects FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_retired_objects FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.prevent_product_submission_object_reuse()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM public.product_submission_retired_objects
    WHERE bucket_id=TG_ARGV[0] AND object_path=NEW.object_path) THEN
    RAISE EXCEPTION 'retired evidence object address cannot be reused' USING ERRCODE='23505';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.prevent_product_submission_object_reuse() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER product_submission_photo_no_reuse BEFORE INSERT ON public.product_submission_photos
  FOR EACH ROW EXECUTE FUNCTION public.prevent_product_submission_object_reuse('product-submission-photos');
CREATE TRIGGER product_submission_reviewer_image_no_reuse BEFORE INSERT ON public.product_submission_reviewer_images
  FOR EACH ROW EXECUTE FUNCTION public.prevent_product_submission_object_reuse('product-submission-reviewer-images');

ALTER FUNCTION public.export_approved_product_submissions(integer,timestamptz,uuid)
  RENAME TO export_approved_product_submissions_internal;
REVOKE ALL ON FUNCTION public.export_approved_product_submissions_internal(integer,timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.export_approved_product_submissions(
  p_limit integer DEFAULT 100,p_after_approved_at timestamptz DEFAULT NULL,p_after_submission_id uuid DEFAULT NULL
) RETURNS TABLE(submission_id uuid,kind public.product_submission_kind,normalized_upc text,target_dsld_id text,
  schema_version text,approved_payload_canonical text,payload_sha256 text,reviewer_id uuid,approved_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE candidate record;
BEGIN
  FOR candidate IN SELECT * FROM public.export_approved_product_submissions_internal(p_limit,p_after_approved_at,p_after_submission_id) LOOP
    PERFORM public.assert_product_submission_approval(candidate.submission_id);
    RETURN QUERY SELECT candidate.submission_id,candidate.kind,candidate.normalized_upc,candidate.target_dsld_id,
      candidate.schema_version,candidate.approved_payload_canonical,candidate.payload_sha256,candidate.reviewer_id,candidate.approved_at;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.export_approved_product_submissions(integer,timestamptz,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.export_approved_product_submissions(integer,timestamptz,uuid) TO service_role;

ALTER FUNCTION public.get_approved_product_submission_image(uuid) RENAME TO get_approved_product_submission_image_internal;
REVOKE ALL ON FUNCTION public.get_approved_product_submission_image_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.get_approved_product_submission_image(p_submission_id uuid)
RETURNS TABLE(bucket_id text,object_path text,content_type text,content_sha256 text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM public.assert_product_submission_approval(p_submission_id);
  RETURN QUERY SELECT * FROM public.get_approved_product_submission_image_internal(p_submission_id);
END;
$$;
REVOKE ALL ON FUNCTION public.get_approved_product_submission_image(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_approved_product_submission_image(uuid) TO service_role;

ALTER FUNCTION public.mark_product_submission_promoted(uuid,text,text) RENAME TO mark_product_submission_promoted_internal;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted_internal(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.mark_product_submission_promoted(p_submission_id uuid,p_catalog_version text,p_resolved_dsld_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM id FROM public.product_submissions WHERE id=p_submission_id FOR UPDATE;
  PERFORM public.assert_product_submission_approval(p_submission_id);
  RETURN public.mark_product_submission_promoted_internal(p_submission_id,p_catalog_version,p_resolved_dsld_id);
END;
$$;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_product_submission_promoted(uuid,text,text) TO service_role;

-- Required-evidence coverage is judged on the current revision's membership
-- (create, finalize and approval all call this).
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
    FROM public.product_submissions AS submission
    JOIN public.product_submission_evidence_revisions AS revision
      ON revision.submission_id = submission.id
     AND revision.revision = submission.evidence_revision
    JOIN public.product_submission_photos AS photo
      ON photo.submission_id = submission.id
     AND photo.photo_id = ANY(revision.photo_ids),
    unnest(photo.categories) AS category
    WHERE submission.id = p_submission_id
      AND photo.user_id = p_user_id
      AND category IN (
        'front_identity',
        'supplement_facts',
        'ingredient_disclosure',
        'barcode'
      )
  );
$$;

-- One owner for photo-manifest validation and insertion, shared by the first
-- upload and by later revisions. Replay of an identical manifest is
-- idempotent; a differing manifest for an already-persisted photo conflicts.
-- Sequence numbers are 1..N within the revision; the revision's membership
-- (kept + appended photos) may not exceed eight.
CREATE FUNCTION public.insert_product_submission_photos_internal(
  p_submission_id uuid,
  p_user_id uuid,
  p_photos jsonb,
  p_revision integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  photo jsonb;
  photo_count integer;
  photo_id_value uuid;
  photo_seq_value integer;
  photo_categories public.product_submission_evidence_category[];
  membership uuid[];
BEGIN
  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_photos) > 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  photo_count := jsonb_array_length(p_photos);

  FOR photo IN SELECT value FROM jsonb_array_elements(p_photos)
  LOOP
    IF jsonb_typeof(photo) IS DISTINCT FROM 'object'
       OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(photo) key)
          IS DISTINCT FROM ARRAY[
            'byte_size',
            'categories',
            'content_sha256',
            'content_type',
            'photo_id',
            'seq'
          ]::text[] THEN
      RAISE EXCEPTION 'invalid photo manifest entry'
        USING ERRCODE = '22023';
    END IF;

    BEGIN
      photo_id_value := (photo->>'photo_id')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid photo id' USING ERRCODE = '22023';
    END;

    IF jsonb_typeof(photo->'seq') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
    END IF;
    photo_seq_value := (photo->>'seq')::numeric::integer;
    IF (photo->>'seq')::numeric <> photo_seq_value
       OR photo_seq_value NOT BETWEEN 1 AND 8 THEN
      RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
    END IF;

    IF jsonb_typeof(photo->'categories') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END IF;
    BEGIN
      SELECT array_agg(
        DISTINCT item.value::public.product_submission_evidence_category
        ORDER BY item.value::public.product_submission_evidence_category
      )
        INTO photo_categories
      FROM jsonb_array_elements_text(photo->'categories') AS item(value);
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END;
    IF coalesce(cardinality(photo_categories), 0) NOT BETWEEN 1 AND 6
       OR jsonb_array_length(photo->'categories')
         <> cardinality(photo_categories) THEN
      RAISE EXCEPTION 'invalid photo categories' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.product_submission_photos (
      submission_id,
      user_id,
      photo_id,
      seq,
      categories,
      object_path,
      content_type,
      byte_size,
      content_sha256,
      revision
    ) VALUES (
      p_submission_id,
      p_user_id,
      photo_id_value,
      photo_seq_value,
      photo_categories,
      p_user_id::text || '/' || p_submission_id::text || '/'
        || photo_id_value::text,
      photo->>'content_type',
      (photo->>'byte_size')::bigint,
      photo->>'content_sha256',
      p_revision
    )
    ON CONFLICT (submission_id, photo_id) DO NOTHING;
  END LOOP;

  -- Every manifest photo must be persisted exactly as sent, in this revision;
  -- this revision must hold exactly the manifest's photos; the total stays
  -- within the cap.
  IF (
    SELECT count(*)
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = p_user_id
      AND persisted_photo.revision = p_revision
  ) <> photo_count
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_photos) AS expected_photo(value)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.product_submission_photos AS persisted_photo
      WHERE persisted_photo.submission_id = p_submission_id
        AND persisted_photo.user_id = p_user_id
        AND persisted_photo.revision = p_revision
        AND persisted_photo.photo_id =
          (expected_photo.value->>'photo_id')::uuid
        AND persisted_photo.seq =
          (expected_photo.value->>'seq')::numeric::integer
        AND persisted_photo.categories = (
          SELECT array_agg(
            DISTINCT item.value
              ::public.product_submission_evidence_category
            ORDER BY item.value
              ::public.product_submission_evidence_category
          )
          FROM jsonb_array_elements_text(
            expected_photo.value->'categories'
          ) AS item(value)
        )
        AND persisted_photo.content_type =
          expected_photo.value->>'content_type'
        AND persisted_photo.byte_size =
          (expected_photo.value->>'byte_size')::bigint
        AND persisted_photo.content_sha256 IS NOT DISTINCT FROM
          expected_photo.value->>'content_sha256'
    )
  ) THEN
    RAISE EXCEPTION 'submission photo replay conflict'
      USING ERRCODE = '23505';
  END IF;

  -- Sequence numbers of this revision are exactly 1..N, no holes.
  IF photo_count > 0 AND (
    SELECT count(DISTINCT persisted_photo.seq) <> photo_count
        OR min(persisted_photo.seq) <> 1
        OR max(persisted_photo.seq) <> photo_count
    FROM public.product_submission_photos AS persisted_photo
    WHERE persisted_photo.submission_id = p_submission_id
      AND persisted_photo.user_id = p_user_id
      AND persisted_photo.revision = p_revision
  ) THEN
    RAISE EXCEPTION 'invalid photo sequence' USING ERRCODE = '22023';
  END IF;

  -- Membership = photos kept at open (already in photo_ids) + this
  -- revision's photos. Idempotent on replay.
  SELECT array_agg(persisted_photo.photo_id ORDER BY persisted_photo.revision, persisted_photo.seq)
    INTO membership
  FROM public.product_submission_photos AS persisted_photo
  JOIN public.product_submission_evidence_revisions AS revision
    ON revision.submission_id = persisted_photo.submission_id
   AND revision.revision = p_revision
  WHERE persisted_photo.submission_id = p_submission_id
    AND (
      persisted_photo.revision = p_revision
      OR persisted_photo.photo_id = ANY(revision.photo_ids)
    );
  IF coalesce(cardinality(membership), 0) > 8 THEN
    RAISE EXCEPTION 'too many photos' USING ERRCODE = '22023';
  END IF;
  UPDATE public.product_submission_evidence_revisions
  SET photo_ids = coalesce(membership, '{}'::uuid[])
  WHERE submission_id = p_submission_id
    AND revision = p_revision
    AND ready_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.insert_product_submission_photos_internal(
  uuid, uuid, jsonb, integer
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_product_submission_v2_internal(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  persisted public.product_submissions%ROWTYPE;
  detail_keys text[];
  category_values public.label_mismatch_category[];
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_submission_id IS NULL THEN
    RAISE EXCEPTION 'submission id required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_photos) > 8 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;

  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''),
    '[^0-9]',
    '',
    'g'
  ), '');
  IF NULLIF(btrim(coalesce(p_upc, '')), '') IS NOT NULL
     AND (
       normalized_upc_value IS NULL
       OR NOT public.is_valid_product_submission_gtin(normalized_upc_value)
     ) THEN
    RAISE EXCEPTION 'invalid UPC/EAN' USING ERRCODE = '22023';
  END IF;

  IF p_kind = 'missing_product' THEN
    IF normalized_upc_value IS NULL OR p_mismatch_detail IS NOT NULL THEN
      RAISE EXCEPTION 'invalid missing-product payload'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF p_mismatch_detail IS NULL
       OR jsonb_typeof(p_mismatch_detail) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'mismatch detail required' USING ERRCODE = '22023';
    END IF;
    SELECT array_agg(key ORDER BY key)
      INTO detail_keys
    FROM jsonb_object_keys(p_mismatch_detail) AS key;
    IF detail_keys IS DISTINCT FROM ARRAY[
      'catalog_source_version',
      'dsld_id',
      'formula_fingerprint',
      'mismatch_categories',
      'source_record_id'
    ]::text[] THEN
      RAISE EXCEPTION 'unexpected mismatch detail field'
        USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_mismatch_detail->'mismatch_categories') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'mismatch categories required'
        USING ERRCODE = '22023';
    END IF;
    SELECT array_agg(
      DISTINCT item.value::public.label_mismatch_category
      ORDER BY item.value::public.label_mismatch_category
    )
      INTO category_values
    FROM jsonb_array_elements_text(
      p_mismatch_detail->'mismatch_categories'
    ) AS item(value);
    IF coalesce(cardinality(category_values), 0) NOT BETWEEN 1 AND 8 THEN
      RAISE EXCEPTION 'invalid mismatch categories'
        USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_mismatch_detail->'mismatch_categories')
       <> cardinality(category_values) THEN
      RAISE EXCEPTION 'duplicate mismatch category'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.product_submissions (
    id,
    user_id,
    kind,
    normalized_upc,
    declared_no_separate_ingredient_panel
  ) VALUES (
    p_submission_id,
    caller_id,
    p_kind,
    normalized_upc_value,
    coalesce(p_no_separate_ingredient_panel, false)
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT submission.*
    INTO persisted
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR persisted.user_id <> caller_id
     OR persisted.kind <> p_kind
     OR persisted.normalized_upc IS DISTINCT FROM normalized_upc_value
     OR persisted.declared_no_separate_ingredient_panel
       IS DISTINCT FROM coalesce(p_no_separate_ingredient_panel, false)
     OR persisted.upload_state NOT IN ('pending', 'ready')
     OR persisted.review_status <> 'submitted'
     OR persisted.evidence_revision <> 1 THEN
    RAISE EXCEPTION 'submission replay conflict' USING ERRCODE = '23505';
  END IF;

  IF p_kind = 'label_mismatch' THEN
    INSERT INTO public.product_submission_mismatch_details (
      submission_id,
      user_id,
      dsld_id,
      source_record_id,
      catalog_source_version,
      formula_fingerprint,
      mismatch_categories
    ) VALUES (
      p_submission_id,
      caller_id,
      btrim(p_mismatch_detail->>'dsld_id'),
      NULLIF(btrim(p_mismatch_detail->>'source_record_id'), ''),
      NULLIF(btrim(p_mismatch_detail->>'catalog_source_version'), ''),
      NULLIF(btrim(p_mismatch_detail->>'formula_fingerprint'), ''),
      category_values
    )
    ON CONFLICT (submission_id) DO NOTHING;
    IF NOT EXISTS (
      SELECT 1
      FROM public.product_submission_mismatch_details AS detail
      WHERE detail.submission_id = p_submission_id
        AND detail.user_id = caller_id
        AND detail.dsld_id = btrim(p_mismatch_detail->>'dsld_id')
        AND detail.source_record_id IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'source_record_id'), '')
        AND detail.catalog_source_version IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'catalog_source_version'), '')
        AND detail.formula_fingerprint IS NOT DISTINCT FROM
          NULLIF(btrim(p_mismatch_detail->>'formula_fingerprint'), '')
        AND detail.mismatch_categories = category_values
    ) THEN
      RAISE EXCEPTION 'submission detail replay conflict'
        USING ERRCODE = '23505';
    END IF;
  ELSE
    INSERT INTO public.product_submission_missing_details (
      submission_id,
      user_id
    ) VALUES (
      p_submission_id,
      caller_id
    )
    ON CONFLICT (submission_id) DO NOTHING;
    IF NOT EXISTS (
      SELECT 1
      FROM public.product_submission_missing_details AS detail
      WHERE detail.submission_id = p_submission_id
        AND detail.user_id = caller_id
    ) THEN
      RAISE EXCEPTION 'submission detail replay conflict'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Revision 1 is opened with the submission; its membership is the first
  -- manifest. The request key is the submission id (one first upload).
  INSERT INTO public.product_submission_evidence_revisions (
    submission_id, revision, request_key, opened_by
  ) VALUES (p_submission_id, 1, p_submission_id, caller_id)
  ON CONFLICT (submission_id, revision) DO NOTHING;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    1
  );

  -- Fail fast on evidence coverage so the user learns before uploading bytes.
  IF p_kind = 'missing_product'
     AND NOT public.product_submission_has_required_evidence(
       p_submission_id,
       caller_id
     ) THEN
    RAISE EXCEPTION 'missing required evidence categories'
      USING ERRCODE = '22023';
  END IF;

  RETURN true;
END;
$$;

-- Public wrapper: lineage handling unchanged from the intake migration; the
-- consent version the app attests is recorded once, at first creation.
DROP FUNCTION public.create_product_submission(
  uuid,
  public.product_submission_kind,
  text,
  jsonb,
  boolean,
  jsonb,
  uuid
);

CREATE FUNCTION public.create_product_submission(
  p_submission_id uuid,
  p_kind public.product_submission_kind,
  p_upc text DEFAULT NULL,
  p_mismatch_detail jsonb DEFAULT NULL,
  p_no_separate_ingredient_panel boolean DEFAULT false,
  p_photos jsonb DEFAULT '[]'::jsonb,
  p_resubmission_of uuid DEFAULT NULL,
  p_consent_version text DEFAULT NULL
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
  consent_version_value text := NULLIF(btrim(coalesce(p_consent_version, '')), '');
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
  IF consent_version_value IS NULL
     OR consent_version_value !~ '^[A-Za-z0-9._-]{1,80}$' THEN
    RAISE EXCEPTION 'consent version required' USING ERRCODE = '22023';
  END IF;
  -- Only a registered, unretired version for this kind can be attested; the
  -- registry pins the copy hash and purposes the version stands for.
  IF NOT EXISTS (
    SELECT 1
    FROM public.product_submission_consent_versions AS consent
    WHERE consent.version = consent_version_value
      AND consent.kind = p_kind
      AND consent.retired_at IS NULL
      AND consent.effective_from <= now()
  ) THEN
    RAISE EXCEPTION 'consent version not recognized' USING ERRCODE = '22023';
  END IF;

  -- An absent row cannot be locked with FOR UPDATE. Serialize first-create
  -- replays by UUID across owners before reading lineage, so a concurrent
  -- request cannot turn the original NULL lineage into a different value.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('product_submission_create:' || p_submission_id::text, 0)
  );

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
      AND public.product_submission_canonical_gtin(target.normalized_upc)
        IS NOT DISTINCT FROM
          public.product_submission_canonical_gtin(normalized_upc_value)
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
  IF had_existing AND EXISTS (
    SELECT 1 FROM public.product_submissions WHERE id = p_submission_id
      AND consent_version IS DISTINCT FROM consent_version_value
  ) THEN
    RAISE EXCEPTION 'consent replay conflict' USING ERRCODE = '23505';
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
    SET resubmission_of = p_resubmission_of,
        consent_version = consent_version_value,
        consented_at = now()
    WHERE submission.id = p_submission_id
      AND submission.user_id = caller_id
      AND (
        submission.resubmission_of IS NULL
        OR submission.resubmission_of IS NOT DISTINCT FROM p_resubmission_of
      )
      AND submission.consent_version IS NULL;
    GET DIAGNOSTICS persisted_count = ROW_COUNT;
    IF persisted_count <> 1 THEN
      RAISE EXCEPTION 'resubmission replay conflict' USING ERRCODE = '23505';
    END IF;
    UPDATE public.product_submission_evidence_revisions
    SET consent_version = consent_version_value, consented_at = now()
    WHERE submission_id = p_submission_id AND revision = 1;
  END IF;

  RETURN result_value;
END;
$$;

REVOKE ALL ON FUNCTION public.create_product_submission(
  uuid, public.product_submission_kind, text, jsonb, boolean, jsonb, uuid, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_product_submission(
  uuid, public.product_submission_kind, text, jsonb, boolean, jsonb, uuid, text
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2b. Revision transitions: expected-version, idempotent, owner- or
--     reviewer-gated. Nothing here deletes or rewrites a photo.
-- ---------------------------------------------------------------------------

-- A reviewer asks the owner for new evidence. Until the owner finalizes a
-- new revision, the request stays open; the reviewer keeps ownership of the
-- review (`under_review`) and the owner may open exactly one revision for it.
CREATE FUNCTION public.request_product_submission_evidence(
  p_submission_id uuid,
  p_reason text,
  p_expected_revision integer,
  p_manifest_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  reason_value public.product_submission_resolution_code;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(p_submission_id,p_expected_revision,p_manifest_sha256);
  BEGIN
    reason_value := btrim(coalesce(p_reason, ''))::public.product_submission_resolution_code;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'evidence request reason required' USING ERRCODE = '22023';
  END;
  IF reason_value NOT IN ('photo_quality', 'missing_panel', 'label_unreadable', 'other') THEN
    RAISE EXCEPTION 'evidence request reason required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.upload_state <> 'ready'
     OR submission.promoted_at IS NOT NULL
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submissions
  SET evidence_requested_at = now(),
      evidence_requested_revision = submission.evidence_revision,
      evidence_requested_by = reviewer_id,
      evidence_request_reason = reason_value
  WHERE id = p_submission_id;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.request_product_submission_evidence(uuid, text, integer, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_product_submission_evidence(uuid, text, integer, text)
  TO authenticated;

-- Open the next evidence revision. The owner states the revision it is
-- replacing (`p_expected_revision`) and a request key; the same request
-- replays to the same revision forever, a different request against a
-- revision that already moved on conflicts, and a review a reviewer owns can
-- be reopened only after that reviewer asked for evidence. Photos named in
-- `p_keep_photo_ids` (members of the current revision) carry into the new
-- membership; everything else stays retained but leaves the working set.
CREATE FUNCTION public.open_product_submission_evidence_revision(
  p_submission_id uuid,
  p_expected_revision integer,
  p_request_key uuid,
  p_keep_photo_ids uuid[] DEFAULT '{}',
  p_consent_version text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  replayed_revision integer;
  replay public.product_submission_evidence_revisions%ROWTYPE;
  next_revision integer;
  kept uuid[] := coalesce(p_keep_photo_ids, '{}'::uuid[]);
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_request_key IS NULL THEN
    RAISE EXCEPTION 'evidence revision request key required' USING ERRCODE = '22023';
  END IF;
  IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'expected evidence revision required' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;

  SELECT revision.*
    INTO replay
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.request_key = p_request_key;
  IF FOUND THEN
    IF replay.replaces_revision IS DISTINCT FROM p_expected_revision
       OR replay.kept_photo_ids IS DISTINCT FROM kept
       OR replay.consent_version IS DISTINCT FROM p_consent_version THEN
      RAISE EXCEPTION 'evidence revision replay conflict' USING ERRCODE = '23505';
    END IF;
    RETURN replay.revision;
  END IF;

  IF submission.evidence_revision <> p_expected_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state <> 'ready'
     OR submission.cleanup_claimed_at IS NOT NULL
     OR submission.promoted_at IS NOT NULL
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required' USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.product_submission_consent_versions consent
    WHERE consent.version = p_consent_version AND consent.kind = submission.kind
      AND consent.retired_at IS NULL AND consent.effective_from <= now()) THEN
    RAISE EXCEPTION 'consent version not recognized' USING ERRCODE = '22023';
  END IF;
  IF submission.review_status = 'under_review'
     AND (
       submission.evidence_requested_at IS NULL
       OR submission.evidence_requested_revision IS DISTINCT FROM submission.evidence_revision
     ) THEN
    RAISE EXCEPTION 'evidence revision requires a reviewer request'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.*
    INTO current_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = submission.evidence_revision;
  IF cardinality(kept) >= 8 THEN
    RAISE EXCEPTION 'retake must leave room for new evidence' USING ERRCODE='22023';
  END IF;
  IF cardinality(kept) <> (SELECT count(DISTINCT id) FROM unnest(kept) AS id)
     OR array_position(kept, NULL) IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM unnest(kept) AS kept_id
       WHERE NOT (kept_id = ANY(current_revision.photo_ids))
     ) THEN
    RAISE EXCEPTION 'kept photos must belong to the current revision'
      USING ERRCODE = '22023';
  END IF;

  SELECT max(revision.revision) + 1
    INTO next_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id;

  INSERT INTO public.product_submission_evidence_revisions (
    submission_id, revision, request_key, opened_by, photo_ids, kept_photo_ids,
    replaces_revision, consent_version, consented_at
  ) VALUES (
    p_submission_id, next_revision, p_request_key, caller_id, kept, kept,
    p_expected_revision, p_consent_version, now()
  );
  UPDATE public.product_submissions
  SET upload_state = 'pending',
      evidence_revision = next_revision,
      evidence_revision_opened_at = now()
  WHERE id = p_submission_id;
  DELETE FROM public.product_submission_push_deliveries
  WHERE submission_id = p_submission_id AND sent_at IS NULL;
  RETURN next_revision;
END;
$$;

REVOKE ALL ON FUNCTION public.open_product_submission_evidence_revision(uuid, integer, uuid, uuid[], text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.open_product_submission_evidence_revision(uuid, integer, uuid, uuid[], text)
  TO authenticated;

-- Append photos to the open revision the caller names. Bytes identical to an
-- earlier photo of the same submission are rejected by the existing
-- per-submission sha256 uniqueness: a retake must bring new evidence.
CREATE FUNCTION public.add_product_submission_evidence(
  p_submission_id uuid,
  p_expected_revision integer,
  p_photos jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_expected_revision IS NULL OR p_expected_revision < 2 THEN
    RAISE EXCEPTION 'expected evidence revision required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_photos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_photos) = 0 THEN
    RAISE EXCEPTION 'invalid photo manifest' USING ERRCODE = '22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;
  IF submission.evidence_revision <> p_expected_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state <> 'pending'
     OR submission.evidence_revision < 2
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open evidence revision required' USING ERRCODE = '55000';
  END IF;
  PERFORM public.insert_product_submission_photos_internal(
    p_submission_id,
    caller_id,
    p_photos,
    submission.evidence_revision
  );
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.add_product_submission_evidence(uuid, integer, jsonb)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_product_submission_evidence(uuid, integer, jsonb)
  TO authenticated;

-- Finalize the pending revision: it needs at least one new photo (a retake
-- with nothing new is not a revision), full evidence coverage over its
-- membership, and bytes for every member. The first submission time is
-- kept across revisions; the revision's manifest is frozen here.
DROP FUNCTION public.finalize_product_submission(uuid);
CREATE FUNCTION public.finalize_product_submission(
  p_submission_id uuid,
  p_expected_revision integer DEFAULT 1
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  current_revision public.product_submission_evidence_revisions%ROWTYPE;
  manifest jsonb;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
    AND candidate.user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = '42501';
  END IF;
  IF p_expected_revision IS DISTINCT FROM submission.evidence_revision THEN
    RAISE EXCEPTION 'evidence revision conflict' USING ERRCODE = '55000';
  END IF;
  IF submission.upload_state = 'ready' THEN
    RETURN true;
  END IF;
  IF submission.upload_state <> 'pending' THEN
    RETURN false;
  END IF;

  SELECT revision.*
    INTO current_revision
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = submission.evidence_revision
    AND revision.ready_at IS NULL
    AND revision.abandoned_at IS NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF submission.evidence_revision > 1 AND NOT EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.revision = submission.evidence_revision
  ) THEN
    RETURN false;
  END IF;

  IF submission.kind = 'missing_product'
     AND NOT public.product_submission_has_required_evidence(
       p_submission_id,
       caller_id
     ) THEN
    RETURN false;
  END IF;
  IF submission.kind = 'label_mismatch' AND NOT EXISTS (
    SELECT 1
    FROM public.product_submission_mismatch_details AS mismatch
    WHERE mismatch.submission_id = p_submission_id
      AND mismatch.user_id = caller_id
  ) THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = p_submission_id
      AND photo.user_id = caller_id
      AND photo.photo_id = ANY(current_revision.photo_ids)
      AND NOT EXISTS (
        SELECT 1
        FROM storage.objects AS object
        WHERE object.bucket_id = 'product-submission-photos'
          AND object.owner_id = caller_id::text
          AND object.name = photo.object_path
          AND coalesce((object.metadata->>'size')::bigint, -1)
            = photo.byte_size
          AND lower(coalesce(object.metadata->>'mimetype', ''))
            = photo.content_type
          AND lower(
            coalesce(object.user_metadata->>'content_sha256', '')
          ) = photo.content_sha256
      )
  ) THEN
    RETURN false;
  END IF;

  manifest := public.product_submission_evidence_manifest(
    p_submission_id, submission.evidence_revision
  );
  UPDATE public.product_submission_evidence_revisions
  SET ready_at = now(),
      manifest = public.product_submission_evidence_records(p_submission_id, submission.evidence_revision),
      manifest_sha256 = public.product_submission_manifest_sha256(
        public.product_submission_evidence_records(p_submission_id, submission.evidence_revision))
  WHERE submission_id = p_submission_id
    AND revision = submission.evidence_revision;
  UPDATE public.product_submissions
  SET upload_state = 'ready',
      submitted_at = coalesce(submitted_at, now()),
      evidence_ready_at = now()
  WHERE id = p_submission_id
    AND user_id = caller_id
    AND upload_state = 'pending';
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_product_submission(uuid,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_product_submission(uuid,integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Draft recording: the reviewer is who the database says is calling, and
--    the draft is bound to the revision it read.
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric
) FROM PUBLIC, anon, authenticated, service_role;
DROP FUNCTION public.record_product_submission_extraction(
  uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric
);

CREATE FUNCTION public.record_product_submission_extraction(
  p_submission_id uuid,
  p_schema_version text,
  p_provider text,
  p_model text,
  p_prompt_version text,
  p_input_image_hashes jsonb,
  p_draft_payload jsonb,
  p_field_provenance jsonb,
  p_confidence numeric DEFAULT NULL,
  p_usage jsonb DEFAULT NULL,
  p_evidence_revision integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  next_version integer;
  submission public.product_submissions%ROWTYPE;
  manifest jsonb;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  IF btrim(coalesce(p_schema_version, '')) <> 'label_draft_v1' THEN
    RAISE EXCEPTION 'unsupported extraction schema version'
      USING ERRCODE = '22023';
  END IF;
  IF p_usage IS NOT NULL AND jsonb_typeof(p_usage) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid extraction usage' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_draft_payload) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_field_provenance) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_input_image_hashes) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid extraction payload' USING ERRCODE = '22023';
  END IF;
  IF p_evidence_revision IS NULL OR p_evidence_revision < 1 THEN
    RAISE EXCEPTION 'extraction evidence revision required'
      USING ERRCODE = '22023';
  END IF;
  IF p_draft_payload->>'schema_version' IS DISTINCT FROM 'label_draft_v1'
     OR p_draft_payload->>'provider' IS DISTINCT FROM p_provider
     OR p_draft_payload->>'model' IS DISTINCT FROM p_model
     OR p_draft_payload->>'prompt_version' IS DISTINCT FROM p_prompt_version
     OR jsonb_typeof(p_draft_payload->'identity') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_draft_payload->'serving') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_draft_payload->'ingredient_rows') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_draft_payload->'sent_inputs') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_draft_payload->'abstained') IS DISTINCT FROM 'boolean'
     OR coalesce(p_draft_payload->>'draft_origin','') NOT IN ('human_transcription','model')
     OR (p_draft_payload->>'draft_origin'='human_transcription'
       AND (p_provider <> 'human' OR p_model <> 'human' OR p_draft_payload->'sent_inputs' <> '[]'::jsonb))
     OR (p_draft_payload->>'draft_origin'='model' AND p_draft_payload->'sent_inputs'='[]'::jsonb) THEN
    RAISE EXCEPTION 'extraction envelope metadata mismatch' USING ERRCODE='22023';
  END IF;
  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.upload_state <> 'ready'
     OR submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'open ready submission required'
      USING ERRCODE = '55000';
  END IF;
  IF p_evidence_revision <> submission.evidence_revision THEN
    RAISE EXCEPTION 'extraction evidence revision is stale'
      USING ERRCODE = '22023';
  END IF;
  -- The outer hash map must be the current revision's manifest, and the
  -- draft's own snapshot and revision must be that same evidence: a draft
  -- read from other photos cannot be stored under verified hashes.
  manifest := public.product_submission_evidence_manifest(
    p_submission_id, submission.evidence_revision
  );
  IF manifest = '{}'::jsonb OR p_input_image_hashes IS DISTINCT FROM manifest THEN
    RAISE EXCEPTION 'extraction image hashes do not match'
      USING ERRCODE = '22023';
  END IF;
  IF p_draft_payload->'evidence_snapshot' IS DISTINCT FROM manifest
     OR jsonb_typeof(p_draft_payload->'evidence_revision') IS DISTINCT FROM 'number'
     OR (p_draft_payload->>'evidence_revision')::numeric
       <> submission.evidence_revision THEN
    RAISE EXCEPTION 'extraction snapshot does not match evidence'
      USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(max(extraction.version), 0) + 1
    INTO next_version
  FROM public.product_submission_extractions AS extraction
  WHERE extraction.submission_id = p_submission_id;
  INSERT INTO public.product_submission_extractions (
    submission_id,
    recorded_by,
    version,
    schema_version,
    provider,
    model,
    prompt_version,
    input_image_hashes,
    draft_payload,
    field_provenance,
    confidence,
    usage,
    actor_kind,
    evidence_revision
  ) VALUES (
    p_submission_id,
    reviewer_id,
    next_version,
    btrim(p_schema_version),
    btrim(p_provider),
    btrim(p_model),
    btrim(p_prompt_version),
    p_input_image_hashes,
    p_draft_payload,
    p_field_provenance,
    p_confidence,
    p_usage,
    'reviewer',
    submission.evidence_revision
  );
  RETURN next_version;
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) TO authenticated;
-- ---------------------------------------------------------------------------
-- 4. A submission whose retake revision is still uploading is still open:
--    the duplicate guard and the intake must count it, or a second attempt
--    for the same barcode could be created during the retake.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reject_duplicate_open_submission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.normalized_upc IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.product_submissions AS existing
    WHERE existing.id <> NEW.id
      AND existing.user_id = NEW.user_id
      AND existing.kind = NEW.kind
      AND lpad(existing.normalized_upc, 14, '0') = lpad(NEW.normalized_upc, 14, '0')
      AND (existing.upload_state = 'ready' OR existing.evidence_revision > 1)
      AND existing.promoted_at IS NULL
      AND existing.review_status IN ('submitted', 'under_review', 'approved')
  ) THEN
    RAISE EXCEPTION
      'open submission already exists for this barcode '
      '(idx_product_submissions_user_open_upc)'
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP INDEX public.idx_product_submissions_user_open_upc;
CREATE UNIQUE INDEX idx_product_submissions_user_open_upc
  ON public.product_submissions (user_id, kind, (lpad(normalized_upc, 14, '0')))
  WHERE normalized_upc IS NOT NULL
    AND promoted_at IS NULL
    AND (upload_state = 'ready' OR evidence_revision > 1)
    AND review_status IN ('submitted', 'under_review', 'approved');

-- Intake reports the revision so the app can resume a retake instead of
-- treating it as a never-finished first upload.
CREATE OR REPLACE FUNCTION public.get_product_submission_intake(
  p_kind public.product_submission_kind,
  p_upc text,
  p_dsld_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  normalized_upc_value text;
  dsld_value text := NULLIF(btrim(coalesce(p_dsld_id, '')), '');
  candidate public.product_submissions%ROWTYPE;
  action_value text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL THEN
    RAISE EXCEPTION 'submission kind required' USING ERRCODE = '22023';
  END IF;
  normalized_upc_value := NULLIF(regexp_replace(
    coalesce(p_upc, ''), '[^0-9]', '', 'g'
  ), '');
  IF (
    NULLIF(btrim(coalesce(p_upc, '')), '') IS NOT NULL
    AND (
      normalized_upc_value IS NULL
      OR NOT public.is_valid_product_submission_gtin(normalized_upc_value)
    )
  ) OR (p_kind = 'missing_product' AND normalized_upc_value IS NULL) THEN
    RAISE EXCEPTION 'invalid UPC/EAN' USING ERRCODE = '22023';
  END IF;
  IF (p_kind = 'label_mismatch'
      AND (dsld_value IS NULL OR dsld_value !~ '^[0-9]{1,30}$'))
     OR (p_kind = 'missing_product' AND dsld_value IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid mismatch target' USING ERRCODE = '22023';
  END IF;

  SELECT submission.*
    INTO candidate
  FROM public.product_submissions AS submission
  WHERE submission.user_id = caller_id
    AND submission.kind = p_kind
    AND public.product_submission_canonical_gtin(submission.normalized_upc)
      IS NOT DISTINCT FROM
        public.product_submission_canonical_gtin(normalized_upc_value)
    AND (
      p_kind = 'missing_product'
      OR (
        -- The create guard blocks open corrections for the same barcode
        -- across catalog targets. Refer to that receipt; never reuse its
        -- evidence or suggest it as a different target's retry lineage.
        normalized_upc_value IS NOT NULL
        AND (submission.upload_state = 'ready' OR submission.evidence_revision > 1)
        AND submission.review_status IN ('submitted', 'under_review', 'approved')
      )
      OR EXISTS (
        SELECT 1
        FROM public.product_submission_mismatch_details AS detail
        WHERE detail.submission_id = submission.id
          AND detail.user_id = caller_id
          AND detail.dsld_id = dsld_value
      )
    )
  ORDER BY
    ((submission.upload_state = 'ready' OR submission.evidence_revision > 1)
      AND submission.review_status IN (
        'submitted', 'under_review', 'approved', 'duplicate'
      )) DESC,
    submission.created_at DESC,
    submission.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('action', 'start_new');
  END IF;
  IF candidate.upload_state = 'pending'
     AND candidate.evidence_revision > 1
     AND candidate.review_status IN ('submitted', 'under_review') THEN
    -- Batch 2 owns the resume UI. Existing clients can safely open this same
    -- receipt now, without throwing on an unsupported action or creating a twin.
    action_value := 'open_existing';
  ELSIF candidate.upload_state = 'ready'
     AND candidate.review_status IN (
       'submitted', 'under_review', 'approved', 'duplicate'
     ) THEN
    action_value := 'open_existing';
  ELSIF candidate.upload_state = 'pending'
        AND candidate.review_status = 'submitted' THEN
    action_value := 'incomplete_upload';
  ELSIF candidate.upload_state = 'ready'
        AND candidate.review_status = 'rejected'
        AND candidate.resolution_code IN (
          'photo_quality', 'missing_panel', 'label_unreadable', 'other'
        ) THEN
    action_value := 'retry_rejected';
  ELSE
    RETURN jsonb_build_object('action', 'start_new');
  END IF;

  -- Existing clients understand open_existing. A revision-resume UI is a
  -- later batch; do not emit an action they cannot parse.
  RETURN jsonb_build_object(
    'action', action_value,
    'submission_id', candidate.id,
    'normalized_upc', candidate.normalized_upc,
    'resolution_code', candidate.resolution_code,
    'resolution_detail', candidate.resolution_detail
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Approval and retention read the current revision.
-- ---------------------------------------------------------------------------

-- The human approval boundary now states which evidence revision the
-- reviewer approved. The identity check, the product image and the payload
-- must all belong to that revision; a retake finalized after the reviewer
-- looked makes the approval request stale instead of approving new photos.
DROP FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid
);

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

REVOKE ALL ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_product_submission(
  uuid, public.product_submission_review_status, text, text, jsonb, text,
  text, uuid, text, text, text, uuid, uuid, integer, text
) TO authenticated;

-- Retention: a retake revision that never finalized is judged by the age of
-- the retake, not of the original contribution, and abandoning it removes
-- only the photos it added. The contribution, its earlier revisions, its
-- review history and reviewer images all stay; the submission returns to
-- its last finalized revision so review can continue.
DROP FUNCTION public.claim_product_submission_cleanup(integer);
CREATE FUNCTION public.claim_product_submission_cleanup(
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
    RETURNING submission.id, submission.upload_state, submission.evidence_revision, submission.cleanup_claim_token
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

DROP FUNCTION public.complete_product_submission_cleanup(uuid[]);
CREATE FUNCTION public.complete_product_submission_cleanup(
  p_submission_ids uuid[],
  p_claims jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  purged_retained_count integer;
  deleted_pending_count integer;
  reverted_count integer := 0;
  abandoned record;
BEGIN
  IF p_submission_ids IS NULL OR cardinality(p_submission_ids) NOT BETWEEN 1 AND 500
     OR cardinality(p_submission_ids) <> (SELECT count(DISTINCT id) FROM unnest(p_submission_ids) id)
     OR jsonb_typeof(p_claims) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid cleanup claims' USING ERRCODE='22023';
  END IF;
  PERFORM id FROM public.product_submissions WHERE id=ANY(p_submission_ids) ORDER BY id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM unnest(p_submission_ids) sid WHERE NOT EXISTS(
    SELECT 1 FROM public.product_submissions submission WHERE submission.id=sid
      AND submission.cleanup_claim_token IS NOT NULL
      AND submission.cleanup_claim_token::text=p_claims->sid::text->>'claim_token'
      AND submission.evidence_revision::text=p_claims->sid::text->>'evidence_revision')) THEN
    RAISE EXCEPTION 'cleanup claim changed' USING ERRCODE='55000';
  END IF;
  -- Review/publication provenance is durable. Retention removes only the
  -- private photo manifest after the Storage worker confirms object deletion.
  INSERT INTO public.product_submission_retired_objects(bucket_id,object_path)
    SELECT 'product-submission-photos',photo.object_path
    FROM public.product_submission_photos photo JOIN public.product_submissions submission ON submission.id=photo.submission_id
    WHERE submission.id=ANY(p_submission_ids) AND submission.cleanup_claimed_at IS NOT NULL
      AND (submission.upload_state='ready' OR submission.evidence_revision=1 OR photo.revision=submission.evidence_revision)
    UNION ALL
    SELECT 'product-submission-reviewer-images',image.object_path
    FROM public.product_submission_reviewer_images image JOIN public.product_submissions submission ON submission.id=image.submission_id
    WHERE submission.id=ANY(p_submission_ids) AND submission.cleanup_claimed_at IS NOT NULL
      AND (submission.upload_state='ready' OR submission.evidence_revision=1)
    ON CONFLICT DO NOTHING;

  DELETE FROM public.product_submission_reviewer_images image USING public.product_submissions submission
  WHERE image.submission_id=submission.id AND submission.id=ANY(p_submission_ids)
    AND submission.cleanup_claimed_at IS NOT NULL AND submission.upload_state='ready'
    AND (submission.review_status IN ('rejected','duplicate') OR submission.promoted_at IS NOT NULL);

  DELETE FROM public.product_submission_photos AS photo
  USING public.product_submissions AS submission
  WHERE photo.submission_id = submission.id
    AND submission.id = ANY(p_submission_ids)
    AND submission.cleanup_claimed_at IS NOT NULL
    AND submission.upload_state = 'ready'
    AND (
      submission.review_status IN ('rejected', 'duplicate')
      OR submission.promoted_at IS NOT NULL
    );

  UPDATE public.product_submissions
  SET evidence_purged_at = now(),
      cleanup_claimed_at = NULL,
      cleanup_claim_token = NULL
  WHERE id = ANY(p_submission_ids)
    AND cleanup_claimed_at IS NOT NULL
    AND upload_state = 'ready'
    AND evidence_purged_at IS NULL
    AND (
      review_status IN ('rejected', 'duplicate')
      OR promoted_at IS NOT NULL
    );
  GET DIAGNOSTICS purged_retained_count = ROW_COUNT;

  -- An abandoned retake: drop only the photos that revision added, mark the
  -- revision abandoned, and restore the last finalized revision.
  FOR abandoned IN
    SELECT submission.id,
           submission.evidence_revision AS abandoned_revision,
           (
             SELECT max(revision.revision)
             FROM public.product_submission_evidence_revisions AS revision
             WHERE revision.submission_id = submission.id
               AND revision.ready_at IS NOT NULL
           ) AS restore_revision
    FROM public.product_submissions AS submission
    WHERE submission.id = ANY(p_submission_ids)
      AND submission.upload_state = 'cleaning'
      AND submission.evidence_revision > 1
      AND submission.cleanup_claimed_at IS NOT NULL
    FOR UPDATE
  LOOP
    DELETE FROM public.product_submission_photos AS photo
    WHERE photo.submission_id = abandoned.id
      AND photo.revision = abandoned.abandoned_revision;
    UPDATE public.product_submission_evidence_revisions AS revision
    SET abandoned_at = now(),
        photo_ids = ARRAY(
          SELECT member
          FROM unnest(revision.photo_ids) AS member
          WHERE EXISTS (
            SELECT 1
            FROM public.product_submission_photos AS photo
            WHERE photo.submission_id = abandoned.id
              AND photo.photo_id = member
          )
        )
    WHERE revision.submission_id = abandoned.id
      AND revision.revision = abandoned.abandoned_revision;
    UPDATE public.product_submissions
    SET upload_state = 'ready',
        evidence_revision = coalesce(abandoned.restore_revision, 1),
        evidence_revision_opened_at = NULL,
        cleanup_claimed_at = NULL,
        cleanup_claim_token = NULL
    WHERE id = abandoned.id;
    reverted_count := reverted_count + 1;
  END LOOP;

  -- An abandoned, never-finalized first upload has no review or publication
  -- record to preserve, so the parent can be removed after its private
  -- objects are gone.
  DELETE FROM public.product_submissions AS submission
  WHERE submission.id = ANY(p_submission_ids)
    AND submission.upload_state = 'cleaning'
    AND submission.evidence_revision = 1
    AND submission.review_status = 'submitted'
    AND submission.cleanup_claimed_at IS NOT NULL;
  GET DIAGNOSTICS deleted_pending_count = ROW_COUNT;

  RETURN purged_retained_count + reverted_count + deleted_pending_count;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_product_submission_cleanup(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_cleanup(integer) TO service_role;
REVOKE ALL ON FUNCTION public.complete_product_submission_cleanup(uuid[],jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_product_submission_cleanup(uuid[],jsonb) TO service_role;

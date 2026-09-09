-- Reviewer workstation: persistent corrections and per-field attestations.
--
-- Two facts the console could not previously keep. A reviewer who reloaded the
-- page lost every correction they had typed and every field they had already
-- read off the photographs, which on a twenty-row multivitamin is the whole
-- job. Both now live in the database, owned by one reviewer, and bound to the
-- exact label text and the exact evidence they were made against.
--
-- Nothing here can approve anything. Approval remains
-- review_product_submission, which consults product_submission_reviewers and
-- the evidence fence on its own. These tables only remember what a human did
-- so the human does not have to do it twice.
--
-- Staleness is compared, never silently repaired. When the label text or the
-- photographs move, older attestations are kept and reported as stale so the
-- console can say which ticks were withdrawn and why, instead of quietly
-- dropping them and letting a reviewer believe work survived that did not.

-- ---------------------------------------------------------------------------
-- 1. One working draft per reviewer per submission.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_reviewer_drafts (
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  evidence_revision integer NOT NULL CHECK (evidence_revision >= 1),
  evidence_manifest_sha256 text NOT NULL
    CHECK (evidence_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  payload jsonb NOT NULL,
  payload_canonical text NOT NULL CHECK (btrim(payload_canonical) <> ''),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (submission_id, reviewer_id)
);
ALTER TABLE public.product_submission_reviewer_drafts
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_reviewer_drafts
  FORCE ROW LEVEL SECURITY;
-- Reached only through the definer functions below: a reviewer's working notes
-- are not readable by other reviewers, by the submitter, or by service_role.
REVOKE ALL ON TABLE public.product_submission_reviewer_drafts
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. One attestation per field, per reviewer, bound to what was on screen.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_field_verifications (
  submission_id uuid NOT NULL,
  reviewer_id uuid NOT NULL,
  field_path text NOT NULL
    CHECK (btrim(field_path) <> '' AND length(field_path) <= 120),
  -- What the label said when the human attested to it. An attestation of an
  -- older value is not an attestation of this one.
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_revision integer NOT NULL CHECK (evidence_revision >= 1),
  evidence_manifest_sha256 text NOT NULL
    CHECK (evidence_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  -- Which photograph the value was read off, when the reviewer said so.
  -- Not a foreign key: photographs are keyed per submission and revision, and
  -- membership of *this* revision is the real rule. It is asserted in
  -- set_product_submission_field_verification, which a key cannot express.
  photo_id uuid,
  verified_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (submission_id, reviewer_id, field_path),
  FOREIGN KEY (submission_id, reviewer_id)
    REFERENCES public.product_submission_reviewer_drafts(submission_id, reviewer_id)
    ON DELETE CASCADE
);
ALTER TABLE public.product_submission_field_verifications
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_field_verifications
  FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_field_verifications
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX product_submission_field_verifications_live_idx
  ON public.product_submission_field_verifications
  (submission_id, reviewer_id, payload_sha256);

-- ---------------------------------------------------------------------------
-- 3. Reviewer access. The allowlist table is the single source of truth; this
--    helper exists so the new entry points cannot each grow their own idea of
--    what a reviewer is.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.assert_product_submission_reviewer() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_reviewer_id uuid := auth.uid();
BEGIN
  IF v_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = v_reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  RETURN v_reviewer_id;
END $$;
REVOKE ALL ON FUNCTION public.assert_product_submission_reviewer()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. The one reader. Every entry point below returns this shape, so the
--    console never has to reconcile two descriptions of the same review.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_reviewer_state_internal(
  p_submission_id uuid, p_reviewer_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
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
REVOKE ALL ON FUNCTION
  public.product_submission_reviewer_state_internal(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Entry points. Each one authenticates the reviewer, fences the evidence
--    through the shared assertion, and returns the same state shape.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.save_product_submission_reviewer_draft(
  p_submission_id uuid,
  p_expected_evidence_revision integer,
  p_evidence_manifest_sha256 text,
  p_payload jsonb,
  p_payload_canonical text,
  p_payload_sha256 text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_reviewer_id uuid := public.assert_product_submission_reviewer();
  submission public.product_submissions%ROWTYPE;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'label payload object required' USING ERRCODE = '22023';
  END IF;
  IF p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
     OR p_payload_canonical IS NULL OR btrim(p_payload_canonical) = '' THEN
    RAISE EXCEPTION 'canonical payload digest required' USING ERRCODE = '22023';
  END IF;
  -- The same fence approval uses. A draft may only be written against
  -- evidence that is still current, so a retake can never be edited blind.
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, p_expected_evidence_revision, p_evidence_manifest_sha256);
  SELECT * INTO submission FROM public.product_submissions
  WHERE id = p_submission_id;
  IF submission.review_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION 'submission is already resolved' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.product_submission_reviewer_drafts AS existing (
    submission_id, reviewer_id, evidence_revision, evidence_manifest_sha256,
    payload, payload_canonical, payload_sha256
  ) VALUES (
    p_submission_id, v_reviewer_id, p_expected_evidence_revision,
    p_evidence_manifest_sha256, p_payload, p_payload_canonical, p_payload_sha256
  )
  ON CONFLICT (submission_id, reviewer_id) DO UPDATE SET
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
    payload = EXCLUDED.payload,
    payload_canonical = EXCLUDED.payload_canonical,
    payload_sha256 = EXCLUDED.payload_sha256,
    updated_at = now()
  -- An unchanged save is not an edit. Leaving the row untouched keeps
  -- updated_at meaningful and avoids waking concurrent readers for nothing.
  WHERE existing.payload_sha256 IS DISTINCT FROM EXCLUDED.payload_sha256
     OR existing.evidence_revision IS DISTINCT FROM EXCLUDED.evidence_revision
     OR existing.evidence_manifest_sha256
        IS DISTINCT FROM EXCLUDED.evidence_manifest_sha256;

  RETURN public.product_submission_reviewer_state_internal(
    p_submission_id, v_reviewer_id);
END $$;

CREATE FUNCTION public.load_product_submission_reviewer_draft(
  p_submission_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_reviewer_id uuid := public.assert_product_submission_reviewer();
BEGIN
  -- Reading is deliberately unfenced: a reviewer returning to a submission
  -- whose photographs changed must be able to see what they had written and
  -- that it is superseded, rather than meeting an error.
  RETURN public.product_submission_reviewer_state_internal(
    p_submission_id, v_reviewer_id);
END $$;

CREATE FUNCTION public.set_product_submission_field_verification(
  p_submission_id uuid,
  p_field_path text,
  p_payload_sha256 text,
  p_verified boolean,
  p_photo_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_reviewer_id uuid := public.assert_product_submission_reviewer();
  draft public.product_submission_reviewer_drafts%ROWTYPE;
BEGIN
  SELECT * INTO draft FROM public.product_submission_reviewer_drafts
  WHERE submission_id = p_submission_id AND reviewer_id = v_reviewer_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'save the reviewed label before attesting to a field'
      USING ERRCODE = '55000';
  END IF;
  -- An attestation names the exact text it attests to. If the caller is
  -- describing a payload that is no longer on screen, the tick is refused
  -- rather than silently rebound to whatever the draft says now.
  IF p_payload_sha256 IS DISTINCT FROM draft.payload_sha256 THEN
    RAISE EXCEPTION 'label changed since this field was read'
      USING ERRCODE = '55000';
  END IF;
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, draft.evidence_revision, draft.evidence_manifest_sha256);
  IF p_photo_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.product_submission_photos AS photo
    WHERE photo.photo_id = p_photo_id AND photo.submission_id = p_submission_id
      AND photo.revision = draft.evidence_revision
  ) THEN
    RAISE EXCEPTION 'source photo is not part of this evidence revision'
      USING ERRCODE = '22023';
  END IF;

  IF p_verified THEN
    INSERT INTO public.product_submission_field_verifications (
      submission_id, reviewer_id, field_path, payload_sha256,
      evidence_revision, evidence_manifest_sha256, photo_id
    ) VALUES (
      p_submission_id, v_reviewer_id, p_field_path, draft.payload_sha256,
      draft.evidence_revision, draft.evidence_manifest_sha256, p_photo_id
    )
    ON CONFLICT (submission_id, reviewer_id, field_path) DO UPDATE SET
      payload_sha256 = EXCLUDED.payload_sha256,
      evidence_revision = EXCLUDED.evidence_revision,
      evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
      photo_id = EXCLUDED.photo_id,
      verified_at = now();
  ELSE
    DELETE FROM public.product_submission_field_verifications
    WHERE submission_id = p_submission_id AND reviewer_id = v_reviewer_id
      AND field_path = p_field_path;
  END IF;

  RETURN public.product_submission_reviewer_state_internal(
    p_submission_id, v_reviewer_id);
END $$;

REVOKE ALL ON FUNCTION public.save_product_submission_reviewer_draft(
  uuid, integer, text, jsonb, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.load_product_submission_reviewer_draft(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_product_submission_field_verification(
  uuid, text, text, boolean, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Reviewers reach these as themselves. service_role stays revoked: a naked
-- key must not be able to author a human's attestation.
GRANT EXECUTE ON FUNCTION public.save_product_submission_reviewer_draft(
  uuid, integer, text, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.load_product_submission_reviewer_draft(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_product_submission_field_verification(
  uuid, text, text, boolean, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. What "fully read" means, owned in one place.
--
--    The console renders a five-item checklist, but a browser cannot be the
--    authority for it: a batch action must not be able to approve an item
--    whose fields nobody ever read. The required set and the assertion live
--    here, so the page is a hint and the database is the rule.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_required_verification_paths()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'identity.brand',
    'identity.product_name',
    'serving.size',
    'ingredient_rows',
    'other_ingredients'
  ]::text[]
$$;

CREATE FUNCTION public.assert_product_submission_fully_verified(
  p_submission_id uuid, p_payload_sha256 text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_reviewer_id uuid := public.assert_product_submission_reviewer();
  draft public.product_submission_reviewer_drafts%ROWTYPE;
  missing text[];
BEGIN
  SELECT * INTO draft FROM public.product_submission_reviewer_drafts
  WHERE submission_id = p_submission_id AND reviewer_id = v_reviewer_id;
  IF NOT FOUND OR draft.payload_sha256 IS DISTINCT FROM p_payload_sha256 THEN
    RAISE EXCEPTION 'this label was not the one reviewed'
      USING ERRCODE = '55000';
  END IF;
  -- The attestations must be this reviewer's, against this exact text, and
  -- against evidence that is still current.
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, draft.evidence_revision, draft.evidence_manifest_sha256);
  SELECT array_agg(required.path ORDER BY required.path) INTO missing
  FROM unnest(public.product_submission_required_verification_paths())
    AS required(path)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.product_submission_field_verifications AS verification
    WHERE verification.submission_id = p_submission_id
      AND verification.reviewer_id = v_reviewer_id
      AND verification.field_path = required.path
      AND verification.payload_sha256 = draft.payload_sha256
      AND verification.evidence_revision = draft.evidence_revision
      AND verification.evidence_manifest_sha256 = draft.evidence_manifest_sha256
  );
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'fields not read off the photographs: %',
      array_to_string(missing, ', ') USING ERRCODE = '55000';
  END IF;
END $$;
REVOKE ALL ON FUNCTION
  public.assert_product_submission_fully_verified(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.assert_product_submission_fully_verified(uuid, text) TO authenticated;

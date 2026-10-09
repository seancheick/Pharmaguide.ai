-- A reviewer can correct the barcode an owner filed.
--
-- The barcode on a missing-product submission is what the owner typed or
-- scanned, and nothing let a reviewer change it. When the owner scanned a
-- neighbouring bottle (Trader Joe's shelves are full of near-identical ones),
-- the label that the photographs show was imported under the wrong barcode:
-- the barcode check, the duplicate guards and the catalog row all read
-- product_submissions.normalized_upc, so approving meant a scan of the other
-- product would answer with this product's score.
--
-- normalized_upc stays the only owner of "the barcode of this submission".
-- A correction rewrites it and appends what was there to a log, so the
-- original filing is never lost and there is no second barcode field to
-- drift. Nothing else needs a change: product_submission_identity_check
-- already compares its recorded check with lpad(normalized_upc, 14, '0'), so
-- a check recorded for the old barcode stops satisfying approval the moment
-- the barcode changes, and the reviewer has to run it again for the new one.
--
-- Only a submission under review can be corrected. create_product_submission
-- finds a retry by its client-chosen id (INSERT ... ON CONFLICT (id) DO NOTHING)
-- and answers it only while the row is still `submitted`; once a reviewer has
-- opened it, every retry already ends in 'submission replay conflict'. A
-- correction made then changes no retry's outcome, and a retry can never create
-- a second submission under the old barcode. Correcting a `submitted` row would
-- turn a retry that succeeds today into that conflict, so it is refused.

CREATE TABLE public.product_submission_barcode_corrections (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  from_upc text NOT NULL
    CHECK (from_upc ~ '^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$'),
  to_upc text NOT NULL
    CHECK (to_upc ~ '^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$'),
  reason text NOT NULL
    CHECK (btrim(reason) <> '' AND char_length(reason) <= 500),
  evidence_revision integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_submission_barcode_correction_changes_identity CHECK (
    public.product_submission_canonical_gtin(from_upc)
      <> public.product_submission_canonical_gtin(to_upc)
  )
);
CREATE INDEX idx_product_submission_barcode_corrections_submission
  ON public.product_submission_barcode_corrections (submission_id, id);
ALTER TABLE public.product_submission_barcode_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_barcode_corrections FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_barcode_corrections
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_submission_barcode_corrections TO service_role;

CREATE FUNCTION public.correct_product_submission_barcode(
  p_submission_id uuid,
  p_new_upc text,
  p_reason text,
  p_expected_revision integer,
  p_manifest_sha256 text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  reviewer_id uuid := auth.uid();
  submission public.product_submissions%ROWTYPE;
  new_upc text;
  reason_value text := btrim(coalesce(p_reason, ''));
  new_target_key text;
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  PERFORM public.assert_product_submission_evidence(
    p_submission_id, p_expected_revision, p_manifest_sha256);

  -- Printed barcodes carry spaces ("0067 1422"); strip exactly what intake
  -- strips, then hold the result to the same GTIN rule intake applies.
  new_upc := NULLIF(regexp_replace(coalesce(p_new_upc, ''), '[^0-9]', '', 'g'), '');
  IF new_upc IS NULL OR NOT public.is_valid_product_submission_gtin(new_upc) THEN
    RAISE EXCEPTION 'valid barcode required' USING ERRCODE = '22023';
  END IF;
  IF reason_value = '' OR char_length(reason_value) > 500 THEN
    RAISE EXCEPTION 'barcode correction reason required' USING ERRCODE = '22023';
  END IF;

  SELECT candidate.*
    INTO submission
  FROM public.product_submissions AS candidate
  WHERE candidate.id = p_submission_id
  FOR UPDATE;
  IF NOT FOUND
     OR submission.kind <> 'missing_product'
     OR submission.normalized_upc IS NULL
     OR submission.upload_state <> 'ready'
     OR submission.promoted_at IS NOT NULL
     OR submission.review_status <> 'under_review' THEN
    RAISE EXCEPTION 'missing-product submission under review required'
      USING ERRCODE = '55000';
  END IF;
  IF public.product_submission_canonical_gtin(new_upc)
     = public.product_submission_canonical_gtin(submission.normalized_upc) THEN
    RAISE EXCEPTION 'barcode unchanged' USING ERRCODE = '22023';
  END IF;

  -- Approval serializes on the review target and refuses a second approved
  -- submission for the same one. Take the same lock on the new barcode, so a
  -- correction cannot slip in beside an approval that is deciding it.
  new_target_key := 'missing_product:'
    || public.product_submission_canonical_gtin(new_upc);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new_target_key, 0));
  IF EXISTS (
    SELECT 1
    FROM public.product_submissions AS other
    WHERE other.id <> p_submission_id
      AND other.review_status = 'approved'
      AND other.promoted_at IS NULL
      AND public.product_submission_review_target_key(other.id) = new_target_key
  ) THEN
    RAISE EXCEPTION 'another approved submission awaits promotion'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.product_submission_barcode_corrections (
    submission_id, reviewer_id, from_upc, to_upc, reason, evidence_revision
  ) VALUES (
    p_submission_id, reviewer_id, submission.normalized_upc, new_upc,
    reason_value, submission.evidence_revision
  );
  -- idx_product_submissions_user_open_upc refuses a barcode the same owner
  -- already has an open submission for, which is the right answer here too.
  UPDATE public.product_submissions
  SET normalized_upc = new_upc
  WHERE id = p_submission_id;

  RETURN jsonb_build_object(
    'from_upc', submission.normalized_upc,
    'to_upc', new_upc
  );
END;
$$;
REVOKE ALL ON FUNCTION public.correct_product_submission_barcode(uuid, text, text, integer, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.correct_product_submission_barcode(uuid, text, text, integer, text)
  TO authenticated;

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
    -- Every reviewer correction of the filed barcode, oldest first, so the
    -- console shows what the owner filed beside what the label prints. The
    -- current barcode stays in product_submissions.normalized_upc alone.
    'barcode_corrections', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'from_upc', correction.from_upc,
        'to_upc', correction.to_upc,
        'reason', correction.reason,
        'corrected_at', correction.created_at
      ) ORDER BY correction.id)
      FROM public.product_submission_barcode_corrections AS correction
      WHERE correction.submission_id = p_submission_id
    ), '[]'::jsonb),
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

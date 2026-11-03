-- ADR-012: the signed release row. Older builds read db_version and checksum and
-- ignore these columns, so applying this changes nothing for them. A build with
-- verification keys reads signed_release and refuses a row without it.

ALTER TABLE public.export_manifest
  ADD COLUMN release_sequence bigint,
  ADD COLUMN signed_release text,
  ADD COLUMN release_signature text,
  ADD CONSTRAINT export_manifest_release_sequence_positive
    CHECK (release_sequence > 0),
  ADD CONSTRAINT export_manifest_signed_release_complete
    CHECK (num_nonnulls(release_sequence, signed_release, release_signature)
           IN (0, 3));

CREATE UNIQUE INDEX export_manifest_release_sequence_unique
  ON public.export_manifest (release_sequence);

-- Dropped rather than replaced: added parameters would leave an overload that
-- makes the publisher's call ambiguous.
DROP FUNCTION public.rotate_manifest_with_submission_approvals(
  text,text,text,text,integer,text,timestamptz,text,jsonb);

CREATE FUNCTION public.rotate_manifest_with_submission_approvals(
  p_db_version text,
  p_pipeline_version text,
  p_scoring_version text,
  p_schema_version text,
  p_product_count integer,
  p_checksum text,
  p_generated_at timestamptz,
  p_min_app_version text DEFAULT '1.0.0',
  p_submission_approvals jsonb DEFAULT '[]'::jsonb,
  p_release_sequence bigint DEFAULT NULL,
  p_signed_release text DEFAULT NULL,
  p_release_signature text DEFAULT NULL
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
  PERFORM public.lock_product_submission_identity();
  IF p_product_count < 0 THEN
    RAISE EXCEPTION 'product_count cannot be negative' USING ERRCODE='22023';
  END IF;
  IF num_nonnulls(p_release_sequence, p_signed_release, p_release_signature)
     NOT IN (0, 3) THEN
    RAISE EXCEPTION 'a signed release needs its sequence, text and signature'
      USING ERRCODE='22023';
  END IF;
  IF p_release_sequence IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.export_manifest AS manifest
    WHERE manifest.release_sequence >= p_release_sequence
  ) THEN
    RAISE EXCEPTION 'release sequence must increase' USING ERRCODE='55000';
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
  -- A version keeps its bytes for life. The one reuse is a signed release naming
  -- the same file under a newer sequence, such as a rules-only release.
  IF FOUND AND (p_release_sequence IS NULL
                OR current_manifest.checksum IS DISTINCT FROM p_checksum) THEN
    RAISE EXCEPTION 'catalog version was already used; use a fresh version'
      USING ERRCODE='55000';
  END IF;
  UPDATE public.export_manifest SET is_current=false WHERE is_current;
  IF current_manifest.id IS NOT NULL THEN
    UPDATE public.export_manifest
    SET is_current=true,
        release_sequence=p_release_sequence,
        signed_release=p_signed_release,
        release_signature=p_release_signature
    WHERE id=current_manifest.id
    RETURNING id INTO new_id;
  ELSE
    INSERT INTO public.export_manifest(
      db_version,pipeline_version,scoring_version,schema_version,
      product_count,checksum,min_app_version,generated_at,is_current,
      release_sequence,signed_release,release_signature
    ) VALUES (
      p_db_version,p_pipeline_version,p_scoring_version,p_schema_version,
      p_product_count,p_checksum,p_min_app_version,p_generated_at,true,
      p_release_sequence,p_signed_release,p_release_signature
    ) RETURNING id INTO new_id;
  END IF;

  PERFORM public.assert_product_submission_catalog_identity();

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
  text,text,text,text,integer,text,timestamptz,text,jsonb,bigint,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_manifest_with_submission_approvals(
  text,text,text,text,integer,text,timestamptz,text,jsonb,bigint,text,text)
  TO service_role;

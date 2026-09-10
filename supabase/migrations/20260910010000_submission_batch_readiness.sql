-- Per-item readiness for batch actions.
--
-- The queue needs to know which submissions this reviewer has actually
-- finished, and it must learn that from the same rule a single approval is
-- held to. This adds no new idea of "ready": it reads the existing reviewer
-- state and the existing required-path list, once per item.
--
-- Nothing here approves anything, and a row appearing here authorizes nothing.
-- Every item in a batch is still applied through the ordinary human transition
-- with its own evidence fence.

CREATE FUNCTION public.product_submission_reviewer_batch_state(
  p_submission_ids uuid[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_reviewer_id uuid := public.assert_product_submission_reviewer();
  result jsonb := '[]'::jsonb;
  candidate uuid;
  state jsonb;
  live_paths text[];
BEGIN
  IF p_submission_ids IS NULL OR array_length(p_submission_ids, 1) IS NULL THEN
    RETURN result;
  END IF;
  -- A batch is one person at one screen. This is not a bulk export.
  IF array_length(p_submission_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too many submissions requested' USING ERRCODE = '22023';
  END IF;

  FOREACH candidate IN ARRAY p_submission_ids LOOP
    BEGIN
      state := public.product_submission_reviewer_state_internal(
        candidate, v_reviewer_id);
    EXCEPTION WHEN others THEN
      -- A submission this reviewer cannot see simply does not appear. It is
      -- not an error for the queue, and it must not leak that it exists.
      CONTINUE;
    END;
    IF state -> 'draft' = 'null'::jsonb OR state -> 'draft' IS NULL THEN
      CONTINUE;
    END IF;
    SELECT COALESCE(array_agg(entry ->> 'field_path'), ARRAY[]::text[])
      INTO live_paths
    FROM jsonb_array_elements(state -> 'verifications') AS entry
    WHERE (entry ->> 'live')::boolean;

    result := result || jsonb_build_array(jsonb_build_object(
      'submission_id', candidate,
      'payload_sha256', state -> 'draft' ->> 'payload_sha256',
      'evidence_revision', (state -> 'draft' ->> 'evidence_revision')::integer,
      'evidence_manifest_sha256', state -> 'draft' ->> 'evidence_manifest_sha256',
      'superseded', (state -> 'draft' ->> 'superseded')::boolean,
      'review_status', state ->> 'review_status',
      -- The same required list the single-approval gate uses.
      'fully_verified', NOT (state -> 'draft' ->> 'superseded')::boolean
        AND public.product_submission_required_verification_paths() <@ live_paths
    ));
  END LOOP;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION
  public.product_submission_reviewer_batch_state(uuid[])
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.product_submission_reviewer_batch_state(uuid[]) TO authenticated;

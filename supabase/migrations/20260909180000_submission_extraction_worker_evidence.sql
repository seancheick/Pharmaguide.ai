-- The real queue client exposed a gap: a leased worker was told which photos to
-- read but had no way to read them. Claim returned content hashes only, and no
-- storage policy admitted the machine account.
--
-- Closing it here rather than inventing a second transport. A signed-URL side
-- channel would have needed the service key in the runner, which is exactly the
-- authority a machine account exists to avoid.

-- ---------------------------------------------------------------------------
-- 1. Claim also returns where the leased bytes live.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_evidence_object_paths(
  p_submission_id uuid,
  p_revision integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_object_agg(photo.photo_id::text, photo.object_path), '{}'::jsonb)
  FROM public.product_submission_evidence_revisions AS revision
  JOIN public.product_submission_photos AS photo
    ON photo.submission_id = revision.submission_id
   AND photo.photo_id = ANY(revision.photo_ids)
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_evidence_object_paths(uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. A worker may read exactly the photos of a revision it currently holds.
-- ---------------------------------------------------------------------------

-- SECURITY DEFINER so the policy can consult the worker allowlist and the job
-- table, neither of which the machine account can read directly.
CREATE FUNCTION public.product_submission_worker_may_read_object(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.product_submission_extraction_workers AS worker
    JOIN public.product_submission_extraction_jobs AS job
      ON job.leased_by = worker.user_id
    JOIN public.product_submission_evidence_revisions AS revision
      ON revision.submission_id = job.submission_id
     AND revision.revision = job.evidence_revision
    JOIN public.product_submission_photos AS photo
      ON photo.submission_id = job.submission_id
     AND photo.photo_id = ANY(revision.photo_ids)
    WHERE worker.user_id = (SELECT auth.uid())
      -- Only while the lease is genuinely live. An expired lease reads nothing,
      -- so a worker cannot keep pulling a person's photos after losing the job.
      AND job.state = 'leased'
      AND job.leased_until > now()
      AND photo.object_path = p_name
  );
$$;
REVOKE ALL ON FUNCTION public.product_submission_worker_may_read_object(text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_worker_may_read_object(text)
  TO authenticated;

CREATE POLICY "product_submission_objects_select_leased_worker"
  ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'product-submission-photos'
    AND public.product_submission_worker_may_read_object(name)
  );

-- ---------------------------------------------------------------------------
-- 3. Claim returns the paths alongside the manifest it already returned.
-- ---------------------------------------------------------------------------

DROP FUNCTION public.claim_product_submission_extraction_jobs(integer);

CREATE FUNCTION public.claim_product_submission_extraction_jobs(
  p_limit integer DEFAULT 1
)
RETURNS TABLE (
  job_id uuid,
  submission_id uuid,
  evidence_revision integer,
  job_key text,
  fencing_token bigint,
  attempts integer,
  leased_until timestamptz,
  evidence_manifest jsonb,
  evidence_object_paths jsonb,
  configuration jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  settings public.product_submission_extraction_settings%ROWTYPE;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'invalid claim limit' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO settings
  FROM public.product_submission_extraction_settings WHERE id;
  IF NOT FOUND OR NOT settings.enabled THEN
    RAISE EXCEPTION 'extraction is disabled' USING ERRCODE = '55000';
  END IF;
  UPDATE public.product_submission_extraction_jobs AS job
  SET state='failed', leased_by=NULL, leased_until=NULL,
      error_code='attempts_exhausted', updated_at=now()
  WHERE job.state='leased' AND job.leased_until <= clock_timestamp()
    AND job.attempts >= settings.max_attempts;
  RETURN QUERY
  WITH claimable AS (
    SELECT job.id
    FROM public.product_submission_extraction_jobs AS job
    JOIN public.product_submissions AS submission
      ON submission.id = job.submission_id
    WHERE (
        job.state IN ('queued', 'retryable_error', 'budget_hold')
        OR (job.state = 'leased' AND job.leased_until < now())
      )
      AND job.next_attempt_at <= now()
      AND job.attempts < settings.max_attempts
      AND submission.upload_state = 'ready'
      AND submission.evidence_revision = job.evidence_revision
      AND submission.review_status IN ('submitted', 'under_review')
      -- Identical to the clause this function already carried: explicit
      -- AI-draft consent, effective when the evidence was captured.
      AND EXISTS (
        SELECT 1 FROM public.product_submission_evidence_revisions revision
        JOIN public.product_submission_consent_versions consent
          ON consent.version=revision.consent_version AND consent.kind=submission.kind
        WHERE revision.submission_id=submission.id AND revision.revision=job.evidence_revision
          AND consent.retired_at IS NULL AND consent.effective_from <= revision.consented_at
          AND 'ai_label_draft'=ANY(consent.purposes))
    ORDER BY job.next_attempt_at, job.created_at
    FOR UPDATE OF job SKIP LOCKED
    LIMIT p_limit
  ), leased AS (
    UPDATE public.product_submission_extraction_jobs AS job
    SET state = 'leased',
        attempts = job.attempts + 1,
        fencing_token = job.fencing_token + 1,
        leased_by = worker_id,
        leased_until = now() + make_interval(secs => settings.lease_seconds),
        updated_at = now()
    FROM claimable
    WHERE job.id = claimable.id
    RETURNING job.*
  )
  SELECT leased.id, leased.submission_id, leased.evidence_revision,
         leased.job_key, leased.fencing_token, leased.attempts,
         leased.leased_until,
         public.product_submission_evidence_manifest(
           leased.submission_id, leased.evidence_revision
         ),
         public.product_submission_evidence_object_paths(
           leased.submission_id, leased.evidence_revision
         ),
         leased.configuration
  FROM leased;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_product_submission_extraction_jobs(integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_extraction_jobs(integer)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Proving what happened to one attempt.
-- ---------------------------------------------------------------------------

-- A completion can time out with the transaction already committed. Retrying
-- blind would double-charge or file a second draft; giving up blind would
-- strand a reservation and lose a draft that exists. The worker asks instead.
--
-- Keyed on the exact attempt, not the job: a later attempt's result is not
-- evidence about this one.
CREATE FUNCTION public.product_submission_extraction_attempt_outcome(
  p_job_id uuid,
  p_fencing_token bigint
)
RETURNS TABLE (
  attempt_is_current boolean,
  job_state public.product_submission_extraction_job_state,
  result_extraction_version integer,
  draft_recorded boolean,
  reservation_open boolean,
  reserved_microcents bigint,
  settled_microcents bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  job public.product_submission_extraction_jobs%ROWTYPE;
BEGIN
  SELECT * INTO job
  FROM public.product_submission_extraction_jobs
  WHERE id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'extraction job not found' USING ERRCODE = '55000';
  END IF;
  RETURN QUERY
  SELECT
    job.fencing_token = p_fencing_token,
    job.state,
    CASE WHEN job.fencing_token = p_fencing_token
      THEN job.result_extraction_version ELSE NULL END,
    -- The draft itself, not the job row, is what proves the write landed.
    EXISTS (
      SELECT 1 FROM public.product_submission_extractions AS extraction
      WHERE extraction.submission_id = job.submission_id
        AND extraction.evidence_revision = job.evidence_revision
        AND extraction.actor_kind = 'worker'
        AND extraction.version = job.result_extraction_version
        AND job.fencing_token = p_fencing_token
    ),
    EXISTS (
      SELECT 1 FROM public.product_submission_extraction_budget AS budget
      WHERE budget.job_id = p_job_id AND budget.fencing_token = p_fencing_token
        AND NOT budget.settled
    ),
    coalesce((SELECT budget.reserved_microcents
      FROM public.product_submission_extraction_budget AS budget
      WHERE budget.job_id = p_job_id AND budget.fencing_token = p_fencing_token), 0)::bigint,
    coalesce((SELECT budget.microcents
      FROM public.product_submission_extraction_budget AS budget
      WHERE budget.job_id = p_job_id AND budget.fencing_token = p_fencing_token
        AND budget.settled), 0)::bigint;
END;
$$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_attempt_outcome(uuid, bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_extraction_attempt_outcome(uuid, bigint)
  TO authenticated;

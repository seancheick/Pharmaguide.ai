-- The claim hands the worker the identity context its deterministic checks need.
--
-- run_checks() can compare the barcode a label prints against the barcode the
-- submission was filed under, and can report that a barcode already resolves
-- in the catalog. Neither could fire in production: the claim never told the
-- worker either fact, and a worker reads nothing but its own lease.
--
-- Two rules shaped this.
--
-- The context is *identity*, not label content. It travels beside the lease
-- and never joins the prepared bytes, so it cannot reach a provider adapter. A
-- model told which catalog entry we suspect is free to agree with us, and its
-- agreement would mean nothing.
--
-- A catalog hit is a candidate, never a disposition. no_match_verified is the
-- reviewer having established the opposite, so it yields no candidate at all.
--
-- This function has been redefined once already, so the definition below is
-- built from the current one. Rebuilding from an older ancestor silently drops
-- whatever the later migration added.

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
  configuration jsonb,
  submission_gtin text,
  catalog_match jsonb
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
         leased.configuration,
         -- One GTIN owner: the same canonicalization the app, the importer and
         -- the dedupe index use. The worker never re-derives it.
         public.product_submission_canonical_gtin(submission.normalized_upc),
         (
           SELECT jsonb_build_object(
             'outcome', match_check.outcome,
             'matched_dsld_id', match_check.matched_dsld_id,
             'candidate_dsld_ids', to_jsonb(match_check.candidate_dsld_ids),
             'canonical_gtin14', match_check.canonical_gtin14
           )
           FROM public.product_submission_match_checks AS match_check
           WHERE match_check.submission_id = leased.submission_id
             -- A check against replaced photographs describes other evidence.
             AND (match_check.evidence_revision IS NULL
                  OR match_check.evidence_revision = leased.evidence_revision)
             -- no_match_verified is the reviewer having established that this
             -- barcode is NOT in the catalog: no candidate to offer.
             AND match_check.outcome IN
                 ('catalog_match', 'dsld_match', 'identity_ambiguous')
           ORDER BY match_check.id DESC
           LIMIT 1
         )
  FROM leased
  JOIN public.product_submissions AS submission
    ON submission.id = leased.submission_id;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_product_submission_extraction_jobs(integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_extraction_jobs(integer)

  TO authenticated;

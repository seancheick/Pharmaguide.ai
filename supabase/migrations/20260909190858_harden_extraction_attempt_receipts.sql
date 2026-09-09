-- Receipt history is a projection of the queue, not a second transition engine.
CREATE TABLE public.product_submission_extraction_attempt_receipts (
  job_id uuid NOT NULL REFERENCES public.product_submission_extraction_jobs(id) ON DELETE CASCADE,
  fencing_token bigint NOT NULL CHECK (fencing_token > 0),
  worker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state public.product_submission_extraction_job_state NOT NULL,
  result_extraction_version integer,
  PRIMARY KEY(job_id, fencing_token)
);
ALTER TABLE public.product_submission_extraction_attempt_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extraction_attempt_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.product_submission_extraction_attempt_receipts FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.product_submission_extraction_attempt_receipts TO service_role;

CREATE FUNCTION public.record_extraction_attempt_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.state='leased' AND NEW.leased_by IS NOT NULL THEN
    INSERT INTO public.product_submission_extraction_attempt_receipts
      (job_id,fencing_token,worker_id,state,result_extraction_version)
    VALUES(NEW.id,NEW.fencing_token,NEW.leased_by,NEW.state,NEW.result_extraction_version)
    ON CONFLICT(job_id,fencing_token) DO NOTHING;
  END IF;
  UPDATE public.product_submission_extraction_attempt_receipts
    SET state=NEW.state,result_extraction_version=NEW.result_extraction_version
    WHERE job_id=NEW.id AND fencing_token=NEW.fencing_token;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.record_extraction_attempt_receipt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER record_extraction_attempt_receipt
AFTER INSERT OR UPDATE ON public.product_submission_extraction_jobs
FOR EACH ROW EXECUTE FUNCTION public.record_extraction_attempt_receipt();
-- Existing live leases have a known owner. Never invent ownership of old attempts.
INSERT INTO public.product_submission_extraction_attempt_receipts
  (job_id,fencing_token,worker_id,state,result_extraction_version)
SELECT id,fencing_token,leased_by,state,result_extraction_version
FROM public.product_submission_extraction_jobs
WHERE state='leased' AND leased_by IS NOT NULL AND fencing_token>0;

CREATE OR REPLACE FUNCTION public.product_submission_extraction_attempt_outcome(
  p_job_id uuid, p_fencing_token bigint
) RETURNS TABLE (
  attempt_is_current boolean, job_state public.product_submission_extraction_job_state,
  result_extraction_version integer, draft_recorded boolean,
  reservation_open boolean, reserved_microcents bigint, settled_microcents bigint
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  caller uuid := public.product_submission_extraction_worker_id();
  receipt public.product_submission_extraction_attempt_receipts%ROWTYPE;
BEGIN
  SELECT * INTO receipt FROM public.product_submission_extraction_attempt_receipts
  WHERE job_id=p_job_id AND fencing_token=p_fencing_token AND worker_id=caller;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'extraction attempt access required' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT job.fencing_token=p_fencing_token, receipt.state, receipt.result_extraction_version,
    EXISTS(SELECT 1 FROM public.product_submission_extractions e
           WHERE e.submission_id=job.submission_id AND e.evidence_revision=job.evidence_revision
             AND e.version=receipt.result_extraction_version AND e.actor_kind='worker'
             AND e.recorded_by=caller),
    coalesce(NOT budget.settled,false),
    coalesce(budget.reserved_microcents,0)::bigint,
    CASE WHEN budget.settled THEN budget.microcents ELSE 0 END::bigint
  FROM public.product_submission_extraction_jobs job
  LEFT JOIN public.product_submission_extraction_budget budget
    ON budget.job_id=job.id AND budget.fencing_token=p_fencing_token
  WHERE job.id=p_job_id;
END $$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_attempt_outcome(uuid,bigint)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_extraction_attempt_outcome(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.product_submission_worker_may_read_object(p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT EXISTS(
  SELECT 1 FROM public.product_submission_extraction_workers worker
  JOIN public.product_submission_extraction_jobs job ON job.leased_by=worker.user_id
  JOIN public.product_submissions submission ON submission.id=job.submission_id
  JOIN public.product_submission_evidence_revisions revision
    ON revision.submission_id=job.submission_id AND revision.revision=job.evidence_revision
  JOIN public.product_submission_photos photo
    ON photo.submission_id=job.submission_id AND photo.photo_id=ANY(revision.photo_ids)
  JOIN public.product_submission_consent_versions consent
    ON consent.version=revision.consent_version AND consent.kind=submission.kind
  WHERE worker.user_id=(SELECT auth.uid()) AND job.state='leased'
    AND job.leased_until>now() AND photo.object_path=p_name
    AND submission.evidence_revision=job.evidence_revision AND submission.upload_state='ready'
    AND submission.review_status IN ('submitted','under_review')
    AND consent.retired_at IS NULL AND consent.effective_from<=revision.consented_at
    AND 'ai_label_draft'=ANY(consent.purposes)
    AND EXISTS(SELECT 1 FROM public.product_submission_extraction_settings WHERE id AND enabled)
);
$$;
REVOKE ALL ON FUNCTION public.product_submission_worker_may_read_object(text)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_worker_may_read_object(text) TO authenticated;

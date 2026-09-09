-- Batch 3: the extraction queue, its worker identity, and the budget it must
-- stay inside. Additive. Extraction is OFF on arrival: the settings row ships
-- disabled, so deploying this migration enqueues nothing and calls no
-- provider. Turning it on is a separate, deliberate act.
--
-- Two boundaries this file exists to hold:
--   * a worker is not a reviewer. It has its own allowlist, it can never be in
--     the reviewer allowlist, and approval consults reviewers only. A machine
--     cannot approve a product no matter what it drafts.
--   * a worker writes drafts through the SAME validator and persistence the
--     human path uses. There is one writer with one set of rules; only the
--     recorded actor differs.

-- ---------------------------------------------------------------------------
-- 1. One draft writer, two authorized callers.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_extraction_workers (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL CHECK (btrim(label) <> ''),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.product_submission_extraction_workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extraction_workers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_extraction_workers
  FROM PUBLIC, anon, authenticated, service_role;

-- A machine identity must never also be a human approver, in either direction.
CREATE FUNCTION public.reject_worker_reviewer_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'product_submission_extraction_workers' THEN
    IF EXISTS (
      SELECT 1 FROM public.product_submission_reviewers AS reviewer
      WHERE reviewer.user_id = NEW.user_id
    ) THEN
      RAISE EXCEPTION 'a reviewer cannot also be an extraction worker'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.product_submission_extraction_workers AS worker
      WHERE worker.user_id = NEW.user_id
    ) THEN
      RAISE EXCEPTION 'an extraction worker cannot also be a reviewer'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER product_submission_worker_not_reviewer
  BEFORE INSERT OR UPDATE ON public.product_submission_extraction_workers
  FOR EACH ROW EXECUTE FUNCTION public.reject_worker_reviewer_overlap();
CREATE TRIGGER product_submission_reviewer_not_worker
  BEFORE INSERT OR UPDATE ON public.product_submission_reviewers
  FOR EACH ROW EXECUTE FUNCTION public.reject_worker_reviewer_overlap();

-- The existing human writer becomes the shared internal one. Its rules are
-- unchanged; it now takes the actor instead of reading auth.uid() itself.
ALTER FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) RENAME TO record_product_submission_extraction_internal;

CREATE OR REPLACE FUNCTION public.record_product_submission_extraction_internal(
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
  p_evidence_revision integer DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_actor_kind text DEFAULT 'reviewer'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  next_version integer;
  submission public.product_submissions%ROWTYPE;
  manifest jsonb;
BEGIN
  IF p_actor_id IS NULL OR p_actor_kind NOT IN ('reviewer', 'worker') THEN
    RAISE EXCEPTION 'extraction actor required' USING ERRCODE = '22023';
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
  -- A machine may only file machine-read drafts. Human transcription is a
  -- human act and cannot be attributed to a worker.
  IF p_actor_kind = 'worker'
     AND p_draft_payload->>'draft_origin' <> 'model' THEN
    RAISE EXCEPTION 'a worker may only record a model draft'
      USING ERRCODE = '22023';
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
    submission_id, recorded_by, version, schema_version, provider, model,
    prompt_version, input_image_hashes, draft_payload, field_provenance,
    confidence, usage, actor_kind, evidence_revision
  ) VALUES (
    p_submission_id, p_actor_id, next_version, btrim(p_schema_version),
    btrim(p_provider), btrim(p_model), btrim(p_prompt_version),
    p_input_image_hashes, p_draft_payload, p_field_provenance, p_confidence,
    p_usage, p_actor_kind, submission.evidence_revision
  );
  RETURN next_version;
END;
$$;
REVOKE ALL ON FUNCTION public.record_product_submission_extraction_internal(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer, uuid, text
) FROM PUBLIC, anon, authenticated, service_role;
-- Adding actor parameters creates an overload, not a replacement. Remove the
-- renamed eleven-argument writer so it cannot remain a second callable path.
DROP FUNCTION public.record_product_submission_extraction_internal(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
);

-- The human path: unchanged signature, unchanged authorization.
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
BEGIN
  IF reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_reviewers AS reviewer
    WHERE reviewer.user_id = reviewer_id
  ) THEN
    RAISE EXCEPTION 'reviewer access required' USING ERRCODE = '42501';
  END IF;
  RETURN public.record_product_submission_extraction_internal(
    p_submission_id, p_schema_version, p_provider, p_model, p_prompt_version,
    p_input_image_hashes, p_draft_payload, p_field_provenance, p_confidence,
    p_usage, p_evidence_revision, reviewer_id, 'reviewer'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_product_submission_extraction(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Settings, budget and the queue itself.
-- ---------------------------------------------------------------------------

CREATE TABLE public.product_submission_extraction_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  -- Ships disabled. Deploying this migration must not start calling a
  -- provider, and no model has qualified.
  enabled boolean NOT NULL DEFAULT false,
  provider text CHECK (provider IS NULL OR btrim(provider) <> ''),
  model text CHECK (model IS NULL OR btrim(model) <> ''),
  model_digest text CHECK (model_digest IS NULL OR model_digest ~ '^[0-9a-f]{64}$'),
  prompt_version text CHECK (prompt_version IS NULL OR btrim(prompt_version) <> ''),
  prep_config_version text NOT NULL DEFAULT 'prep_v1'
    CHECK (btrim(prep_config_version) <> ''),
  retention_policy_version text CHECK (btrim(retention_policy_version) <> ''),
  max_cost_microcents bigint NOT NULL DEFAULT 0 CHECK (max_cost_microcents >= 0),
  max_attempts integer NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
  lease_seconds integer NOT NULL DEFAULT 300
    CHECK (lease_seconds BETWEEN 30 AND 3600),
  pilot_cap_microcents bigint NOT NULL DEFAULT 0 CHECK (pilot_cap_microcents >= 0),
  monthly_cap_microcents bigint NOT NULL DEFAULT 0
    CHECK (monthly_cap_microcents >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- Enabling requires naming exactly what will run, so "on" can never mean an
  -- unpinned model.
  CONSTRAINT product_submission_extraction_settings_enabled_is_specified CHECK (
    NOT enabled OR (
      provider IS NOT NULL AND model IS NOT NULL
      AND model_digest IS NOT NULL AND prompt_version IS NOT NULL
      AND monthly_cap_microcents > 0
      AND retention_policy_version IS NOT NULL
      AND (provider IN ('fake', 'ollama') OR max_cost_microcents > 0)
    )
  )
);
ALTER TABLE public.product_submission_extraction_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extraction_settings FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_extraction_settings
  FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO public.product_submission_extraction_settings (id) VALUES (true);

CREATE TYPE public.product_submission_extraction_job_state AS ENUM (
  'queued',
  'leased',
  'review_ready',
  'needs_evidence',
  'budget_hold',
  'retryable_error',
  'failed',
  'cancelled'
);

CREATE TABLE public.product_submission_extraction_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  evidence_revision integer NOT NULL CHECK (evidence_revision >= 1),
  -- Identity of the work, not of the row: the exact evidence plus the exact
  -- preparation. Re-readying the same revision cannot enqueue twice, and a
  -- new revision is different work.
  job_key text NOT NULL CHECK (job_key ~ '^[0-9a-f]{64}$'),
  configuration jsonb NOT NULL CHECK (jsonb_typeof(configuration) = 'object'),
  state public.product_submission_extraction_job_state NOT NULL DEFAULT 'queued',
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  -- Bumped on every claim. A worker whose lease expired holds a stale token
  -- and cannot complete over the worker that replaced it.
  fencing_token bigint NOT NULL DEFAULT 0,
  leased_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  leased_until timestamptz,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  error_code text CHECK (error_code IS NULL OR btrim(error_code) <> ''),
  result_extraction_version integer
    CHECK (result_extraction_version IS NULL OR result_extraction_version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_submission_extraction_jobs_key_unique
    UNIQUE (submission_id, job_key),
  CONSTRAINT product_submission_extraction_jobs_lease_shape CHECK (
    (state = 'leased') = (leased_by IS NOT NULL AND leased_until IS NOT NULL)
  )
);
ALTER TABLE public.product_submission_extraction_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extraction_jobs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_extraction_jobs
  FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX idx_product_submission_extraction_jobs_ready
  ON public.product_submission_extraction_jobs (next_attempt_at)
  WHERE state IN ('queued', 'retryable_error');

CREATE TABLE public.product_submission_extraction_budget (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id uuid REFERENCES public.product_submission_extraction_jobs(id)
    ON DELETE SET NULL,
  month_key text NOT NULL CHECK (month_key ~ '^[0-9]{4}-[0-9]{2}$'),
  -- Integer micro-cents. Money in floating point drifts, and a cap that
  -- drifts is not a cap.
  microcents bigint NOT NULL CHECK (microcents >= 0),
  fencing_token bigint NOT NULL,
  reserved_microcents bigint NOT NULL CHECK (reserved_microcents >= 0),
  settled boolean NOT NULL DEFAULT false,
  UNIQUE (job_id, fencing_token),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.product_submission_extraction_budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_submission_extraction_budget FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_submission_extraction_budget
  FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX idx_product_submission_extraction_budget_month
  ON public.product_submission_extraction_budget (month_key);

-- ---------------------------------------------------------------------------
-- 3. Enqueue when a revision becomes ready. No network in the transaction.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_extraction_job_key(
  p_submission_id uuid,
  p_revision integer,
  p_prep_config_version text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT encode(
    extensions.digest(
      convert_to(
        p_submission_id::text || ':' || p_revision::text || ':'
          || coalesce(revision.manifest_sha256, '') || ':'
          || p_prep_config_version,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  FROM public.product_submission_evidence_revisions AS revision
  WHERE revision.submission_id = p_submission_id
    AND revision.revision = p_revision;
$$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_job_key(uuid, integer, text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.enqueue_product_submission_extraction()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  settings public.product_submission_extraction_settings%ROWTYPE;
  key text;
BEGIN
  -- A retake or terminal review must not leave an old job stranded in the
  -- queue. Leased work is fenced by clearing its lease; a stale worker then
  -- fails the same lease check as any other expired attempt. Completed draft
  -- history is retained for audit and is deliberately not cancelled.
  IF NEW.evidence_revision IS DISTINCT FROM OLD.evidence_revision THEN
    UPDATE public.product_submission_extraction_jobs
    SET state = 'cancelled', leased_by = NULL, leased_until = NULL,
        error_code = 'superseded_evidence', updated_at = now()
    WHERE submission_id = NEW.id
      AND evidence_revision <> NEW.evidence_revision
      AND state IN ('queued', 'leased', 'retryable_error', 'budget_hold');
  ELSIF NEW.review_status NOT IN ('submitted', 'under_review')
        AND OLD.review_status IN ('submitted', 'under_review') THEN
    UPDATE public.product_submission_extraction_jobs
    SET state = 'cancelled', leased_by = NULL, leased_until = NULL,
        error_code = 'submission_closed', updated_at = now()
    WHERE submission_id = NEW.id
      AND state IN ('queued', 'leased', 'retryable_error', 'budget_hold');
  END IF;

  IF NEW.upload_state <> 'ready' OR OLD.upload_state = 'ready' THEN
    RETURN NEW;
  END IF;
  IF NEW.kind <> 'missing_product'
     OR NEW.review_status NOT IN ('submitted', 'under_review') THEN
    RETURN NEW;
  END IF;
  -- No consent, no automated reading of this person's photos, and the consent
  -- that matters is the one this REVISION was captured under, not whatever the
  -- contribution started with. Legacy receipts carry none and stay manual.
  IF NOT EXISTS (
    SELECT 1
    FROM public.product_submission_evidence_revisions AS revision
    JOIN public.product_submission_consent_versions AS consent
      ON consent.version = revision.consent_version
     AND consent.kind = NEW.kind
     AND consent.retired_at IS NULL
     AND consent.effective_from <= revision.consented_at
     AND 'ai_label_draft' = ANY(consent.purposes)
    WHERE revision.submission_id = NEW.id
      AND revision.revision = NEW.evidence_revision
  ) THEN
    RETURN NEW;
  END IF;
  SELECT * INTO settings
  FROM public.product_submission_extraction_settings
  WHERE id;
  IF NOT FOUND OR NOT settings.enabled THEN
    RETURN NEW;
  END IF;
  key := public.product_submission_extraction_job_key(
    NEW.id, NEW.evidence_revision, settings.prep_config_version
  );
  IF key IS NULL THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.product_submission_extraction_jobs (
    submission_id, evidence_revision, job_key, configuration
  ) VALUES (NEW.id, NEW.evidence_revision, key, jsonb_build_object(
    'provider', settings.provider, 'model', settings.model,
    'model_digest', settings.model_digest, 'prompt_version', settings.prompt_version,
    'prep_config_version', settings.prep_config_version,
    'retention_policy_version', settings.retention_policy_version,
    'max_cost_microcents', settings.max_cost_microcents))
  ON CONFLICT (submission_id, job_key) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER product_submission_extraction_enqueue
  AFTER UPDATE OF upload_state, review_status, evidence_revision
  ON public.product_submissions
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_product_submission_extraction();

-- ---------------------------------------------------------------------------
-- 4. Worker RPCs. Every one derives the actor from the session and checks the
--    worker allowlist; service_role and anon are revoked throughout.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.product_submission_extraction_worker_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := auth.uid();
BEGIN
  IF worker_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.product_submission_extraction_workers AS worker
    WHERE worker.user_id = worker_id
  ) THEN
    RAISE EXCEPTION 'extraction worker access required' USING ERRCODE = '42501';
  END IF;
  RETURN worker_id;
END;
$$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_worker_id()
  FROM PUBLIC, anon, authenticated, service_role;

-- Claim work. Returns the job plus the evidence manifest of the exact revision
-- leased, so a worker never has to go looking for photos itself.
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
      -- Never lease work whose evidence already moved on.
      AND submission.upload_state = 'ready'
      AND submission.evidence_revision = job.evidence_revision
      AND submission.review_status IN ('submitted', 'under_review')
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
         ), leased.configuration
  FROM leased;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_product_submission_extraction_jobs(integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_product_submission_extraction_jobs(integer)
  TO authenticated;

CREATE FUNCTION public.heartbeat_product_submission_extraction_job(
  p_job_id uuid,
  p_fencing_token bigint
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  settings public.product_submission_extraction_settings%ROWTYPE;
  extended timestamptz;
BEGIN
  SELECT * INTO settings
  FROM public.product_submission_extraction_settings WHERE id;
  UPDATE public.product_submission_extraction_jobs
  SET leased_until = now() + make_interval(secs => settings.lease_seconds),
      updated_at = now()
  WHERE id = p_job_id
    AND state = 'leased'
    AND leased_by = worker_id
    AND fencing_token = p_fencing_token
    AND leased_until > clock_timestamp()
  RETURNING leased_until INTO extended;
  IF extended IS NULL THEN
    RAISE EXCEPTION 'extraction lease is not held' USING ERRCODE = '55000';
  END IF;
  RETURN extended;
END;
$$;
REVOKE ALL ON FUNCTION public.heartbeat_product_submission_extraction_job(uuid, bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.heartbeat_product_submission_extraction_job(uuid, bigint)
  TO authenticated;

-- Record a model draft and close the job in one transaction, under the lease
-- the caller actually holds.
CREATE FUNCTION public.complete_product_submission_extraction_job(
  p_job_id uuid,
  p_fencing_token bigint,
  p_outcome text,
  p_schema_version text DEFAULT NULL,
  p_provider text DEFAULT NULL,
  p_model text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_input_image_hashes jsonb DEFAULT NULL,
  p_draft_payload jsonb DEFAULT NULL,
  p_field_provenance jsonb DEFAULT NULL,
  p_confidence numeric DEFAULT NULL,
  p_usage jsonb DEFAULT NULL,
  p_error_code text DEFAULT NULL,
  p_cost_microcents bigint DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  settings public.product_submission_extraction_settings%ROWTYPE;
  job public.product_submission_extraction_jobs%ROWTYPE;
  recorded_version integer;
  next_state public.product_submission_extraction_job_state;
  reservation public.product_submission_extraction_budget%ROWTYPE;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('review_ready', 'needs_evidence', 'retryable_error', 'failed', 'budget_hold') THEN
    RAISE EXCEPTION 'invalid extraction outcome' USING ERRCODE = '22023';
  END IF;
  IF p_cost_microcents < 0 THEN
    RAISE EXCEPTION 'invalid extraction cost' USING ERRCODE = '22023';
  END IF;
  -- Settlement shares the reservation lock so allowance is always consistent.
  SELECT * INTO settings
  FROM public.product_submission_extraction_settings WHERE id FOR UPDATE;
  -- Review/retake locks the receipt before its jobs. Use that same order so
  -- concurrent completion cannot deadlock against the cancellation trigger.
  PERFORM 1 FROM public.product_submissions
  WHERE id=(SELECT submission_id FROM public.product_submission_extraction_jobs WHERE id=p_job_id)
  FOR UPDATE;
  SELECT * INTO job
  FROM public.product_submission_extraction_jobs
  WHERE id = p_job_id
  FOR UPDATE;
  IF NOT FOUND
     OR job.state <> 'leased'
     OR job.leased_by <> worker_id
     OR job.fencing_token IS DISTINCT FROM p_fencing_token
     OR job.leased_until <= clock_timestamp() THEN
    -- An expired attempt must never overwrite the result of the worker that
    -- replaced it, even when it is the same worker.
    RAISE EXCEPTION 'extraction lease is not held' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO reservation FROM public.product_submission_extraction_budget
  WHERE job_id=p_job_id AND fencing_token=p_fencing_token;
  IF (p_outcome='review_ready' OR p_cost_microcents>0) AND NOT FOUND THEN
    RAISE EXCEPTION 'extraction budget reservation required' USING ERRCODE='55000';
  END IF;
  IF p_outcome='budget_hold' AND reservation.id IS NOT NULL THEN
    RAISE EXCEPTION 'reserved attempts cannot report an admission hold' USING ERRCODE='22023';
  END IF;

  IF p_outcome = 'review_ready' THEN
    IF p_provider IS DISTINCT FROM job.configuration->>'provider'
       OR p_model IS DISTINCT FROM job.configuration->>'model'
       OR p_prompt_version IS DISTINCT FROM job.configuration->>'prompt_version' THEN
      RAISE EXCEPTION 'draft does not match leased configuration' USING ERRCODE='22023';
    END IF;
    recorded_version := public.record_product_submission_extraction_internal(
      job.submission_id, p_schema_version, p_provider, p_model,
      p_prompt_version, p_input_image_hashes, p_draft_payload,
      p_field_provenance, p_confidence, p_usage, job.evidence_revision,
      worker_id, 'worker'
    );
  END IF;

  next_state := p_outcome::public.product_submission_extraction_job_state;
  IF p_outcome = 'retryable_error' AND job.attempts >= settings.max_attempts THEN
    next_state := 'failed';
  END IF;

  UPDATE public.product_submission_extraction_jobs
  SET state = next_state,
      -- Admission denial did not call a provider; it must not exhaust retries.
      attempts = CASE WHEN next_state='budget_hold' THEN greatest(0,job.attempts-1) ELSE job.attempts END,
      leased_by = NULL,
      leased_until = NULL,
      error_code = NULLIF(btrim(coalesce(p_error_code, '')), ''),
      result_extraction_version = recorded_version,
      -- Exponential backoff, capped, so a failing provider is not hammered.
      next_attempt_at = CASE
        WHEN next_state = 'retryable_error'
          THEN now() + make_interval(
            secs => least(3600, 60 * power(2, job.attempts)::integer)
          )
        ELSE now()
      END,
      updated_at = now()
  WHERE id = p_job_id;

  IF reservation.id IS NOT NULL AND p_cost_microcents IS NOT NULL THEN
    -- Never discard a cost already incurred. An adapter exceeding its declared
    -- bound disables new spending; the truthful charge and draft still persist.
    UPDATE public.product_submission_extraction_budget
    SET microcents=p_cost_microcents, settled=true WHERE id=reservation.id;
    IF p_cost_microcents > reservation.reserved_microcents THEN
      UPDATE public.product_submission_extraction_settings SET enabled=false WHERE id;
    END IF;
  END IF;
  RETURN recorded_version;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_product_submission_extraction_job(
  uuid, bigint, text, text, text, text, text, jsonb, jsonb, jsonb, numeric,
  jsonb, text, bigint
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.complete_product_submission_extraction_job(
  uuid, bigint, text, text, text, text, text, jsonb, jsonb, jsonb, numeric,
  jsonb, text, bigint
) TO authenticated;

-- One ledger calculation, shared by admission and operator reporting. Unknown
-- costs (crash/timeout) retain their reservation until explicitly reconciled.
CREATE FUNCTION public.product_submission_extraction_allowance()
RETURNS TABLE (spent bigint, outstanding bigint, remaining bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  WITH totals AS (
    SELECT coalesce(sum(microcents) FILTER (WHERE month_key=to_char(now() AT TIME ZONE 'UTC','YYYY-MM')),0) AS monthly,
      coalesce(sum(reserved_microcents) FILTER (WHERE NOT settled),0) AS pending,
      coalesce(sum(microcents),0) AS lifetime
    FROM public.product_submission_extraction_budget)
  SELECT monthly::bigint, pending::bigint,
    greatest(0, least(settings.monthly_cap_microcents-monthly-pending,
      CASE WHEN settings.pilot_cap_microcents>0 THEN settings.pilot_cap_microcents-lifetime-pending
           ELSE settings.monthly_cap_microcents-monthly-pending END))::bigint
  FROM totals CROSS JOIN public.product_submission_extraction_settings settings WHERE settings.id;
$$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_allowance() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.reserve_product_submission_extraction_budget(p_job_id uuid, p_fencing_token bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  settings public.product_submission_extraction_settings%ROWTYPE;
  job public.product_submission_extraction_jobs%ROWTYPE;
  needed bigint;
BEGIN
  SELECT * INTO settings FROM public.product_submission_extraction_settings WHERE id FOR UPDATE;
  IF NOT settings.enabled THEN RAISE EXCEPTION 'extraction is disabled' USING ERRCODE='55000'; END IF;
  SELECT * INTO job FROM public.product_submission_extraction_jobs WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND OR job.state<>'leased' OR job.leased_by<>worker_id OR job.fencing_token IS DISTINCT FROM p_fencing_token
     OR job.leased_until<=clock_timestamp() THEN
    RAISE EXCEPTION 'extraction lease is not held' USING ERRCODE='55000';
  END IF;
  IF EXISTS(SELECT 1 FROM public.product_submission_extraction_budget WHERE job_id=p_job_id AND fencing_token=p_fencing_token) THEN
    RETURN true;
  END IF;
  needed := (job.configuration->>'max_cost_microcents')::bigint;
  IF needed > (SELECT remaining FROM public.product_submission_extraction_allowance()) THEN RETURN false; END IF;
  INSERT INTO public.product_submission_extraction_budget(job_id, fencing_token, month_key, microcents, reserved_microcents)
  VALUES(p_job_id,p_fencing_token,to_char(now() AT TIME ZONE 'UTC','YYYY-MM'),0,needed);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_product_submission_extraction_budget(uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_product_submission_extraction_budget(uuid,bigint) TO authenticated;

-- Includes outstanding reservations and the pilot cap.
CREATE FUNCTION public.product_submission_extraction_budget_state()
RETURNS TABLE (month_key text, spent_microcents bigint, monthly_cap_microcents bigint, remaining_microcents bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  worker_id uuid := public.product_submission_extraction_worker_id();
  settings public.product_submission_extraction_settings%ROWTYPE;
  current_month text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM');
  allowance record;
BEGIN
  PERFORM worker_id;
  SELECT * INTO settings
  FROM public.product_submission_extraction_settings WHERE id;
  SELECT * INTO allowance FROM public.product_submission_extraction_allowance();
  RETURN QUERY SELECT current_month, allowance.spent, settings.monthly_cap_microcents, allowance.remaining;
END;
$$;
REVOKE ALL ON FUNCTION public.product_submission_extraction_budget_state()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.product_submission_extraction_budget_state()
  TO authenticated;

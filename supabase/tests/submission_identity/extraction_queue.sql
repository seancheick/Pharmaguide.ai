-- Batch 3: the extraction queue, its worker identity and its budget.
-- Extraction ships disabled, so most of these first turn it on deliberately.

-- A model-origin draft: same envelope as fixture.draft but attributed to the
-- machine, with a sent input so the writer's provenance rule is satisfied.
CREATE FUNCTION fixture.model_draft(sid uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT fixture.draft(sid)
    || jsonb_build_object(
      'draft_origin', 'model', 'provider', 'fake', 'model', 'fake-1',
      'sent_inputs', (
        SELECT jsonb_agg(jsonb_build_object(
          'input_id', 'i' || photo.seq::text,
          'photo_id', photo.photo_id::text,
          'original_sha256', photo.content_sha256,
          'sent_sha256', photo.content_sha256))
        FROM public.product_submission_photos AS photo
        JOIN public.product_submission_evidence_revisions AS revision
          ON revision.submission_id = photo.submission_id
         AND photo.photo_id = ANY(revision.photo_ids)
        WHERE photo.submission_id = sid
          AND revision.revision = (
            SELECT evidence_revision FROM public.product_submissions WHERE id = sid)
      ));
$$;

CREATE FUNCTION fixture.enable_extraction() RETURNS void LANGUAGE sql AS $$
  UPDATE public.product_submission_extraction_settings
  SET enabled = true, provider = 'fake', model = 'fake-1',
      model_digest = repeat('c', 64), prompt_version = 'p1',
      retention_policy_version='fixture.local.v1', max_cost_microcents=100,
      monthly_cap_microcents = 1000000
  WHERE id;
$$;

-- user 4 is the machine identity; user 3 remains the human reviewer.
CREATE FUNCTION fixture.add_worker() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.product_submission_extraction_workers(user_id, label)
  VALUES (fixture.user_id(4), 'fixture-worker')
  ON CONFLICT DO NOTHING;
$$;

SELECT fixture.test('extraction ships disabled and enabling names what will run', $case$
DO $$ BEGIN
  PERFORM fixture.assert(NOT (SELECT enabled FROM public.product_submission_extraction_settings WHERE id),
    'a deployed migration must not start calling a provider');
  PERFORM fixture.throws(
    'UPDATE public.product_submission_extraction_settings SET enabled = true WHERE id',
    '23514', 'enabled_is_specified');
  PERFORM fixture.enable_extraction();
  PERFORM fixture.assert((SELECT enabled FROM public.product_submission_extraction_settings WHERE id),
    'a fully specified configuration may be enabled');
END $$ $case$);

SELECT fixture.test('expired lease cannot be renewed or completed before replacement', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  UPDATE public.product_submission_extraction_jobs SET leased_until = now() - interval '1 second'
  WHERE id = claimed.job_id;
  PERFORM fixture.throws(format('SELECT public.heartbeat_product_submission_extraction_job(%L,%s)',
    claimed.job_id, claimed.fencing_token), '55000', 'lease is not held');
  PERFORM fixture.throws(format('SELECT public.complete_product_submission_extraction_job(%L,%s,''failed'')',
    claimed.job_id, claimed.fencing_token), '55000', 'lease is not held');
END $$ $case$);

SELECT fixture.test('private-review consent does not authorize AI extraction', $case$
DO $$ DECLARE sid uuid; BEGIN
  PERFORM fixture.enable_extraction();
  UPDATE public.product_submission_consent_versions SET purposes = ARRAY['private_review']
  WHERE version = 'fixture.consent.v1';
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_extraction_jobs WHERE submission_id=sid),
    'recognized consent must explicitly include ai_label_draft');
END $$ $case$);

SELECT fixture.test('a worker is never a reviewer, in either direction', $case$
DO $$ BEGIN
  PERFORM fixture.add_worker();
  PERFORM fixture.throws(format(
    'INSERT INTO public.product_submission_reviewers(user_id) VALUES (%L)', fixture.user_id(4)),
    '23514', 'cannot also be a reviewer');
  PERFORM fixture.throws(format(
    'INSERT INTO public.product_submission_extraction_workers(user_id, label) VALUES (%L, ''x'')',
    fixture.user_id(3)), '23514', 'cannot also be an extraction worker');
END $$ $case$);

SELECT fixture.test('only an allowlisted worker may claim, heartbeat or complete', $case$
DO $$ BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws('SELECT * FROM public.claim_product_submission_extraction_jobs(1)',
    '42501', 'extraction worker access required');
  -- A human reviewer is not a worker either.
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws('SELECT * FROM public.claim_product_submission_extraction_jobs(1)',
    '42501', 'extraction worker access required');
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM fixture.throws('SELECT * FROM public.claim_product_submission_extraction_jobs(1)',
    '42501', 'extraction worker access required');
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.claim_product_submission_extraction_jobs(integer)', 'EXECUTE'),
    'a service key must not drain the queue');
  PERFORM fixture.assert(NOT has_function_privilege('anon',
    'public.complete_product_submission_extraction_job(uuid,bigint,text,text,text,text,text,jsonb,jsonb,jsonb,numeric,jsonb,text,bigint)', 'EXECUTE'),
    'anon must not complete extraction work');
END $$ $case$);

SELECT fixture.test('nothing is enqueued while extraction is disabled', $case$
DO $$ DECLARE sid uuid; BEGIN
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM fixture.assert(NOT EXISTS(
    SELECT 1 FROM public.product_submission_extraction_jobs WHERE submission_id = sid),
    'the default configuration must enqueue no work');
END $$ $case$);

SELECT fixture.test('a ready revision enqueues once and a retake is new work', $case$
DO $$ DECLARE sid uuid; first_key text; BEGIN
  PERFORM fixture.enable_extraction();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM fixture.assert((SELECT count(*) = 1 FROM public.product_submission_extraction_jobs
    WHERE submission_id = sid), 'a ready revision enqueues exactly one job');
  SELECT job_key INTO first_key FROM public.product_submission_extraction_jobs
  WHERE submission_id = sid;
  -- Re-readying the same evidence is the same work, not a second job.
  UPDATE public.product_submissions SET upload_state = 'pending' WHERE id = sid;
  UPDATE public.product_submissions SET upload_state = 'ready' WHERE id = sid;
  PERFORM fixture.assert((SELECT count(*) = 1 FROM public.product_submission_extraction_jobs
    WHERE submission_id = sid), 'the same evidence must not enqueue twice');
  PERFORM fixture.assert((SELECT job_key = first_key FROM public.product_submission_extraction_jobs
    WHERE submission_id = sid), 'the job key is the evidence, not the row');
END $$ $case$);

SELECT fixture.test('a legacy receipt without recognized consent is never enqueued', $case$
DO $$ DECLARE sid uuid; BEGIN
  PERFORM fixture.enable_extraction();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  DELETE FROM public.product_submission_extraction_jobs WHERE submission_id = sid;
  UPDATE public.product_submission_evidence_revisions SET consent_version = NULL
  WHERE submission_id = sid;
  UPDATE public.product_submissions SET upload_state = 'pending' WHERE id = sid;
  UPDATE public.product_submissions SET upload_state = 'ready' WHERE id = sid;
  PERFORM fixture.assert(NOT EXISTS(
    SELECT 1 FROM public.product_submission_extraction_jobs WHERE submission_id = sid),
    'photos with no attested consent must not be read automatically');
END $$ $case$);

SELECT fixture.test('a claim leases the current revision and fences the attempt', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(5);
  PERFORM fixture.assert(claimed.submission_id = sid AND claimed.evidence_revision = 1,
    'the lease names the evidence to read');
  PERFORM fixture.assert(claimed.fencing_token = 1 AND claimed.attempts = 1,
    'each claim advances the fence and counts the attempt');
  PERFORM fixture.assert(claimed.evidence_manifest = public.product_submission_evidence_manifest(sid, 1),
    'the worker is handed the manifest, not left to find photos');
  -- A leased job is not claimable again while the lease holds.
  PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.claim_product_submission_extraction_jobs(5)),
    'a live lease is exclusive');
END $$ $case$);

SELECT fixture.test('an expired attempt cannot overwrite the one that replaced it', $case$
DO $$ DECLARE sid uuid; stale bigint; fresh record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT fencing_token INTO stale FROM public.claim_product_submission_extraction_jobs(1);
  -- The lease lapses and the same worker picks the job up again.
  UPDATE public.product_submission_extraction_jobs SET leased_until = now() - interval '1 minute'
  WHERE submission_id = sid;
  SELECT * INTO fresh FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.assert(fresh.fencing_token > stale, 'the second claim fences the first');
  PERFORM fixture.throws(format(
    'SELECT public.complete_product_submission_extraction_job(%L, %s, ''failed'')',
    fresh.job_id, stale), '55000', 'extraction lease is not held');
  PERFORM fixture.throws(format(
    'SELECT public.heartbeat_product_submission_extraction_job(%L, %s)', fresh.job_id, stale),
    '55000', 'extraction lease is not held');
END $$ $case$);

SELECT fixture.test('a worker records a model draft through the one shared writer', $case$
DO $$ DECLARE sid uuid; claimed record; version_value integer; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM public.reserve_product_submission_extraction_budget(claimed.job_id, claimed.fencing_token);
  version_value := public.complete_product_submission_extraction_job(
    claimed.job_id, claimed.fencing_token, 'review_ready',
    'label_draft_v1', 'fake', 'fake-1', 'p1',
    public.product_submission_evidence_manifest(sid, 1),
    fixture.model_draft(sid), '{}'::jsonb, 0.5, '{"cost_microcents": 42}'::jsonb,
    NULL, 42);
  PERFORM fixture.assert(version_value = 1, 'the worker draft is version 1');
  PERFORM fixture.assert((SELECT actor_kind = 'worker' AND recorded_by = fixture.user_id(4)
    AND evidence_revision = 1
    FROM public.product_submission_extractions WHERE submission_id = sid AND version = 1),
    'the machine is recorded as the machine');
  PERFORM fixture.assert((SELECT state = 'review_ready' AND leased_by IS NULL
    FROM public.product_submission_extraction_jobs WHERE id = claimed.job_id),
    'a completed job releases its lease');
  PERFORM fixture.assert((SELECT sum(microcents) = 42
    FROM public.product_submission_extraction_budget WHERE job_id = claimed.job_id),
    'spend is recorded in integer micro-cents');
END $$ $case$);

SELECT fixture.test('a worker may not file a human transcription or approve', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'under_review', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM public.reserve_product_submission_extraction_budget(claimed.job_id, claimed.fencing_token);
  PERFORM fixture.throws(format(
    'SELECT public.complete_product_submission_extraction_job(%L, %s, ''review_ready'', ''label_draft_v1'', ''human'', ''human'', ''p1'', %L, %L, ''{}''::jsonb)',
    claimed.job_id, claimed.fencing_token,
    public.product_submission_evidence_manifest(sid, 1), fixture.draft(sid)),
    '22023', 'draft does not match leased configuration');
  -- The machine identity cannot move a review forward, whatever it drafted.
  -- Called directly, because the approve helper switches to a human first.
  PERFORM fixture.throws(format(
    'SELECT public.review_product_submission(%L, ''under_review'')', sid),
    '42501', 'reviewer access required');
END $$ $case$);

SELECT fixture.test('a retryable failure backs off and gives up at the attempt cap', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  UPDATE public.product_submission_extraction_settings SET max_attempts = 2 WHERE id;
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM public.complete_product_submission_extraction_job(
    claimed.job_id, claimed.fencing_token, 'retryable_error', p_error_code => 'provider_timeout');
  PERFORM fixture.assert((SELECT state = 'retryable_error' AND next_attempt_at > now()
    FROM public.product_submission_extraction_jobs WHERE id = claimed.job_id),
    'a retry waits before it runs again');
  UPDATE public.product_submission_extraction_jobs SET next_attempt_at = now()
  WHERE id = claimed.job_id;
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM public.complete_product_submission_extraction_job(
    claimed.job_id, claimed.fencing_token, 'retryable_error', p_error_code => 'provider_timeout');
  PERFORM fixture.assert((SELECT state = 'failed'
    FROM public.product_submission_extraction_jobs WHERE id = claimed.job_id),
    'the attempt cap stops an endlessly failing job');
  PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.claim_product_submission_extraction_jobs(1)),
    'a failed job is not handed out again');
END $$ $case$);

SELECT fixture.test('budget is reserved before spend and settled once', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  UPDATE public.product_submission_extraction_settings
  SET monthly_cap_microcents = 10, pilot_cap_microcents = 10, max_cost_microcents = 10
  WHERE id;
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.assert(public.reserve_product_submission_extraction_budget(claimed.job_id, claimed.fencing_token),
    'the permitted maximum is reserved before the call');
  PERFORM fixture.assert(public.reserve_product_submission_extraction_budget(claimed.job_id, claimed.fencing_token),
    'a network retry does not reserve twice');
  PERFORM fixture.assert((SELECT remaining_microcents = 0 FROM public.product_submission_extraction_budget_state()),
    'outstanding reservations consume allowance');
  PERFORM public.complete_product_submission_extraction_job(
    claimed.job_id, claimed.fencing_token, 'retryable_error',
    p_cost_microcents => 6);
  PERFORM fixture.assert((SELECT coalesce(sum(microcents), 0) = 6 AND count(*)=1
    FROM public.product_submission_extraction_budget),
    'one settlement records actual cost');
  PERFORM fixture.assert((SELECT remaining_microcents = 4 FROM public.product_submission_extraction_budget_state()),
    'unused allowance is returned after settlement');
END $$ $case$);

SELECT fixture.test('a queued job retains its configuration and completion checks it', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  UPDATE public.product_submission_extraction_settings SET model='different', prompt_version='p2' WHERE id;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.assert(claimed.configuration->>'model'='fake-1', 'lease carries the enqueued configuration');
  PERFORM public.reserve_product_submission_extraction_budget(claimed.job_id, claimed.fencing_token);
  PERFORM fixture.throws(format(
    'SELECT public.complete_product_submission_extraction_job(%L,%s,''review_ready'',''label_draft_v1'',''fake'',''different'',''p1'',%L,%L,''{}''::jsonb)',
    claimed.job_id, claimed.fencing_token, public.product_submission_evidence_manifest(sid,1),fixture.model_draft(sid)),
    '22023','leased configuration');
END $$ $case$);

SELECT fixture.test('reservations respect pilot cap and unknown spend stays held', $case$
DO $$ DECLARE first_job record; second_job record; BEGIN
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  UPDATE public.product_submission_extraction_settings
  SET monthly_cap_microcents=100, pilot_cap_microcents=10, max_cost_microcents=10 WHERE id;
  PERFORM fixture.seed(1,'012345678905','submitted',NULL);
  PERFORM fixture.seed(2,'036000291452','submitted',NULL);
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(4)::text,false);
  SELECT * INTO first_job FROM public.claim_product_submission_extraction_jobs(1);
  SELECT * INTO second_job FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.assert(public.reserve_product_submission_extraction_budget(first_job.job_id,first_job.fencing_token),'first fits');
  PERFORM fixture.assert(NOT public.reserve_product_submission_extraction_budget(second_job.job_id,second_job.fencing_token),'pilot cap fences second worker');
  PERFORM public.complete_product_submission_extraction_job(first_job.job_id,first_job.fencing_token,'retryable_error');
  PERFORM fixture.assert((SELECT remaining_microcents=0 FROM public.product_submission_extraction_budget_state()),'unknown cost retains full reservation');
END $$ $case$);

SELECT fixture.test('actual overrun is recorded and disables future spending', $case$
DO $$ DECLARE claimed record; BEGIN
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  UPDATE public.product_submission_extraction_settings SET max_cost_microcents=10 WHERE id;
  PERFORM fixture.seed(1,'012345678905','submitted',NULL);
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(4)::text,false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM public.reserve_product_submission_extraction_budget(claimed.job_id,claimed.fencing_token);
  PERFORM public.complete_product_submission_extraction_job(claimed.job_id,claimed.fencing_token,'failed',p_cost_microcents=>11);
  PERFORM fixture.assert((SELECT sum(microcents)=11 FROM public.product_submission_extraction_budget),'incurred spend cannot be erased');
  PERFORM fixture.assert(NOT (SELECT enabled FROM public.product_submission_extraction_settings WHERE id),'overrun closes the spending switch');
END $$ $case$);

SELECT fixture.test('renamed writer overload is removed and final expired attempt terminates', $case$
DO $$ DECLARE claimed record; BEGIN
  PERFORM fixture.assert(to_regprocedure('public.record_product_submission_extraction_internal(uuid,text,text,text,text,jsonb,jsonb,jsonb,numeric,jsonb,integer)') IS NULL,
    'the old writer must not survive as an overload');
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  UPDATE public.product_submission_extraction_settings SET max_attempts=1 WHERE id;
  PERFORM fixture.seed(1,'012345678905','submitted',NULL);
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(4)::text,false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  UPDATE public.product_submission_extraction_jobs SET leased_until=now()-interval '1 second' WHERE id=claimed.job_id;
  PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.claim_product_submission_extraction_jobs(1)), 'final attempt cannot be reclaimed');
  PERFORM fixture.assert((SELECT state='failed' FROM public.product_submission_extraction_jobs WHERE id=claimed.job_id),'expired last attempt leaves leased state');
END $$ $case$);

SELECT fixture.test('a null fence cannot complete a lease and budget holds do not exhaust attempts', $case$
DO $$ DECLARE claimed record; attempt integer; BEGIN
  PERFORM fixture.enable_extraction(); PERFORM fixture.add_worker();
  PERFORM fixture.seed(1,'012345678905','submitted',NULL);
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(4)::text,false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.throws(format('SELECT public.complete_product_submission_extraction_job(%L,NULL,''failed'')',claimed.job_id),
    '55000','lease is not held');
  PERFORM fixture.throws(format('SELECT public.reserve_product_submission_extraction_budget(%L,NULL)',claimed.job_id),
    '55000','lease is not held');
  PERFORM public.complete_product_submission_extraction_job(claimed.job_id,claimed.fencing_token,'budget_hold',p_cost_microcents=>0);
  FOR attempt IN 1..4 LOOP
    SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
    PERFORM fixture.assert(claimed.job_id IS NOT NULL,'a no-call budget hold cannot consume retries');
    PERFORM public.complete_product_submission_extraction_job(claimed.job_id,claimed.fencing_token,'budget_hold',p_cost_microcents=>0);
  END LOOP;
END $$ $case$);

SELECT fixture.test('work whose evidence moved on is not leased', $case$
DO $$ DECLARE sid uuid; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'under_review', NULL);
  -- The owner opens a retake, so revision 1 is no longer what a reviewer sees.
  UPDATE public.product_submissions SET evidence_revision = 2, upload_state = 'pending'
  WHERE id = sid;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.claim_product_submission_extraction_jobs(1)),
    'a job for superseded evidence must not be leased');
END $$ $case$);

SELECT fixture.test('superseded or closed work is cancelled, not stranded', $case$
DO $$ DECLARE sid uuid; sid2 uuid; old_job uuid; closed_job uuid; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  SELECT id INTO old_job FROM public.product_submission_extraction_jobs
  WHERE submission_id = sid;
  -- A retake changes the evidence revision while the prior job is still
  -- queued. The trigger fences that work instead of leaving an unclaimable row.
  UPDATE public.product_submissions SET evidence_revision = 2, upload_state = 'pending'
  WHERE id = sid;
  PERFORM fixture.assert((SELECT state = 'cancelled' AND error_code = 'superseded_evidence'
    FROM public.product_submission_extraction_jobs WHERE id = old_job),
    'a retake cancels work for the old evidence');

  -- A review decision also closes queued work, while preserving the row for
  -- operational history. Use a fresh receipt so the two cancellation reasons
  -- remain independently observable.
  sid2 := fixture.seed(1, '036000291452', 'submitted', NULL);
  SELECT id INTO closed_job FROM public.product_submission_extraction_jobs
  WHERE submission_id = sid2;
  UPDATE public.product_submissions
  SET review_status = 'rejected', reviewed_at = now(),
      reviewed_by = fixture.user_id(3), resolution_code = 'photo_quality'
  WHERE id = sid2;
  PERFORM fixture.assert((SELECT state = 'cancelled' AND error_code = 'submission_closed'
    FROM public.product_submission_extraction_jobs WHERE id = closed_job),
    'a terminal review cancels outstanding work');
END $$ $case$);

SELECT fixture.test('a claim tells the worker where the leased bytes live', $case$
DO $$ DECLARE sid uuid; claimed record; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  PERFORM fixture.assert(claimed.evidence_object_paths ? '10000000-0000-0000-0000-000000000001',
    'the lease names the object for each photo it hands over');
  PERFORM fixture.assert(
    (claimed.evidence_object_paths->>'10000000-0000-0000-0000-000000000001')
      = (SELECT object_path FROM public.product_submission_photos
         WHERE submission_id = sid),
    'the path is the real stored object, not a guess');
  -- Manifest and paths describe the same photos: neither may be broader.
  PERFORM fixture.assert(
    (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(claimed.evidence_manifest) k)
      = (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(claimed.evidence_object_paths) k),
    'a worker is told about exactly the photos it may read');
END $$ $case$);

SELECT fixture.test('a worker may read leased photos and nothing else', $case$
DO $$ DECLARE sid uuid; other_sid uuid; claimed record; leased_path text; BEGIN
  PERFORM fixture.enable_extraction();
  PERFORM fixture.add_worker();
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  other_sid := fixture.seed(2, '036000291452', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(4)::text, false);
  SELECT * INTO claimed FROM public.claim_product_submission_extraction_jobs(1);
  leased_path := (SELECT object_path FROM public.product_submission_photos WHERE submission_id = claimed.submission_id);
  PERFORM fixture.assert(public.product_submission_worker_may_read_object(leased_path),
    'the leased revision is readable while the lease is live');
  PERFORM fixture.assert(NOT public.product_submission_worker_may_read_object(
    (SELECT object_path FROM public.product_submission_photos
     WHERE submission_id <> claimed.submission_id LIMIT 1)),
    'another submission is not this lease');

  -- An expired lease reads nothing: a worker cannot keep pulling private
  -- photographs after it has lost the job.
  UPDATE public.product_submission_extraction_jobs
  SET leased_until = now() - interval '1 minute' WHERE id = claimed.job_id;
  PERFORM fixture.assert(NOT public.product_submission_worker_may_read_object(leased_path),
    'an expired lease must not still read evidence');

  -- And a human, however privileged, is not a worker on this path.
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.assert(NOT public.product_submission_worker_may_read_object(leased_path),
    'the worker read path is for workers only');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.assert(NOT public.product_submission_worker_may_read_object(leased_path),
    'the owner reads through the owner policy, not this one');
END $$ $case$);

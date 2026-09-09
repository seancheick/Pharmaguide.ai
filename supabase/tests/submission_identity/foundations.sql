-- Batch 1 foundations: consent recorded at creation, immutable evidence
-- revisions, and one authorized draft-recording path. Runs after intake.sql in
-- scripts/test_submission_identity.sh against the real migration chain.

SELECT fixture.test('consent version is required and recorded once at creation', $case$
DO $$ DECLARE sid uuid := gen_random_uuid(); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos())',
    sid, 'missing_product', '012345678905'), '22023', 'consent version required');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => %L)',
    sid, 'missing_product', '012345678905', 'bad version!'), '22023', 'consent version required');
  PERFORM public.create_product_submission(sid, 'missing_product', '012345678905',
    p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1');
  PERFORM fixture.assert((SELECT consent_version = 'fixture.consent.v1' AND consented_at IS NOT NULL
    FROM public.product_submissions WHERE id = sid), 'consent must be recorded with the submission');
  -- An idempotent replay with a different attested version keeps the original.
  PERFORM public.create_product_submission(sid, 'missing_product', '012345678905',
    p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v2');
  PERFORM fixture.assert((SELECT consent_version = 'fixture.consent.v1'
    FROM public.product_submissions WHERE id = sid), 'replay must not rewrite the recorded consent');
END $$ $case$);

SELECT fixture.test('old caller-identified extraction signature no longer exists', $case$
DO $$ BEGIN
  PERFORM fixture.assert(to_regprocedure(
    'public.record_product_submission_extraction(uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric)') IS NULL,
    'the spoofable signature must be dropped');
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.record_product_submission_extraction(uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer)', 'EXECUTE'),
    'service_role must not execute draft recording');
  PERFORM fixture.assert(NOT has_function_privilege('anon',
    'public.record_product_submission_extraction(uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer)', 'EXECUTE'),
    'anon must not execute draft recording');
  PERFORM fixture.assert(has_function_privilege('authenticated',
    'public.record_product_submission_extraction(uuid, text, text, text, text, jsonb, jsonb, jsonb, numeric, jsonb, integer)', 'EXECUTE'),
    'authenticated callers reach the reviewer check inside');
END $$ $case$);

CREATE OR REPLACE FUNCTION fixture.record_draft(p_id uuid, p_usage jsonb DEFAULT NULL, p_revision integer DEFAULT NULL)
RETURNS integer LANGUAGE sql AS $$
  SELECT public.record_product_submission_extraction(p_id, 'label_draft_v1', 'fake', 'fake-1', 'p1',
    (SELECT coalesce(jsonb_object_agg(photo.photo_id::text, photo.content_sha256 ORDER BY photo.photo_id::text), '{}'::jsonb)
       FROM public.product_submission_photos AS photo WHERE photo.submission_id = p_id),
    '{"fixture": true}'::jsonb, '{}'::jsonb, 0.5, p_usage, p_revision)
$$;

SELECT fixture.test('draft recording derives the reviewer from the session and allowlist', $case$
DO $$ DECLARE sid uuid; version_value integer; BEGIN
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws(format('SELECT fixture.record_draft(%L)', sid), '42501', 'reviewer access required');
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM fixture.throws(format('SELECT fixture.record_draft(%L)', sid), '42501', 'reviewer access required');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  version_value := fixture.record_draft(sid, '{"billed_units": 1234, "cost_microcents": 160}'::jsonb, 1);
  PERFORM fixture.assert(version_value = 1, 'first draft is version 1');
  PERFORM fixture.assert((SELECT recorded_by = fixture.user_id(3) AND actor_kind = 'reviewer'
      AND evidence_revision = 1 AND usage->>'cost_microcents' = '160'
    FROM public.product_submission_extractions WHERE submission_id = sid AND version = 1),
    'draft must carry the session reviewer, actor kind, revision and usage');
  PERFORM fixture.throws(format('SELECT fixture.record_draft(%L, NULL, 2)', sid), '22023', 'extraction evidence revision is stale');
  PERFORM fixture.throws(format('SELECT public.record_product_submission_extraction(%L, %L, %L, %L, %L, %L, %L, %L, NULL, %L)',
    sid, 'label_draft_v1', 'fake', 'fake-1', 'p1', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[1]'::jsonb), '22023', 'invalid extraction usage');
END $$ $case$);

SELECT fixture.test('evidence revision appends photos without rewriting the originals', $case$
DO $$ DECLARE sid uuid; original_sha text; new_photo jsonb; revision_value integer; BEGIN
  sid := fixture.seed(1, '012345678905', 'submitted', NULL);
  original_sha := (SELECT content_sha256 FROM public.product_submission_photos WHERE submission_id = sid);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  -- A first upload that never finalized cannot open a revision.
  PERFORM fixture.throws(format('SELECT public.open_product_submission_evidence_revision(%L)',
    fixture.seed(1, '036000291452', 'submitted', NULL, 'missing_product', NULL, 'pending')), '55000', 'open ready submission required');
  -- Adding evidence needs an opened revision.
  new_photo := jsonb_build_array(jsonb_build_object(
    'photo_id', '10000000-0000-0000-0000-000000000002', 'seq', 2,
    'categories', jsonb_build_array('supplement_facts'),
    'content_type', 'image/jpeg', 'byte_size', 120, 'content_sha256', repeat('b', 64)));
  PERFORM fixture.throws(format('SELECT public.add_product_submission_evidence(%L, %L)', sid, new_photo), '55000', 'open evidence revision required');
  revision_value := public.open_product_submission_evidence_revision(sid);
  PERFORM fixture.assert(revision_value = 2, 'revision advances to 2');
  PERFORM fixture.assert(public.open_product_submission_evidence_revision(sid) = 2, 'reopening replays the open revision');
  PERFORM fixture.assert((SELECT upload_state = 'pending' AND evidence_revision = 2 AND evidence_revision_opened_at IS NOT NULL
    FROM public.product_submissions WHERE id = sid), 'submission returns to pending for the new revision');
  -- Identical bytes are not new evidence.
  PERFORM fixture.throws(format('SELECT public.add_product_submission_evidence(%L, %L)', sid, jsonb_build_array(jsonb_build_object(
    'photo_id', '10000000-0000-0000-0000-000000000003', 'seq', 2, 'categories', jsonb_build_array('supplement_facts'),
    'content_type', 'image/jpeg', 'byte_size', 100, 'content_sha256', original_sha))), '23505', 'product_submission_photos_sha_unique');
  -- Sequence must continue after the existing photos.
  PERFORM fixture.throws(format('SELECT public.add_product_submission_evidence(%L, %L)', sid, jsonb_set(new_photo, '{0,seq}', '1'::jsonb)), '22023', 'invalid photo sequence');
  PERFORM public.add_product_submission_evidence(sid, new_photo);
  PERFORM public.add_product_submission_evidence(sid, new_photo);
  PERFORM fixture.assert((SELECT count(*) = 2 AND bool_and(CASE WHEN revision = 1 THEN content_sha256 = original_sha ELSE seq = 2 END)
    FROM public.product_submission_photos WHERE submission_id = sid), 'original photo untouched; new photo carries revision 2');
  PERFORM fixture.throws(format('SELECT public.add_product_submission_evidence(%L, %L)', sid, jsonb_set(new_photo, '{0,byte_size}', '121'::jsonb)), '23505', 'submission photo replay conflict');
END $$ $case$);

SELECT fixture.test('a pending revision keeps the submission open and blocks approval until finalized', $case$
DO $$ DECLARE sid uuid; new_photo jsonb; BEGIN
  sid := fixture.seed(1, '012345678905', 'under_review', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM public.open_product_submission_evidence_revision(sid);
  -- The duplicate guard still sees this barcode as open.
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => %L)',
    gen_random_uuid(), 'missing_product', '0012345678905', 'fixture.consent.v1'), '23505', 'idx_product_submissions_user_open_upc');
  PERFORM fixture.assert((public.get_product_submission_intake('missing_product', '012345678905')->>'action') = 'resume_evidence_revision',
    'intake resumes the open revision');
  PERFORM fixture.assert((public.get_product_submission_intake('missing_product', '012345678905')->>'evidence_revision') = '2',
    'intake reports the revision');
  -- A reviewer cannot approve or record a draft against a revision mid-upload.
  PERFORM fixture.throws(format('SELECT fixture.approve(%L)', sid), '55000', 'ready submission required');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format('SELECT fixture.record_draft(%L)', sid), '55000', 'open ready submission required');
  -- Finalizing the revision restores readiness, keeps the first submitted_at,
  -- and makes the old photo set stale for drafts.
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  new_photo := jsonb_build_array(jsonb_build_object(
    'photo_id', '10000000-0000-0000-0000-000000000002', 'seq', 2,
    'categories', jsonb_build_array('supplement_facts'),
    'content_type', 'image/jpeg', 'byte_size', 120, 'content_sha256', repeat('b', 64)));
  PERFORM public.add_product_submission_evidence(sid, new_photo);
  UPDATE public.product_submissions SET submitted_at = now() - interval '1 day' WHERE id = sid;
  PERFORM fixture.assert(NOT public.finalize_product_submission(sid), 'finalize waits for the new bytes');
  INSERT INTO storage.objects(bucket_id, name, owner_id, metadata, user_metadata)
  SELECT 'product-submission-photos', object_path, user_id::text,
    jsonb_build_object('size', byte_size, 'mimetype', content_type),
    jsonb_build_object('content_sha256', content_sha256)
  FROM public.product_submission_photos WHERE submission_id = sid AND revision = 2;
  PERFORM fixture.assert(public.finalize_product_submission(sid), 'finalize succeeds once every photo has bytes');
  PERFORM fixture.assert((SELECT upload_state = 'ready' AND evidence_ready_at IS NOT NULL AND submitted_at < now() - interval '23 hours'
    FROM public.product_submissions WHERE id = sid), 'revision is ready and the original submitted_at is kept');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format('SELECT public.record_product_submission_extraction(%L, %L, %L, %L, %L, %L, %L, %L)',
    sid, 'label_draft_v1', 'fake', 'fake-1', 'p1',
    jsonb_build_object('10000000-0000-0000-0000-000000000001', repeat('a', 64)), '{}'::jsonb, '{}'::jsonb),
    '22023', 'extraction image hashes do not match');
  PERFORM fixture.assert(fixture.record_draft(sid, NULL, 2) = 1, 'a draft over the full revision-2 evidence records');
END $$ $case$);

-- Batch 4: persistent reviewer corrections and per-field attestations.
--
-- The rule under test throughout: a tick is an attestation about one exact
-- label text read off one exact set of photographs. Anything that moves either
-- of those must leave the tick visibly withdrawn, never silently carried over.

CREATE FUNCTION fixture.manifest(sid uuid) RETURNS text LANGUAGE sql AS $$
  SELECT revision.manifest_sha256
  FROM public.product_submission_evidence_revisions AS revision
  JOIN public.product_submissions AS submission ON submission.id = revision.submission_id
  WHERE revision.submission_id = sid AND revision.revision = submission.evidence_revision
$$;

CREATE FUNCTION fixture.label(p_brand text DEFAULT 'Acme') RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('brandName', p_brand) $$;

-- Canonical form and digest are produced by the caller in production (the Edge
-- Function), so the fixture mirrors that rather than inventing a second rule.
CREATE FUNCTION fixture.save(sid uuid, p_brand text DEFAULT 'Acme') RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.save_product_submission_reviewer_draft(
    sid,
    (SELECT evidence_revision FROM public.product_submissions WHERE id = sid),
    fixture.manifest(sid),
    fixture.label(p_brand),
    fixture.label(p_brand)::text,
    encode(extensions.digest(fixture.label(p_brand)::text, 'sha256'), 'hex'))
$$;

CREATE FUNCTION fixture.sha(p_brand text DEFAULT 'Acme') RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(fixture.label(p_brand)::text, 'sha256'), 'hex') $$;

SELECT fixture.test('only an allowlisted reviewer may keep a working draft', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM fixture.throws(format('SELECT fixture.save(%L)', sid), '42501', 'reviewer access required');
  -- The submitter owns the photographs and still may not author a review.
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws(format('SELECT fixture.save(%L)', sid), '42501', 'reviewer access required');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.assert(fixture.save(sid) -> 'draft' ->> 'payload_sha256' = fixture.sha(),
    'the reviewer draft was not stored');
END $$;
$case$);

SELECT fixture.test('a reload returns the same corrections and ticks', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Corrected');
  PERFORM public.set_product_submission_field_verification(
    sid, 'identity.brand', fixture.sha('Corrected'), true,
    '10000000-0000-0000-0000-000000000001');
  state := public.load_product_submission_reviewer_draft(sid);
  PERFORM fixture.assert(state -> 'draft' -> 'payload' ->> 'brandName' = 'Corrected',
    'the typed correction did not survive a reload');
  PERFORM fixture.assert((state -> 'verifications' -> 0 ->> 'live')::boolean,
    'the attestation did not survive a reload');
  PERFORM fixture.assert(state -> 'verifications' -> 0 ->> 'photo_id'
    = '10000000-0000-0000-0000-000000000001', 'the source photograph was not kept');
END $$;
$case$);

SELECT fixture.test('a field cannot be attested before the label is saved', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format(
    'SELECT public.set_product_submission_field_verification(%L, %L, %L, true)',
    sid, 'identity.brand', fixture.sha()), '55000', 'save the reviewed label');
END $$;
$case$);

SELECT fixture.test('an attestation naming another label text is refused', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  -- A tick that describes a payload nobody is looking at must not be rebound
  -- to whatever the draft happens to say now.
  PERFORM fixture.throws(format(
    'SELECT public.set_product_submission_field_verification(%L, %L, %L, true)',
    sid, 'identity.brand', fixture.sha('Different')), '55000', 'label changed');
END $$;
$case$);

SELECT fixture.test('editing the label withdraws the earlier ticks', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM public.set_product_submission_field_verification(
    sid, 'identity.brand', fixture.sha('Acme'), true);
  state := fixture.save(sid, 'Edited');
  PERFORM fixture.assert(NOT (state -> 'verifications' -> 0 ->> 'live')::boolean,
    'a tick against the old text still counted after an edit');
  -- Kept, not deleted: the console has to be able to say what was withdrawn.
  PERFORM fixture.assert(jsonb_array_length(state -> 'verifications') = 1,
    'the withdrawn attestation was destroyed instead of reported');
END $$;
$case$);

SELECT fixture.test('a retake supersedes the draft and voids every tick', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM public.set_product_submission_field_verification(
    sid, 'identity.brand', fixture.sha('Acme'), true);
  -- A second revision: the reviewer's reading was of photographs that are no
  -- longer the evidence.
  INSERT INTO public.product_submission_evidence_revisions(
    submission_id, revision, request_key, opened_by, photo_ids,
    consent_version, consented_at, ready_at, manifest, manifest_sha256)
  VALUES (sid, 2, gen_random_uuid(), fixture.user_id(1),
    ARRAY['10000000-0000-0000-0000-000000000001'::uuid],
    'fixture.consent.v1', now(), now(), '{}'::jsonb, repeat('b', 64));
  UPDATE public.product_submissions SET evidence_revision = 2 WHERE id = sid;
  state := public.load_product_submission_reviewer_draft(sid);
  PERFORM fixture.assert((state -> 'draft' ->> 'superseded')::boolean,
    'a draft written against replaced photographs was not reported superseded');
  PERFORM fixture.assert(NOT (state -> 'verifications' -> 0 ->> 'live')::boolean,
    'an attestation survived the photographs it was made against');
END $$;
$case$);

SELECT fixture.test('a source photograph must belong to this revision', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review');
        other uuid := fixture.seed(2, '012345678929', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.throws(format(
    'SELECT public.set_product_submission_field_verification(%L, %L, %L, true, %L)',
    sid, 'identity.brand', fixture.sha('Acme'), gen_random_uuid()),
    '22023', 'source photo is not part of this evidence revision');
END $$;
$case$);

SELECT fixture.test('one reviewer cannot read another reviewer''s working notes', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  INSERT INTO public.product_submission_reviewers(user_id) VALUES (fixture.user_id(5))
    ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(5)::text, false);
  state := public.load_product_submission_reviewer_draft(sid);
  PERFORM fixture.assert(state -> 'draft' = 'null'::jsonb,
    'a reviewer saw another reviewer''s unfinished corrections');
END $$;
$case$);

SELECT fixture.test('a resolved submission accepts no further corrections', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'rejected'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format('SELECT fixture.save(%L)', sid),
    '55000', 'already resolved');
END $$;
$case$);

SELECT fixture.test('a naked service key cannot author a human attestation', $case$
DO $$ BEGIN
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.save_product_submission_reviewer_draft(uuid,integer,text,jsonb,text,text)', 'EXECUTE'),
    'service_role could write a reviewer draft');
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.set_product_submission_field_verification(uuid,text,text,boolean,uuid)', 'EXECUTE'),
    'service_role could author an attestation');
  PERFORM fixture.assert(NOT has_table_privilege('service_role',
    'public.product_submission_field_verifications', 'SELECT'),
    'service_role could read attestations directly');
END $$;
$case$);

CREATE FUNCTION fixture.tick_all(sid uuid, p_brand text DEFAULT 'Acme')
RETURNS void LANGUAGE sql AS $$
  SELECT public.set_product_submission_field_verification(
    sid, path, fixture.sha(p_brand), true)
  FROM unnest(public.product_submission_required_verification_paths()) AS path;
$$;

SELECT fixture.test('a batch cannot approve fields nobody read', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM public.set_product_submission_field_verification(
    sid, 'identity.brand', fixture.sha('Acme'), true);
  -- Four of five read. The database, not the browser, refuses.
  PERFORM fixture.throws(format(
    'SELECT public.assert_product_submission_fully_verified(%L, %L)',
    sid, fixture.sha('Acme')), '55000', 'fields not read off the photographs');
END $$;
$case$);

SELECT fixture.test('a fully read label satisfies the server-side gate', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  PERFORM public.assert_product_submission_fully_verified(sid, fixture.sha('Acme'));
END $$;
$case$);

SELECT fixture.test('the gate refuses a label other than the one reviewed', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  PERFORM fixture.throws(format(
    'SELECT public.assert_product_submission_fully_verified(%L, %L)',
    sid, fixture.sha('Something else')), '55000', 'not the one reviewed');
END $$;
$case$);

SELECT fixture.test('an edit after reading reopens every field', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  -- One correction, and the earlier reading no longer describes this label.
  PERFORM fixture.save(sid, 'Edited');
  PERFORM fixture.throws(format(
    'SELECT public.assert_product_submission_fully_verified(%L, %L)',
    sid, fixture.sha('Edited')), '55000', 'fields not read off the photographs');
END $$;
$case$);

SELECT fixture.test('one reviewer''s reading cannot approve for another', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  INSERT INTO public.product_submission_reviewers(user_id) VALUES (fixture.user_id(5))
    ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(5)::text, false);
  PERFORM fixture.throws(format(
    'SELECT public.assert_product_submission_fully_verified(%L, %L)',
    sid, fixture.sha('Acme')), '55000', 'not the one reviewed');
END $$;
$case$);

SELECT fixture.test('batch state reports readiness by the same rule as approval', $case$
DO $$ DECLARE a uuid := fixture.seed(1, '012345678905', 'under_review');
        b uuid := fixture.seed(2, '012345678929', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(a, 'Acme');
  PERFORM fixture.tick_all(a, 'Acme');
  PERFORM fixture.save(b, 'Acme');
  PERFORM public.set_product_submission_field_verification(
    b, 'identity.brand', fixture.sha('Acme'), true);
  state := public.product_submission_reviewer_batch_state(ARRAY[a, b]);
  PERFORM fixture.assert(jsonb_array_length(state) = 2, 'both drafts should appear');
  PERFORM fixture.assert((SELECT (entry ->> 'fully_verified')::boolean
    FROM jsonb_array_elements(state) entry WHERE entry ->> 'submission_id' = a::text),
    'a fully read label was not reported ready');
  PERFORM fixture.assert((SELECT NOT (entry ->> 'fully_verified')::boolean
    FROM jsonb_array_elements(state) entry WHERE entry ->> 'submission_id' = b::text),
    'a partly read label was reported ready');
END $$;
$case$);

SELECT fixture.test('batch state never reports another reviewer''s work', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  INSERT INTO public.product_submission_reviewers(user_id) VALUES (fixture.user_id(5))
    ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(5)::text, false);
  state := public.product_submission_reviewer_batch_state(ARRAY[sid]);
  PERFORM fixture.assert(jsonb_array_length(state) = 0,
    'a reviewer saw another reviewer''s readiness');
END $$;
$case$);

SELECT fixture.test('a retake withdraws batch readiness', $case$
DO $$ DECLARE sid uuid := fixture.seed(1, '012345678905', 'under_review'); state jsonb; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.save(sid, 'Acme');
  PERFORM fixture.tick_all(sid, 'Acme');
  INSERT INTO public.product_submission_evidence_revisions(
    submission_id, revision, request_key, opened_by, photo_ids,
    consent_version, consented_at, ready_at, manifest, manifest_sha256)
  VALUES (sid, 2, gen_random_uuid(), fixture.user_id(1),
    ARRAY['10000000-0000-0000-0000-000000000001'::uuid],
    'fixture.consent.v1', now(), now(), '{}'::jsonb, repeat('b', 64));
  UPDATE public.product_submissions SET evidence_revision = 2 WHERE id = sid;
  state := public.product_submission_reviewer_batch_state(ARRAY[sid]);
  PERFORM fixture.assert(
    (state -> 0 ->> 'superseded')::boolean
    AND NOT (state -> 0 ->> 'fully_verified')::boolean,
    'readiness survived the photographs it was based on');
END $$;
$case$);

SELECT fixture.test('a naked service key cannot read batch readiness', $case$
DO $$ BEGIN
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.product_submission_reviewer_batch_state(uuid[])', 'EXECUTE'),
    'service_role could enumerate reviewer readiness');
END $$;
$case$);
SELECT fixture.test('every unchecked review overload stays private', $case$
DO $$ BEGIN
  PERFORM fixture.assert(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='review_product_submission_unchecked'
  ),'internal implementation exists');
  PERFORM fixture.assert(NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) roles(name)
    WHERE n.nspname='public' AND p.proname='review_product_submission_unchecked'
      AND has_function_privilege(roles.name,p.oid,'EXECUTE')
  ),'no API role can bypass the guarded RPC using any overload');
END $$ $case$);

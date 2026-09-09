SELECT fixture.test('retry accepts 12/13/14 widths and preserves stored digits', $case$
DO $$ DECLARE original uuid; sid uuid := gen_random_uuid(); BEGIN
  original := fixture.seed(1);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM public.create_product_submission(sid, 'missing_product', '0012345678905',
    p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => original);
  PERFORM fixture.assert((SELECT normalized_upc = '0012345678905' AND resubmission_of = original
    FROM public.product_submissions WHERE id = sid), 'canonical retry must retain original scanned width');
  PERFORM public.create_product_submission(gen_random_uuid(), 'missing_product', '00012345678905',
    p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => original);
END $$ $case$);

SELECT fixture.test('lineage owner kind state reason identity and self guards', $case$
DO $$ DECLARE target uuid; sid uuid := gen_random_uuid(); code text; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  target := fixture.seed(2);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '012345678905', target), '22023', 'invalid resubmission lineage');
  target := fixture.seed(1, '012345678905', 'rejected', 'photo_quality', 'label_mismatch', '123');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '012345678905', target), '22023', 'invalid resubmission lineage');
  target := fixture.seed(1, '012345678905', 'rejected', 'not_a_supplement');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '012345678905', target), '22023', 'invalid resubmission lineage');
  target := fixture.seed(1, '012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '012345678905', target), '22023', 'invalid resubmission lineage');
  target := fixture.seed(1);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '036000291452', target), '22023', 'invalid resubmission lineage');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    target, 'missing_product', '012345678905', target), '22023', 'invalid resubmission lineage');
  FOREACH code IN ARRAY ARRAY['photo_quality','missing_panel','label_unreadable','product_identity_mismatch','other'] LOOP
    target := fixture.seed(1, '012345678905', 'rejected', code::public.product_submission_resolution_code);
    PERFORM public.create_product_submission(gen_random_uuid(), 'missing_product', '012345678905',
      p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => target);
  END LOOP;
END $$ $case$);

SELECT fixture.test('mismatch retry requires same dsld and immutable formula replay', $case$
DO $$ DECLARE target uuid; sid uuid := gen_random_uuid(); BEGIN
  target := fixture.seed(1, '012345678905', 'rejected', 'photo_quality', 'label_mismatch', '123');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, fixture.detail(%L), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'label_mismatch', '012345678905', '456', target), '22023', 'invalid resubmission lineage');
  PERFORM public.create_product_submission(sid, 'label_mismatch', '0012345678905', fixture.detail('123', repeat('a',64)), p_consent_version => 'fixture.consent.v1', p_resubmission_of => target);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, fixture.detail(%L, %L), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'label_mismatch', '0012345678905', '123', repeat('b',64), target), '23505', 'submission detail replay conflict');
END $$ $case$);

SELECT fixture.test('immutable create replay rejects changed width lineage and photos', $case$
DO $$ DECLARE target uuid; sid uuid := gen_random_uuid(); BEGIN
  target := fixture.seed(1);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM public.create_product_submission(sid, 'missing_product', '012345678905', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => target);
  PERFORM public.create_product_submission(sid, 'missing_product', '012345678905', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => target);
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '0012345678905', target), '23505', 'submission replay conflict');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'')',
    sid, 'missing_product', '012345678905'), '23505', 'resubmission replay conflict');
  PERFORM fixture.throws(format('SELECT public.create_product_submission(%L, %L, %L, p_photos => %L::jsonb, p_consent_version => ''fixture.consent.v1'', p_resubmission_of => %L)',
    sid, 'missing_product', '012345678905', jsonb_set(fixture.photos(), '{0,content_sha256}', to_jsonb(repeat('b',64))), target),
    '23505', 'submission photo replay conflict');
END $$ $case$);

SELECT fixture.test('GTIN-8 retry accepts zero padded equivalent', $case$
DO $$ DECLARE target uuid; BEGIN
  target := fixture.seed(1, '96385074');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM public.create_product_submission(gen_random_uuid(), 'missing_product', '00000096385074', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1', p_resubmission_of => target);
END $$ $case$);

SELECT fixture.test('different owners retain independent receipts; canonical duplicate review succeeds', $case$
DO $$ DECLARE target uuid; candidate uuid; BEGIN
  target := fixture.seed(1, '036000291452', 'approved', NULL);
  candidate := fixture.seed(2, '0036000291452', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM public.review_product_submission(candidate, 'duplicate', p_duplicate_of => target, p_resolution_code => 'duplicate_submission');
  PERFORM fixture.assert((SELECT duplicate_of = target FROM public.product_submissions WHERE id = candidate), 'review must retain separate receipt');
END $$ $case$);

SELECT fixture.test('canonical approval uniqueness guards cross-owner publication', $case$
DO $$ DECLARE target uuid; candidate uuid; BEGIN
  target := fixture.seed(1, '4006381333931', 'under_review', NULL);
  candidate := fixture.seed(2, '04006381333931', 'under_review', NULL);
  PERFORM fixture.approve(target);
  PERFORM fixture.throws(format('SELECT fixture.approve(%L)', candidate), '23505', 'another approved submission awaits promotion');
END $$ $case$);

SELECT fixture.test('duplicate review never merges unrelated barcode or mismatch target', $case$
DO $$ DECLARE target uuid; candidate uuid; BEGIN
  target := fixture.seed(4, '012345678905', 'approved', NULL);
  candidate := fixture.seed(4, '96385074', 'submitted', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L, %L, p_duplicate_of => %L, p_resolution_code => %L)',
    candidate, 'duplicate', target, 'duplicate_submission'), '22023', 'approved matching submission');
  target := fixture.seed(4, NULL, 'approved', NULL, 'label_mismatch', '123');
  candidate := fixture.seed(4, NULL, 'submitted', NULL, 'label_mismatch', '456');
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L, %L, p_duplicate_of => %L, p_resolution_code => %L)',
    candidate, 'duplicate', target, 'duplicate_submission'), '22023', 'approved matching submission');
END $$ $case$);

SELECT fixture.test('create and reviewer authentication boundaries preserved', $case$
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM fixture.throws('SELECT public.create_product_submission(gen_random_uuid(), ''missing_product'', ''012345678905'', p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'')', '42501', 'authentication required');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws('SELECT public.review_product_submission(gen_random_uuid(), ''approved'')', '42501', 'reviewer access required');
  PERFORM fixture.assert(NOT has_function_privilege('service_role',
    'public.review_product_submission(uuid,public.product_submission_review_status,text,text,jsonb,text,text,uuid,text,text,text,uuid,uuid)', 'EXECUTE'),
    'service role must not receive human approval authority');
  PERFORM fixture.assert(NOT has_function_privilege('authenticated',
    'public.review_product_submission_human_internal(uuid,uuid,public.product_submission_review_status,text,text,jsonb,text,text,uuid,text,text,text)', 'EXECUTE'),
    'internal reviewer function must not be exposed');
END $$ $case$);

SELECT fixture.test('authenticated create preserves own ready replay and cross-owner receipts', $case$
DO $$ DECLARE ready_id uuid; second_id uuid := gen_random_uuid(); BEGIN
  ready_id := fixture.seed(1, '012345678905', 'submitted', NULL);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM public.create_product_submission(ready_id, 'missing_product', '012345678905', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1');
  PERFORM fixture.throws('SELECT public.create_product_submission(gen_random_uuid(), ''missing_product'', ''0012345678905'', p_photos => fixture.photos(), p_consent_version => ''fixture.consent.v1'')',
    '23505', 'idx_product_submissions_user_open_upc');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(2)::text, false);
  PERFORM public.create_product_submission(second_id, 'missing_product', '00012345678905', p_photos => fixture.photos(), p_consent_version => 'fixture.consent.v1');
  PERFORM fixture.assert((SELECT count(*) = 1 AND bool_and(id = second_id) FROM public.product_submissions), 'RLS exposes only the second owner receipt');
END $$ $case$);

SELECT fixture.test('human approval still requires verified match image payload and barcode evidence', $case$
DO $$ DECLARE sid uuid; BEGIN
  sid := fixture.seed(1, '012345678905', 'under_review', NULL);
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L, ''approved'')', sid),
    '55000', 'fresh verified no-match required');
  UPDATE public.product_submission_photos SET categories = ARRAY['barcode']::public.product_submission_evidence_category[]
  WHERE submission_id = sid;
  PERFORM fixture.throws(format('SELECT fixture.approve(%L)', sid), '22023', 'front evidence photo required');
  UPDATE public.product_submission_photos SET categories = ARRAY['front_identity']::public.product_submission_evidence_category[]
  WHERE submission_id = sid;
  PERFORM fixture.throws(format('SELECT fixture.approve(%L)', sid), '55000', 'barcode-bound evidence required');
  INSERT INTO public.product_submission_match_checks(submission_id, reviewer_id, canonical_gtin14, outcome, index_built_at)
  VALUES (sid, fixture.user_id(3), '00012345678905', 'no_match_verified', now());
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L, ''approved'', p_product_image_photo_id => ''10000000-0000-0000-0000-000000000001'')', sid),
    '22023', 'approved canonical payload required');
END $$ $case$);

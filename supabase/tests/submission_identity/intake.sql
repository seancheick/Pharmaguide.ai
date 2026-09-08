SELECT fixture.test('intake validates auth kind GTIN and mismatch target', $case$
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'', ''012345678905'')', '42501', 'authentication required');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(NULL, ''012345678905'')', '22023', 'submission kind required');
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'', NULL)', '22023', 'UPC/EAN');
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'', ''012345678904'')', '22023', 'UPC/EAN');
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'', ''012345678905'', ''123'')', '22023', 'mismatch target');
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''label_mismatch'', NULL)', '22023', 'mismatch target');
  PERFORM fixture.throws('SELECT public.get_product_submission_intake(''label_mismatch'', ''junk'', ''123'')', '22023', 'UPC/EAN');
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product', ' 012-345-678905 ') = '{"action":"start_new"}'::jsonb,
    'valid formatted GTIN without history starts new');
  PERFORM fixture.assert(public.get_product_submission_intake('label_mismatch', NULL, '123') = '{"action":"start_new"}'::jsonb,
    'mismatch can omit UPC with exact catalog target');
END $$ $case$);

SELECT fixture.test('intake only exposes own kind and minimal receipt fields', $case$
DO $$ DECLARE sid uuid; receipt jsonb; BEGIN
  PERFORM fixture.seed(2, '012345678905', 'submitted', NULL);
  PERFORM fixture.seed(1, '012345678905', 'rejected', 'photo_quality', 'label_mismatch', '123');
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product', '00012345678905') = '{"action":"start_new"}'::jsonb,
    'another owner or kind cannot supply a receipt');
  sid := fixture.seed(1);
  receipt := public.get_product_submission_intake('missing_product', '0012345678905');
  PERFORM fixture.assert(receipt = jsonb_build_object('action', 'retry_rejected', 'submission_id', sid,
    'normalized_upc','012345678905','resolution_code','photo_quality','resolution_detail',NULL),
    'only action and four own receipt fields may be returned');
END $$ $case$);

SELECT fixture.test('intake prioritizes ready receipts over newer pending or rejected attempts', $case$
DO $$ DECLARE ready_id uuid; pending_id uuid; BEGIN
  pending_id := fixture.seed(1, '012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending');
  ready_id := fixture.seed(1, '0012345678905', 'submitted', NULL);
  UPDATE public.product_submissions SET created_at = now() + interval '1 second' WHERE id = pending_id;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product', '00012345678905')->>'submission_id' = ready_id::text,
    'ready work should open ahead of a newer incomplete upload');
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product', '012345678905')->>'action' = 'open_existing', 'ready receipt opens');
END $$ $case$);

SELECT fixture.test('intake opens submitted under review approved promoted and duplicate receipts', $case$
DO $$ DECLARE sid uuid; status text; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  FOREACH status IN ARRAY ARRAY['submitted','under_review','approved','duplicate'] LOOP
    sid := fixture.seed(1, '012345678905', status::public.product_submission_review_status,
      CASE WHEN status = 'duplicate' THEN 'already_in_catalog'::public.product_submission_resolution_code END);
    PERFORM fixture.assert(public.get_product_submission_intake('missing_product', '00012345678905')->>'action' = 'open_existing', status || ' should open');
    IF status IN ('approved','duplicate') THEN
      UPDATE public.product_submissions SET promoted_at = now(), promoted_catalog_version = 'fixture', resolved_dsld_id = '123' WHERE id = sid;
      PERFORM fixture.assert(public.get_product_submission_intake('missing_product', '00012345678905')->>'action' = 'open_existing', 'promoted receipt remains discoverable');
    END IF;
    DELETE FROM public.product_submissions WHERE id = sid;
  END LOOP;
END $$ $case$);

SELECT fixture.test('intake latest incomplete attempt wins and never mutates or promises bytes', $case$
DO $$ DECLARE rejected_id uuid; pending_id uuid; before_rows jsonb; BEGIN
  rejected_id := fixture.seed(1);
  pending_id := fixture.seed(1, '0012345678905', 'submitted', NULL, 'missing_product', NULL, 'pending');
  UPDATE public.product_submissions SET created_at = now() + interval '1 second' WHERE id = pending_id;
  SELECT jsonb_agg(to_jsonb(s) ORDER BY id) INTO before_rows FROM public.product_submissions s;
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905')->>'action' = 'incomplete_upload', 'latest pending must be explicit');
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905')->>'submission_id' = pending_id::text, 'pending receipt chosen');
  PERFORM fixture.assert((SELECT jsonb_agg(to_jsonb(s) ORDER BY id) = before_rows FROM public.product_submissions s), 'preflight must not write any submission');
END $$ $case$);

SELECT fixture.test('intake auto retry limited to retakeable reasons and latest attempt', $case$
DO $$ DECLARE sid uuid; code text; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  FOREACH code IN ARRAY ARRAY['photo_quality','missing_panel','label_unreadable','other'] LOOP
    sid := fixture.seed(1, '96385074', 'rejected', code::public.product_submission_resolution_code);
    PERFORM fixture.assert(public.get_product_submission_intake('missing_product','00000096385074')->>'action' = 'retry_rejected', code || ' permits retake suggestion');
    DELETE FROM public.product_submissions WHERE id = sid;
  END LOOP;
  PERFORM fixture.seed(1);
  sid := fixture.seed(1, '0012345678905', 'rejected', 'product_identity_mismatch');
  UPDATE public.product_submissions SET created_at = now() + interval '1 second' WHERE id = sid;
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905') = '{"action":"start_new"}'::jsonb,
    'latest identity rejection must not resurrect older retake advice');
  UPDATE public.product_submissions SET resolution_code = 'not_a_supplement' WHERE id = sid;
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905') = '{"action":"start_new"}'::jsonb,
    'not a supplement cannot suggest automatic retry');
END $$ $case$);

SELECT fixture.test('mismatch intake uses target scope except barcode-open transaction conflict', $case$
DO $$ DECLARE sid uuid; BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  sid := fixture.seed(1, NULL, 'rejected', 'photo_quality', 'label_mismatch', '123');
  PERFORM fixture.assert(public.get_product_submission_intake('label_mismatch',NULL,'456') = '{"action":"start_new"}'::jsonb, 'null UPC mismatch must match dsld');
  PERFORM fixture.assert(public.get_product_submission_intake('label_mismatch',NULL,'123')->>'submission_id' = sid::text, 'same null UPC target may retry');
  sid := fixture.seed(1, '012345678905', 'submitted', NULL, 'label_mismatch', '123');
  PERFORM fixture.assert(public.get_product_submission_intake('label_mismatch','0012345678905','456')->>'submission_id' = sid::text,
    'existing barcode correction must open because create would reject it even for a different target');
  PERFORM fixture.throws('SELECT public.create_product_submission(gen_random_uuid(), ''label_mismatch'', ''0012345678905'', fixture.detail(''456''))',
    '23505', 'idx_product_submissions_user_open_upc');
END $$ $case$);

SET ROLE authenticated;
SELECT fixture.test('authenticated intake runs with real role grants', $case$
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(1)::text, false);
  PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905') = '{"action":"start_new"}'::jsonb, 'authenticated RPC callable');
  PERFORM fixture.throws('SELECT * FROM public.product_submission_review_events', '42501', 'permission denied');
END $$ $case$);
RESET ROLE;
SELECT fixture.test('intake denies anonymous and service role execution', $case$
DO $$ BEGIN
  PERFORM fixture.assert(NOT has_function_privilege('anon','public.get_product_submission_intake(public.product_submission_kind,text,text)','EXECUTE'), 'anon must have no execute');
  PERFORM fixture.assert(NOT has_function_privilege('service_role','public.get_product_submission_intake(public.product_submission_kind,text,text)','EXECUTE'), 'service role must have no execute');
END $$ $case$);

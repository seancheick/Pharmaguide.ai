-- A reviewer can correct the barcode an owner filed; the original is kept, the
-- recorded barcode check cannot carry over to the new barcode, and nothing
-- outside an open missing-product review can be corrected.

SELECT fixture.test('a correction rewrites the one barcode, logs the original and reopens the check', $case$
DO $$ DECLARE sid uuid; r jsonb; s jsonb; BEGIN
 sid:=fixture.seed(1,'00671477','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 INSERT INTO public.product_submission_match_checks(submission_id,reviewer_id,outcome,canonical_gtin14,index_built_at,evidence_revision)
 VALUES(sid,fixture.user_id(3),'no_match_verified','00000000671477',now(),1);
 PERFORM fixture.assert((public.load_product_submission_reviewer_draft(sid)->'identity_check'->>'satisfies_approval')::boolean,'the old barcode was verified');
 PERFORM fixture.assert(public.load_product_submission_reviewer_draft(sid)->'barcode_corrections'='[]'::jsonb,'no correction yet');
 -- Printed barcodes carry spaces; intake strips them, so does the correction.
 r:=public.correct_product_submission_barcode(sid,'0067 1422','Bottle prints 0067 1422, owner scanned a neighbour',1,fixture.manifest_hash(sid));
 PERFORM fixture.assert(r='{"from_upc":"00671477","to_upc":"00671422"}'::jsonb,'the result names both barcodes');
 PERFORM fixture.assert((SELECT normalized_upc='00671422' FROM public.product_submissions WHERE id=sid),'normalized_upc is the one barcode');
 PERFORM fixture.assert((SELECT count(*)=1 AND bool_and(from_upc='00671477' AND to_upc='00671422'
     AND reason='Bottle prints 0067 1422, owner scanned a neighbour' AND evidence_revision=1 AND reviewer_id=fixture.user_id(3))
   FROM public.product_submission_barcode_corrections WHERE submission_id=sid),'the original filing is kept');
 s:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(s->'barcode_corrections'->0->>'from_upc'='00671477' AND s->'barcode_corrections'->0->>'to_upc'='00671422','the console reads the history');
 PERFORM fixture.assert(NOT s->'barcode_corrections'->0 ? 'reviewer_id','no reviewer account exposed');
 PERFORM fixture.assert(NOT (s->'identity_check'->>'satisfies_approval')::boolean,'a check for the old barcode no longer satisfies approval');
 INSERT INTO public.product_submission_match_checks(submission_id,reviewer_id,outcome,canonical_gtin14,index_built_at,evidence_revision)
 VALUES(sid,fixture.user_id(3),'no_match_verified','00000000671422',now(),1);
 PERFORM fixture.assert((public.load_product_submission_reviewer_draft(sid)->'identity_check'->>'satisfies_approval')::boolean,'a check for the new barcode does');
 -- Corrected again: the log keeps every step, oldest first.
 PERFORM public.correct_product_submission_barcode(sid,'036000291452','Second look',1,fixture.manifest_hash(sid));
 PERFORM fixture.assert((SELECT array_agg(from_upc||'>'||to_upc ORDER BY id)=ARRAY['00671477>00671422','00671422>036000291452']
   FROM public.product_submission_barcode_corrections WHERE submission_id=sid),'every correction is logged in order');
END $$ $case$);

SELECT fixture.test('an approval after a correction needs a check for the new barcode and carries it', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'00671477','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.correct_product_submission_barcode(sid,'00671422','Owner scanned a neighbour',1,fixture.manifest_hash(sid));
 PERFORM fixture.assert(fixture.approve(sid),'approval needs a check for the new barcode and accepts it');
 PERFORM fixture.assert((SELECT normalized_upc='00671422' FROM public.product_submissions WHERE id=sid),'the approved submission carries the corrected barcode');
END $$ $case$);

SELECT fixture.test('a correction needs a reviewer, a valid barcode, a reason and a real change', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 h:=fixture.manifest_hash(sid);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',''why'',1,%L)',sid,h),'42501','reviewer access required');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291453'',''why'',1,%L)',sid,h),'22023','valid barcode required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''abc'',''why'',1,%L)',sid,h),'22023','valid barcode required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,NULL,''why'',1,%L)',sid,h),'22023','valid barcode required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',''   '',1,%L)',sid,h),'22023','reason required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',NULL,1,%L)',sid,h),'22023','reason required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',%L,1,%L)',sid,repeat('x',501),h),'22023','reason required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''012345678905'',''why'',1,%L)',sid,h),'22023','barcode unchanged');
 -- The same GTIN in another width is the same product, not a correction.
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''0012345678905'',''why'',1,%L)',sid,h),'22023','barcode unchanged');
 PERFORM fixture.assert((SELECT normalized_upc='012345678905' FROM public.product_submissions WHERE id=sid)
   AND NOT EXISTS(SELECT 1 FROM public.product_submission_barcode_corrections WHERE submission_id=sid),'a refused correction changes and records nothing');
END $$ $case$);

SELECT fixture.test('only a missing-product submission under review on current evidence can be corrected', $case$
DO $$ DECLARE rejected uuid; unopened uuid; open_id uuid; h text; BEGIN
 rejected:=fixture.seed(1,'012345678905','rejected');
 unopened:=fixture.seed(4,'012345678905','submitted',NULL);
 open_id:=fixture.seed(2,'036000291452','under_review',NULL);
 h:=fixture.manifest_hash(open_id);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''00671422'',''why'',1,%L)',rejected,fixture.manifest_hash(rejected)),'55000','under review required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''00671422'',''why'',1,%L)',unopened,fixture.manifest_hash(unopened)),'55000','under review required');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''00671422'',''why'',1,%L)',open_id,repeat('0',64)),'55000','changed since review');
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''00671422'',''why'',2,%L)',open_id,h),'55000','changed since review');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_barcode_corrections),'nothing was recorded');
END $$ $case$);

SELECT fixture.test('a correction cannot collide with the owner''s other open submission or an approved one', $case$
DO $$ DECLARE a uuid; b uuid; other uuid; mine uuid; BEGIN
 a:=fixture.seed(1,'012345678905','under_review',NULL);
 b:=fixture.seed(1,'036000291452','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',''why'',1,%L)',a,fixture.manifest_hash(a)),'23505','idx_product_submissions_user_open_upc');
 PERFORM fixture.assert((SELECT normalized_upc='012345678905' FROM public.product_submissions WHERE id=a)
   AND NOT EXISTS(SELECT 1 FROM public.product_submission_barcode_corrections WHERE submission_id=a),'the collision rolls the log back with the update');
 other:=fixture.seed(2,'00671422','under_review',NULL);
 PERFORM fixture.assert(fixture.approve(other),'another owner''s submission for the target barcode is approved');
 mine:=fixture.seed(4,'00671477','under_review',NULL);
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''00671422'',''why'',1,%L)',mine,fixture.manifest_hash(mine)),'23505','another approved submission awaits promotion');
END $$ $case$);

SELECT fixture.test('owners and signed-in users cannot read or call the correction log', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'00671477','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.correct_product_submission_barcode(sid,'00671422','why',1,fixture.manifest_hash(sid));
 SET LOCAL ROLE authenticated;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,true);
 PERFORM fixture.throws('SELECT count(*) FROM public.product_submission_barcode_corrections','42501','permission denied');
 SET LOCAL ROLE anon;
 PERFORM fixture.throws(format('SELECT public.correct_product_submission_barcode(%L,''036000291452'',''why'',1,''x'')',sid),'42501','permission denied');
END $$ $case$);

SELECT fixture.test('display names are owner scoped and never change identity or review', $case$
DO $$ DECLARE sid uuid; other uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 other:=fixture.seed(2,'012345678905','under_review',NULL);
 SET LOCAL ROLE authenticated;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,true);
 PERFORM fixture.assert(public.set_product_submission_display_name(sid,' Seed · DS-01 '),'backend receives a true acknowledgement');
 PERFORM fixture.assert((SELECT display_name='Seed · DS-01'
   AND normalized_upc='012345678905' AND review_status='under_review'
   FROM public.product_submissions WHERE id=sid),'only the display name changes');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_display_name(%L,''Other'')',other),'42501','submission unavailable');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_display_name(%L,'' '')',sid),'22023','display name');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_display_name(%L,%L)',sid,repeat('x',161)),'22023','display name');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_display_name(%L,%L)',sid,E'line\nbreak'),'22023','display name');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submissions WHERE id=other),'other owner stays hidden');
 RESET ROLE;
END $$ $case$);

SELECT fixture.test('review display names are bounded and never invent missing names', $case$
DO $$ BEGIN
 PERFORM fixture.assert(public.submission_label_display_name('{"brandName":"Brand"}') IS NULL,'brand alone is not a product name');
 PERFORM fixture.assert(public.submission_label_display_name('{"fullName":123}') IS NULL,'malformed name rejected');
 PERFORM fixture.assert(public.submission_label_display_name('{"brandName":"Seed","fullName":"Seed DS-01"}')='Seed DS-01','brand not duplicated');
 PERFORM fixture.assert(char_length(public.submission_label_display_name(jsonb_build_object('fullName',repeat('x',200))))=160,'bounded display label');
END $$ $case$);

SELECT fixture.test('current reviewer draft supplies a name but never overrides an approval', $case$
DO $$ DECLARE sid uuid; payload jsonb:='{"brandName":"Seed","fullName":"DS-01"}'; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.save_product_submission_reviewer_draft(sid,1,fixture.manifest(sid),payload,payload::text,encode(extensions.digest(payload::text,'sha256'),'hex'));
 PERFORM fixture.assert((SELECT display_name='Seed · DS-01' FROM public.product_submissions WHERE id=sid),'draft name reaches history');
 INSERT INTO public.product_submission_approved_labels(submission_id,schema_version,approved_payload,approved_payload_canonical,payload_sha256,reviewer_id)
 VALUES(sid,'manual_label_v1','{"fullName":"Signed off"}','{"fullName":"Signed off"}',repeat('a',64),fixture.user_id(3));
 PERFORM public.save_product_submission_reviewer_draft(sid,1,fixture.manifest(sid),payload,payload::text,encode(extensions.digest(payload::text,'sha256'),'hex'));
 PERFORM fixture.assert((SELECT display_name='Signed off' FROM public.product_submissions WHERE id=sid),'approved name wins');
END $$ $case$);

SELECT fixture.test('approved product names reach history without a catalog release', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','approved');
 INSERT INTO public.product_submission_approved_labels(submission_id,schema_version,approved_payload,approved_payload_canonical,payload_sha256,reviewer_id)
 VALUES(sid,'manual_label_v1','{"brandName":"Align","fullName":"Women''s Dual Action"}','{"brandName":"Align","fullName":"Women''s Dual Action"}',repeat('a',64),fixture.user_id(3));
 PERFORM fixture.assert((SELECT display_name='Align · Women''s Dual Action' FROM public.product_submissions WHERE id=sid),'approved name projected');
 PERFORM fixture.assert((SELECT normalized_upc='012345678905' AND review_status='approved' FROM public.product_submissions WHERE id=sid),'identity and approval unchanged');
END $$ $case$);

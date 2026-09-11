SELECT fixture.test('review pictures survive reopening and reject other submissions', $case$
DO $$ DECLARE sid uuid; other uuid; iid uuid:=gen_random_uuid(); path text; r jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review');
 other:=fixture.seed(2,'012345678905','under_review');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.save(sid);
 path:=public.create_product_submission_reviewer_image(sid,iid,'manufacturer_provided',true,NULL,1,fixture.manifest(sid));
 PERFORM fixture.throws(format('SELECT public.set_product_submission_review_image(%L,1,%L,''reviewer'',%L)',sid,fixture.manifest(sid),iid),'22023','verified reviewer image');
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('product-submission-reviewer-images',path,'{"size":120}');
 PERFORM public.finalize_product_submission_reviewer_image(sid,iid,'image/jpeg',120,repeat('a',64));
 PERFORM fixture.assert(public.set_product_submission_review_image(sid,1,fixture.manifest(sid),'reviewer',iid),'selection saved');
 r:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(r->'product_image'->>'id'=iid::text,'selection reopens');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_review_image(%L,1,%L,''reviewer'',%L)',other,fixture.manifest(other),iid),'22023','verified reviewer image');
 PERFORM fixture.throws(format('SELECT public.set_product_submission_review_image(%L,1,%L,''photo'',%L)',sid,fixture.manifest(sid),iid),'22023','front photo');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.load_product_submission_reviewer_draft(%L)',sid),'42501','reviewer access');
END $$ $case$);

SELECT fixture.test('approved records reopen without a personal working draft', $case$
DO $$ DECLARE sid uuid; r jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','approved');
 INSERT INTO public.product_submission_approved_labels(submission_id,schema_version,approved_payload,approved_payload_canonical,payload_sha256,reviewer_id)
 VALUES(sid,'manual_label_v1','{"brandName":"Approved"}','{"brandName":"Approved"}',repeat('a',64),fixture.user_id(3));
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 r:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(r->'draft'='null'::jsonb,'no personal draft');
 PERFORM fixture.assert(r->'approved_label'->'approved_payload'->>'brandName'='Approved','approved label is independent of personal drafts');
END $$ $case$);

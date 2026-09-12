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

SELECT fixture.test('saved identity history reopens without exposing reviewer accounts', $case$
DO $$ DECLARE sid uuid; other uuid; r jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review');
 other:=fixture.seed(2,'012345678905','under_review');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 r:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(r->'identity_check'='{"recorded":false,"satisfies_approval":false,"catalog_match_live":false}'::jsonb,'no history is explicit');
 INSERT INTO public.product_submission_match_checks(submission_id,reviewer_id,outcome,canonical_gtin14,index_built_at,evidence_revision)
 VALUES(sid,fixture.user_id(3),'no_match_verified','00012345678905',now(),1);
 r:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(r->'identity_check'->>'outcome'='no_match_verified','recorded check survives reopen');
 PERFORM fixture.assert((r->'identity_check'->>'satisfies_approval')::boolean,'server confirms current identity binding');
 PERFORM fixture.assert(r->'identity_check'->>'evidence_revision'='1','revision binding returned');
 PERFORM fixture.assert(NOT (r->'identity_check' ? 'reviewer_id'),'no reviewer account exposed');
 PERFORM fixture.assert(public.load_product_submission_reviewer_draft(other)->'identity_check'='{"recorded":false,"satisfies_approval":false,"catalog_match_live":false}'::jsonb,'no cross-submission history');
 INSERT INTO public.product_submission_match_checks(submission_id,reviewer_id,outcome,canonical_gtin14,index_built_at,evidence_revision,matched_dsld_id)
 VALUES(sid,fixture.user_id(3),'catalog_match','00012345678905',now(),1,'123');
 r:=public.load_product_submission_reviewer_draft(sid);
 PERFORM fixture.assert(r->'identity_check'->>'outcome'='catalog_match','latest outcome wins same-timestamp tie');
 PERFORM fixture.assert(NOT (r->'identity_check'->>'satisfies_approval')::boolean,'later catalog match invalidates earlier no match');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.load_product_submission_reviewer_draft(%L)',sid),'42501','reviewer access');
END $$ $case$);

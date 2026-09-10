-- Behavioral tests of the actual RPCs; synthetic evidence only.
SELECT fixture.test('legacy evidence is frozen without inventing historical consent', $case$
SELECT fixture.assert(EXISTS(SELECT 1 FROM public.product_submissions submission
 JOIN public.product_submission_evidence_revisions revision ON revision.submission_id=submission.id
 JOIN public.product_submission_photos photo ON photo.submission_id=submission.id
 WHERE submission.id='90000000-0000-0000-0000-000000000002' AND submission.consent_version IS NULL
   AND submission.consented_at IS NULL AND revision.consent_version IS NULL AND revision.consented_at IS NULL
   AND revision.revision=1 AND revision.ready_at='2026-08-01T12:00:00Z' AND photo.byte_size=123
   AND photo.content_sha256=repeat('d',64) AND photo.photo_id=ANY(revision.photo_ids)
   AND revision.manifest=public.product_submission_evidence_records(submission.id,1)),
 'migration must preserve original evidence and unknown consent');
$case$);
DELETE FROM public.product_submissions WHERE id='90000000-0000-0000-0000-000000000002';
DELETE FROM auth.users WHERE id='90000000-0000-0000-0000-000000000001';

CREATE FUNCTION fixture.retake(sid uuid, request_key uuid DEFAULT gen_random_uuid(), kept uuid[] DEFAULT '{}')
RETURNS integer LANGUAGE sql AS $$
 SELECT public.open_product_submission_evidence_revision(sid,1,request_key,kept,'fixture.consent.v1')
$$;
CREATE FUNCTION fixture.new_photo(n integer DEFAULT 2) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_array(jsonb_build_object('photo_id',('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 'seq',1,'categories',jsonb_build_array('front_identity','supplement_facts','ingredient_disclosure','barcode'),
 'content_type','image/jpeg','byte_size',120,'content_sha256',md5(n::text)||md5(n::text)))
$$;
CREATE FUNCTION fixture.upload_revision(sid uuid, rev integer) RETURNS void LANGUAGE sql AS $$
 INSERT INTO storage.objects(bucket_id,name,owner_id,metadata,user_metadata)
 SELECT 'product-submission-photos',object_path,user_id::text,
 jsonb_build_object('size',byte_size,'mimetype',content_type),jsonb_build_object('content_sha256',content_sha256)
 FROM public.product_submission_photos WHERE submission_id=sid AND revision=rev
 ON CONFLICT DO NOTHING
$$;
CREATE FUNCTION fixture.unknown_field() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
 SELECT '{"value":null,"status":"unreadable","confidence":null,"sources":[]}'::jsonb
$$;
CREATE FUNCTION fixture.draft(sid uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema_version','label_draft_v1','draft_origin','human_transcription',
 'provider','human','model','human','prompt_version','p1','evidence_revision',evidence_revision,
 'evidence_snapshot',public.product_submission_evidence_manifest(sid,evidence_revision),
 'sent_inputs','[]'::jsonb,'photo_roles','[]'::jsonb,
 'identity',jsonb_build_object('brand',fixture.unknown_field(),'product_name',fixture.unknown_field(),'barcode_digits_seen',NULL),
 'serving',jsonb_build_object('size',fixture.unknown_field(),'servings_per_container',fixture.unknown_field(),'basis_text',fixture.unknown_field(),'amount',NULL),
 'ingredient_rows','[]'::jsonb,'other_ingredients',jsonb_build_object('text',NULL,'disclosure_hint','unknown'),'statements','[]'::jsonb,
 'discrepancies','[]'::jsonb,'abstained',true,'abstain_reason','manual fixture','overall_confidence',NULL)
 FROM public.product_submissions WHERE id=sid
$$;
CREATE FUNCTION fixture.record_draft(sid uuid, revision integer DEFAULT 1, payload jsonb DEFAULT NULL)
RETURNS integer LANGUAGE sql AS $$
 SELECT public.record_product_submission_extraction(sid,'label_draft_v1','human','human','p1',
 public.product_submission_evidence_manifest(sid,revision),coalesce(payload,fixture.draft(sid)),
 '{}'::jsonb,NULL,'{"cost_microcents":0}'::jsonb,revision)
$$;

SELECT fixture.test('consent registry requires recognized copy and immutable replay', $case$
DO $$ DECLARE sid uuid:=gen_random_uuid(); BEGIN
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.create_product_submission(%L,''missing_product'',''012345678905'',p_photos=>fixture.photos())',sid),'22023','consent version required');
 PERFORM fixture.throws(format('SELECT public.create_product_submission(%L,''missing_product'',''012345678905'',p_photos=>fixture.photos(),p_consent_version=>''unknown.v1'')',sid),'22023','not recognized');
 PERFORM public.create_product_submission(sid,'missing_product','012345678905',p_photos=>fixture.photos(),p_consent_version=>'fixture.consent.v1');
 PERFORM fixture.assert((SELECT consent_version='fixture.consent.v1' AND consented_at IS NOT NULL FROM public.product_submission_evidence_revisions WHERE submission_id=sid),'consent must bind revision');
 PERFORM fixture.throws(format('SELECT public.create_product_submission(%L,''missing_product'',''012345678905'',p_photos=>fixture.photos(),p_consent_version=>''fixture.consent.v2'')',sid),'23505','consent replay conflict');
END $$ $case$);

SELECT fixture.test('draft authentication bindings and typed envelope errors', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM fixture.assert(to_regprocedure('public.record_product_submission_extraction(uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,numeric)') IS NULL,'spoofable writer must be gone');
 PERFORM fixture.assert(NOT has_function_privilege('service_role','public.record_product_submission_extraction(uuid,text,text,text,text,jsonb,jsonb,jsonb,numeric,jsonb,integer)','EXECUTE'),'service key must not record human draft');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L)',sid),'42501','reviewer access required');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.assert(fixture.record_draft(sid)=1,'valid bound human draft');
 PERFORM fixture.assert((SELECT recorded_by=fixture.user_id(3) AND evidence_revision=1 AND usage->>'cost_microcents'='0'
 FROM public.product_submission_extractions WHERE submission_id=sid),'session actor and usage');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,NULL)',sid),'22023','revision required');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,1,%L)',sid,jsonb_set(fixture.draft(sid),'{evidence_revision}','999')),'22023','snapshot');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,1,%L)',sid,fixture.draft(sid)-'evidence_revision'),'22023','snapshot');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,1,%L)',sid,jsonb_set(fixture.draft(sid),'{evidence_snapshot}','{}')),'22023','snapshot');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,1,%L)',sid,jsonb_set(fixture.draft(sid),'{provider}','"other"')),'22023','metadata');
 PERFORM fixture.throws(format('SELECT fixture.record_draft(%L,1,''{}'')',sid),'22023','metadata');
END $$ $case$);

SELECT fixture.test('empty revisions legacy finalize and changed replay fail closed', $case$
DO $$ DECLARE sid uuid; key uuid:=gen_random_uuid(); BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.assert(fixture.retake(sid,key)=2,'new revision');
 PERFORM fixture.assert(NOT public.finalize_product_submission(sid,2),'old photos cannot finalize empty retake');
 PERFORM fixture.throws(format('SELECT public.finalize_product_submission(%L)',sid),'55000','revision conflict');
 PERFORM fixture.assert(fixture.retake(sid,key)=2,'same request is idempotent');
 PERFORM fixture.throws(format('SELECT fixture.retake(%L)',sid),'55000','revision conflict');
 PERFORM fixture.throws(format('SELECT fixture.retake(%L,%L,ARRAY[''10000000-0000-0000-0000-000000000001''::uuid])',sid,key),'23505','replay conflict');
 PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
 PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
 PERFORM fixture.assert(NOT public.finalize_product_submission(sid,2),'bytes must exist');
 PERFORM fixture.upload_revision(sid,2);
 PERFORM fixture.assert(public.finalize_product_submission(sid,2),'new full manifest finalizes');
 PERFORM fixture.assert(fixture.retake(sid,key)=2,'delayed same key never creates revision3');
 PERFORM fixture.assert((SELECT count(*)=2 FROM public.product_submission_photos WHERE submission_id=sid),'old evidence retained');
 PERFORM fixture.assert((SELECT cardinality(photo_ids)=1 FROM public.product_submission_evidence_revisions WHERE submission_id=sid AND revision=2),'history is not implicitly current');
END $$ $case$);

SELECT fixture.test('active review requires request and pending revision keeps duplicate guard', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT fixture.retake(%L)',sid),'55000','reviewer request');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.request_product_submission_evidence(sid,'photo_quality',1,fixture.manifest_hash(sid));
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid);
 PERFORM fixture.assert(public.get_product_submission_intake('missing_product','012345678905')->>'action'='open_existing','current app must understand pending retake');
  PERFORM fixture.throws('SELECT public.create_product_submission(gen_random_uuid(),''missing_product'',''0012345678905'',p_photos=>fixture.photos(),p_consent_version=>''fixture.consent.v1'')','23505','idx_product_submissions_user_open_upc');
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''approved'')',sid),'55000','not the one reviewed');
END $$ $case$);

SELECT fixture.test('new retake not expired by original receipt age and cleanup fences completion', $case$
DO $$ DECLARE sid uuid; claim record; claims jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 UPDATE public.product_submissions SET created_at=now()-interval '2 days' WHERE id=sid;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid);
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid),'fresh retake must not enter cleanup');
 PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
 PERFORM fixture.upload_revision(sid,2);
 UPDATE public.product_submissions SET evidence_revision_opened_at=now()-interval '25 hours' WHERE id=sid;
 SELECT * INTO claim FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid;
 PERFORM fixture.assert(cardinality(claim.evidence_object_paths)=1 AND cardinality(claim.reviewer_object_paths)=0,'only new retake bytes eligible');
 claims:=jsonb_build_object(sid::text,jsonb_build_object('claim_token',claim.claim_token,'evidence_revision',2));
 PERFORM fixture.throws(format('SELECT public.complete_product_submission_cleanup(ARRAY[%L::uuid],''{}'')',sid),'55000','claim changed');
 PERFORM fixture.assert(NOT public.finalize_product_submission(sid,2),'cleanup excludes finalize');
 PERFORM fixture.assert(public.complete_product_submission_cleanup(ARRAY[sid],claims)=1,'current claim completes');
 PERFORM fixture.assert((SELECT evidence_revision=1 AND upload_state='ready' FROM public.product_submissions WHERE id=sid),'restore durable last revision');
 PERFORM fixture.assert((SELECT count(*)=1 AND bool_and(revision=1) FROM public.product_submission_photos WHERE submission_id=sid),'original evidence preserved');
 PERFORM fixture.assert((SELECT abandoned_at IS NOT NULL FROM public.product_submission_evidence_revisions WHERE submission_id=sid AND revision=2),'abandoned revision retained');
END $$ $case$);

SELECT fixture.test('retake never permits writes to retained storage evidence', $case$
DO $$ DECLARE sid uuid; n integer; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid);
 SET LOCAL ROLE authenticated;
 UPDATE storage.objects SET user_metadata='{}' WHERE bucket_id='product-submission-photos';
 GET DIAGNOSTICS n=ROW_COUNT;
 PERFORM fixture.assert(n=0,'old bytes must not become writable');
 DELETE FROM storage.objects WHERE bucket_id='product-submission-photos';
 GET DIAGNOSTICS n=ROW_COUNT;
 PERFORM fixture.assert(n=0,'old bytes must not become deletable');
END $$ $case$);

SELECT fixture.test('old match old image and stale review cannot approve new revision', $case$
DO $$ DECLARE sid uuid; old_hash text; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL); old_hash:=fixture.manifest_hash(sid);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.record_product_submission_match_check(sid,'no_match_verified','00012345678905',now(),
 p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>old_hash);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid); PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
  PERFORM fixture.upload_revision(sid,2); PERFORM public.finalize_product_submission(sid,2);
  PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
  PERFORM fixture.prepare_review(sid);
  PERFORM fixture.throws(format('SELECT public.record_product_submission_match_check(%L,''no_match_verified'',''00012345678905'',now(),p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>%L)',sid,old_hash),'55000','changed since review');
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''approved'',p_payload_sha256=>%L,p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>%L)',sid,encode(extensions.digest('{"fixture":true}', 'sha256'), 'hex'),old_hash),'55000','changed since review');
  PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''approved'',p_payload_sha256=>%L,p_expected_evidence_revision=>2,p_evidence_manifest_sha256=>%L)',sid,encode(extensions.digest('{"fixture":true}', 'sha256'), 'hex'),fixture.manifest_hash(sid)),'55000','no-match');
 PERFORM fixture.throws(format('SELECT fixture.approve(%L)',sid),'22023','front evidence photo');
END $$ $case$);

SELECT fixture.test('export image and promotion reject a stale approval binding', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.export_approved_product_submissions() WHERE submission_id=sid),'current approval exports');
 UPDATE public.product_submission_approved_labels SET evidence_revision=999 WHERE submission_id=sid;
 PERFORM fixture.throws('SELECT * FROM public.export_approved_product_submissions()','55000','approval evidence changed');
 PERFORM fixture.throws(format('SELECT * FROM public.get_approved_product_submission_image(%L)',sid),'55000','approval evidence changed');
 PERFORM fixture.throws(format('SELECT public.mark_product_submission_promoted(%L,''2026.09.09'',''12345'')',sid),'55000','approval evidence changed');
END $$ $case$);

SELECT fixture.test('reviewer image finalization is immutable and revision bound', $case$
DO $$ DECLARE sid uuid; image_id uuid:=gen_random_uuid(); path text; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 path:=public.create_product_submission_reviewer_image(sid,image_id,'operator_photo',true,
 p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>fixture.manifest_hash(sid));
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('product-submission-reviewer-images',path,'{"size":120}');
 PERFORM public.finalize_product_submission_reviewer_image(sid,image_id,'image/jpeg',120,repeat('a',64));
 PERFORM fixture.assert(public.finalize_product_submission_reviewer_image(sid,image_id,'image/jpeg',120,repeat('a',64)),'identical retry allowed');
 PERFORM fixture.throws(format('SELECT public.finalize_product_submission_reviewer_image(%L,%L,''image/jpeg'',120,%L)',sid,image_id,repeat('b',64)),'23505','image already finalized');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid);
 PERFORM fixture.throws(format('SELECT public.finalize_product_submission_reviewer_image(%L,%L,''image/jpeg'',120,%L)',sid,image_id,repeat('a',64)),'55000','current evidence');
END $$ $case$);

SELECT fixture.test('purged history remains readable but cannot be reviewed', $case$
DO $$ DECLARE sid uuid; context jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','rejected',NULL);
 UPDATE public.product_submissions SET evidence_purged_at=now() WHERE id=sid;
 DELETE FROM public.product_submission_photos WHERE submission_id=sid;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 context:=public.get_product_submission_evidence(sid);
 PERFORM fixture.assert(context->'photos'='[]'::jsonb,'history can render without private bytes');
 PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''under_review'',p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>%L)',sid,fixture.manifest_hash(sid)),'55000','ready evidence');
END $$ $case$);

SELECT fixture.test('expired cleanup workers cannot delete recycled photo addresses', $case$
DO $$ DECLARE sid uuid; a record; b record; claims jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.retake(sid); PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
 PERFORM fixture.upload_revision(sid,2);
 UPDATE public.product_submissions SET evidence_revision_opened_at=now()-interval '25 hours' WHERE id=sid;
 SELECT * INTO a FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid;
 UPDATE public.product_submissions SET cleanup_claimed_at=now()-interval '16 minutes' WHERE id=sid;
 SELECT * INTO b FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid;
 PERFORM fixture.assert(a.claim_token<>b.claim_token,'expired lease must receive a new token');
 DELETE FROM storage.objects WHERE name=ANY(b.evidence_object_paths);
 claims:=jsonb_build_object(sid::text,jsonb_build_object('claim_token',b.claim_token,'evidence_revision',2));
 PERFORM public.complete_product_submission_cleanup(ARRAY[sid],claims);
 PERFORM fixture.assert(fixture.retake(sid)=3,'abandoned revisions are not reused');
 PERFORM fixture.throws(format('SELECT public.add_product_submission_evidence(%L,3,fixture.new_photo())',sid),'23505','retired evidence object');
 PERFORM public.add_product_submission_evidence(sid,3,fixture.new_photo(3));
 PERFORM fixture.upload_revision(sid,3); PERFORM public.finalize_product_submission(sid,3);
 DELETE FROM storage.objects WHERE name=ANY(a.evidence_object_paths);
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM storage.objects object JOIN public.product_submission_photos photo
   ON photo.object_path=object.name WHERE photo.submission_id=sid AND photo.revision=3),'late delete cannot address new bytes');
 claims:=jsonb_build_object(sid::text,jsonb_build_object('claim_token',a.claim_token,'evidence_revision',2));
 PERFORM fixture.throws(format('SELECT public.complete_product_submission_cleanup(ARRAY[%L::uuid],%L)',sid,claims),'55000','claim changed');
END $$ $case$);

SELECT fixture.test('cleaned first uploads cannot reuse retired storage addresses', $case$
DO $$ DECLARE sid uuid; claim record; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL,'missing_product',NULL,'pending');
 UPDATE public.product_submissions SET created_at=now()-interval '25 hours' WHERE id=sid;
 SELECT * INTO claim FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid;
 DELETE FROM storage.objects WHERE name=ANY(claim.evidence_object_paths);
 PERFORM public.complete_product_submission_cleanup(ARRAY[sid],jsonb_build_object(sid::text,
   jsonb_build_object('claim_token',claim.claim_token,'evidence_revision',1)));
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submissions WHERE id=sid),'private abandoned first upload removed');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.create_product_submission(%L,''missing_product'',''012345678905'',p_photos=>fixture.photos(),p_consent_version=>''fixture.consent.v1'')',sid),'23505','retired evidence object');
END $$ $case$);

SELECT fixture.test('a retake must leave capacity for a newly captured photo', $case$
DO $$ DECLARE sid uuid; kept uuid[]; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL,'missing_product',NULL,'pending');
 INSERT INTO public.product_submission_photos(submission_id,user_id,photo_id,seq,categories,object_path,content_type,byte_size,content_sha256,revision)
 SELECT sid,fixture.user_id(1),('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,n,
 ARRAY['front_identity']::public.product_submission_evidence_category[],fixture.user_id(1)::text||'/'||sid||'/10000000-0000-0000-0000-'||lpad(n::text,12,'0'),
 'image/jpeg',120,md5(n::text)||md5(n::text),1 FROM generate_series(2,8)n;
 SELECT array_agg(photo_id ORDER BY seq) INTO kept FROM public.product_submission_photos WHERE submission_id=sid;
 UPDATE public.product_submission_evidence_revisions SET photo_ids=kept WHERE submission_id=sid;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.upload_revision(sid,1); PERFORM public.finalize_product_submission(sid,1);
 PERFORM fixture.throws(format('SELECT fixture.retake(%L,gen_random_uuid(),%L::uuid[])',sid,kept),'22023','leave room for new evidence');
 PERFORM fixture.assert((SELECT upload_state='ready' AND evidence_revision=1 FROM public.product_submissions WHERE id=sid),'failed open must not strand receipt');
END $$ $case$);

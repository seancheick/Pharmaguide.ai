-- Approval corrections preserve history, exact release identity, and points.

SELECT fixture.test('approved rows are revisioned and immutable', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels
  WHERE submission_id=sid AND approval_revision=1;
 PERFORM fixture.assert((SELECT approval_revision=1 AND promoted_approval_revision=0
  FROM public.product_submissions WHERE id=sid),'first approval revision');
 PERFORM fixture.throws(format('UPDATE public.product_submission_approved_labels SET payload_sha256=%L WHERE submission_id=%L AND approval_revision=1',repeat('0',64),sid),'55000','immutable');
 PERFORM fixture.assert(length(h)=64,'approval hash retained');
END $$ $case$);

SELECT fixture.test('reopen is authenticated fenced audited seeded and idempotent', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels
  WHERE submission_id=sid AND approval_revision=1;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.reopen_product_submission_approval(%L,1,%L,''Fix transcription'')',sid,h),'42501','reviewer access required');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.throws(format('SELECT public.reopen_product_submission_approval(%L,1,%L,'' '')',sid,h),'22023','reason required');
 PERFORM fixture.throws(format('SELECT public.reopen_product_submission_approval(%L,2,%L,''Fix transcription'')',sid,h),'55000','approval changed');
 PERFORM fixture.throws(format('SELECT public.reopen_product_submission_approval(%L,1,%L,''Fix transcription'')',sid,repeat('0',64)),'55000','approval changed');
 PERFORM fixture.assert(public.reopen_product_submission_approval(sid,1,h,'Fix transcription'),'reopened');
 PERFORM fixture.assert(public.reopen_product_submission_approval(sid,1,h,'Fix transcription'),'identical retry');
 PERFORM fixture.assert((SELECT review_status='under_review' AND approval_revision=1
  FROM public.product_submissions WHERE id=sid),'correction under review');
 PERFORM fixture.assert((SELECT payload_sha256=h FROM public.product_submission_reviewer_drafts
  WHERE submission_id=sid AND reviewer_id=fixture.user_id(3)),'draft seeded');
 PERFORM fixture.assert((public.load_product_submission_reviewer_draft(sid)->'product_image'->>'id') =
  '10000000-0000-0000-0000-000000000001','approved product image selection retained');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_field_verifications
  WHERE submission_id=sid),'attestations invalidated');
 PERFORM fixture.assert((SELECT count(*)=1 FROM public.product_submission_review_events
  WHERE submission_id=sid AND from_status='approved' AND to_status='under_review'
    AND review_notes='Fix transcription'),'one audit event');
 PERFORM fixture.throws(format('SELECT public.reopen_product_submission_approval(%L,1,%L,''Different reason'')',sid,h),'55000','already reopened');
END $$ $case$);

SELECT fixture.test('correction evidence is protected from historical retention cleanup', $case$
DO $$ DECLARE sid uuid; ordinary uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels
  WHERE submission_id=sid AND approval_revision=1;
 -- Stamp old publication at its first assignment; the preservation trigger
 -- correctly rejects a subsequent attempt to backdate an existing promotion.
 UPDATE public.product_submissions SET promoted_at=now()-interval '91 days',
  promoted_catalog_version='catalog-1', promoted_approval_revision=1,
  resolved_dsld_id='PG_SUB_33333333333333333333333333333333' WHERE id=sid;
 PERFORM fixture.assert((SELECT promoted_at < now()-interval '90 days' FROM public.product_submissions WHERE id=sid),'stored correction fixture is genuinely old');
 ordinary:=fixture.seed(2,'4006381333931','under_review',NULL);
 PERFORM fixture.approve(ordinary);
 UPDATE public.product_submissions SET promoted_at=now()-interval '91 days',
  promoted_catalog_version='catalog-1', promoted_approval_revision=1,
  resolved_dsld_id='PG_SUB_44444444444444444444444444444444' WHERE id=ordinary;
 PERFORM fixture.assert((SELECT promoted_at < now()-interval '90 days' FROM public.product_submissions WHERE id=ordinary),'stored ordinary fixture is genuinely old');
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Correct old transcription');
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.claim_product_submission_cleanup(100) WHERE submission_id=ordinary),'ordinary old publication is selected for cleanup');
 PERFORM fixture.assert(NOT EXISTS(
  SELECT 1 FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid),
  'open correction evidence must not be purged');
 PERFORM fixture.prepare_review(sid);
 PERFORM fixture.approve(sid);
 PERFORM fixture.assert(NOT EXISTS(
  SELECT 1 FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid),
  'approved correction awaiting release must not be purged');
END $$ $case$);

SELECT fixture.test('new submitter evidence records immutable uploader provenance', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','submitted',NULL);
 PERFORM fixture.assert((SELECT uploader_id=user_id AND uploader_role='submitter'
  FROM public.product_submission_photos WHERE submission_id=sid),
  'canonical photo insert must default submitter provenance');
 PERFORM fixture.assert((SELECT manifest_schema_version='evidence_manifest_v2'
  FROM public.product_submission_evidence_revisions
  WHERE submission_id=sid AND revision=1),'new evidence uses manifest v2');
 PERFORM fixture.assert((public.product_submission_evidence_records(sid,1)->0->>'uploader_id')
  = fixture.user_id(1)::text,'v2 manifest binds uploader identity');
END $$ $case$);

SELECT fixture.test('reapproval appends revision two and preserves revision one', $case$
DO $$ DECLARE sid uuid; h text; payload jsonb:='{"fixture":true,"corrected":true}'::jsonb; canonical text; BEGIN
 canonical:=payload::text;
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Correct amount');
 PERFORM fixture.prepare_review(sid,payload);
 PERFORM public.review_product_submission(sid,'approved',p_approved_schema_version=>'manual_label_v1',
  p_approved_payload=>payload,p_approved_payload_canonical=>canonical,
  p_payload_sha256=>encode(extensions.digest(canonical,'sha256'),'hex'),
  p_product_image_photo_id=>'10000000-0000-0000-0000-000000000001',
  p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>fixture.manifest_hash(sid));
 PERFORM fixture.assert((SELECT approval_revision=2 FROM public.product_submissions WHERE id=sid),'revision advanced');
 PERFORM fixture.assert((SELECT count(*)=2 FROM public.product_submission_approved_labels WHERE submission_id=sid),'two immutable approvals');
 PERFORM fixture.assert((SELECT payload_sha256=h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1),'revision one unchanged');
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.export_approved_product_submissions() WHERE submission_id=sid AND approval_revision=2),'only revision two exports');
END $$ $case$);

SELECT fixture.test('promotion is exact and contribution points remain one time', $case$
DO $$ DECLARE sid uuid; h1 text; h2 text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h1 FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM fixture.assert(public.mark_product_submission_promoted(sid,1,h1,'catalog-1','PG_SUB_11111111111111111111111111111111'),'first promotion');
 PERFORM public.reopen_product_submission_approval(sid,1,h1,'Correct transcription');
 PERFORM fixture.assert((SELECT count(*)=1 FROM public.get_approved_product_submission_image(sid,1,h1)),
  'last promoted image remains retrievable while correction is open');
 PERFORM fixture.assert((SELECT promoted_approval_revision=1 AND promoted_catalog_version='catalog-1'
  FROM public.product_submissions WHERE id=sid),'promoted version remains live');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.export_approved_product_submissions() WHERE submission_id=sid),'open correction is not exportable');
 PERFORM fixture.prepare_review(sid);
 PERFORM fixture.approve(sid);
 PERFORM fixture.assert((SELECT resolved_dsld_id='PG_SUB_11111111111111111111111111111111'
  FROM public.product_submissions WHERE id=sid),'released catalog link retained through reapproval');
 SELECT payload_sha256 INTO h2 FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=2;
 PERFORM fixture.throws(format('SELECT public.mark_product_submission_promoted(%L,1,%L,''catalog-2'',''PG_SUB_11111111111111111111111111111111'')',sid,h1),'55000','approval changed');
 PERFORM fixture.throws(format('SELECT public.mark_product_submission_promoted(%L,2,%L,''catalog-2'',''PG_SUB_11111111111111111111111111111111'')',sid,repeat('0',64)),'55000','approval changed');
 PERFORM fixture.assert(public.mark_product_submission_promoted(sid,2,h2,'catalog-2','PG_SUB_11111111111111111111111111111111'),'correction promoted');
 PERFORM fixture.assert((SELECT promoted_approval_revision=2 FROM public.product_submissions WHERE id=sid),'promoted revision advanced');
 PERFORM fixture.assert((SELECT count(*)=1 FROM public.product_contribution_ledger WHERE submission_id=sid),'points awarded once');
END $$ $case$);

SELECT fixture.test('catalog activation atomically validates and promotes exact approvals', $case$
DO $$ DECLARE sid uuid; h text; activated uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels
  WHERE submission_id=sid AND approval_revision=1;
 activated:=public.rotate_manifest_with_submission_approvals(
  'correction-atomic-1','pipeline','score','schema',1,'sha256:atomic',now(),'1.0.0',
  jsonb_build_array(jsonb_build_object(
    'submission_id',sid,'approval_revision',1,'payload_sha256',h,
    'resolved_dsld_id','PG_SUB_44444444444444444444444444444444')));
 PERFORM fixture.assert(activated IS NOT NULL AND (SELECT is_current
  FROM public.export_manifest WHERE id=activated),'manifest activated');
 PERFORM fixture.assert((SELECT promoted_approval_revision=1
  FROM public.product_submissions WHERE id=sid),'same transaction promoted approval');
 PERFORM fixture.assert((SELECT count(*)=1 FROM public.product_contribution_ledger
  WHERE submission_id=sid),'activation awards points once');
END $$ $case$);

SELECT fixture.test('reopened approval aborts activation before manifest rotation', $case$
DO $$ DECLARE sid uuid; h text; before_id uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels
  WHERE submission_id=sid AND approval_revision=1;
 UPDATE public.export_manifest SET is_current=false WHERE is_current;
 INSERT INTO public.export_manifest(db_version,pipeline_version,scoring_version,
  schema_version,product_count,checksum,min_app_version,generated_at,is_current)
 VALUES ('correction-before','pipeline','score','schema',1,'sha256:before','1.0.0',now(),true);
 SELECT id INTO before_id FROM public.export_manifest WHERE is_current;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Fix before release');
 PERFORM fixture.throws(format(
  'SELECT public.rotate_manifest_with_submission_approvals(''correction-stale-1'',''pipeline'',''score'',''schema'',1,''sha256:stale'',now(),''1.0.0'',%L::jsonb)',
  jsonb_build_array(jsonb_build_object('submission_id',sid,'approval_revision',1,
    'payload_sha256',h,'resolved_dsld_id','PG_SUB_55555555555555555555555555555555'))::text),
  '55000','approval changed');
 PERFORM fixture.assert((SELECT id=before_id FROM public.export_manifest WHERE is_current),
  'failed activation leaves previous manifest current');
 PERFORM fixture.assert((SELECT promoted_approval_revision=0
  FROM public.product_submissions WHERE id=sid),'failed activation promotes nothing');
END $$ $case$);

SELECT fixture.test('purged evidence seeds correction but blocks reapproval', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 UPDATE public.product_submissions SET evidence_purged_at=now() WHERE id=sid;
 DELETE FROM public.product_submission_photos WHERE submission_id=sid;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Replace missing evidence');
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.product_submission_reviewer_drafts WHERE submission_id=sid),'old transcription retained');
 PERFORM fixture.throws(format('SELECT fixture.approve(%L)',sid),'55000','evidence');
END $$ $case$);

SELECT fixture.test('reviewer replacement evidence uses the existing revision owner', $case$
DO $$ DECLARE sid uuid; h text; result jsonb; rev integer; manifest text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Reviewer replacement photos');
 result:=public.create_product_submission_reviewer_evidence_revision(sid,1,h,
  '20000000-0000-4000-8000-000000000001',fixture.new_photo(9));
 rev:=(result->>'evidence_revision')::integer;
 PERFORM fixture.assert(rev=2 AND jsonb_array_length(result->'uploads')=1,'reviewer revision opened');
 PERFORM fixture.assert((public.create_product_submission_reviewer_evidence_revision(
  sid,1,h,'20000000-0000-4000-8000-000000000001',fixture.new_photo(9))->>'evidence_revision')::integer=rev,
  'lost response retry is idempotent');
 PERFORM fixture.throws(format(
  'SELECT public.create_product_submission_reviewer_evidence_revision(%L,1,%L,%L,jsonb_set(fixture.new_photo(9),''{0,byte_size}'',''999''::jsonb))',
  sid,h,'20000000-0000-4000-8000-000000000001'),'23505','replay conflict');
 PERFORM fixture.throws(format(
  'SELECT public.create_product_submission_reviewer_evidence_revision(%L,1,%L,%L,fixture.new_photo(10))',
  sid,h,'20000000-0000-4000-8000-000000000002'),'55000','already pending');
 PERFORM fixture.assert((SELECT evidence_revision=2 FROM public.product_submissions
  WHERE id=sid),'competing key cannot strand the pending revision');
 INSERT INTO storage.objects(bucket_id,name,owner_id,metadata,user_metadata)
 SELECT 'product-submission-photos',object_path,fixture.user_id(3)::text,
  jsonb_build_object('size',byte_size,'mimetype',content_type),jsonb_build_object('content_sha256',content_sha256)
 FROM public.product_submission_photos WHERE submission_id=sid AND revision=rev;
 manifest:=public.product_submission_manifest_sha256(public.product_submission_evidence_records(sid,rev));
 PERFORM fixture.assert(public.finalize_product_submission_reviewer_evidence_revision(sid,rev,manifest),'reviewer evidence finalized');
 PERFORM fixture.assert((SELECT bool_and(uploader_id=fixture.user_id(3) AND uploader_role='reviewer')
  FROM public.product_submission_photos WHERE submission_id=sid AND revision=rev),'reviewer provenance retained');
 PERFORM fixture.assert((SELECT upload_state='ready' AND evidence_purged_at IS NULL FROM public.product_submissions WHERE id=sid),'replacement evidence is current');
END $$ $case$);

SELECT fixture.test('catalog versions are globally immutable after first use', $case$
DO $$ BEGIN
 UPDATE public.export_manifest SET is_current=false WHERE is_current;
 INSERT INTO public.export_manifest(db_version,pipeline_version,scoring_version,
  schema_version,product_count,checksum,min_app_version,generated_at,is_current)
 VALUES ('historical-version','pipeline','score','schema',1,'sha256:old','1.0.0',now(),false);
 PERFORM fixture.throws(
  'SELECT public.rotate_manifest_with_submission_approvals(''historical-version'',''pipeline'',''score'',''schema'',1,''sha256:new'',now(),''1.0.0'',''[]''::jsonb)',
  '55000','already used');
 PERFORM fixture.assert((SELECT count(*)=1 FROM public.export_manifest
  WHERE db_version='historical-version'),'historical version remains singular');
END $$ $case$);


SELECT fixture.test('approved account cascade succeeds but direct history and parent deletes fail', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 PERFORM fixture.throws(format('DELETE FROM public.product_submission_approved_labels WHERE submission_id=%L',sid),'55000','immutable');
 PERFORM fixture.throws(format('DELETE FROM public.product_submissions WHERE id=%L',sid),'55000','account deletion');
 DELETE FROM auth.users WHERE id=fixture.user_id(1);
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submissions WHERE id=sid),'account cascade removed submission');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_approved_labels WHERE submission_id=sid),'account cascade removed private approval');
END $$ $case$);

SELECT fixture.test('published correction supports requested submitter retakes', $case$
DO $$ DECLARE sid uuid; h text; rev integer; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.mark_product_submission_promoted(sid,1,h,'catalog-1','PG_SUB_11111111111111111111111111111111');
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Need clearer source photo');
 PERFORM public.request_product_submission_evidence(sid,'photo_quality',ARRAY['supplement_facts'],1,fixture.manifest_hash(sid));
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 rev:=public.open_product_submission_evidence_revision(sid,1,gen_random_uuid(),ARRAY['10000000-0000-0000-0000-000000000001'::uuid],'fixture.consent.v1');
 PERFORM fixture.assert(rev=2,'submitter retake opened');
 PERFORM fixture.assert((SELECT promoted_approval_revision=1 AND promoted_catalog_version='catalog-1' FROM public.product_submissions WHERE id=sid),'prior publication retained during retake');
 PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo(2));
 PERFORM fixture.upload_revision(sid,2);
 PERFORM fixture.assert(public.finalize_product_submission(sid,2),'submitter retake finalizes');
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=2;
 PERFORM public.mark_product_submission_promoted(sid,2,h,'catalog-2','PG_SUB_11111111111111111111111111111111');
 PERFORM fixture.assert((SELECT count(*)=1 AND sum(points)=10 FROM public.product_contribution_ledger WHERE submission_id=sid),'correction awards no duplicate points');
 PERFORM fixture.assert((SELECT promoted_approval_revision=2 AND promoted_catalog_version='catalog-2' FROM public.product_submissions WHERE id=sid),'prior publication retained');
END $$ $case$);

SELECT fixture.test('published correction awaiting release blocks competing approval', $case$
DO $$ DECLARE sid uuid; other uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.mark_product_submission_promoted(sid,1,h,'catalog-1','PG_SUB_11111111111111111111111111111111');
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Fix original label');
 PERFORM fixture.approve(sid);
 other:=fixture.seed(2,'0012345678905','under_review',NULL);
 PERFORM fixture.throws(format('SELECT fixture.approve(%L)',other),'23505','awaits promotion');
END $$ $case$);

SELECT fixture.test('expired reviewer upload restarts beyond abandoned history', $case$
DO $$ DECLARE sid uuid; h text; result jsonb; claim jsonb; rev integer; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'New evidence required');
 -- A previous submitter request must not mislabel reviewer-owned uploads.
 UPDATE public.product_submissions SET evidence_requested_at=now(), evidence_requested_revision=1,
  evidence_requested_by=fixture.user_id(3), evidence_request_reason='photo_quality',
  evidence_request_panels=ARRAY['supplement_facts']::public.product_submission_evidence_category[] WHERE id=sid;
 result:=public.create_product_submission_reviewer_evidence_revision(sid,1,h,
  '20000000-0000-4000-8000-000000000001',fixture.new_photo(9));
 PERFORM fixture.assert((SELECT evidence_requested_at IS NULL AND evidence_requested_revision IS NULL
   AND evidence_request_panels IS NULL AND evidence_requested_by IS NULL FROM public.product_submissions WHERE id=sid),'reviewer upload clears stale retake request');
 UPDATE public.product_submissions SET evidence_revision_opened_at=now()-interval '25 hours' WHERE id=sid;
 SELECT jsonb_build_object(sid::text,jsonb_build_object('claim_token',claim_token,'evidence_revision',evidence_revision)) INTO claim
 FROM public.claim_product_submission_cleanup(100) WHERE submission_id=sid;
 PERFORM fixture.throws(format('SELECT public.finalize_product_submission_reviewer_evidence_revision(%L,2,%L)',sid,repeat('a',64)),'55000','current correction evidence');
 PERFORM public.complete_product_submission_cleanup(ARRAY[sid],claim);
 PERFORM fixture.assert((SELECT abandoned_at IS NOT NULL FROM public.product_submission_evidence_revisions WHERE submission_id=sid AND revision=2),'expired revision abandoned');
 PERFORM fixture.throws(format('SELECT public.create_product_submission_reviewer_evidence_revision(%L,1,%L,%L,fixture.new_photo(9))',sid,h,'20000000-0000-4000-8000-000000000001'),'55000','abandoned');
 result:=public.create_product_submission_reviewer_evidence_revision(sid,1,h,
  '20000000-0000-4000-8000-000000000002',fixture.new_photo(10));
 rev:=(result->>'evidence_revision')::integer;
 PERFORM fixture.assert(rev=3,'restart allocates past abandoned revision');
END $$ $case$);

SELECT fixture.test('correction retake entry points reject OAuth clients', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1;
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Need source correction');
 PERFORM set_config('request.jwt.claims','{"client_id":"untrusted-client"}',true);
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',ARRAY[''supplement_facts''],1,%L)',sid,fixture.manifest_hash(sid)),'42501','AI assistant');
 PERFORM fixture.throws(format('SELECT public.open_product_submission_evidence_revision(%L,1,gen_random_uuid(),''{}''::uuid[],''fixture.consent.v1'')',sid),'42501','AI assistant');
 PERFORM fixture.throws(format('SELECT public.create_product_submission_reviewer_evidence_revision(%L,1,%L,gen_random_uuid(),fixture.new_photo(9))',sid,h),'42501','AI assistant');
END $$ $case$);

-- The review function's queue list reads the current approval hash with the
-- service role, so reopen and reviewer evidence can echo what was approved.
-- Without this grant every approved submission broke the whole list.
SELECT fixture.test('service role reads approval identity but not approved payloads', $case$
DO $$ BEGIN
 PERFORM fixture.assert(has_column_privilege('service_role','public.product_submission_approved_labels','payload_sha256','SELECT'),'service role reads approval hash');
 PERFORM fixture.assert(has_column_privilege('service_role','public.product_submission_approved_labels','submission_id','SELECT'),'service role filters by submission');
 PERFORM fixture.assert(has_column_privilege('service_role','public.product_submission_approved_labels','approval_revision','SELECT'),'service role filters by revision');
 PERFORM fixture.assert(NOT has_column_privilege('service_role','public.product_submission_approved_labels','approved_payload','SELECT'),'service role cannot read approved payloads');
 PERFORM fixture.assert(NOT has_table_privilege('service_role','public.product_submission_approved_labels','INSERT,UPDATE,DELETE'),'service role cannot write approvals');
END $$ $case$);

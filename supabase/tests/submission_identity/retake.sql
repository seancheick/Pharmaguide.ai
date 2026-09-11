-- Reviewer-requested retakes: the request names panels, reaches the owner
-- once per revision, and the owner can see which photos it may keep.

SELECT fixture.test('a reviewer request names panels and tells the owner once', $case$
DO $$ DECLARE sid uuid; pushes integer; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 pushes:=(SELECT count(*) FROM public.product_submission_push_deliveries WHERE submission_id=sid);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.assert(public.request_product_submission_evidence(
   sid,'photo_quality',ARRAY['supplement_facts'],1,fixture.manifest_hash(sid)),'request accepted');
 PERFORM fixture.assert((SELECT evidence_request_panels='{supplement_facts}'
     AND evidence_request_reason='photo_quality' AND evidence_requested_revision=1
   FROM public.product_submissions WHERE id=sid),'panels and reason recorded against the revision');
 PERFORM fixture.assert((SELECT count(*) FROM public.product_submission_push_deliveries
   WHERE submission_id=sid AND user_id=fixture.user_id(1) AND sent_at IS NULL)=pushes+1,'the owner is told');
 -- Correcting the request on the same revision updates it without a second nudge.
 PERFORM public.request_product_submission_evidence(
   sid,'label_unreadable',ARRAY['supplement_facts','barcode'],1,fixture.manifest_hash(sid));
 PERFORM fixture.assert((SELECT evidence_request_panels='{supplement_facts,barcode}'
     AND evidence_request_reason='label_unreadable'
   FROM public.product_submissions WHERE id=sid),'a corrected request replaces the panels');
 PERFORM fixture.assert((SELECT count(*) FROM public.product_submission_push_deliveries
   WHERE submission_id=sid)=pushes+1,'one notification per revision');
END $$ $case$);

SELECT fixture.test('an evidence request needs a reviewer, a retake reason and a known panel', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',ARRAY[''supplement_facts''],1,%L)',sid,fixture.manifest_hash(sid)),'42501','reviewer access required');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''not_a_supplement'',ARRAY[''supplement_facts''],1,%L)',sid,fixture.manifest_hash(sid)),'22023','evidence request reason required');
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',ARRAY[]::text[],1,%L)',sid,fixture.manifest_hash(sid)),'22023','evidence request panels required');
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',NULL,1,%L)',sid,fixture.manifest_hash(sid)),'22023','evidence request panels required');
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',ARRAY[''back_label''],1,%L)',sid,fixture.manifest_hash(sid)),'22023','evidence request panels required');
 PERFORM fixture.throws(format('SELECT public.request_product_submission_evidence(%L,''photo_quality'',ARRAY[''barcode'',''barcode''],1,%L)',sid,fixture.manifest_hash(sid)),'22023','evidence request panels required');
 PERFORM fixture.assert((SELECT evidence_requested_at IS NULL FROM public.product_submissions WHERE id=sid),'a refused request records nothing');
END $$ $case$);

SELECT fixture.test('owners read which photos their current revision holds and nothing else', $case$
DO $$ DECLARE sid uuid; other uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 other:=fixture.seed(2,'012345678905','under_review',NULL);
 SET LOCAL ROLE authenticated;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,true);
 PERFORM fixture.assert((SELECT photo_ids FROM public.product_submission_evidence_revisions
   WHERE submission_id=sid AND revision=1)='{10000000-0000-0000-0000-000000000001}','the owner sees the membership');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_evidence_revisions
   WHERE submission_id=other),'another owner''s revisions stay hidden');
 PERFORM fixture.throws(format('SELECT request_key FROM public.product_submission_evidence_revisions WHERE submission_id=%L',sid),'42501','permission denied');
 PERFORM fixture.throws(format('UPDATE public.product_submission_evidence_revisions SET photo_ids=''{}'' WHERE submission_id=%L',sid),'42501','permission denied');
 RESET ROLE;
END $$ $case$);

SELECT fixture.test('a requested retake keeps the review and notifies again only for the next request', $case$
DO $$ DECLARE sid uuid; key uuid:=gen_random_uuid(); BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.request_product_submission_evidence(sid,'photo_quality',ARRAY['supplement_facts'],1,fixture.manifest_hash(sid));
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.assert(fixture.retake(sid,key)=2,'the owner opens the next revision');
 PERFORM public.add_product_submission_evidence(sid,2,fixture.new_photo());
 PERFORM fixture.upload_revision(sid,2);
 PERFORM fixture.assert(public.finalize_product_submission(sid,2),'the retake finalizes');
 PERFORM fixture.assert((SELECT review_status='under_review' AND reviewed_by=fixture.user_id(3)
     AND evidence_requested_revision=1 AND evidence_revision=2 AND upload_state='ready'
   FROM public.product_submissions WHERE id=sid),'the reviewer keeps the review; the request is answered');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM public.request_product_submission_evidence(sid,'missing_panel',ARRAY['barcode'],2,fixture.manifest_hash(sid));
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.product_submission_push_deliveries
   WHERE submission_id=sid AND sent_at IS NULL),'a request on the new revision notifies again');
END $$ $case$);

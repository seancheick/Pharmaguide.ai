-- Contribution points: one append-only ledger, written only by promotion.

SELECT fixture.test('promotion awards ten points once, to the submitter', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 PERFORM public.mark_product_submission_promoted(sid,'2026.09.11','12345');
 -- The importer re-runs after every release; a replay must not pay again.
 PERFORM public.mark_product_submission_promoted(sid,'2026.09.11','12345');
 PERFORM fixture.assert((SELECT count(*) FROM public.product_contribution_ledger
   WHERE submission_id=sid)=1,'one award per submission');
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.product_contribution_ledger
   WHERE submission_id=sid AND user_id=fixture.user_id(1)
     AND event='earned_catalog_added' AND points=10
     AND catalog_version='2026.09.11'),'award names the submitter, points and release');
END $$ $case$);

SELECT fixture.test('a refused promotion awards nothing', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 UPDATE public.product_submission_approved_labels SET evidence_revision=999 WHERE submission_id=sid;
 PERFORM fixture.throws(format('SELECT public.mark_product_submission_promoted(%L,''2026.09.11'',''12345'')',sid),'55000','approval evidence changed');
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_contribution_ledger
   WHERE submission_id=sid),'no points without a promotion');
END $$ $case$);

SELECT fixture.test('an unpromoted approval earns nothing yet', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 PERFORM public.award_product_contribution_points_internal(sid);
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_contribution_ledger
   WHERE submission_id=sid),'approval alone is not catalog promotion');
END $$ $case$);

SELECT fixture.test('owners read only their own points and write none', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 PERFORM fixture.approve(sid);
 PERFORM public.mark_product_submission_promoted(sid,'2026.09.11','12345');
 SET LOCAL ROLE authenticated;
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,true);
 PERFORM fixture.assert((SELECT coalesce(sum(points),0) FROM public.product_contribution_ledger)=10,
   'the submitter sees their points');
 PERFORM fixture.throws(format('INSERT INTO public.product_contribution_ledger(user_id,submission_id,event,points,catalog_version) VALUES (%L,%L,''earned_catalog_added'',10,''x'')',fixture.user_id(1),sid),'42501','permission denied');
 PERFORM fixture.throws('UPDATE public.product_contribution_ledger SET points=1000','42501','permission denied');
 PERFORM fixture.throws('DELETE FROM public.product_contribution_ledger','42501','permission denied');
 PERFORM fixture.throws(format('SELECT public.award_product_contribution_points_internal(%L)',sid),'42501','permission denied');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(2)::text,true);
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_contribution_ledger),
   'another account sees none of them');
 RESET ROLE;
END $$ $case$);

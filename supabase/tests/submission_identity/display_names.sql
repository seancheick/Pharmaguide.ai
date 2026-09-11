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

SELECT fixture.test('reviewer extraction reader filters and bounds private drafts', $case$
DO $$ DECLARE sid uuid; other uuid; rows jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review');
 other:=fixture.seed(2,'012345678905','under_review');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 FOR i IN 1..6 LOOP PERFORM fixture.record_draft(sid); END LOOP;
 PERFORM fixture.record_draft(other);
 rows:=public.get_product_submission_extractions(sid,1);
 PERFORM fixture.assert(jsonb_array_length(rows)=5,'latest five only');
 PERFORM fixture.assert((rows->0->>'version')::integer=6 AND (rows->4->>'version')::integer=2,'newest first');
 PERFORM fixture.assert(public.get_product_submission_extractions(sid,2)='[]'::jsonb,'no cross-revision draft');
 PERFORM fixture.assert(jsonb_array_length(public.get_product_submission_extractions(other,1))=1,'no cross-submission draft');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws(format('SELECT public.get_product_submission_extractions(%L,1)',sid),'42501','reviewer access');
 PERFORM fixture.assert(NOT has_function_privilege('service_role','public.get_product_submission_extractions(uuid,integer)','EXECUTE'),'service role cannot read');
 PERFORM fixture.assert(NOT has_function_privilege('anon','public.get_product_submission_extractions(uuid,integer)','EXECUTE'),'anon cannot read');
END $$ $case$);

SELECT fixture.test('row grounding is allowlisted and optional', $case$
DO $$ DECLARE sid uuid; rows jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review');
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(3)::text,false);
 PERFORM fixture.record_draft(sid);
 rows:=public.get_product_submission_extractions(sid,1);
 PERFORM fixture.assert(rows->0->'grounding'='null'::jsonb,'legacy report remains absent');
 UPDATE public.product_submission_extractions SET usage = '{"private_debug":"never expose","grounding":{"schema_version":"grounding_report_v1","status":"ok","rows":[{"row_index":0,"status":"supported"}],"region_coordinate_space":"orientation_corrected_original","private_internal":"never expose"}}'::jsonb WHERE submission_id=sid;
 rows:=public.get_product_submission_extractions(sid,1);
 PERFORM fixture.assert(rows->0->'grounding'->'rows'->0->>'status'='supported','row report reaches reviewer');
 PERFORM fixture.assert(NOT (rows->0 ? 'usage'),'raw usage is private');
 PERFORM fixture.assert(NOT (rows->0->'grounding' ? 'private_internal'),'only allowed grounding fields');
END $$ $case$);

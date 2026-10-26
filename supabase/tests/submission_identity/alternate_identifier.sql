SELECT fixture.test('alternate identity validates exact text without numeric coercion', $case$
DO $$ DECLARE identifier jsonb := '{"observed_code":"X002FLZ3X7","code_type":"other","issuer":null,"brandName":"Example","fullName":"Label","listing_url":null,"no_code":false}'; BEGIN
  PERFORM fixture.assert(public.validate_product_submission_identifier(identifier) = identifier, 'exact alternate code retained');
  PERFORM fixture.throws(format('SELECT public.validate_product_submission_identifier(%L::jsonb)', identifier || '{"no_code":true}'), '22023', 'identifier');
  PERFORM fixture.throws(format('SELECT public.validate_product_submission_identifier(%L::jsonb)', identifier || jsonb_build_object('observed_code', E'X\n123')), '22023', 'identifier');
  PERFORM fixture.assert(public.validate_product_submission_identifier(identifier || '{"observed_code":null,"code_type":"none","no_code":true}') ->> 'no_code' = 'true', 'explicit absent code accepted');
END $$ $case$);

CREATE FUNCTION fixture.alternate_identifier(p_code text DEFAULT 'X002FLZ3X7',p_brand text DEFAULT 'Example',p_name text DEFAULT 'Label') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
 SELECT jsonb_build_object('observed_code',p_code,'code_type',CASE WHEN p_code IS NULL THEN 'none' ELSE 'other' END,'issuer',NULL,'brandName',p_brand,'fullName',p_name,'listing_url',NULL,'no_code',p_code IS NULL)
$$;
CREATE FUNCTION fixture.alternate_review(sid uuid,p_brand text DEFAULT 'Example',p_name text DEFAULT 'Label',p_candidates text[] DEFAULT '{}') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM fixture.prepare_review(sid,jsonb_build_object('brandName',p_brand,'fullName',p_name));
 PERFORM public.record_product_submission_match_check(sid,'new_product_verified',NULL,now(),NULL,p_candidates,NULL,1,fixture.manifest_hash(sid),'label_review',jsonb_build_object('code_type','other','issuer',NULL,'verified_gtin',NULL,'package','60 capsules','reason','Compared full label and all current candidates'),true,'fixture-complete-index');
END $$;
CREATE FUNCTION fixture.approve_alternate(sid uuid) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE d public.product_submission_reviewer_drafts%ROWTYPE; envelope jsonb; wire text;
BEGIN
 SELECT * INTO d FROM public.product_submission_reviewer_drafts WHERE submission_id=sid AND reviewer_id=fixture.user_id(3);
 envelope:=public.prepare_product_submission_approval_payload(sid,d.payload); wire:=envelope::text;
 RETURN public.review_product_submission(sid,'approved',p_approved_schema_version=>'manual_label_v2',p_approved_payload=>envelope,p_approved_payload_canonical=>wire,p_payload_sha256=>encode(extensions.digest(wire,'sha256'),'hex'),p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>fixture.manifest_hash(sid),p_product_image_photo_id=>'10000000-0000-0000-0000-000000000001');
END $$;
SELECT fixture.test('alternate create exact replay and rejected resubmission preserve private code', $case$
DO $$ DECLARE sid uuid:=gen_random_uuid(); nextid uuid:=gen_random_uuid(); ident jsonb:=fixture.alternate_identifier(); BEGIN
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM public.create_product_submission(sid,'missing_product',p_photos=>fixture.photos(),p_consent_version=>'pharmaguide.submission_consent.2026-10-26.v2',p_identifier=>ident);
 PERFORM public.create_product_submission(sid,'missing_product',p_photos=>fixture.photos(),p_consent_version=>'pharmaguide.submission_consent.2026-10-26.v2',p_identifier=>ident);
 PERFORM fixture.assert((SELECT normalized_upc IS NULL AND identifier=ident FROM public.product_submissions WHERE id=sid),'stored exact code without numeric fallback');
 PERFORM fixture.assert((SELECT identifier=ident FROM public.product_submission_evidence_revisions WHERE submission_id=sid),'revision binds observed identity');
 PERFORM fixture.throws(format('SELECT public.create_product_submission(%L,''missing_product'',p_photos=>fixture.photos(),p_consent_version=>''pharmaguide.submission_consent.2026-10-26.v2'',p_identifier=>%L::jsonb)',sid,fixture.alternate_identifier('Changed')),'23505','replay conflict');
 UPDATE public.product_submissions SET review_status='rejected',reviewed_at=now(),reviewed_by=fixture.user_id(3),resolution_code='photo_quality' WHERE id=sid;
 PERFORM public.create_product_submission(nextid,'missing_product',p_photos=>fixture.photos(),p_resubmission_of=>sid,p_consent_version=>'pharmaguide.submission_consent.2026-10-26.v2',p_identifier=>ident);
 PERFORM fixture.assert((SELECT resubmission_of=sid AND identifier=ident FROM public.product_submissions WHERE id=nextid),'explicit rejection retry keeps new UUID and lineage');
 PERFORM fixture.throws('SELECT public.create_product_submission(gen_random_uuid(),''missing_product'',''X036000291452'',p_photos=>fixture.photos(),p_consent_version=>''pharmaguide.submission_consent.2026-10-26.v2'')','22023','UPC/EAN');
END $$ $case$);
SELECT fixture.test('no-code waives only barcode and identity is manifest-bound', $case$
DO $$ DECLARE sid uuid:=gen_random_uuid(); photos jsonb:=fixture.photos(); ident jsonb:=fixture.alternate_identifier(NULL); h text; BEGIN
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 photos:=jsonb_set(photos,'{0,categories}','["front_identity","supplement_facts","ingredient_disclosure"]');
 PERFORM public.create_product_submission(sid,'missing_product',p_photos=>photos,p_consent_version=>'pharmaguide.submission_consent.2026-10-26.v2',p_identifier=>ident);
 h:=public.product_submission_manifest_sha256(public.product_submission_evidence_records(sid,1));
 PERFORM fixture.assert(public.product_submission_has_required_evidence(sid,fixture.user_id(1)),'no-code covers missing barcode');
 UPDATE public.product_submission_evidence_revisions SET identifier=fixture.alternate_identifier() WHERE submission_id=sid;
 PERFORM fixture.assert(NOT public.product_submission_has_required_evidence(sid,fixture.user_id(1)),'printed code still requires photo');
 PERFORM fixture.assert(h<>public.product_submission_manifest_sha256(public.product_submission_evidence_records(sid,1)),'declaration changes evidence digest');
 DELETE FROM public.product_submissions WHERE id=sid;
 photos:=jsonb_set(photos,'{0,categories}','["front_identity","supplement_facts"]');
 PERFORM fixture.throws(format('SELECT public.create_product_submission(gen_random_uuid(),''missing_product'',p_photos=>%L::jsonb,p_consent_version=>''pharmaguide.submission_consent.2026-10-26.v2'',p_identifier=>%L::jsonb)',photos,ident),'22023','required evidence');
END $$ $case$);
SELECT fixture.test('label review freezes full envelope and export never borrows parent UPC', $case$
DO $$ DECLARE sid uuid; h text; envelope jsonb; BEGIN
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 UPDATE public.product_submissions SET identifier=fixture.alternate_identifier(),normalized_upc=NULL WHERE id=sid;
 UPDATE public.product_submission_evidence_revisions SET identifier=fixture.alternate_identifier() WHERE submission_id=sid;
 PERFORM fixture.alternate_review(sid);
 PERFORM fixture.assert(fixture.approve_alternate(sid),'approved reviewed label');
 SELECT approved_payload,payload_sha256 INTO envelope,h FROM public.product_submission_approved_labels WHERE submission_id=sid;
 PERFORM fixture.assert(envelope#>>'{identity,observed,observed_code}'='X002FLZ3X7','private observed code frozen');
 PERFORM fixture.assert(envelope#>>'{identity,decision,verified_gtin}' IS NULL AND envelope#>>'{label,brandName}'='Example','label and nullable reviewed GTIN frozen');
 UPDATE public.product_submissions SET normalized_upc='012345678905' WHERE id=sid;
 PERFORM fixture.assert((SELECT normalized_upc IS NULL FROM public.export_approved_product_submissions() WHERE submission_id=sid),'frozen null cannot fall back to mutable parent');
 PERFORM fixture.assert((SELECT encode(extensions.digest(approved_payload_canonical,'sha256'),'hex')=h FROM public.product_submission_approved_labels WHERE submission_id=sid),'single hash commits complete envelope');
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Correct label text');
 PERFORM fixture.assert((SELECT payload->>'brandName'='Example' AND NOT payload?'identity' FROM public.product_submission_reviewer_drafts WHERE submission_id=sid),'reopen seeds only label draft');
END $$ $case$);

CREATE FUNCTION fixture.seed_alternate(p_user integer,p_brand text DEFAULT 'Example',p_name text DEFAULT 'Label') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid;
BEGIN
 sid:=fixture.seed(p_user,'012345678905','under_review',NULL);
 UPDATE public.product_submissions SET normalized_upc=NULL,identifier=fixture.alternate_identifier('X002FLZ3X7',p_brand,p_name) WHERE id=sid;
 UPDATE public.product_submission_evidence_revisions SET identifier=fixture.alternate_identifier('X002FLZ3X7',p_brand,p_name) WHERE submission_id=sid;
 PERFORM fixture.alternate_review(sid,p_brand,p_name);
 RETURN sid;
END $$;
SELECT fixture.test('same code different products stays distinct while reviewed bucket conflicts fail closed', $case$
DO $$ DECLARE a uuid; b uuid; c uuid; BEGIN
 a:=fixture.seed_alternate(1,'Brand A','Formula A');
 PERFORM fixture.approve_alternate(a);
 b:=fixture.seed_alternate(2,'Brand B','Formula B');
 PERFORM fixture.approve_alternate(b);
 PERFORM fixture.assert(a<>b AND (SELECT count(*)=2 FROM public.product_submission_approved_labels WHERE submission_id IN(a,b)),'code is not a unique identity key');
 c:=fixture.seed(4,'012345678905','under_review',NULL);
 UPDATE public.product_submissions SET normalized_upc=NULL,identifier=fixture.alternate_identifier('Different','Brand A','Formula A') WHERE id=c;
 UPDATE public.product_submission_evidence_revisions SET identifier=fixture.alternate_identifier('Different','Brand A','Formula A') WHERE submission_id=c;
 PERFORM fixture.prepare_review(c,'{"brandName":"Brand A","fullName":"Formula A"}');
 PERFORM fixture.throws(format('SELECT public.record_product_submission_match_check(%L,''new_product_verified'',NULL,now(),NULL,''{}'',NULL,1,%L,''label_review'',%L::jsonb,true,''index'')',c,fixture.manifest_hash(c),'{"code_type":"other","issuer":null,"verified_gtin":null,"package":"60 capsules","reason":"Read all labels"}'),'55000','conflict candidates');
END $$ $case$);
SELECT fixture.test('approval first refuses conflicting catalog activation even empty approval list', $case$
DO $$ DECLARE sid uuid; h text; BEGIN
 sid:=fixture.seed_alternate(1);
 PERFORM fixture.approve_alternate(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid;
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('conflict-catalog','999','Label','Example');
 PERFORM fixture.throws('SELECT public.rotate_manifest_with_submission_approvals(''conflict-catalog'',''p'',''s'',''1'',1,''hash'',now(),''1.0.0'',''[]'')','23505','activation conflicts');
 PERFORM fixture.assert((SELECT payload_sha256=h FROM public.product_submission_approved_labels WHERE submission_id=sid),'immutable approval unchanged');
END $$ $case$);
SELECT fixture.test('catalog first rejects stale receipt and active generation mutation is fenced', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed_alternate(1);
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('first-catalog','999','Label','Example');
 PERFORM public.rotate_manifest_with_submission_approvals('first-catalog','p','s','1',1,'hash',now());
 PERFORM fixture.throws(format('SELECT fixture.approve_alternate(%L)',sid),'55000','fresh verified no-match');
END $$ $case$);
SELECT fixture.test('identity bucket pair encoding is unambiguous NFC and whitespace normalized', $case$
DO $$ BEGIN
 PERFORM fixture.assert(public.product_submission_label_bucket('A:B','C')<>public.product_submission_label_bucket('A','B:C'),'delimiter ambiguity prevented');
 PERFORM fixture.assert(public.product_submission_label_bucket(' EXAMPLE ',E'Label\t Name')=public.product_submission_label_bucket('example','label name'),'normalization is one coordination policy');
END $$ $case$);
SELECT fixture.test('v2 approval cannot substitute an unreviewed label while retaining reviewed hash', $case$
DO $$ DECLARE sid uuid; d public.product_submission_reviewer_drafts%ROWTYPE; BEGIN
 sid:=fixture.seed_alternate(1);
 SELECT * INTO d FROM public.product_submission_reviewer_drafts WHERE submission_id=sid;
 PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''approved'',p_approved_schema_version=>''manual_label_v2'',p_approved_payload=>''{"brandName":"Unreviewed","fullName":"Changed"}'',p_approved_payload_canonical=>%L,p_payload_sha256=>%L,p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>%L,p_product_image_photo_id=>''10000000-0000-0000-0000-000000000001'')',sid,d.payload_canonical,d.payload_sha256,fixture.manifest_hash(sid)),'55000','not the one reviewed');
END $$ $case$);
SELECT fixture.test('unrelated promotion list and active search writes cannot bypass identity conflict', $case$
DO $$ DECLARE sid uuid; unrelated uuid; h text; approvals jsonb; BEGIN
 unrelated:=fixture.seed(2,'4006381333931','under_review',NULL);
 PERFORM fixture.approve(unrelated);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=unrelated;
 sid:=fixture.seed_alternate(1);
 PERFORM fixture.approve_alternate(sid);
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('unrelated-list-catalog','998','Label','Example');
 approvals:=jsonb_build_array(jsonb_build_object('submission_id',unrelated,'approval_revision',1,'payload_sha256',h));
 PERFORM fixture.throws(format('SELECT public.rotate_manifest_with_submission_approvals(''unrelated-list-catalog'',''p'',''s'',''1'',1,''hash'',now(),''1.0.0'',%L::jsonb)',approvals),'23505','activation conflicts');
 PERFORM public.rotate_manifest_with_submission_approvals('unrelated-active-catalog','p','s','1',0,'hash',now());
 PERFORM fixture.throws('INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES(''unrelated-active-catalog'',''998'',''Label'',''Example'')','23505','activation conflicts');
END $$ $case$);
SELECT fixture.test('later learned UPC refuses published identity reassignment and retains old approval', $case$
DO $$ DECLARE sid uuid; h text; stable text; d public.product_submission_reviewer_drafts%ROWTYPE; BEGIN
 sid:=fixture.seed_alternate(1);
 stable:='PG_SUB_'||upper(replace(sid::text,'-',''));
 PERFORM fixture.approve_alternate(sid);
 SELECT payload_sha256 INTO h FROM public.product_submission_approved_labels WHERE submission_id=sid;
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('own-catalog',stable,'Label','Example');
 PERFORM public.rotate_manifest_with_submission_approvals('own-catalog','p','s','1',1,'hash',now(),'1.0.0',jsonb_build_array(jsonb_build_object('submission_id',sid,'approval_revision',1,'payload_sha256',h,'resolved_dsld_id',stable)));
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name,upc_sku) VALUES('own-catalog','777','Other label','Other brand','012345678905');
 PERFORM public.reopen_product_submission_approval(sid,1,h,'Learned manufacturer barcode');
 PERFORM public.correct_product_submission_barcode(sid,'012345678905','Read verified manufacturer barcode',1,fixture.manifest_hash(sid));
 PERFORM fixture.prepare_review(sid,'{"brandName":"Example","fullName":"Label"}');
 PERFORM public.record_product_submission_match_check(sid,'catalog_match','00012345678905',now(),'777',ARRAY[stable],NULL,1,fixture.manifest_hash(sid),'label_review','{"code_type":"manufacturer_sku","issuer":null,"verified_gtin":"012345678905","package":"60 capsules","reason":"Read barcode and compared complete candidates"}',true,'learned-gtin-index');
 SELECT * INTO d FROM public.product_submission_reviewer_drafts WHERE submission_id=sid;
 d.payload:=public.prepare_product_submission_approval_payload(sid,d.payload,'777',NULL); d.payload_canonical:=d.payload::text; d.payload_sha256:=encode(extensions.digest(d.payload_canonical,'sha256'),'hex');
 PERFORM fixture.throws(format('SELECT public.review_product_submission(%L,''approved'',p_approved_schema_version=>''manual_label_v2'',p_approved_payload=>%L::jsonb,p_approved_payload_canonical=>%L,p_payload_sha256=>%L,p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>%L,p_product_image_photo_id=>''10000000-0000-0000-0000-000000000001'',p_correction_target_dsld_id=>''777'')',sid,d.payload,d.payload_canonical,d.payload_sha256,fixture.manifest_hash(sid)),'23505','catalog identity conflict');
 PERFORM fixture.assert((SELECT resolved_dsld_id=stable AND promoted_approval_revision=1 FROM public.product_submissions WHERE id=sid),'stable published identity retained');
 PERFORM fixture.assert((SELECT payload_sha256=h FROM public.product_submission_approved_labels WHERE submission_id=sid AND approval_revision=1),'old published approval retained');
END $$ $case$);
SELECT fixture.test('alternate requested retake retains UUID and exact declaration on interrupted replay', $case$
DO $$ DECLARE sid uuid; req uuid:=gen_random_uuid(); ident jsonb; rev integer; BEGIN
 sid:=fixture.seed_alternate(1);
 PERFORM public.request_product_submission_evidence(sid,'photo_quality',ARRAY['front_identity']::text[],1,fixture.manifest_hash(sid));
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 rev:=public.open_product_submission_evidence_revision(sid,1,req,'{}','pharmaguide.submission_consent.2026-10-26.v2');
 PERFORM fixture.assert(rev=2 AND public.open_product_submission_evidence_revision(sid,1,req,'{}','pharmaguide.submission_consent.2026-10-26.v2')=2,'transport retry resumes same revision');
 SELECT identifier INTO ident FROM public.product_submissions WHERE id=sid;
 PERFORM fixture.assert((SELECT count(*)=2 AND bool_and(identifier=ident) FROM public.product_submission_evidence_revisions WHERE submission_id=sid),'both revisions preserve exact observed declaration');
 PERFORM fixture.assert((SELECT identifier->>'observed_code'='X002FLZ3X7' AND normalized_upc IS NULL AND evidence_revision=2 FROM public.product_submissions WHERE id=sid),'original UUID remains lifecycle anchor');
END $$ $case$);
SELECT fixture.test('intake rejects alphanumeric wrappers rather than extracting numeric substrings', $case$
DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.sub',fixture.user_id(1)::text,false);
 PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'',''X036000291452'')','22023','UPC/EAN');
 PERFORM fixture.throws('SELECT public.get_product_submission_intake(''missing_product'',''036000291452X'')','22023','UPC/EAN');
END $$ $case$);
SELECT fixture.test('C1 controls reject and optional whitespace metadata canonicalizes to null', $case$
DO $$ DECLARE ident jsonb:=fixture.alternate_identifier(); BEGIN
 PERFORM fixture.throws(format('SELECT public.validate_product_submission_identifier(%L::jsonb)',ident||jsonb_build_object('observed_code',U&'X\0085Y')),'22023','identifier');
 PERFORM fixture.assert(public.validate_product_submission_identifier(ident||jsonb_build_object('issuer',U&' \00A0 ','listing_url','   '))=ident,'optional whitespace is canonical null');
END $$ $case$);
SELECT fixture.test('reviewer identity edits invalidate prior checklist attestations', $case$
DO $$ DECLARE sid uuid; BEGIN
 sid:=fixture.seed_alternate(1);
 PERFORM fixture.assert(EXISTS(SELECT 1 FROM public.product_submission_field_verifications WHERE submission_id=sid),'review checklist exists');
 PERFORM public.correct_product_submission_barcode(sid,'012345678905','Read manufacturer barcode',1,fixture.manifest_hash(sid));
 PERFORM fixture.assert(NOT EXISTS(SELECT 1 FROM public.product_submission_field_verifications WHERE submission_id=sid),'identity edit clears checklist');
END $$ $case$);
SELECT fixture.test('pending selected target cannot disappear through activation or active generation deletion', $case$
DO $$ DECLARE sid uuid; envelope jsonb; wire text; BEGIN
 INSERT INTO public.catalog_search(catalog_version,dsld_id,product_name,brand_name) VALUES('selected-target-catalog','900','Label','Example');
 PERFORM public.rotate_manifest_with_submission_approvals('selected-target-catalog','p','s','1',1,'hash',now());
 sid:=fixture.seed(1,'012345678905','under_review',NULL);
 UPDATE public.product_submissions SET identifier=fixture.alternate_identifier(),normalized_upc=NULL WHERE id=sid;
 UPDATE public.product_submission_evidence_revisions SET identifier=fixture.alternate_identifier() WHERE submission_id=sid;
 PERFORM fixture.prepare_review(sid,'{"brandName":"Example","fullName":"Label"}');
 PERFORM public.record_product_submission_match_check(sid,'catalog_match',NULL,now(),'900','{}',NULL,1,fixture.manifest_hash(sid),'label_review','{"code_type":"other","issuer":null,"verified_gtin":null,"package":"60 capsules","reason":"Reviewed matching catalog label"}',true,'selected-target-index');
 envelope:=public.prepare_product_submission_approval_payload(sid,'{"brandName":"Example","fullName":"Label"}','900'); wire:=envelope::text;
 PERFORM public.review_product_submission(sid,'approved',p_approved_schema_version=>'manual_label_v2',p_approved_payload=>envelope,p_approved_payload_canonical=>wire,p_payload_sha256=>encode(extensions.digest(wire,'sha256'),'hex'),p_expected_evidence_revision=>1,p_evidence_manifest_sha256=>fixture.manifest_hash(sid),p_product_image_photo_id=>'10000000-0000-0000-0000-000000000001',p_correction_target_dsld_id=>'900');
 PERFORM fixture.throws('DELETE FROM public.catalog_search WHERE catalog_version=''selected-target-catalog'' AND dsld_id=''900''','23505','reviewed catalog target');
 PERFORM fixture.throws('SELECT public.rotate_manifest_with_submission_approvals(''removed-target-catalog'',''p'',''s'',''1'',0,''hash'',now())','23505','reviewed catalog target');
END $$ $case$);

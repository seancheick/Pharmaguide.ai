-- Synthetic existing receipt, inserted BEFORE the foundations migration.
INSERT INTO auth.users(id) VALUES('90000000-0000-0000-0000-000000000001');
INSERT INTO public.product_submissions(id,user_id,kind,normalized_upc)
VALUES('90000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001','missing_product','012345678905');
INSERT INTO public.product_submission_photos(submission_id,user_id,photo_id,seq,categories,object_path,content_type,byte_size,content_sha256)
VALUES('90000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001',
 '90000000-0000-0000-0000-000000000003',1,
 ARRAY['front_identity','supplement_facts','ingredient_disclosure','barcode']::public.product_submission_evidence_category[],
 '90000000-0000-0000-0000-000000000001/90000000-0000-0000-0000-000000000002/90000000-0000-0000-0000-000000000003',
 'image/jpeg',123,repeat('d',64));
UPDATE public.product_submissions SET upload_state='ready',submitted_at='2026-08-01T12:00:00Z'
WHERE id='90000000-0000-0000-0000-000000000002';

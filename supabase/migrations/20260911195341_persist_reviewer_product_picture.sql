-- Picture choice belongs to the existing reviewer draft, never the label payload.
ALTER TABLE public.product_submission_reviewer_drafts ADD COLUMN product_image jsonb;

CREATE FUNCTION public.set_product_submission_review_image(
  p_submission_id uuid, p_expected_evidence_revision integer,
  p_evidence_manifest_sha256 text, p_kind text, p_image_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE reviewer uuid := public.assert_product_submission_reviewer();
BEGIN
  PERFORM public.assert_product_submission_evidence(p_submission_id,
    p_expected_evidence_revision,p_evidence_manifest_sha256);
  IF NOT EXISTS (SELECT 1 FROM public.product_submissions WHERE id=p_submission_id
    AND kind='missing_product' AND review_status IN ('submitted','under_review')) THEN
    RAISE EXCEPTION 'editable missing product required' USING ERRCODE='55000';
  END IF;
  IF p_kind='photo' THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_submission_photos
      WHERE submission_id=p_submission_id AND photo_id=p_image_id
      AND revision=p_expected_evidence_revision AND 'front_identity'=ANY(categories)) THEN
      RAISE EXCEPTION 'current front photo required' USING ERRCODE='22023';
    END IF;
  ELSIF p_kind='reviewer' THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_submission_reviewer_images
      WHERE submission_id=p_submission_id AND object_id=p_image_id
      AND reviewer_id=reviewer AND evidence_revision=p_expected_evidence_revision
      AND finalized_at IS NOT NULL) THEN
      RAISE EXCEPTION 'current verified reviewer image required' USING ERRCODE='22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'picture kind required' USING ERRCODE='22023';
  END IF;
  UPDATE public.product_submission_reviewer_drafts SET product_image=jsonb_build_object(
    'kind',p_kind,'id',p_image_id,'evidence_revision',p_expected_evidence_revision,
    'manifest',p_evidence_manifest_sha256),updated_at=now()
    WHERE submission_id=p_submission_id AND reviewer_id=reviewer
    AND evidence_revision=p_expected_evidence_revision
    AND evidence_manifest_sha256=p_evidence_manifest_sha256;
  IF NOT FOUND THEN RAISE EXCEPTION 'save current review first' USING ERRCODE='55000'; END IF;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.set_product_submission_review_image(uuid,integer,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_product_submission_review_image(uuid,integer,text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.load_product_submission_reviewer_draft(p_submission_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE reviewer uuid:=public.assert_product_submission_reviewer(); result jsonb; picture jsonb; approved jsonb;
BEGIN
  result:=public.product_submission_reviewer_state_internal(p_submission_id,reviewer);
  SELECT product_image INTO picture FROM public.product_submission_reviewer_drafts
    WHERE submission_id=p_submission_id AND reviewer_id=reviewer;
  IF picture->>'evidence_revision' IS DISTINCT FROM result->>'current_evidence_revision'
    OR picture->>'manifest' IS DISTINCT FROM result->>'current_evidence_manifest_sha256' THEN
    picture:=NULL;
  END IF;
  IF result->>'review_status'='approved' THEN
    SELECT jsonb_build_object('approved_payload',approved_payload,
      'payload_sha256',payload_sha256,'approved_at',approved_at,
      'product_image_photo_id',approved_product_image_photo_id,
      'product_image_reviewer_object_id',approved_product_image_reviewer_object_id)
      INTO approved FROM public.product_submission_approved_labels WHERE submission_id=p_submission_id;
    picture:=CASE WHEN approved->>'product_image_reviewer_object_id' IS NOT NULL THEN
      jsonb_build_object('kind','reviewer','id',approved->>'product_image_reviewer_object_id')
      WHEN approved->>'product_image_photo_id' IS NOT NULL THEN
      jsonb_build_object('kind','photo','id',approved->>'product_image_photo_id') ELSE NULL END;
  END IF;
  RETURN result || jsonb_build_object('approved_label',approved,'product_image',picture,
    'reviewer_images',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'object_id',image.object_id,'object_path',image.object_path))
      FROM public.product_submission_reviewer_images image
      WHERE image.submission_id=p_submission_id
      AND image.evidence_revision=(result->>'current_evidence_revision')::integer
      AND (image.reviewer_id=reviewer OR image.object_id::text=approved->>'product_image_reviewer_object_id')
      AND EXISTS (SELECT 1 FROM storage.objects object WHERE object.bucket_id='product-submission-reviewer-images'
        AND object.name=image.object_path)), '[]'::jsonb));
END $$;

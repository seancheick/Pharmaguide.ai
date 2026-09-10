CREATE SCHEMA fixture;
GRANT USAGE ON SCHEMA fixture TO authenticated, anon, service_role;
CREATE TABLE fixture.results (name text, error text);
GRANT INSERT, SELECT ON fixture.results TO authenticated, anon, service_role;

CREATE FUNCTION fixture.assert(p_value boolean, p_message text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF p_value IS DISTINCT FROM true THEN RAISE EXCEPTION '%', p_message; END IF;
END $$;

-- Record every failing case so baseline runs show independent defects.
CREATE FUNCTION fixture.test(p_name text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  EXECUTE p_sql;
  -- Roll back successful cases too, so receipt histories cannot leak between cases.
  RAISE EXCEPTION 'fixture rollback' USING ERRCODE = 'Z0001';
EXCEPTION WHEN others THEN
  INSERT INTO fixture.results VALUES (p_name,
    CASE WHEN SQLSTATE <> 'Z0001' THEN SQLSTATE || ': ' || SQLERRM END);
END $$;

CREATE FUNCTION fixture.throws(p_sql text, p_state text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$ DECLARE caught boolean := false; BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    caught := true;
    PERFORM fixture.assert(SQLSTATE = p_state AND SQLERRM LIKE '%' || p_message || '%',
      'unexpected failure: ' || SQLSTATE || ': ' || SQLERRM);
  END;
  PERFORM fixture.assert(caught, 'expected failure: ' || p_state || ': ' || p_message);
END $$;

CREATE FUNCTION fixture.user_id(p_number integer) RETURNS uuid LANGUAGE sql IMMUTABLE
AS $$ SELECT ('00000000-0000-0000-0000-' || lpad(p_number::text, 12, '0'))::uuid $$;
INSERT INTO auth.users(id) SELECT fixture.user_id(n) FROM generate_series(1, 5) n;
INSERT INTO public.product_submission_reviewers(user_id) VALUES (fixture.user_id(3));
INSERT INTO public.product_submission_consent_versions(version, kind, purposes, copy_sha256, effective_from)
SELECT version, kind, ARRAY['private_review', 'ai_label_draft'], repeat('f',64), '2020-01-01'
FROM unnest(ARRAY['fixture.consent.v1','fixture.consent.v2']) version
CROSS JOIN unnest(enum_range(NULL::public.product_submission_kind)) kind;

CREATE FUNCTION fixture.photos() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
SELECT jsonb_build_array(jsonb_build_object(
  'photo_id', '10000000-0000-0000-0000-000000000001', 'seq', 1,
  'categories', jsonb_build_array('front_identity', 'supplement_facts', 'ingredient_disclosure', 'barcode'),
  'content_type', 'image/jpeg', 'byte_size', 100,
  'content_sha256', repeat('a', 64)))
$$;

CREATE FUNCTION fixture.detail(p_dsld text, p_formula text DEFAULT NULL) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object(
  'dsld_id', p_dsld, 'source_record_id', NULL, 'catalog_source_version', NULL,
  'formula_fingerprint', p_formula, 'mismatch_categories', jsonb_build_array('product_identity')) $$;

-- Set up reviewed states as the database owner; user behavior below always
-- calls production RPCs. A single evidence photo covers all required faces.
CREATE FUNCTION fixture.seed(p_user integer, p_upc text DEFAULT '012345678905',
  p_status public.product_submission_review_status DEFAULT 'rejected',
  p_code public.product_submission_resolution_code DEFAULT 'photo_quality',
  p_kind public.product_submission_kind DEFAULT 'missing_product',
  p_dsld text DEFAULT NULL,
  p_state public.product_submission_upload_state DEFAULT 'ready')
RETURNS uuid LANGUAGE plpgsql AS $$ DECLARE sid uuid := gen_random_uuid(); BEGIN
  INSERT INTO public.product_submissions(id, user_id, kind, normalized_upc)
  VALUES (sid, fixture.user_id(p_user), p_kind, p_upc);
  IF p_kind = 'missing_product' THEN
    INSERT INTO public.product_submission_missing_details(submission_id, user_id)
    VALUES (sid, fixture.user_id(p_user));
  ELSE
    INSERT INTO public.product_submission_mismatch_details(
      submission_id, user_id, dsld_id, mismatch_categories)
    VALUES (sid, fixture.user_id(p_user), p_dsld, ARRAY['product_identity']::public.label_mismatch_category[]);
  END IF;
  INSERT INTO public.product_submission_photos(
    submission_id, user_id, photo_id, seq, categories, object_path,
    content_type, byte_size, content_sha256)
  VALUES (sid, fixture.user_id(p_user), '10000000-0000-0000-0000-000000000001', 1,
    ARRAY['front_identity','supplement_facts','ingredient_disclosure','barcode']::public.product_submission_evidence_category[],
    fixture.user_id(p_user)::text || '/' || sid::text || '/10000000-0000-0000-0000-000000000001',
    'image/jpeg', 100, repeat('a',64));
  INSERT INTO storage.objects(bucket_id, name, owner_id, metadata, user_metadata)
  SELECT 'product-submission-photos', object_path, user_id::text,
    jsonb_build_object('size', byte_size, 'mimetype', content_type),
    jsonb_build_object('content_sha256', content_sha256)
  FROM public.product_submission_photos WHERE submission_id = sid;
  -- Production records the consent on the revision as well as the submission
  -- (create_product_submission stamps revision 1), and consumers read the
  -- revision's. A fixture that omits it is not the shape the app produces.
  INSERT INTO public.product_submission_evidence_revisions(
    submission_id, revision, request_key, opened_by, photo_ids,
    consent_version, consented_at)
  VALUES (sid, 1, sid, fixture.user_id(p_user), ARRAY['10000000-0000-0000-0000-000000000001'::uuid],
    'fixture.consent.v1', now());
  IF p_state = 'ready' THEN
    UPDATE public.product_submission_evidence_revisions SET ready_at = now(),
      manifest = public.product_submission_evidence_records(sid,1),
      manifest_sha256 = public.product_submission_manifest_sha256(public.product_submission_evidence_records(sid,1))
    WHERE submission_id = sid;
  END IF;
  UPDATE public.product_submissions SET upload_state = p_state, review_status = p_status,
    consent_version = 'fixture.consent.v1', consented_at = now(),
    reviewed_at = CASE WHEN p_status <> 'submitted' THEN now() END,
    reviewed_by = CASE WHEN p_status <> 'submitted' THEN fixture.user_id(3) END,
    resolution_code = CASE WHEN p_status IN ('rejected','duplicate') THEN p_code END,
    resolution_detail = CASE WHEN p_code = 'other' THEN 'Please retake the label.' END
  WHERE id = sid;
  RETURN sid;
END $$;

CREATE FUNCTION fixture.approve(p_id uuid) RETURNS boolean LANGUAGE plpgsql AS $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  INSERT INTO public.product_submission_match_checks(
    submission_id, reviewer_id, canonical_gtin14, outcome,
    index_built_at, candidate_dsld_ids)
  SELECT p_id, fixture.user_id(3), lpad(normalized_upc, 14, '0'), 'no_match_verified',
    now(), ARRAY[]::text[] FROM public.product_submissions WHERE id = p_id;
  PERFORM fixture.prepare_review(p_id);
  RETURN public.review_product_submission(p_id, 'approved',
    p_approved_schema_version => 'manual_label_v1', p_approved_payload => '{"fixture":true}'::jsonb,
    p_approved_payload_canonical => '{"fixture":true}',
    p_payload_sha256 => encode(extensions.digest('{"fixture":true}', 'sha256'), 'hex'),
    p_product_image_photo_id => '10000000-0000-0000-0000-000000000001',
    p_expected_evidence_revision => (SELECT evidence_revision FROM public.product_submissions WHERE id = p_id),
    p_evidence_manifest_sha256 => (SELECT manifest_sha256 FROM public.product_submission_evidence_revisions
      WHERE submission_id = p_id AND revision=(SELECT evidence_revision FROM public.product_submissions WHERE id=p_id)));
END $$;

-- Seed the complete reviewer workstation state required by the production
-- approval gate.  This helper refreshes an existing review after a fixture
-- mutates evidence, so tests reach the inner transition they intend to test.
CREATE FUNCTION fixture.prepare_review(p_id uuid, p_payload jsonb DEFAULT '{"fixture":true}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $$ DECLARE
  current_revision integer;
  current_manifest text;
  -- The fixture payload is intentionally already in the canonical wire form
  -- used by the approval call. Keep this explicit instead of relying on
  -- jsonb::text formatting, which is not the contract under test.
  payload_canonical text := CASE WHEN p_payload = '{"fixture":true}'::jsonb
    THEN '{"fixture":true}' ELSE p_payload::text END;
  payload_sha text := encode(extensions.digest(payload_canonical, 'sha256'), 'hex');
BEGIN
  PERFORM set_config('request.jwt.claim.sub', fixture.user_id(3)::text, false);
  -- Recompute the fixture snapshot from the current rows before binding the
  -- review. This mirrors the production finalize boundary and prevents a
  -- test fixture's hand-built manifest from masking the approval fence.
  SELECT evidence_revision INTO current_revision
  FROM public.product_submissions WHERE id = p_id;
  current_manifest := public.product_submission_manifest_sha256(
    public.product_submission_evidence_records(p_id, current_revision));
  UPDATE public.product_submission_evidence_revisions
  SET manifest = public.product_submission_evidence_records(p_id, current_revision),
      manifest_sha256 = current_manifest
  WHERE submission_id = p_id AND revision = current_revision;
  INSERT INTO public.product_submission_reviewer_drafts(
    submission_id, reviewer_id, evidence_revision, evidence_manifest_sha256,
    payload, payload_canonical, payload_sha256)
  SELECT p_id, fixture.user_id(3), s.evidence_revision, current_manifest,
    p_payload, payload_canonical, payload_sha
  FROM public.product_submissions AS s
  JOIN public.product_submission_evidence_revisions AS r
    ON r.submission_id = s.id AND r.revision = s.evidence_revision
  WHERE s.id = p_id
  ON CONFLICT (submission_id, reviewer_id) DO UPDATE SET
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256,
    payload = EXCLUDED.payload,
    payload_canonical = EXCLUDED.payload_canonical,
    payload_sha256 = EXCLUDED.payload_sha256,
    updated_at = now();
  DELETE FROM public.product_submission_field_verifications
  WHERE submission_id = p_id AND reviewer_id = fixture.user_id(3);
  INSERT INTO public.product_submission_field_verifications(
    submission_id, reviewer_id, field_path, payload_sha256,
    evidence_revision, evidence_manifest_sha256)
  SELECT p_id, fixture.user_id(3), required.path,
    payload_sha,
    s.evidence_revision, current_manifest
  FROM public.product_submissions AS s
  JOIN public.product_submission_evidence_revisions AS r
    ON r.submission_id = s.id AND r.revision = s.evidence_revision
  CROSS JOIN unnest(public.product_submission_required_verification_paths())
    AS required(path)
  WHERE s.id = p_id
  ON CONFLICT (submission_id, reviewer_id, field_path) DO UPDATE SET
    payload_sha256 = EXCLUDED.payload_sha256,
    evidence_revision = EXCLUDED.evidence_revision,
    evidence_manifest_sha256 = EXCLUDED.evidence_manifest_sha256;
END $$;

CREATE FUNCTION fixture.manifest_hash(sid uuid) RETURNS text LANGUAGE sql AS $$
 SELECT manifest_sha256 FROM public.product_submission_evidence_revisions
 WHERE submission_id=sid AND revision=(SELECT evidence_revision FROM public.product_submissions WHERE id=sid)
$$;
-- Owner-only synthetic corruption setup for testing independent inner gates.
CREATE FUNCTION fixture.refreeze(sid uuid) RETURNS void LANGUAGE sql AS $$
 UPDATE public.product_submission_evidence_revisions SET
 manifest=public.product_submission_evidence_records(sid,revision),
 manifest_sha256=public.product_submission_manifest_sha256(public.product_submission_evidence_records(sid,revision))
 WHERE submission_id=sid
$$;

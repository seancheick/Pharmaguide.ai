-- =============================================================================
-- Private, structured product-label mismatch reports
-- =============================================================================
-- Reports contain only product/catalog lineage and closed mismatch categories.
-- They intentionally contain no user-entered narrative fields. Submission is
-- append-only for authenticated clients: reviewers use server-held
-- service-role authority, and no trigger or foreign key touches catalog data.

CREATE TYPE public.label_mismatch_category AS ENUM (
  'product_identity',
  'ingredient_missing',
  'ingredient_extra',
  'amount_or_unit',
  'form_or_parenthetical',
  'serving_size_or_directions',
  'other_ingredients',
  'catalog_version_or_status'
);

CREATE TYPE public.label_mismatch_report_status AS ENUM (
  'submitted',
  'under_review',
  'resolved',
  'dismissed'
);

CREATE TYPE public.label_mismatch_upload_state AS ENUM (
  'pending',
  'ready',
  'cleaning'
);

CREATE TYPE public.label_mismatch_photo_slot AS ENUM (
  'front',
  'supplement_facts',
  'other_ingredients'
);

CREATE TABLE public.label_mismatch_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dsld_id text NOT NULL CHECK (btrim(dsld_id) <> ''),
  upc text CHECK (upc IS NULL OR btrim(upc) <> ''),
  source_record_id text
    CHECK (source_record_id IS NULL OR btrim(source_record_id) <> ''),
  catalog_source_version text
    CHECK (
      catalog_source_version IS NULL
      OR btrim(catalog_source_version) <> ''
    ),
  formula_fingerprint text
    CHECK (
      formula_fingerprint IS NULL
      OR formula_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  mismatch_categories public.label_mismatch_category[] NOT NULL
    CHECK (cardinality(mismatch_categories) BETWEEN 1 AND 8)
    CHECK (array_position(mismatch_categories, NULL) IS NULL),
  upload_state public.label_mismatch_upload_state NOT NULL DEFAULT 'pending',
  status public.label_mismatch_report_status NOT NULL DEFAULT 'submitted',
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  CONSTRAINT label_mismatch_reports_id_user_unique UNIQUE (id, user_id)
);

CREATE TABLE public.label_mismatch_report_photos (
  report_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_slot public.label_mismatch_photo_slot NOT NULL,
  object_path text NOT NULL,
  content_type text NOT NULL
    CHECK (
      content_type IN (
        'image/jpeg',
        'image/png',
        'image/heic',
        'image/heif',
        'image/webp'
      )
    ),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 15728640),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (report_id, photo_slot),
  CONSTRAINT label_mismatch_report_photos_owner_fkey
    FOREIGN KEY (report_id, user_id)
    REFERENCES public.label_mismatch_reports(id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT label_mismatch_report_photos_object_path_check
    CHECK (
      object_path =
        user_id::text || '/' || report_id::text || '/' || photo_slot::text
    )
);

-- Owner filters and reviewer queues remain index-backed. The photo primary key
-- already covers report_id; the additional unique path index prevents two
-- metadata records from ever referring to one stored object.
CREATE INDEX idx_label_mismatch_reports_user_submitted
  ON public.label_mismatch_reports (user_id, submitted_at DESC);
CREATE INDEX idx_label_mismatch_reports_status_submitted
  ON public.label_mismatch_reports (status, submitted_at);
CREATE INDEX idx_label_mismatch_reports_review_queue
  ON public.label_mismatch_reports (
    upload_state,
    status,
    submitted_at DESC,
    id DESC
  );
CREATE INDEX idx_label_mismatch_reports_review_all
  ON public.label_mismatch_reports (
    upload_state,
    submitted_at DESC,
    id DESC
  );
CREATE INDEX idx_label_mismatch_report_photos_user
  ON public.label_mismatch_report_photos (user_id);
CREATE UNIQUE INDEX idx_label_mismatch_report_photos_object_path
  ON public.label_mismatch_report_photos (object_path);

-- Ownership is immutable even for a privileged reviewer update. Authenticated
-- clients receive no table UPDATE or DELETE privilege at all.
CREATE OR REPLACE FUNCTION public.enforce_label_mismatch_owner_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'label mismatch report ownership is immutable'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER label_mismatch_reports_immutable_owner
  BEFORE UPDATE ON public.label_mismatch_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_label_mismatch_owner_immutable();

CREATE TRIGGER label_mismatch_report_photos_immutable_owner
  BEFORE UPDATE ON public.label_mismatch_report_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_label_mismatch_owner_immutable();

-- Serialize a new manifest row with finalization and stale-report cleanup.
-- AFTER INSERT preserves idempotent ON CONFLICT DO NOTHING retries because a
-- duplicate row does not fire this trigger, while a genuinely late row is
-- rolled back unless its parent report is still pending.
CREATE OR REPLACE FUNCTION public.enforce_label_mismatch_photo_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  parent_upload_state public.label_mismatch_upload_state;
BEGIN
  SELECT report.upload_state
    INTO parent_upload_state
  FROM public.label_mismatch_reports AS report
  WHERE report.id = NEW.report_id
    AND report.user_id = NEW.user_id
  FOR UPDATE;

  IF NOT FOUND OR parent_upload_state <> 'pending' THEN
    RAISE EXCEPTION 'photo manifest is closed'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER label_mismatch_report_photos_pending_parent
  AFTER INSERT ON public.label_mismatch_report_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_label_mismatch_photo_pending();

-- Authenticated clients cannot mark a report reviewable themselves. This
-- owner-scoped SECURITY DEFINER function returns false until every declared
-- manifest path exists in the private bucket, and is idempotent after success.
CREATE OR REPLACE FUNCTION public.finalize_label_mismatch_report(
  p_report_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  current_upload_state public.label_mismatch_upload_state;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT report.upload_state
    INTO current_upload_state
  FROM public.label_mismatch_reports AS report
  WHERE report.id = p_report_id
    AND report.user_id = caller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'report not found' USING ERRCODE = '42501';
  END IF;
  IF current_upload_state = 'ready' THEN
    RETURN true;
  END IF;
  IF current_upload_state <> 'pending' THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.label_mismatch_report_photos AS photo
    WHERE photo.report_id = p_report_id
      AND photo.user_id = caller_id
      AND NOT EXISTS (
        SELECT 1
        FROM storage.objects AS object
        WHERE object.bucket_id = 'label-mismatch-report-photos'
          AND object.owner_id = caller_id::text
          AND object.name = photo.object_path
      )
  ) THEN
    RETURN false;
  END IF;

  UPDATE public.label_mismatch_reports
  SET upload_state = 'ready',
      submitted_at = now()
  WHERE id = p_report_id
    AND user_id = caller_id
    AND upload_state = 'pending';
  RETURN true;
END;
$$;

ALTER TABLE public.label_mismatch_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.label_mismatch_reports FORCE ROW LEVEL SECURITY;
ALTER TABLE public.label_mismatch_report_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.label_mismatch_report_photos FORCE ROW LEVEL SECURITY;

CREATE POLICY "label_mismatch_reports_select_own"
  ON public.label_mismatch_reports
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "label_mismatch_reports_insert_own"
  ON public.label_mismatch_reports
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND upload_state = 'pending'
    AND status = 'submitted'
    AND reviewed_at IS NULL
  );

CREATE POLICY "label_mismatch_report_photos_select_own"
  ON public.label_mismatch_report_photos
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "label_mismatch_report_photos_insert_own"
  ON public.label_mismatch_report_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1
      FROM public.label_mismatch_reports AS report
      WHERE report.id = label_mismatch_report_photos.report_id
        AND report.user_id = label_mismatch_report_photos.user_id
        AND report.upload_state = 'pending'
    )
  );

-- Reviewer access is server-only. service_role bypasses RLS in Supabase, but
-- explicit policies and narrow grants keep the intended operations auditable.
CREATE POLICY "label_mismatch_reports_reviewer_select"
  ON public.label_mismatch_reports
  FOR SELECT TO service_role
  USING (true);

CREATE POLICY "label_mismatch_reports_reviewer_update"
  ON public.label_mismatch_reports
  FOR UPDATE TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "label_mismatch_reports_reviewer_delete_cleaning"
  ON public.label_mismatch_reports
  FOR DELETE TO service_role
  USING (upload_state = 'cleaning');

CREATE POLICY "label_mismatch_report_photos_reviewer_select"
  ON public.label_mismatch_report_photos
  FOR SELECT TO service_role
  USING (true);

REVOKE ALL ON TYPE public.label_mismatch_category FROM PUBLIC, anon;
REVOKE ALL ON TYPE public.label_mismatch_report_status FROM PUBLIC, anon;
REVOKE ALL ON TYPE public.label_mismatch_upload_state FROM PUBLIC, anon;
REVOKE ALL ON TYPE public.label_mismatch_photo_slot FROM PUBLIC, anon;
GRANT USAGE ON TYPE public.label_mismatch_category
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.label_mismatch_report_status
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.label_mismatch_upload_state
  TO authenticated, service_role;
GRANT USAGE ON TYPE public.label_mismatch_photo_slot
  TO authenticated, service_role;

REVOKE ALL ON TABLE public.label_mismatch_reports
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.label_mismatch_report_photos
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.label_mismatch_reports TO authenticated;
GRANT INSERT (
  id,
  user_id,
  dsld_id,
  upc,
  source_record_id,
  catalog_source_version,
  formula_fingerprint,
  mismatch_categories
) ON TABLE public.label_mismatch_reports TO authenticated;
GRANT SELECT ON TABLE public.label_mismatch_report_photos TO authenticated;
GRANT INSERT (
  report_id,
  user_id,
  photo_slot,
  object_path,
  content_type,
  byte_size
) ON TABLE public.label_mismatch_report_photos TO authenticated;
GRANT SELECT, DELETE, UPDATE (status, reviewed_at, upload_state)
  ON TABLE public.label_mismatch_reports TO service_role;
GRANT SELECT ON TABLE public.label_mismatch_report_photos TO service_role;

REVOKE ALL ON FUNCTION public.enforce_label_mismatch_owner_immutable()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_label_mismatch_owner_immutable()
  TO service_role;
REVOKE ALL ON FUNCTION public.enforce_label_mismatch_photo_pending()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_label_mismatch_photo_pending()
  TO service_role;
REVOKE ALL ON FUNCTION public.finalize_label_mismatch_report(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_label_mismatch_report(uuid)
  TO authenticated, service_role;

-- =============================================================================
-- Private photo bucket
-- =============================================================================
-- Exact object path: {user_id}/{report_id}/{front|supplement_facts|other_ingredients}
-- Slot names are extensionless; content type is separately constrained in the
-- bucket and metadata table. One object name per slot prevents extension-based
-- duplicates from bypassing the three-photo contract.
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) VALUES (
  'label-mismatch-report-photos',
  'label-mismatch-report-photos',
  false,
  15728640,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "label_mismatch_objects_select_own"
  ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_insert_own"
  ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_update_own"
  ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_delete_own"
  ON storage.objects;
DROP POLICY IF EXISTS "label_mismatch_objects_reviewer_select"
  ON storage.objects;

CREATE POLICY "label_mismatch_objects_select_own"
  ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'label-mismatch-report-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND (storage.foldername(name))[2] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) IN (
      'front',
      'supplement_facts',
      'other_ingredients'
    )
  );

CREATE POLICY "label_mismatch_objects_insert_own"
  ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'label-mismatch-report-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND (storage.foldername(name))[2] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) IN (
      'front',
      'supplement_facts',
      'other_ingredients'
    )
    AND EXISTS (
      SELECT 1
      FROM public.label_mismatch_report_photos AS photo
      JOIN public.label_mismatch_reports AS report
        ON report.id = photo.report_id
       AND report.user_id = photo.user_id
      WHERE photo.user_id = (SELECT auth.uid())
        AND photo.report_id::text = (storage.foldername(name))[2]
        AND photo.photo_slot::text = storage.filename(name)
        AND photo.object_path = name
        AND report.upload_state = 'pending'
    )
  );

CREATE POLICY "label_mismatch_objects_update_own"
  ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'label-mismatch-report-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND (storage.foldername(name))[2] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) IN (
      'front',
      'supplement_facts',
      'other_ingredients'
    )
    AND EXISTS (
      SELECT 1
      FROM public.label_mismatch_report_photos AS photo
      JOIN public.label_mismatch_reports AS report
        ON report.id = photo.report_id
       AND report.user_id = photo.user_id
      WHERE photo.user_id = (SELECT auth.uid())
        AND photo.report_id::text = (storage.foldername(name))[2]
        AND photo.photo_slot::text = storage.filename(name)
        AND photo.object_path = name
        AND report.upload_state = 'pending'
    )
  )
  WITH CHECK (
    bucket_id = 'label-mismatch-report-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND (storage.foldername(name))[2] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) IN (
      'front',
      'supplement_facts',
      'other_ingredients'
    )
    AND EXISTS (
      SELECT 1
      FROM public.label_mismatch_report_photos AS photo
      JOIN public.label_mismatch_reports AS report
        ON report.id = photo.report_id
       AND report.user_id = photo.user_id
      WHERE photo.user_id = (SELECT auth.uid())
        AND photo.report_id::text = (storage.foldername(name))[2]
        AND photo.photo_slot::text = storage.filename(name)
        AND photo.object_path = name
        AND report.upload_state = 'pending'
    )
  );

CREATE POLICY "label_mismatch_objects_delete_own"
  ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'label-mismatch-report-photos'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND (storage.foldername(name))[2] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) IN (
      'front',
      'supplement_facts',
      'other_ingredients'
    )
    AND EXISTS (
      SELECT 1
      FROM public.label_mismatch_report_photos AS photo
      JOIN public.label_mismatch_reports AS report
        ON report.id = photo.report_id
       AND report.user_id = photo.user_id
      WHERE photo.user_id = (SELECT auth.uid())
        AND photo.report_id::text = (storage.foldername(name))[2]
        AND photo.photo_slot::text = storage.filename(name)
        AND photo.object_path = name
        AND report.upload_state = 'pending'
    )
  );

CREATE POLICY "label_mismatch_objects_reviewer_select"
  ON storage.objects
  FOR SELECT TO service_role
  USING (bucket_id = 'label-mismatch-report-photos');

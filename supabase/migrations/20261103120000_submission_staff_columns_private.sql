-- A submitter reads their own submission and photo rows, but which staff account
-- reviewed them and the cleanup worker's claim are not theirs to see. Replace the
-- table-wide SELECT with the columns the app reads. Service-role access and the
-- SECURITY DEFINER functions are unaffected; supabase/tests/backend_security pins
-- both the hidden columns and the app's exact select lists.
REVOKE SELECT ON TABLE public.product_submissions FROM authenticated;
GRANT SELECT (
  id, user_id, kind, normalized_upc, identifier, upload_state, review_status,
  created_at, submitted_at, reviewed_at, promoted_catalog_version, promoted_at,
  duplicate_of, evidence_purged_at, declared_no_separate_ingredient_panel,
  resolution_code, resolution_detail, resolved_dsld_id, resubmission_of,
  dismissed_at, consent_version, consented_at, evidence_revision,
  evidence_revision_opened_at, evidence_ready_at, evidence_requested_at,
  evidence_requested_revision, evidence_request_reason, evidence_request_panels,
  display_name, correction_target_dsld_id, edition_of_dsld_id, approval_revision,
  promoted_approval_revision
) ON public.product_submissions TO authenticated;

REVOKE SELECT ON TABLE public.product_submission_photos FROM authenticated;
GRANT SELECT (
  submission_id, user_id, photo_id, seq, categories, object_path, content_type,
  byte_size, content_sha256, created_at, revision, uploader_role
) ON public.product_submission_photos TO authenticated;

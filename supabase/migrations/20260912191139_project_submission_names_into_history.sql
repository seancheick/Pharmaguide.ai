-- Display-only projection of reviewer-entered identity. No approval, matching,
-- evidence, scores or reviewer account data is exposed or changed.
CREATE FUNCTION public.submission_label_display_name(payload jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE brand text; name text;
BEGIN
  IF jsonb_typeof(payload->'fullName') <> 'string' THEN RETURN NULL; END IF;
  name := btrim(regexp_replace(payload->>'fullName', '[[:cntrl:]]', ' ', 'g'));
  IF name IS NULL OR name = '' THEN RETURN NULL; END IF;
  IF jsonb_typeof(payload->'brandName') = 'string' THEN
    brand := btrim(regexp_replace(payload->>'brandName', '[[:cntrl:]]', ' ', 'g'));
  END IF;
  IF brand IS NOT NULL AND brand <> '' AND lower(name) <> lower(brand)
     AND left(lower(name), char_length(brand)+1) <> lower(brand)||' ' THEN
    name := brand || ' · ' || name;
  END IF;
  RETURN btrim(left(name,160));
END $$;
REVOKE ALL ON FUNCTION public.submission_label_display_name(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.project_submission_history_name()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE name text;
BEGIN
  PERFORM 1 FROM public.product_submissions WHERE id=NEW.submission_id FOR UPDATE;
  IF TG_TABLE_NAME = 'product_submission_approved_labels' THEN
    name := public.submission_label_display_name(NEW.approved_payload);
  ELSE
    -- Only a draft for the current evidence may supply a display name.
    -- A signed-off label always wins over unfinished reviewer edits.
    IF EXISTS (SELECT 1 FROM public.product_submission_approved_labels a
               WHERE a.submission_id=NEW.submission_id) OR NOT EXISTS (
      SELECT 1 FROM public.product_submissions s
      JOIN public.product_submission_evidence_revisions r
        ON r.submission_id=s.id AND r.revision=s.evidence_revision
      WHERE s.id=NEW.submission_id AND s.evidence_revision=NEW.evidence_revision
        AND r.manifest_sha256=NEW.evidence_manifest_sha256
    ) THEN RETURN NEW; END IF;
    name := public.submission_label_display_name(NEW.payload);
  END IF;
  IF name IS NOT NULL THEN
    UPDATE public.product_submissions SET display_name=name
    WHERE id=NEW.submission_id AND display_name IS DISTINCT FROM name;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.project_submission_history_name()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER approved_submission_history_name
AFTER INSERT OR UPDATE OF approved_payload ON public.product_submission_approved_labels
FOR EACH ROW EXECUTE FUNCTION public.project_submission_history_name();
CREATE TRIGGER draft_submission_history_name
AFTER INSERT OR UPDATE OF payload ON public.product_submission_reviewer_drafts
FOR EACH ROW EXECUTE FUNCTION public.project_submission_history_name();

-- Restore existing history from saved work, never from a barcode guess.
WITH names AS (
  SELECT DISTINCT ON (s.id) s.id,
    public.submission_label_display_name(d.payload) AS name
  FROM public.product_submissions s
  JOIN public.product_submission_reviewer_drafts d ON d.submission_id=s.id
  JOIN public.product_submission_evidence_revisions r
    ON r.submission_id=s.id AND r.revision=s.evidence_revision
  WHERE d.evidence_revision=s.evidence_revision
    AND d.evidence_manifest_sha256=r.manifest_sha256
    AND public.submission_label_display_name(d.payload) IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.product_submission_approved_labels a WHERE a.submission_id=s.id)
  ORDER BY s.id,d.updated_at DESC,d.reviewer_id
)
UPDATE public.product_submissions s SET display_name=n.name
FROM names n WHERE s.id=n.id AND s.display_name IS NULL;

UPDATE public.product_submissions s
SET display_name=public.submission_label_display_name(a.approved_payload)
FROM public.product_submission_approved_labels a
WHERE a.submission_id=s.id
  AND public.submission_label_display_name(a.approved_payload) IS NOT NULL
  AND s.display_name IS DISTINCT FROM public.submission_label_display_name(a.approved_payload);

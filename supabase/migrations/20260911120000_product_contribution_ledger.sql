-- Contribution points become an append-only server ledger.
--
-- Until now the app derived points on the phone: ten for every submission it
-- saw as approved, ready and promoted. A derived formula can re-price history
-- the moment its inputs or its code change, which is why the app's own
-- comment forbade making points redeemable before this ledger existed.
--
-- One producer: promotion. `mark_product_submission_promoted` is the only way
-- a submission reaches the catalog (the pipeline importer calls it), so the
-- award is written in that same transaction and nowhere else. No role can
-- insert, update or delete rows directly; owners can only read their own.
--
-- The backfill uses the same award function, so every submission the app
-- already counts earns exactly what it shows today, dated at its promotion.

CREATE TABLE public.product_contribution_ledger (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  submission_id uuid NOT NULL
    REFERENCES public.product_submissions(id) ON DELETE CASCADE,
  event text NOT NULL CHECK (event = 'earned_catalog_added'),
  points integer NOT NULL CHECK (points > 0),
  catalog_version text NOT NULL
    CHECK (char_length(catalog_version) BETWEEN 1 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- A submission earns once, however often the importer replays.
  UNIQUE (submission_id, event)
);

CREATE INDEX idx_product_contribution_ledger_user
  ON public.product_contribution_ledger (user_id);

ALTER TABLE public.product_contribution_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_contribution_ledger FORCE ROW LEVEL SECURITY;

CREATE POLICY "product_contribution_ledger_select_own"
  ON public.product_contribution_ledger
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

REVOKE ALL ON TABLE public.product_contribution_ledger
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.product_contribution_ledger TO authenticated;

-- The award rule, once. It matches what the app counted: approved, uploaded
-- and promoted into a catalog release.
CREATE FUNCTION public.award_product_contribution_points_internal(
  p_submission_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.product_contribution_ledger (
    user_id, submission_id, event, points, catalog_version, created_at
  )
  SELECT submission.user_id, submission.id, 'earned_catalog_added', 10,
    submission.promoted_catalog_version,
    coalesce(submission.promoted_at, now())
  FROM public.product_submissions AS submission
  WHERE submission.id = p_submission_id
    AND submission.review_status = 'approved'
    AND submission.upload_state = 'ready'
    AND submission.promoted_catalog_version IS NOT NULL
  ON CONFLICT (submission_id, event) DO NOTHING;
$$;
REVOKE ALL ON FUNCTION public.award_product_contribution_points_internal(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Same wrapper as 20260909013000, plus the award inside its transaction.
CREATE OR REPLACE FUNCTION public.mark_product_submission_promoted(
  p_submission_id uuid,
  p_catalog_version text,
  p_resolved_dsld_id text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  promoted boolean;
BEGIN
  PERFORM id FROM public.product_submissions WHERE id=p_submission_id FOR UPDATE;
  PERFORM public.assert_product_submission_approval(p_submission_id);
  promoted := public.mark_product_submission_promoted_internal(
    p_submission_id, p_catalog_version, p_resolved_dsld_id
  );
  PERFORM public.award_product_contribution_points_internal(p_submission_id);
  RETURN promoted;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_product_submission_promoted(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_product_submission_promoted(uuid,text,text)
  TO service_role;

-- Backfill through the one award rule.
SELECT public.award_product_contribution_points_internal(submission.id)
FROM public.product_submissions AS submission
WHERE submission.promoted_catalog_version IS NOT NULL;

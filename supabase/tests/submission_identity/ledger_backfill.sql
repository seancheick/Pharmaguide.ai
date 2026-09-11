-- Loaded before the ledger migration in a transaction the runner rolls back.
-- These promotions therefore use the old, non-ledger promotion function.
CREATE TABLE fixture.historical_awards (
  submission_id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  promoted_at timestamptz NOT NULL
);
DO $$ DECLARE sid uuid; owner_number integer; BEGIN
  FOR owner_number IN 1..2 LOOP
    sid := fixture.seed(owner_number, CASE owner_number
      WHEN 1 THEN '012345678905' ELSE '030772032565' END, 'under_review', NULL);
    PERFORM fixture.approve(sid);
    PERFORM public.mark_product_submission_promoted(sid, '2026.09.01', '12345');
    UPDATE public.product_submissions SET promoted_at = '2026-09-01T12:00:00Z'
      WHERE id = sid;
    INSERT INTO fixture.historical_awards
      SELECT id, user_id, promoted_at FROM public.product_submissions WHERE id = sid;
  END LOOP;
  -- Neither rejection nor approval without promotion earned points previously.
  PERFORM fixture.seed(4, '012345678905');
  sid := fixture.seed(5, '036000291452', 'under_review', NULL);
  PERFORM fixture.approve(sid);
END $$;

CREATE FUNCTION fixture.check_ledger_backfill() RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  PERFORM fixture.assert((SELECT count(*) FROM public.product_contribution_ledger) = 2,
    'backfill awards only the two historical promotions');
  PERFORM fixture.assert(NOT EXISTS (
    SELECT 1 FROM fixture.historical_awards expected
    LEFT JOIN public.product_contribution_ledger actual
      ON actual.submission_id = expected.submission_id
    WHERE actual.id IS NULL OR actual.user_id <> expected.user_id
      OR actual.points <> 10 OR actual.created_at <> expected.promoted_at
      OR actual.catalog_version <> '2026.09.01'
  ), 'backfill preserves owners, original points, promotion dates and releases');
  PERFORM public.award_product_contribution_points_internal(submission_id)
    FROM fixture.historical_awards;
  PERFORM fixture.assert((SELECT sum(points) FROM public.product_contribution_ledger) = 20,
    'replaying historical awards does not pay twice');
END $$;

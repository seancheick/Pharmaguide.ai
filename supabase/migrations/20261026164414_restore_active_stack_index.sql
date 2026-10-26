-- Restore the existing active-stack index omitted from the historical live schema.
CREATE INDEX IF NOT EXISTS idx_user_stacks_user_active
  ON public.user_stacks(user_id) WHERE deleted_at IS NULL;

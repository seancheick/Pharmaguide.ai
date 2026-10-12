-- Minimal external Supabase surfaces for the AI connector suite. Every app
-- table, policy and function is loaded unchanged from supabase/migrations.
-- The storage stubs mirror supabase/tests/submission_identity/bootstrap.sql,
-- without its pending_products stub (the real table comes from migrations).
CREATE TABLE storage.buckets (
  id text PRIMARY KEY, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
CREATE TABLE storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text,
  owner_id text, metadata jsonb, user_metadata jsonb
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql IMMUTABLE
AS $$ SELECT (string_to_array($1, '/'))[1:array_length(string_to_array($1, '/'), 1)-1] $$;
CREATE FUNCTION storage.filename(text) RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT (string_to_array($1, '/'))[array_length(string_to_array($1, '/'), 1)] $$;

-- The Postgres image ships auth.uid() but not auth.jwt(), which Supabase Auth
-- installs. This is Auth's definition: the request claims PostgREST sets.
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;
GRANT EXECUTE ON FUNCTION auth.jwt() TO PUBLIC;

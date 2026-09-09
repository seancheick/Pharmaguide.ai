-- Minimal external Supabase surfaces. All submission tables, functions, RLS,
-- grants, indexes, and triggers are loaded unchanged from real migrations.
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
CREATE TABLE public.pending_products (id uuid);

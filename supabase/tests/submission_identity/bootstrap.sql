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

-- Pipeline-owned distribution seam required by the correction activation
-- migration. The app suite models only the table/function shape; pipeline
-- tests own the full distribution behavior.
CREATE TABLE public.export_manifest (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  db_version text NOT NULL,
  pipeline_version text NOT NULL,
  scoring_version text NOT NULL,
  schema_version text NOT NULL,
  product_count integer NOT NULL,
  checksum text NOT NULL,
  min_app_version text NOT NULL DEFAULT '1.0.0',
  generated_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  is_current boolean NOT NULL DEFAULT true
);
ALTER TABLE public.export_manifest ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX export_manifest_one_current_fixture
  ON public.export_manifest((true)) WHERE is_current;
CREATE FUNCTION public.rotate_manifest(
  text,text,text,text,integer,text,timestamptz,text
) RETURNS uuid LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;
GRANT EXECUTE ON FUNCTION public.rotate_manifest(
  text,text,text,text,integer,text,timestamptz,text) TO service_role;

-- Minimal Auth JWT surface, shared with the AI connector fixture.
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT coalesce(nullif(current_setting('request.jwt.claim',true),''),
                 nullif(current_setting('request.jwt.claims',true),''))::jsonb
$$;
GRANT EXECUTE ON FUNCTION auth.jwt() TO PUBLIC;

-- Latest submitter RPCs retain the production OAuth-client guard. auth.jwt()
-- is the minimal Auth shape above; the guard body is the production definition.
CREATE OR REPLACE FUNCTION public.reject_oauth_client_request()
RETURNS void LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF (auth.jwt() ->> 'client_id') IS NOT NULL THEN
    RAISE EXCEPTION 'AI assistant connections cannot call this function' USING ERRCODE='42501';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.reject_oauth_client_request() FROM PUBLIC,anon,authenticated;

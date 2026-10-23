-- Durable consent extends the existing connection and pairing owners. No tokens or health data.
BEGIN;
ALTER TABLE public.ai_connections ADD COLUMN oauth_issuer text, ADD COLUMN consent_id text;
ALTER TABLE public.ai_connection_pairings ADD COLUMN oauth_issuer text, ADD COLUMN consent_id text,
 ADD COLUMN created_connection boolean NOT NULL DEFAULT false;
-- Existing completed legacy pairings created their connection; preserve compensation ownership.
UPDATE public.ai_connection_pairings SET created_connection=true WHERE connection_id IS NOT NULL;
ALTER TABLE public.ai_connection_pairing_limits ADD COLUMN revocation_generation integer NOT NULL DEFAULT 0,
 ADD COLUMN revoking_client_id text;
ALTER TABLE public.ai_connections ALTER COLUMN expires_at DROP NOT NULL;
ALTER TABLE public.ai_connection_pairings ALTER COLUMN browser_session_id DROP NOT NULL;
-- WorkOS issuer is an HTTPS origin; the caller additionally pins its configured exact issuer.
ALTER TABLE public.ai_connections ADD CONSTRAINT ai_connections_workos_binding CHECK (
 (oauth_issuer IS NULL AND consent_id IS NULL AND expires_at IS NOT NULL) OR
 (oauth_issuer IS NOT NULL AND oauth_issuer ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'
 AND consent_id IS NOT NULL AND length(btrim(consent_id)) BETWEEN 1 AND 255 AND session_id IS NULL));
ALTER TABLE public.ai_connection_pairings ADD CONSTRAINT ai_pairings_workos_binding CHECK (
 (oauth_issuer IS NULL AND consent_id IS NULL AND browser_session_id IS NOT NULL) OR
 (oauth_issuer IS NOT NULL AND oauth_issuer ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'
 AND consent_id IS NOT NULL AND length(btrim(consent_id)) BETWEEN 1 AND 255));
CREATE UNIQUE INDEX ai_connections_workos_consent_unique ON public.ai_connections(oauth_issuer,consent_id)
 WHERE oauth_issuer IS NOT NULL;
CREATE UNIQUE INDEX ai_pairings_workos_authorization_unique ON public.ai_connection_pairings(authorization_id)
 WHERE oauth_issuer IS NOT NULL;
-- Never reassign a durable identity, including revoked tombstones.
CREATE FUNCTION public.ai_workos_identity_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF OLD.oauth_issuer IS NOT NULL AND (NEW.user_id IS DISTINCT FROM OLD.user_id
 OR NEW.client_id IS DISTINCT FROM OLD.client_id OR NEW.oauth_issuer IS DISTINCT FROM OLD.oauth_issuer
 OR NEW.consent_id IS DISTINCT FROM OLD.consent_id) THEN
 RAISE EXCEPTION 'immutable WorkOS consent identity' USING ERRCODE='23514'; END IF;
 IF TG_TABLE_NAME='ai_connections' THEN
  IF OLD.oauth_issuer IS NOT NULL AND OLD.status='revoked' AND NEW.status<>'revoked' THEN
   RAISE EXCEPTION 'revoked WorkOS consent' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER ai_connections_workos_immutable BEFORE UPDATE ON public.ai_connections
 FOR EACH ROW EXECUTE FUNCTION public.ai_workos_identity_immutable();
CREATE TRIGGER ai_pairings_workos_immutable BEFORE UPDATE ON public.ai_connection_pairings
 FOR EACH ROW EXECUTE FUNCTION public.ai_workos_identity_immutable();
CREATE FUNCTION public.read_ai_connection_generation(p_user_id uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer; BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 INSERT INTO public.ai_connection_pairing_limits(user_id) VALUES(p_user_id) ON CONFLICT DO NOTHING;
 SELECT revocation_generation INTO n FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id;
 RETURN n;
END $$;
CREATE FUNCTION public.register_workos_ai_pairing(p_user_id uuid,p_client_id text,p_oauth_issuer text,
 p_consent_id text,p_client_name text,p_redirect_uri text,p_code_hash text,p_expected_generation integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; host text; aid text; expiry timestamptz;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF p_expected_generation IS NULL OR public.read_ai_connection_generation(p_user_id)<>p_expected_generation
 OR EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 host:=substring(p_redirect_uri FROM '^https?://(\[[^]]+\]|[^/:?#]+)');
 IF p_oauth_issuer IS NULL OR p_oauth_issuer !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'
 OR p_consent_id IS NULL OR length(btrim(p_consent_id)) NOT BETWEEN 1 AND 255
 OR p_client_id IS NULL OR length(btrim(p_client_id)) NOT BETWEEN 1 AND 255
 OR p_client_name IS NULL OR length(btrim(p_client_name)) NOT BETWEEN 1 AND 200
 OR p_redirect_uri IS NULL OR length(p_redirect_uri)>2048 OR host IS NULL OR host LIKE '%@%' OR length(host)>200
 OR p_code_hash IS NULL OR p_code_hash !~ '^[0-9a-f]{64}$'
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- Global consent lock prevents cross-user races before a connection exists.
 PERFORM pg_advisory_xact_lock(hashtextextended('ai-consent:'||p_oauth_issuer||':'||p_consent_id,0));
 IF EXISTS(SELECT FROM public.ai_connections WHERE oauth_issuer=p_oauth_issuer AND consent_id=p_consent_id
 AND (user_id<>p_user_id OR client_id<>p_client_id OR status<>'active' OR revoked_at IS NOT NULL))
 OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE oauth_issuer=p_oauth_issuer AND consent_id=p_consent_id
 AND (user_id<>p_user_id OR client_id<>p_client_id OR cancelled_at IS NOT NULL))
 OR EXISTS(SELECT FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND status='active'
 AND (oauth_issuer IS DISTINCT FROM p_oauth_issuer OR consent_id IS DISTINCT FROM p_consent_id))
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND client_id=p_client_id
 AND oauth_issuer=p_oauth_issuer AND consent_id=p_consent_id AND cancelled_at IS NULL AND consumed_at IS NULL
 AND expires_at>clock_timestamp() ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN jsonb_build_object('authorization_id',r.authorization_id,'expires_at',r.expires_at); END IF;
 IF NOT public.ai_pairing_budget(p_user_id,true) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF EXISTS(SELECT FROM public.ai_connection_pairings WHERE code_hash=p_code_hash) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 aid:=gen_random_uuid()::text;
 INSERT INTO public.ai_connection_pairings(user_id,authorization_id,client_id,client_name,redirect_uri,callback_host,code_hash,oauth_issuer,consent_id)
 VALUES(p_user_id,aid,p_client_id,p_client_name,p_redirect_uri,host,p_code_hash,p_oauth_issuer,p_consent_id)
 RETURNING expires_at INTO expiry;
 RETURN jsonb_build_object('authorization_id',aid,'expires_at',expiry);
END $$;
CREATE FUNCTION public.preview_workos_ai_pairing(p_user_id uuid,p_authorization_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND authorization_id=p_authorization_id
 AND oauth_issuer IS NOT NULL AND cancelled_at IS NULL AND consumed_at IS NULL AND expires_at>clock_timestamp();
 IF NOT FOUND OR EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 RETURN jsonb_build_object('authorization_id',r.authorization_id,'client_id',r.client_id,'client_name',r.client_name,
 'redirect_uri',r.redirect_uri,'callback_host',r.callback_host,'expires_at',r.expires_at,'oauth_issuer',r.oauth_issuer);
END $$;

CREATE OR REPLACE FUNCTION public.start_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,
 p_client_id text,p_client_name text,p_redirect_uri text,p_code_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE expiry timestamptz; host text; r public.ai_connection_pairings;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF NOT public.ai_pairing_live_session(p_user_id,p_session_id::text) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 SELECT * INTO r FROM public.ai_connection_pairings WHERE authorization_id=p_authorization_id AND oauth_issuer IS NOT NULL FOR UPDATE;
 IF FOUND THEN
  IF r.user_id<>p_user_id OR r.cancelled_at IS NOT NULL OR r.consumed_at IS NOT NULL OR r.expires_at<=clock_timestamp()
  OR r.browser_session_id IS NOT NULL OR p_client_id IS DISTINCT FROM r.client_id OR p_redirect_uri IS DISTINCT FROM r.redirect_uri
  OR p_code_hash IS NULL OR p_code_hash !~ '^[0-9a-f]{64}$'
  OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE code_hash=p_code_hash)
  THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  UPDATE public.ai_connection_pairings SET browser_session_id=p_session_id,code_hash=p_code_hash WHERE id=r.id;
  RETURN jsonb_build_object('expires_at',r.expires_at);
 END IF;
 -- A legacy request must not replace or cancel a durable provider consent.
 IF EXISTS(SELECT FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF NOT public.ai_pairing_budget(p_user_id,true) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 host:=substring(p_redirect_uri FROM '^https?://(\[[^]]+\]|[^/:?#]+)');
 IF p_authorization_id IS NULL OR length(btrim(p_authorization_id)) NOT BETWEEN 1 AND 255
 OR p_client_id IS NULL OR length(btrim(p_client_id)) NOT BETWEEN 1 AND 255
 OR p_client_name IS NULL OR length(btrim(p_client_name)) NOT BETWEEN 1 AND 200
 OR p_redirect_uri IS NULL OR length(p_redirect_uri)>2048 OR host IS NULL OR host LIKE '%@%'
 OR length(host)>200 OR p_code_hash IS NULL OR p_code_hash !~ '^[0-9a-f]{64}$'
 OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE code_hash=p_code_hash
 OR (user_id=p_user_id AND browser_session_id=p_session_id AND authorization_id=p_authorization_id))
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 UPDATE public.ai_connection_pairings SET cancelled_at=clock_timestamp()
 WHERE user_id=p_user_id AND client_id=p_client_id AND consumed_at IS NULL AND cancelled_at IS NULL;
 INSERT INTO public.ai_connection_pairings(user_id,browser_session_id,authorization_id,client_id,client_name,redirect_uri,callback_host,code_hash)
 VALUES(p_user_id,p_session_id,p_authorization_id,p_client_id,p_client_name,p_redirect_uri,host,p_code_hash)
 RETURNING expires_at INTO expiry;
 RETURN jsonb_build_object('expires_at',expiry);
END $$;
CREATE OR REPLACE FUNCTION public.complete_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,p_client_id text,p_redirect_uri text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; cid uuid; expiry timestamptz; live_count integer; created boolean:=false;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id
 AND authorization_id=p_authorization_id AND client_id=p_client_id AND redirect_uri=p_redirect_uri FOR UPDATE;
 IF NOT FOUND OR r.expires_at<=clock_timestamp() OR r.cancelled_at IS NOT NULL OR r.consumed_at IS NOT NULL
 OR r.approved_session_id IS NULL OR r.approved_session_id=p_session_id THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- Protect against concurrent session deletion until this transaction commits.
 SELECT count(*) INTO live_count FROM (SELECT id FROM auth.sessions WHERE user_id=p_user_id
 AND id IN(p_session_id,r.approved_session_id) AND oauth_client_id IS NULL
 AND (not_after IS NULL OR not_after>clock_timestamp()) ORDER BY id FOR SHARE) s;
 IF live_count<>2 OR r.expires_at<=clock_timestamp() THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF r.oauth_issuer IS NOT NULL THEN
  SELECT connection_id INTO cid FROM public.ai_connections WHERE oauth_issuer=r.oauth_issuer AND consent_id=r.consent_id
  AND user_id=p_user_id AND client_id=p_client_id AND status='active' AND revoked_at IS NULL FOR UPDATE;
  IF cid IS NULL THEN
   IF EXISTS(SELECT FROM public.ai_connections WHERE (oauth_issuer=r.oauth_issuer AND consent_id=r.consent_id)
    OR (user_id=p_user_id AND client_id=p_client_id AND status='active'))
   THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
   INSERT INTO public.ai_connections(user_id,client_id,client_name,callback_host,scope,expires_at,oauth_issuer,consent_id)
   VALUES(p_user_id,p_client_id,r.client_name,r.callback_host,'{"categories":["supplements"]}',NULL,r.oauth_issuer,r.consent_id)
   RETURNING connection_id INTO cid;
   created:=true;
  END IF;
  UPDATE public.ai_connection_pairings SET consumed_at=clock_timestamp(),connection_id=cid,created_connection=created WHERE id=r.id;
  RETURN jsonb_build_object('connection_id',cid,'expires_at',NULL,'oauth_issuer',r.oauth_issuer);
 END IF;
 IF EXISTS(SELECT FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 DELETE FROM public.ai_share_snapshots WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND status='active');
 DELETE FROM public.mcp_access_log WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND status='active');
 UPDATE public.ai_connections SET status='revoked',revoked_at=clock_timestamp() WHERE user_id=p_user_id AND client_id=p_client_id AND status='active';
 INSERT INTO public.ai_connections(user_id,client_id,client_name,callback_host,scope,created_at,expires_at)
 VALUES(p_user_id,p_client_id,r.client_name,r.callback_host,'{"categories":["supplements"]}',clock_timestamp(),clock_timestamp()+interval '24 hours')
 RETURNING connection_id,expires_at INTO cid,expiry;
 UPDATE public.ai_connection_pairings SET consumed_at=clock_timestamp(),connection_id=cid,created_connection=true WHERE id=r.id;
 RETURN jsonb_build_object('connection_id',cid,'expires_at',expiry);
END $$;
DROP FUNCTION public.cancel_ai_connection_pairing(uuid,uuid,text);
CREATE FUNCTION public.cancel_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; revocation jsonb;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 -- Preview exposes Deny before a phone code attaches the browser. Only the
 -- verified owner's live first-party session may cancel that unbound pending row.
 -- Once attached, cancellation stays bound to the original browser session.
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND authorization_id=p_authorization_id
 AND (browser_session_id=p_session_id OR (oauth_issuer IS NOT NULL AND browser_session_id IS NULL
 AND consumed_at IS NULL AND public.ai_pairing_live_session(p_user_id,p_session_id::text))) FOR UPDATE;
 IF NOT FOUND THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 UPDATE public.ai_connection_pairings SET cancelled_at=coalesce(cancelled_at,clock_timestamp()) WHERE id=r.id;
 -- A repeated WorkOS approval may refer to a pre-existing connection. Only
 -- the pairing which created authority may compensate that authority.
 IF r.created_connection THEN
 -- Compensation after a lost complete response or failed issuer approval is
 -- exact-connection, never the newest connection for that assistant.
 DELETE FROM public.ai_share_snapshots WHERE connection_id=r.connection_id;
 DELETE FROM public.mcp_access_log WHERE connection_id=r.connection_id;
 UPDATE public.ai_connections SET status='revoked',revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE connection_id=r.connection_id;
 END IF;
 -- Provider deletion is client-wide. A cancelled retry never owns authority
 -- created by another pairing, even if that pairing approved a different SID.
 IF r.oauth_issuer IS NULL OR EXISTS(SELECT FROM public.ai_connections
 WHERE user_id=p_user_id AND client_id=r.client_id AND status='active' AND revoked_at IS NULL)
 THEN RETURN '{"cancelled":true}'; END IF;
 revocation:=public.begin_ai_connection_revocation(p_user_id,r.client_id);
 IF revocation ? 'error' THEN RETURN revocation || jsonb_build_object('client_id',r.client_id); END IF;
 RETURN jsonb_build_object('cancelled',true,'client_id',r.client_id,'revocation_generation',revocation->'generation');
END $$;
REVOKE ALL ON FUNCTION public.cancel_ai_connection_pairing(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_ai_connection_pairing(uuid,uuid,text) TO service_role;
CREATE FUNCTION public.ai_revoke_connection_local(p_user_id uuid,p_client_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 UPDATE public.ai_connection_pairings SET cancelled_at=coalesce(cancelled_at,clock_timestamp()) WHERE user_id=p_user_id AND client_id=p_client_id;
 DELETE FROM public.ai_share_snapshots WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id);
 DELETE FROM public.mcp_access_log WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id);
 UPDATE public.ai_connections SET status='revoked',revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE user_id=p_user_id AND client_id=p_client_id AND status='active';
END $$;
CREATE FUNCTION public.begin_ai_connection_revocation(p_user_id uuid,p_client_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer; current_client text; BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 n:=public.read_ai_connection_generation(p_user_id);
 SELECT revoking_client_id INTO current_client FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id;
 IF current_client IS NOT NULL AND current_client<>p_client_id THEN RETURN '{"error":"revocation_pending"}'; END IF;
 IF p_client_id IS NULL OR length(btrim(p_client_id)) NOT BETWEEN 1 AND 255 THEN RETURN '{"error":"revocation_unavailable"}'; END IF;
 IF current_client IS NULL THEN
  UPDATE public.ai_connection_pairing_limits SET revocation_generation=revocation_generation+1,revoking_client_id=p_client_id
  WHERE user_id=p_user_id RETURNING revocation_generation INTO n;
 END IF;
 PERFORM public.ai_revoke_connection_local(p_user_id,p_client_id);
 RETURN jsonb_build_object('generation',n);
END $$;
CREATE FUNCTION public.finish_ai_connection_revocation(p_user_id uuid,p_client_id text,p_expected_generation integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 UPDATE public.ai_connection_pairing_limits SET revoking_client_id=NULL
 WHERE user_id=p_user_id AND revoking_client_id=p_client_id AND revocation_generation=p_expected_generation;
 IF NOT FOUND THEN RETURN '{"error":"revocation_unavailable"}'; END IF;
 RETURN '{"finished":true}';
END $$;
CREATE OR REPLACE FUNCTION public.revoke_ai_connection_pairings(p_user_id uuid,p_client_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF EXISTS(SELECT FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 OR EXISTS(SELECT FROM public.ai_connection_pairings WHERE user_id=p_user_id AND client_id=p_client_id AND oauth_issuer IS NOT NULL)
 THEN PERFORM public.begin_ai_connection_revocation(p_user_id,p_client_id); RETURN; END IF;
 PERFORM public.read_ai_connection_generation(p_user_id);
 UPDATE public.ai_connection_pairing_limits SET revocation_generation=revocation_generation+1 WHERE user_id=p_user_id AND revoking_client_id IS NULL;
 PERFORM public.ai_revoke_connection_local(p_user_id,p_client_id);
END $$;
REVOKE ALL ON FUNCTION public.ai_workos_identity_immutable(),public.ai_revoke_connection_local(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_ai_connection_generation(uuid),public.register_workos_ai_pairing(uuid,text,text,text,text,text,text,integer),public.preview_workos_ai_pairing(uuid,text),public.begin_ai_connection_revocation(uuid,text),public.finish_ai_connection_revocation(uuid,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_connection_generation(uuid),public.register_workos_ai_pairing(uuid,text,text,text,text,text,text,integer),public.preview_workos_ai_pairing(uuid,text),public.begin_ai_connection_revocation(uuid,text),public.finish_ai_connection_revocation(uuid,text,integer) TO service_role;
COMMIT;

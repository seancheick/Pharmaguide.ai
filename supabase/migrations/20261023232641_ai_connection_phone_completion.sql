-- Complete WorkOS approval on the phone; legacy OAuth remains two-step.
BEGIN;
CREATE OR REPLACE FUNCTION public.complete_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,p_client_id text,p_redirect_uri text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; cid uuid; expiry timestamptz; live_count integer; created boolean:=false;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id
 AND authorization_id=p_authorization_id AND client_id=p_client_id AND redirect_uri=p_redirect_uri FOR UPDATE;
 IF NOT FOUND OR r.cancelled_at IS NOT NULL
 OR r.approved_session_id IS NULL OR r.approved_session_id=p_session_id THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- Protect against concurrent session deletion until this transaction commits.
 SELECT count(*) INTO live_count FROM (SELECT id FROM auth.sessions WHERE user_id=p_user_id
 AND id IN(p_session_id,r.approved_session_id) AND oauth_client_id IS NULL
 AND (not_after IS NULL OR not_after>clock_timestamp()) ORDER BY id FOR SHARE) s;
 IF live_count<>2 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- A completed WorkOS challenge is a receipt, not a new grant. Returning it
 -- never creates, resets or revives authority and no longer depends on code TTL.
 IF r.consumed_at IS NOT NULL THEN
  IF r.oauth_issuer IS NULL THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  SELECT connection_id,expires_at INTO cid,expiry FROM public.ai_connections
  WHERE connection_id=r.connection_id AND user_id=p_user_id AND client_id=r.client_id
  AND oauth_issuer=r.oauth_issuer AND consent_id=r.consent_id
  AND status='active' AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>clock_timestamp()) FOR SHARE;
  IF NOT FOUND THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  RETURN jsonb_build_object('connection_id',cid,'expires_at',expiry,'oauth_issuer',r.oauth_issuer);
 END IF;
 IF r.expires_at<=clock_timestamp() THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
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

CREATE OR REPLACE FUNCTION public.ai_pairing_phone(p_code text,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id'; canonical text; r public.ai_connection_pairings; completion jsonb;
BEGIN
 IF u IS NULL OR auth.jwt()->>'client_id' IS NOT NULL
 OR coalesce(auth.jwt()->>'is_anonymous','false')<>'false' OR NOT public.ai_pairing_live_session(u,sid)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF NOT public.ai_pairing_budget(u,false) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF p_code IS NULL OR length(p_code)>100 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 canonical:=upper(regexp_replace(p_code,'[-[:space:]]','','g'));
 IF canonical !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$' THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=u
 AND code_hash=encode(extensions.digest(canonical,'sha256'),'hex') FOR UPDATE;
 IF NOT FOUND OR r.browser_session_id::text=sid OR r.cancelled_at IS NOT NULL
 OR (r.consumed_at IS NULL AND r.expires_at<=clock_timestamp()) OR NOT public.ai_pairing_live_session(u,sid)
 OR NOT public.ai_pairing_live_session(u,r.browser_session_id::text)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- A lost phone response may retry only from the exact approving session.
 IF r.consumed_at IS NOT NULL THEN
  IF r.oauth_issuer IS NULL OR p_action<>'approve' OR r.approved_session_id::text IS DISTINCT FROM sid
  THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  completion:=public.complete_ai_connection_pairing(u,r.browser_session_id,r.authorization_id,r.client_id,r.redirect_uri);
  IF completion ? 'error' THEN RETURN completion; END IF;
  RETURN completion || '{"approved":true}'::jsonb;
 END IF;
 IF p_action='preview'  THEN RETURN jsonb_build_object('client_name',r.client_name,'callback_host',r.callback_host,'expires_at',r.expires_at);
 ELSIF p_action='approve' THEN
  IF r.approved_session_id IS NOT NULL AND r.approved_session_id::text<>sid THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  UPDATE public.ai_connection_pairings SET approved_session_id=sid::uuid WHERE id=r.id;
  IF r.oauth_issuer IS NOT NULL THEN
   completion:=public.complete_ai_connection_pairing(u,r.browser_session_id,r.authorization_id,r.client_id,r.redirect_uri);
   IF completion ? 'error' THEN
    UPDATE public.ai_connection_pairings SET approved_session_id=r.approved_session_id WHERE id=r.id;
    RETURN completion;
   END IF;
   RETURN completion || '{"approved":true}'::jsonb;
  END IF;
  RETURN '{"approved":true}';
 ELSIF p_action='cancel' THEN
  UPDATE public.ai_connection_pairings SET cancelled_at=clock_timestamp() WHERE id=r.id;
  RETURN '{"cancelled":true}';
 END IF;
 RETURN '{"error":"pairing_unavailable"}';
END $$;

CREATE OR REPLACE FUNCTION public.ai_connection_pairing_status(p_user_id uuid,p_session_id uuid,p_authorization_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; completion jsonb;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id AND authorization_id=p_authorization_id;
 IF NOT FOUND OR r.cancelled_at IS NOT NULL
 OR NOT public.ai_pairing_live_session(p_user_id,p_session_id::text)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF r.consumed_at IS NOT NULL THEN
  completion:=public.complete_ai_connection_pairing(p_user_id,p_session_id,r.authorization_id,r.client_id,r.redirect_uri);
  IF completion ? 'error' THEN RETURN completion; END IF;
  RETURN jsonb_build_object('approved',true,'connection_id',r.connection_id,'expires_at',r.expires_at);
 END IF;
 IF r.expires_at<=clock_timestamp() THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 RETURN jsonb_build_object('approved' ,r.approved_session_id IS NOT NULL AND public.ai_pairing_live_session(p_user_id,r.approved_session_id::text),'expires_at',r.expires_at);
END $$;

CREATE OR REPLACE FUNCTION public.preview_workos_ai_pairing(p_user_id uuid,p_authorization_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; completion jsonb; BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND authorization_id=p_authorization_id
 AND oauth_issuer IS NOT NULL AND cancelled_at IS NULL;
 IF NOT FOUND OR EXISTS(SELECT FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id AND revoking_client_id IS NOT NULL)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF r.consumed_at IS NOT NULL THEN
  completion:=public.complete_ai_connection_pairing(p_user_id,r.browser_session_id,r.authorization_id,r.client_id,r.redirect_uri);
  IF completion ? 'error' THEN RETURN completion; END IF;
 ELSIF r.expires_at<=clock_timestamp() THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 RETURN jsonb_build_object('authorization_id' ,r.authorization_id,'client_id',r.client_id,'client_name',r.client_name,
 'redirect_uri',r.redirect_uri,'callback_host',r.callback_host,'expires_at',r.expires_at,'oauth_issuer',r.oauth_issuer) || CASE WHEN r.consumed_at IS NOT NULL THEN jsonb_build_object('connection_id',r.connection_id) ELSE '{}'::jsonb END;
END $$;

-- The storage owner closes the findConnection -> upload race. Writers and
-- revokers serialize on the same user lock, including direct PostgREST upserts.
CREATE FUNCTION public.ai_share_snapshot_live_connection() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.ai_connections;
BEGIN
 PERFORM public.ai_pairing_lock(NEW.user_id);
 SELECT * INTO c FROM public.ai_connections WHERE connection_id=NEW.connection_id AND user_id=NEW.user_id FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'snapshot connection owner mismatch' USING ERRCODE='23503'; END IF;
 IF c.status<>'active' OR c.revoked_at IS NOT NULL OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'snapshot connection unavailable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER ai_share_snapshot_live_connection BEFORE INSERT OR UPDATE ON public.ai_share_snapshots
 FOR EACH ROW EXECUTE FUNCTION public.ai_share_snapshot_live_connection();
REVOKE ALL ON FUNCTION public.ai_share_snapshot_live_connection() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;

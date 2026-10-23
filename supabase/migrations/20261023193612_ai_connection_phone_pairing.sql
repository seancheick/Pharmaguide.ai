-- Publish schema and final RPC privileges atomically, including plain psql.
BEGIN;
-- S6 protocol state only. No raw pairing code, tokens or health payloads.
-- Not deployed: issuer containment and rollout flags remain unchanged.
CREATE TABLE public.ai_connection_pairings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 browser_session_id uuid NOT NULL,
 authorization_id text NOT NULL CHECK(length(authorization_id) BETWEEN 1 AND 255),
 client_id text NOT NULL CHECK(length(client_id) BETWEEN 1 AND 255),
 client_name text NOT NULL CHECK(length(btrim(client_name)) BETWEEN 1 AND 200),
 redirect_uri text NOT NULL CHECK(length(redirect_uri) BETWEEN 1 AND 2048),
 callback_host text NOT NULL CHECK(length(callback_host) BETWEEN 1 AND 200),
 code_hash text NOT NULL UNIQUE CHECK(code_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT (clock_timestamp()+interval '5 minutes'),
 approved_session_id uuid,
 consumed_at timestamptz,
 cancelled_at timestamptz,
 connection_id uuid REFERENCES public.ai_connections(connection_id) ON DELETE SET NULL,
 UNIQUE(user_id,browser_session_id,authorization_id)
);
CREATE INDEX ai_connection_pairings_user_client ON public.ai_connection_pairings(user_id,client_id);
-- A fixed-size counter row per user, shared across all sessions. Failures
-- return JSON instead of raising, so PostgREST commits these counters.
CREATE TABLE public.ai_connection_pairing_limits (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 start_window timestamptz NOT NULL DEFAULT clock_timestamp(),
 starts integer NOT NULL DEFAULT 0,
 lookup_window timestamptz NOT NULL DEFAULT clock_timestamp(),
 lookups integer NOT NULL DEFAULT 0
);
ALTER TABLE public.ai_connection_pairings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_connection_pairing_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_connection_pairings,public.ai_connection_pairing_limits FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.ai_connection_pairings,public.ai_connection_pairing_limits TO service_role;

-- All mutators use this same user lock, including disconnect. Locking the
-- whole user is deliberately stronger than (user,client), bounding rates too.
CREATE FUNCTION public.ai_pairing_lock(p_user uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT pg_advisory_xact_lock(hashtextextended('ai-pairing:'||p_user::text,0))
$$;
CREATE FUNCTION public.ai_pairing_live_session(p_user uuid,p_session text) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT FROM auth.sessions s WHERE s.id::text=p_session AND s.user_id=p_user
 AND s.oauth_client_id IS NULL AND (s.not_after IS NULL OR s.not_after>clock_timestamp()))
$$;
CREATE FUNCTION public.ai_pairing_budget(p_user uuid,p_start boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer;
BEGIN
 PERFORM public.ai_pairing_lock(p_user);
 INSERT INTO public.ai_connection_pairing_limits(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 IF p_start THEN
  UPDATE public.ai_connection_pairing_limits SET
   starts=CASE WHEN start_window<=clock_timestamp()-interval '10 minutes' THEN 1 ELSE least(starts+1,6) END,
   start_window=CASE WHEN start_window<=clock_timestamp()-interval '10 minutes' THEN clock_timestamp() ELSE start_window END
  WHERE user_id=p_user RETURNING starts INTO n;
  RETURN n<=5;
 ELSE
  UPDATE public.ai_connection_pairing_limits SET
   lookups=CASE WHEN lookup_window<=clock_timestamp()-interval '10 minutes' THEN 1 ELSE least(lookups+1,21) END,
   lookup_window=CASE WHEN lookup_window<=clock_timestamp()-interval '10 minutes' THEN clock_timestamp() ELSE lookup_window END
  WHERE user_id=p_user RETURNING lookups INTO n;
  RETURN n<=20;
 END IF;
END $$;
CREATE FUNCTION public.start_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,
 p_client_id text,p_client_name text,p_redirect_uri text,p_code_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE expiry timestamptz; host text;
BEGIN
 IF NOT public.ai_pairing_live_session(p_user_id,p_session_id::text) THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
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

-- Internal implementation shared by authenticated preview/approve/cancel.
-- Callers cannot choose a user/session or invoke this helper directly.
CREATE FUNCTION public.ai_pairing_phone(p_code text,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id'; canonical text; r public.ai_connection_pairings;
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
 IF NOT FOUND OR r.browser_session_id::text=sid OR r.consumed_at IS NOT NULL OR r.cancelled_at IS NOT NULL
 OR r.expires_at<=clock_timestamp() OR NOT public.ai_pairing_live_session(u,sid)
 OR NOT public.ai_pairing_live_session(u,r.browser_session_id::text)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 IF p_action='preview' THEN RETURN jsonb_build_object('client_name',r.client_name,'callback_host',r.callback_host,'expires_at',r.expires_at);
 ELSIF p_action='approve' THEN
  IF r.approved_session_id IS NOT NULL AND r.approved_session_id::text<>sid THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
  UPDATE public.ai_connection_pairings SET approved_session_id=sid::uuid WHERE id=r.id;
  RETURN '{"approved":true}';
 ELSIF p_action='cancel' THEN
  UPDATE public.ai_connection_pairings SET cancelled_at=clock_timestamp() WHERE id=r.id;
  RETURN '{"cancelled":true}';
 END IF;
 RETURN '{"error":"pairing_unavailable"}';
END $$;
CREATE FUNCTION public.preview_ai_connection_pairing(p_code text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT public.ai_pairing_phone(p_code,'preview') $$;
CREATE FUNCTION public.approve_ai_connection_pairing(p_code text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT public.ai_pairing_phone(p_code,'approve') $$;
CREATE FUNCTION public.cancel_my_ai_connection_pairing(p_code text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT public.ai_pairing_phone(p_code,'cancel') $$;

CREATE FUNCTION public.ai_connection_pairing_status(p_user_id uuid,p_session_id uuid,p_authorization_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id AND authorization_id=p_authorization_id;
 IF NOT FOUND OR r.expires_at<=clock_timestamp() OR r.cancelled_at IS NOT NULL OR r.consumed_at IS NOT NULL
 OR NOT public.ai_pairing_live_session(p_user_id,p_session_id::text)
 THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 RETURN jsonb_build_object('approved',r.approved_session_id IS NOT NULL AND public.ai_pairing_live_session(p_user_id,r.approved_session_id::text),'expires_at',r.expires_at);
END $$;

CREATE FUNCTION public.complete_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text,p_client_id text,p_redirect_uri text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings; cid uuid; expiry timestamptz; live_count integer;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id
 AND authorization_id=p_authorization_id AND client_id=p_client_id AND redirect_uri=p_redirect_uri FOR UPDATE;
 IF NOT FOUND OR r.expires_at<=clock_timestamp() OR r.cancelled_at IS NOT NULL OR r.consumed_at IS NOT NULL
 OR r.approved_session_id IS NULL OR r.approved_session_id=p_session_id THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 -- Protect against concurrent session deletion until this transaction commits.
 SELECT count(*) INTO live_count FROM (SELECT id FROM auth.sessions WHERE user_id=p_user_id
 AND id IN(p_session_id,r.approved_session_id) AND oauth_client_id IS NULL
 AND (not_after IS NULL OR not_after>clock_timestamp()) ORDER BY id FOR SHARE) s;
 IF live_count<>2 OR r.expires_at<=clock_timestamp() THEN RETURN '{"error":"pairing_unavailable"}'; END IF;
 DELETE FROM public.ai_share_snapshots WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND status='active');
 DELETE FROM public.mcp_access_log WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id AND status='active');
 UPDATE public.ai_connections SET status='revoked',revoked_at=clock_timestamp() WHERE user_id=p_user_id AND client_id=p_client_id AND status='active';
 INSERT INTO public.ai_connections(user_id,client_id,client_name,callback_host,scope,created_at,expires_at)
 VALUES(p_user_id,p_client_id,r.client_name,r.callback_host,'{"categories":["supplements"]}',clock_timestamp(),clock_timestamp()+interval '24 hours')
 RETURNING connection_id,expires_at INTO cid,expiry;
 UPDATE public.ai_connection_pairings SET consumed_at=clock_timestamp(),connection_id=cid WHERE id=r.id;
 RETURN jsonb_build_object('connection_id',cid,'expires_at',expiry);
END $$;

CREATE FUNCTION public.cancel_ai_connection_pairing(p_user_id uuid,p_session_id uuid,p_authorization_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ai_connection_pairings;
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 SELECT * INTO r FROM public.ai_connection_pairings WHERE user_id=p_user_id AND browser_session_id=p_session_id AND authorization_id=p_authorization_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 UPDATE public.ai_connection_pairings SET cancelled_at=coalesce(cancelled_at,clock_timestamp()) WHERE id=r.id;
 -- Compensation after a lost complete response or failed issuer approval is
 -- exact-connection, never the newest connection for that assistant.
 DELETE FROM public.ai_share_snapshots WHERE connection_id=r.connection_id;
 DELETE FROM public.mcp_access_log WHERE connection_id=r.connection_id;
 UPDATE public.ai_connections SET status='revoked',revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE connection_id=r.connection_id;
END $$;
CREATE FUNCTION public.revoke_ai_connection_pairings(p_user_id uuid,p_client_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 UPDATE public.ai_connection_pairings SET cancelled_at=coalesce(cancelled_at,clock_timestamp()) WHERE user_id=p_user_id AND client_id=p_client_id;
 DELETE FROM public.ai_share_snapshots WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id);
 DELETE FROM public.mcp_access_log WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND client_id=p_client_id);
 UPDATE public.ai_connections SET status='revoked',revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE user_id=p_user_id AND client_id=p_client_id AND status='active';
END $$;

REVOKE ALL ON FUNCTION public.ai_pairing_lock(uuid),public.ai_pairing_live_session(uuid,text),public.ai_pairing_budget(uuid,boolean),public.ai_pairing_phone(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.start_ai_connection_pairing(uuid,uuid,text,text,text,text,text),public.ai_connection_pairing_status(uuid,uuid,text),public.complete_ai_connection_pairing(uuid,uuid,text,text,text),public.cancel_ai_connection_pairing(uuid,uuid,text),public.revoke_ai_connection_pairings(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.start_ai_connection_pairing(uuid,uuid,text,text,text,text,text),public.ai_connection_pairing_status(uuid,uuid,text),public.complete_ai_connection_pairing(uuid,uuid,text,text,text),public.cancel_ai_connection_pairing(uuid,uuid,text),public.revoke_ai_connection_pairings(uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.preview_ai_connection_pairing(text),public.approve_ai_connection_pairing(text),public.cancel_my_ai_connection_pairing(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_ai_connection_pairing(text),public.approve_ai_connection_pairing(text),public.cancel_my_ai_connection_pairing(text) TO authenticated;

COMMIT;

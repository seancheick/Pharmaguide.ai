-- Account deletion extends the existing
-- per-user revocation barrier; no new table, queue, or auth owner.
BEGIN;
CREATE OR REPLACE FUNCTION public.ai_revoke_connection_local(p_user_id uuid,p_client_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 UPDATE public.ai_connection_pairings SET cancelled_at=coalesce(cancelled_at,clock_timestamp()) WHERE user_id=p_user_id AND (p_client_id IS NULL OR client_id=p_client_id);
 DELETE FROM public.ai_share_snapshots WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND (p_client_id IS NULL OR client_id=p_client_id));
 DELETE FROM public.mcp_access_log WHERE connection_id IN(SELECT connection_id FROM public.ai_connections WHERE user_id=p_user_id AND (p_client_id IS NULL OR client_id=p_client_id));
 UPDATE public.ai_connections SET status='revoked',revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE user_id=p_user_id AND (p_client_id IS NULL OR client_id=p_client_id) AND status='active';
END $$;
CREATE OR REPLACE FUNCTION public.begin_ai_connection_revocation(p_user_id uuid,p_client_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer; current_client text; deletion_barrier constant text:=repeat('!',256); BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 n:=public.read_ai_connection_generation(p_user_id);
 SELECT revoking_client_id INTO current_client FROM public.ai_connection_pairing_limits WHERE user_id=p_user_id;
 -- NULL is account-wide deletion. The 256-character sentinel is outside the
 -- accepted client-ID length. Only auth-user deletion may clear this barrier.
 IF p_client_id IS NULL THEN
  IF current_client IS DISTINCT FROM deletion_barrier THEN
   UPDATE public.ai_connection_pairing_limits SET revocation_generation=revocation_generation+1,revoking_client_id=deletion_barrier
   WHERE user_id=p_user_id RETURNING revocation_generation INTO n;
  END IF;
  PERFORM public.ai_revoke_connection_local(p_user_id,NULL);
  RETURN jsonb_build_object('generation',n);
 END IF;
 IF current_client IS NOT NULL AND current_client<>p_client_id THEN RETURN '{"error":"revocation_pending"}'; END IF;
 IF p_client_id IS NULL OR length(btrim(p_client_id)) NOT BETWEEN 1 AND 255 THEN RETURN '{"error":"revocation_unavailable"}'; END IF;
 IF current_client IS NULL THEN
  UPDATE public.ai_connection_pairing_limits SET revocation_generation=revocation_generation+1,revoking_client_id=p_client_id
  WHERE user_id=p_user_id RETURNING revocation_generation INTO n;
 END IF;
 PERFORM public.ai_revoke_connection_local(p_user_id,p_client_id);
 RETURN jsonb_build_object('generation',n);
END $$;
CREATE OR REPLACE FUNCTION public.finish_ai_connection_revocation(p_user_id uuid,p_client_id text,p_expected_generation integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 PERFORM public.ai_pairing_lock(p_user_id);
 IF p_client_id IS NULL OR length(p_client_id)>255 THEN RETURN '{"error":"revocation_unavailable"}'; END IF;
 UPDATE public.ai_connection_pairing_limits SET revoking_client_id=NULL
 WHERE user_id=p_user_id AND revoking_client_id=p_client_id AND revocation_generation=p_expected_generation;
 IF NOT FOUND THEN RETURN '{"error":"revocation_unavailable"}'; END IF;
 RETURN '{"finished":true}';
END $$;
COMMIT;

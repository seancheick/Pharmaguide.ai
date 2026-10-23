-- S6 pairing lifecycle; deliberately uses separate committed calls so failed
-- lookups cannot hide rolled-back rate counters.
SELECT aic.assert(to_regprocedure('public.start_ai_connection_pairing(uuid,uuid,text,text,text,text,text)') IS NOT NULL,
 'phone pairing service seam exists');
CREATE FUNCTION aic.phone(p_user integer, p_session integer, p_oauth boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
 PERFORM aic.act_as(aic.user_id(p_user), CASE WHEN p_oauth THEN 'evil' ELSE NULL END);
 PERFORM set_config('request.jwt.claims', (auth.jwt() || jsonb_build_object('session_id', aic.user_id(p_session)))::text, true);
END $$;
INSERT INTO auth.sessions(id,user_id,created_at) VALUES
 (aic.user_id(101),aic.user_id(1),now()),(aic.user_id(102),aic.user_id(1),now()),
 (aic.user_id(103),aic.user_id(2),now());
INSERT INTO auth.sessions(id,user_id,created_at,oauth_client_id) VALUES(aic.user_id(104),aic.user_id(1),now(),aic.user_id(999));
CREATE FUNCTION aic.pair_start(p_auth text, p_code text, p_client text DEFAULT 'pair-client') RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),p_auth,p_client,'Verified Codex','https://chatgpt.com/callback',encode(extensions.digest(p_code,'sha256'),'hex')) $$;
SELECT aic.assert(aic.pair_start('a1','ABCDEFGHJKLM') ? 'expires_at','start succeeds');
SELECT aic.assert((SELECT expires_at-created_at BETWEEN interval '299 seconds' AND interval '301 seconds' FROM public.ai_connection_pairings WHERE authorization_id='a1'),'five minute TTL');
-- Privileges and no raw-code persistence.
SELECT aic.assert(NOT has_table_privilege('authenticated','public.ai_connection_pairings','SELECT'), 'no direct pairing read');
SELECT aic.assert(NOT has_function_privilege('authenticated','public.start_ai_connection_pairing(uuid,uuid,text,text,text,text,text)','EXECUTE'), 'start service only');
SELECT aic.assert(NOT has_function_privilege('authenticated','public.complete_ai_connection_pairing(uuid,uuid,text,text,text)','EXECUTE'), 'complete service only');
SELECT aic.assert(NOT has_function_privilege('anon','public.approve_ai_connection_pairing(text)','EXECUTE'), 'no anonymous approval');
SELECT aic.assert(NOT has_function_privilege('authenticated','public.ai_connection_pairing_status(uuid,uuid,text)','EXECUTE') AND NOT has_function_privilege('authenticated','public.cancel_ai_connection_pairing(uuid,uuid,text)','EXECUTE') AND NOT has_function_privilege('authenticated','public.revoke_ai_connection_pairings(uuid,text)','EXECUTE'),'status and service cancellation private');
SELECT aic.assert(NOT has_function_privilege('authenticated','public.ai_pairing_phone(text,text)','EXECUTE'),'phone internal helper private');
SELECT aic.assert(NOT EXISTS(SELECT FROM information_schema.columns WHERE table_name='ai_connection_pairings' AND column_name='code'),'no raw code column');
BEGIN;
SELECT aic.phone(1,101);
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','browser cannot self approve');
COMMIT;
BEGIN;
SELECT aic.phone(2,103);
SELECT aic.assert(public.preview_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','wrong account cannot preview');
COMMIT;
BEGIN;
SELECT aic.phone(1,102,true);
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','OAuth denied');
COMMIT;
BEGIN;
SELECT aic.phone(1,102);
SELECT set_config('request.jwt.claims',(auth.jwt() || '{"is_anonymous":true}'::jsonb)::text,true);
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','anonymous account denied');
COMMIT;
BEGIN;
SELECT aic.phone(1,105);
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','nonexistent session denied');
COMMIT;
BEGIN;
SELECT aic.phone(1,104);
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM') ? 'error','live OAuth session denied even without client claim');
COMMIT;
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.preview_ai_connection_pairing('ABCDEFGHIJKL') ? 'error','ambiguous I outside alphabet rejected');
SELECT aic.assert(public.preview_ai_connection_pairing('ABCDEFGHJKL') ? 'error','short code rejected');
SELECT aic.assert(public.preview_ai_connection_pairing('ABCDEFGHJKLMN') ? 'error','long code rejected');
SELECT aic.assert(public.preview_ai_connection_pairing('abcd-efgh jklm')->>'client_name'='Verified Codex','canonical code and verified preview');
SELECT aic.assert(public.approve_ai_connection_pairing('ABCDEFGHJKLM')->>'approved'='true','phone approval');
COMMIT;
SELECT aic.assert(public.ai_connection_pairing_status(aic.user_id(1),aic.user_id(101),'a1')->>'approved'='true','approved status');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a1','pair-client','https://evil.test') ? 'error','callback exact');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(102),'a1','pair-client','https://chatgpt.com/callback') ? 'error','browser session exact');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a1','wrong-client','https://chatgpt.com/callback') ? 'error','client exact');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a1','pair-client','https://chatgpt.com/callback') ? 'connection_id','atomic completion');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a1','pair-client','https://chatgpt.com/callback') ? 'error','single use');
SELECT aic.assert((SELECT scope='{"categories":["supplements"]}'::jsonb AND client_name='Verified Codex' AND callback_host='chatgpt.com' FROM public.ai_connections WHERE client_id='pair-client' AND status='active'),'only existing scope and verified metadata');
SELECT aic.assert(aic.pair_start('a2','BCDEFGHJKLMN') ? 'expires_at','second start');
BEGIN;
SELECT aic.phone(1,102);
SELECT public.approve_ai_connection_pairing('BCDEFGHJKLMN');
COMMIT;
DELETE FROM auth.sessions WHERE id=aic.user_id(102);
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a2','pair-client','https://chatgpt.com/callback') ? 'error','deleted phone session invalidates completion');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES(aic.user_id(102),aic.user_id(1),now());
SELECT public.revoke_ai_connection_pairings(aic.user_id(1),'pair-client');
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a2','pair-client','https://chatgpt.com/callback') ? 'error','disconnect invalidates pending approval');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='pair-client' AND status='active'),'disconnect atomically revokes connection');
SELECT aic.assert(aic.pair_start('a3','CDEFGHJKLMNP') ? 'expires_at','cancel fixture');
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.cancel_my_ai_connection_pairing('CDEFGHJKLMNP')->>'cancelled'='true','phone cancellation');
COMMIT;
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a3','pair-client','https://chatgpt.com/callback') ? 'error','cancel prevents completion');
SELECT aic.assert(aic.pair_start('a4','DEFGHJKLMNPQ') ? 'expires_at','expiry fixture');
UPDATE public.ai_connection_pairings SET expires_at=clock_timestamp()-interval '1 second' WHERE authorization_id='a4';
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.approve_ai_connection_pairing('DEFGHJKLMNPQ') ? 'error','expired code denied');
COMMIT;
SELECT aic.assert(aic.pair_start('a5','EFGHJKLMNPQR') ? 'expires_at','fifth start allowed');
SELECT aic.assert(aic.pair_start('a6','FGHJKLMNPQRS') ? 'error','sixth start rate limited');
-- Invalid codes persist failed attempts and cap future correct-code requests.
DO $$ BEGIN FOR i IN 1..20 LOOP
 PERFORM aic.phone(1,102);
 PERFORM public.preview_ai_connection_pairing('AAAAAAAAAAAA');
END LOOP; END $$;
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.preview_ai_connection_pairing('EFGHJKLMNPQR') ? 'error','durable user lookup budget exhausted');
COMMIT;
SELECT aic.assert((SELECT lookups=21 AND starts=6 FROM public.ai_connection_pairing_limits WHERE user_id=aic.user_id(1)), 'failed budgets persisted across committed requests');
-- Reset the window by advancing fixture time, not by bypassing a caller guard.
UPDATE public.ai_connection_pairing_limits SET start_window=now()-interval '11 minutes',lookup_window=now()-interval '11 minutes' WHERE user_id=aic.user_id(1);
SELECT aic.assert(aic.pair_start('a7','GHJKLMNPQRST') ? 'expires_at','window reset');
BEGIN;
SELECT aic.phone(1,102);
SELECT public.approve_ai_connection_pairing('GHJKLMNPQRST');
COMMIT;
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=aic.user_id(101);
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a7','pair-client','https://chatgpt.com/callback') ? 'error','expired browser session denied at completion');
UPDATE auth.sessions SET not_after=NULL WHERE id=aic.user_id(101);
DELETE FROM auth.sessions WHERE id=aic.user_id(101);
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a7','pair-client','https://chatgpt.com/callback') ? 'error','deleted browser session denied at completion');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES(aic.user_id(101),aic.user_id(1),now());
-- Forced storage failure verifies connection creation cannot consume a code.
CREATE FUNCTION aic.fail_pair_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.client_id='pair-client' THEN RAISE EXCEPTION 'fixture write failure' USING ERRCODE='Z0002'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aic_fail_pair BEFORE INSERT ON public.ai_connections FOR EACH ROW EXECUTE FUNCTION aic.fail_pair_insert();
DO $$ DECLARE failed boolean:=false; BEGIN
 BEGIN PERFORM public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a7','pair-client','https://chatgpt.com/callback');
 EXCEPTION WHEN SQLSTATE 'Z0002' THEN failed:=true; END;
 PERFORM aic.assert(failed,'insert failure exercised');
 PERFORM aic.assert((SELECT consumed_at IS NULL FROM public.ai_connection_pairings WHERE authorization_id='a7'),'insert rollback preserves unconsumed pairing');
END $$;
DROP TRIGGER aic_fail_pair ON public.ai_connections;
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a7','pair-client','https://chatgpt.com/callback') ? 'connection_id','retry after storage rollback');
SELECT aic.assert(aic.pair_start('a8','HJKLMNPQRSTU') ? 'expires_at','replacement fixture');
BEGIN;
SELECT aic.phone(1,102);
SELECT public.approve_ai_connection_pairing('HJKLMNPQRSTU');
COMMIT;
SELECT aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a8','pair-client','https://chatgpt.com/callback') ? 'connection_id','replacement completes');
SELECT public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a7');
SELECT aic.assert((SELECT c.status='active' FROM public.ai_connections c JOIN public.ai_connection_pairings p USING(connection_id) WHERE p.authorization_id='a8'),'old compensation does not revoke newer connection');
SELECT public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a8');
SELECT public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'a8');
SELECT aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='pair-client' AND status='active'),'consumed compensation idempotently revokes exact connection');
-- Prepared for the harness's overlapping two-session completion test.
SELECT aic.assert(aic.pair_start('race','JKLMNPQRSTUV') ? 'expires_at','concurrent fixture');
BEGIN;
SELECT aic.phone(1,102);
SELECT public.approve_ai_connection_pairing('JKLMNPQRSTUV');
COMMIT;

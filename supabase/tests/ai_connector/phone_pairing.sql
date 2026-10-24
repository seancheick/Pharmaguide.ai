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
 IF NEW.client_id IN('pair-client','phone-atomic-client') THEN RAISE EXCEPTION 'fixture write failure' USING ERRCODE='Z0002'; END IF;
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

-- Durable WorkOS registration is service-only and creates no authority.
SELECT aic.assert(to_regprocedure('public.read_ai_connection_generation(uuid)') IS NOT NULL,'WorkOS generation seam exists');
CREATE FUNCTION aic.work_register(p_sid text,p_client text DEFAULT 'workos-client',p_user integer DEFAULT 1,p_issuer text DEFAULT 'https://fixture.authkit.app',p_generation integer DEFAULT NULL) RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.register_workos_ai_pairing(aic.user_id(p_user),p_client,p_issuer,p_sid,'Verified WorkOS Codex','https://chatgpt.com/callback',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'),coalesce(p_generation,public.read_ai_connection_generation(aic.user_id(p_user)))) $$;
UPDATE public.ai_connection_pairing_limits SET start_window=now()-interval '11 minutes',lookup_window=now()-interval '11 minutes';
DO $$ DECLARE a text; b text; cid uuid; gen integer; r jsonb; BEGIN
 PERFORM aic.assert(NOT has_function_privilege('authenticated','public.register_workos_ai_pairing(uuid,text,text,text,text,text,text,integer)','EXECUTE'),'registration service only');
 PERFORM aic.assert(NOT has_function_privilege('authenticated','public.begin_ai_connection_revocation(uuid,text)','EXECUTE'),'revocation barrier service only');
 r:=aic.work_register('sid-one'); a:=r->>'authorization_id';
 PERFORM aic.assert(a::uuid IS NOT NULL,'opaque server generated setup ID');
 PERFORM aic.assert((SELECT browser_session_id IS NULL AND expires_at-created_at BETWEEN interval '299 seconds' AND interval '301 seconds' FROM public.ai_connection_pairings WHERE authorization_id=a),'unattached pending five minute expiry');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='workos-client'),'registration grants no authority');
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),'legacy-bypass','workos-client','Legacy','https://chatgpt.com/callback',repeat('f',64)) ? 'error','legacy route cannot cancel durable pending');
 PERFORM aic.assert(aic.work_register('sid-one')->>'authorization_id'=a,'same identity retries reuse pending');
 PERFORM aic.assert(aic.work_register('sid-one','other-client') ? 'error','consent cannot change client');
 PERFORM aic.assert(aic.work_register('sid-one','workos-client',2) ? 'error','consent cannot change user');
 PERFORM aic.assert(aic.work_register('bad-issuer','workos-client',1,'https://fixture.authkit.app/path') ? 'error','issuer must be explicit HTTPS origin');
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(2),a) ? 'error','wrong user cannot preview');
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(1),a)->>'client_name'='Verified WorkOS Codex','preview uses trusted registered metadata');
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'wrong-client','Spoofed','https://chatgpt.com/callback',repeat('a',64)) ? 'error','cannot attach other client');
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(2),aic.user_id(103),a,'workos-client','Spoofed','https://chatgpt.com/callback',repeat('a',64)) ? 'error','cannot attach other user');
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'workos-client','Spoofed','https://chatgpt.com/callback',encode(extensions.digest('MNPQRSTUVWXY','sha256'),'hex')) ? 'expires_at','attach live browser');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'workos-client','https://chatgpt.com/callback') ? 'error','no authority before phone');
 PERFORM aic.phone(1,101);
 PERFORM aic.assert(public.approve_ai_connection_pairing('MNPQRSTUVWXY') ? 'error','same browser cannot approve WorkOS');
 PERFORM aic.phone(1,102);
 r:=public.approve_ai_connection_pairing('MNPQRSTUVWXY');
 PERFORM aic.assert(r->>'approved'='true','different live phone approves WorkOS');
 PERFORM aic.assert(r ? 'connection_id','phone approval completes WorkOS without browser');
 PERFORM aic.assert(public.approve_ai_connection_pairing('MNPQRSTUVWXY')->>'connection_id'=r->>'connection_id','same phone retry preserves completed connection');
 PERFORM set_config('role','none',true);
 cid:=(r->>'connection_id')::uuid;
 PERFORM aic.assert((SELECT status='active' FROM public.ai_connections WHERE connection_id=cid),'phone completion persists before browser returns');
 PERFORM aic.assert(public.ai_connection_pairing_status(aic.user_id(1),aic.user_id(101),a)->>'connection_id'=cid::text,'browser status observes phone completion');
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(1),a)->>'connection_id'=cid::text,'browser preview observes phone completion');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(2),aic.user_id(103),a,'workos-client','https://chatgpt.com/callback') ? 'error','completed receipt rejects wrong user');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(102),a,'workos-client','https://chatgpt.com/callback') ? 'error','completed receipt rejects wrong browser');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'wrong-client','https://chatgpt.com/callback') ? 'error','completed receipt rejects wrong client');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'workos-client','https://wrong.test') ? 'error','completed receipt rejects wrong redirect');
 UPDATE public.ai_connection_pairings SET expires_at=clock_timestamp()-interval '1 second' WHERE authorization_id=a;
 PERFORM aic.assert(public.ai_connection_pairing_status(aic.user_id(1),aic.user_id(101),a)->>'connection_id'=cid::text,'completed receipt survives challenge expiry');
 UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=aic.user_id(102);
 PERFORM aic.assert(public.ai_connection_pairing_status(aic.user_id(1),aic.user_id(101),a) ? 'error','completed receipt still checks phone session');
 UPDATE auth.sessions SET not_after=NULL WHERE id=aic.user_id(102);
 r:=public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'workos-client','https://chatgpt.com/callback');
 PERFORM aic.assert(r->>'connection_id'=cid::text,'browser completion idempotently preserves phone result');
 PERFORM aic.assert(cid IS NOT NULL,'WorkOS atomic completion');
 PERFORM aic.assert((SELECT expires_at IS NULL AND session_id IS NULL AND oauth_issuer='https://fixture.authkit.app' AND consent_id='sid-one' FROM public.ai_connections WHERE connection_id=cid),'durable consent explicit and separate from Supabase session');
 UPDATE public.ai_connections SET scope='{"categories":["supplements","medications"]}' WHERE connection_id=cid;
 INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
 VALUES(cid,aic.user_id(1),'pharmaguide-brief-markdown/v1','{}','\x00','\x00',1,now()+interval '1 hour');
 b:=aic.work_register('sid-one')->>'authorization_id';
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),b,'workos-client','Spoofed','https://chatgpt.com/callback',encode(extensions.digest('NPQRSTUVWXYZ','sha256'),'hex')) ? 'expires_at','repeat exact consent pairing');
 PERFORM aic.phone(1,102); PERFORM public.approve_ai_connection_pairing('NPQRSTUVWXYZ');
 PERFORM set_config('role','none',true);
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),b,'workos-client','https://chatgpt.com/callback')->>'connection_id'=cid::text,'duplicate exact approval retains connection');
 PERFORM aic.assert((SELECT scope='{"categories":["supplements","medications"]}'::jsonb FROM public.ai_connections WHERE connection_id=cid) AND EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid),'duplicate approval retains scope and snapshot');
 -- Cancelling an attached but unconsumed retry must also leave authority alone.
 r:=aic.work_register('sid-one');
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),r->>'authorization_id','workos-client','Spoofed','https://chatgpt.com/callback',repeat('e',64)) ? 'expires_at','unconsumed retry attaches');
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),r->>'authorization_id');
 PERFORM aic.assert((SELECT status='active' FROM public.ai_connections WHERE connection_id=cid)
 AND EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid),'unconsumed retry cancellation preserves original authority');
 -- A repeat approval reuses the original authority; cancellation cannot own it.
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),b);
 PERFORM aic.assert((SELECT status='active' FROM public.ai_connections WHERE connection_id=cid)
 AND EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid),'repeat compensation preserves original connection and snapshot');
 PERFORM aic.assert((SELECT revoking_client_id IS NULL FROM public.ai_connection_pairing_limits WHERE user_id=aic.user_id(1)),'repeat cancellation does not revoke provider authority');
 UPDATE public.ai_share_snapshots SET generated_at=now()-interval '2 hours',expires_at=now()-interval '1 hour' WHERE connection_id=cid;
 PERFORM public.purge_expired_ai_share_snapshots();
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid) AND (SELECT status='active' FROM public.ai_connections WHERE connection_id=cid),'snapshot expires independently of durable consent');
 INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
 VALUES(cid,aic.user_id(1),'pharmaguide-brief-markdown/v1','{}','\x00','\x00',1,now()+interval '1 hour');
 PERFORM aic.assert(aic.work_register('sid-two') ? 'error','other active consent for same client denied');
 PERFORM aic.assert(aic.work_register('sid-one','workos-client',1,'https://other.authkit.app') ? 'error','other issuer cannot replace active client');
 BEGIN UPDATE public.ai_connections SET client_id='hijack' WHERE connection_id=cid; RAISE EXCEPTION 'FAIL immutable owner'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE public.ai_connections SET oauth_issuer=NULL,consent_id=NULL WHERE connection_id=cid; RAISE EXCEPTION 'FAIL explicit null expiry'; EXCEPTION WHEN check_violation THEN NULL; END;
 gen:=public.read_ai_connection_generation(aic.user_id(1));
 r:=public.begin_ai_connection_revocation(aic.user_id(1),'workos-client');
 PERFORM aic.assert((r->>'generation')::integer=gen+1,'disconnect increments generation');
 PERFORM aic.assert(public.begin_ai_connection_revocation(aic.user_id(1),'workos-client')=r,'same disconnect retry keeps generation');
 PERFORM aic.assert(public.begin_ai_connection_revocation(aic.user_id(1),'other-client') ? 'error','other client cannot overwrite barrier');
 PERFORM aic.assert(aic.work_register('sid-new','new-client') ? 'error','user barrier blocks registration');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_share_snapshots WHERE connection_id=cid),'disconnect purges snapshot');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'workos-client',gen) ? 'error','stale provider completion cannot clear barrier');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'other-client',gen+1) ? 'error','wrong client cannot clear barrier');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'workos-client',gen+1)->>'finished'='true','exact provider completion clears barrier');
 PERFORM aic.assert(aic.work_register('sid-new','new-client',1,'https://fixture.authkit.app',gen) ? 'error','UserInfo before revoke cannot register after finish');
 PERFORM aic.assert(aic.work_register('sid-one') ? 'error','revoked consent is permanent tombstone');
 PERFORM aic.assert(public.ai_connection_pairing_status(aic.user_id(1),aic.user_id(101),a) ? 'error','revoked phone completion no longer resolves');
 PERFORM aic.assert(public.complete_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'workos-client','https://chatgpt.com/callback') ? 'error','revoked receipt cannot resurrect consent');
 BEGIN UPDATE public.ai_connections SET status='active',revoked_at=NULL WHERE connection_id=cid; RAISE EXCEPTION 'FAIL tombstone revival'; EXCEPTION WHEN check_violation THEN NULL; END;
 -- Cancel a pending, never-approved consent and prove delayed registration cannot revive it.
 b:=aic.work_register('cancel-sid','cancel-client')->>'authorization_id';
 PERFORM aic.assert(b IS NOT NULL,'cancel pending fixture');
 PERFORM public.revoke_ai_connection_pairings(aic.user_id(1),'cancel-client');
 PERFORM aic.assert((SELECT revoking_client_id='cancel-client' FROM public.ai_connection_pairing_limits WHERE user_id=aic.user_id(1)),'legacy revoke cannot bypass WorkOS barrier');
 PERFORM public.finish_ai_connection_revocation(aic.user_id(1),'cancel-client',public.read_ai_connection_generation(aic.user_id(1)));
 PERFORM aic.assert(aic.work_register('cancel-sid','cancel-client') ? 'error','cancelled pending consent cannot revive');
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(1),b) ? 'error','cancelled pending unavailable');
END $$;
UPDATE public.ai_connection_pairing_limits SET start_window=now()-interval '11 minutes',lookup_window=now()-interval '11 minutes';
SELECT aic.assert(pg_get_function_result('public.cancel_ai_connection_pairing(uuid,uuid,text)'::regprocedure)='jsonb','cancel atomically reports revocation ownership');
-- Deny is available immediately after preview, before the browser attaches a phone code.
DO $$ DECLARE a text; b text; result jsonb; gen integer; BEGIN
 a:=aic.work_register('deny-before-start','deny-client')->>'authorization_id';
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(1),a)->>'client_id'='deny-client','preview unbound setup before denial');
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(2),aic.user_id(103),a);
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(999),a);
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(104),a);
 PERFORM aic.assert((SELECT cancelled_at IS NULL FROM public.ai_connection_pairings WHERE authorization_id=a),'wrong owner and non-live or OAuth sessions cannot deny unbound setup');
 result:=public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a);
 gen:=(result->>'revocation_generation')::integer;
 PERFORM aic.assert(result->>'client_id'='deny-client' AND result->>'cancelled'='true' AND gen IS NOT NULL,'unbound Deny atomically returns provider generation');
 PERFORM aic.assert((SELECT revoking_client_id='deny-client' AND revocation_generation=gen FROM public.ai_connection_pairing_limits WHERE user_id=aic.user_id(1)),'unbound Deny persists recoverable barrier');
 PERFORM aic.assert((SELECT cancelled_at IS NOT NULL AND browser_session_id IS NULL FROM public.ai_connection_pairings WHERE authorization_id=a),'owner Deny cancels unbound WorkOS setup');
 PERFORM aic.assert(public.preview_workos_ai_pairing(aic.user_id(1),a) ? 'error','denied setup cannot preview');
 PERFORM aic.assert(aic.work_register('another-consent','deny-client') ? 'error','Deny barrier blocks new registration');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'deny-client',gen-1) ? 'error','stale finish cannot clear Deny barrier');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(1),'deny-client',gen)->>'finished'='true','provider finishes Deny');
 PERFORM aic.assert(aic.work_register('deny-before-start','deny-client') ? 'error','denied unbound consent cannot revive');
 b:=aic.work_register('deny-after-start','deny-bound-client')->>'authorization_id';
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),b,'deny-bound-client','Verified WorkOS Codex','https://chatgpt.com/callback',repeat('9',64)) ? 'expires_at','attach browser before denial');
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(102),b);
 PERFORM aic.assert((SELECT cancelled_at IS NULL FROM public.ai_connection_pairings WHERE authorization_id=b),'attached setup still requires exact browser for cancellation');
 PERFORM public.cancel_ai_connection_pairing(aic.user_id(1),aic.user_id(101),b);
 PERFORM aic.assert((SELECT cancelled_at IS NOT NULL FROM public.ai_connection_pairings WHERE authorization_id=b),'attached browser can deny');
 PERFORM public.finish_ai_connection_revocation(aic.user_id(1),'deny-bound-client',public.read_ai_connection_generation(aic.user_id(1)));
END $$;
UPDATE public.ai_connection_pairing_limits SET start_window=now()-interval '11 minutes',lookup_window=now()-interval '11 minutes';

-- Failed phone completion must not leave an approval or partial connection.
CREATE TRIGGER aic_fail_pair BEFORE INSERT ON public.ai_connections FOR EACH ROW EXECUTE FUNCTION aic.fail_pair_insert();
DO $$ DECLARE a text; failed boolean:=false; BEGIN
 a:=aic.work_register('phone-atomic-sid','phone-atomic-client')->>'authorization_id';
 PERFORM aic.assert(public.start_ai_connection_pairing(aic.user_id(1),aic.user_id(101),a,'phone-atomic-client','Verified WorkOS Codex','https://chatgpt.com/callback',encode(extensions.digest('STUVWXYZA234','sha256'),'hex')) ? 'expires_at','phone atomic fixture');
 PERFORM public.begin_ai_connection_revocation(aic.user_id(1),'phone-unrelated');
 PERFORM aic.phone(1,102);
 PERFORM aic.assert(public.approve_ai_connection_pairing('STUVWXYZA234') ? 'error','phone approval fails closed during provider barrier');
 PERFORM set_config('role','none',true);
 PERFORM aic.assert((SELECT approved_session_id IS NULL AND consumed_at IS NULL FROM public.ai_connection_pairings WHERE authorization_id=a),'barrier failure leaves no approval');
 PERFORM public.finish_ai_connection_revocation(aic.user_id(1),'phone-unrelated',public.read_ai_connection_generation(aic.user_id(1)));
 BEGIN
  PERFORM aic.phone(1,102);
  PERFORM public.approve_ai_connection_pairing('STUVWXYZA234');
 EXCEPTION WHEN SQLSTATE 'Z0002' THEN failed:=true; END;
 PERFORM set_config('role','none',true);
 PERFORM aic.assert(failed,'phone connection storage failure exercised');
 PERFORM aic.assert((SELECT approved_session_id IS NULL AND consumed_at IS NULL FROM public.ai_connection_pairings WHERE authorization_id=a),'storage failure rolls back phone approval');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE client_id='phone-atomic-client'),'storage failure creates no authority');
END $$;
DROP TRIGGER aic_fail_pair ON public.ai_connections;
BEGIN;
SELECT aic.phone(1,102);
SELECT aic.assert(public.approve_ai_connection_pairing('STUVWXYZA234') ? 'connection_id','phone retry completes after storage recovery');
COMMIT;
INSERT INTO auth.sessions(id,user_id,created_at) VALUES(aic.user_id(106),aic.user_id(1),now());
BEGIN;
SELECT aic.phone(1,106);
SELECT aic.assert(public.approve_ai_connection_pairing('STUVWXYZA234') ? 'error','another live phone cannot replay completed receipt');
COMMIT;
DELETE FROM auth.sessions WHERE id=aic.user_id(106);
SELECT public.begin_ai_connection_revocation(aic.user_id(1),'phone-atomic-client');
SELECT public.finish_ai_connection_revocation(aic.user_id(1),'phone-atomic-client',public.read_ai_connection_generation(aic.user_id(1)));
UPDATE public.ai_connection_pairing_limits SET start_window=now()-interval '11 minutes',lookup_window=now()-interval '11 minutes';

-- Account deletion must block every client before asynchronous provider cleanup.
DO $$ DECLARE g integer; old_g integer; r jsonb; BEGIN
 r:=aic.work_register('account-delete-pending','delete-pending-client',2);
 PERFORM aic.assert(r ? 'authorization_id','pending account deletion fixture');
 old_g:=(public.begin_ai_connection_revocation(aic.user_id(2),'delete-old-client')->>'generation')::integer;
 INSERT INTO public.ai_connections(user_id,client_id,expires_at) VALUES
 (aic.user_id(2),'delete-client-a',now()+interval '1 day'),
 (aic.user_id(2),'delete-client-b',now()+interval '1 day');
 INSERT INTO public.ai_share_snapshots(connection_id,user_id,format,scope,ciphertext,nonce,key_version,expires_at)
 SELECT connection_id,user_id,'pharmaguide-brief-markdown/v1','{}','\x00','\x00',1,now()+interval '1 hour'
 FROM public.ai_connections WHERE user_id=aic.user_id(2) AND client_id IN('delete-client-a','delete-client-b');
 r:=public.begin_ai_connection_revocation(aic.user_id(2),NULL);
 PERFORM aic.assert(r ? 'generation','account deletion enters atomic global barrier');
 g:=(r->>'generation')::integer;
 PERFORM aic.assert(g>old_g,'account deletion supersedes in-flight client revocation');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(2),'delete-old-client',old_g) ? 'error','old provider completion cannot clear deletion barrier');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_connection_pairings WHERE user_id=aic.user_id(2) AND cancelled_at IS NULL),'all pending approvals cancelled');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_connections WHERE user_id=aic.user_id(2) AND status='active'),'all account clients revoked');
 PERFORM aic.assert(NOT EXISTS(SELECT FROM public.ai_share_snapshots WHERE user_id=aic.user_id(2)),'all account snapshots purged');
 PERFORM aic.assert(public.begin_ai_connection_revocation(aic.user_id(2),NULL)->>'generation'=g::text,'account deletion retry preserves generation');
 PERFORM aic.assert(public.begin_ai_connection_revocation(aic.user_id(2),'delete-client-a') ? 'error','client disconnect cannot replace deletion barrier');
 PERFORM aic.assert(public.finish_ai_connection_revocation(aic.user_id(2),repeat('!',256),g) ? 'error','finish cannot clear account deletion barrier');
 PERFORM aic.assert(aic.work_register('delete-race-sid','delete-new-client',2) ? 'error','new consent blocked during failed account deletion');
 PERFORM aic.assert(public.read_ai_connection_generation(aic.user_id(2))=g,'rejected operations preserve deletion generation');
END $$;

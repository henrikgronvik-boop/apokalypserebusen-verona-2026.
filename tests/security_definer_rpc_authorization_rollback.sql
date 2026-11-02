-- Authenticated SECURITY DEFINER RPC authorization regression.
-- Negative calls must fail at the authorization guard, not at a later constraint.
-- All calls run in a transaction that is rolled back; no codes are disclosed.
-- This does NOT prove rate limiting, client E2E, or that all RPCs are secure.
BEGIN;
SELECT set_config('audit.rpc_member',(SELECT m.user_id::text FROM public.team_members m
  WHERE NOT EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
  ORDER BY m.user_id LIMIT 1),true);
SELECT set_config('audit.rpc_team',(SELECT m.team_id::text FROM public.team_members m
  WHERE m.user_id::text=current_setting('audit.rpc_member',true) LIMIT 1),true);
SELECT set_config('audit.rpc_hk',(SELECT a.user_id::text FROM public.admins a ORDER BY a.user_id LIMIT 1),true);
SELECT set_config('audit.rpc_outsider',gen_random_uuid()::text,true);
SET LOCAL ROLE authenticated;
DO $rpc$
DECLARE
 member_uid uuid := nullif(current_setting('audit.rpc_member',true),'')::uuid;
 member_team uuid := nullif(current_setting('audit.rpc_team',true),'')::uuid;
 hk_uid uuid := nullif(current_setting('audit.rpc_hk',true),'')::uuid;
 outsider_uid uuid := nullif(current_setting('audit.rpc_outsider',true),'')::uuid;
 test_case record;
 identity_uid uuid;
 actual_message text;
 checks integer := 0;
BEGIN
 IF member_uid IS NULL OR member_team IS NULL OR hk_uid IS NULL OR outsider_uid IS NULL
 OR member_uid=hk_uid OR outsider_uid=member_uid OR outsider_uid=hk_uid
 THEN RAISE EXCEPTION 'Required distinct test identities unavailable'; END IF;
 FOREACH identity_uid IN ARRAY ARRAY[member_uid,outsider_uid] LOOP
   PERFORM set_config('request.jwt.claim.sub',identity_uid::text,true);
   IF auth.uid() IS DISTINCT FROM identity_uid THEN RAISE EXCEPTION 'JWT identity mismatch'; END IF;
   FOR test_case IN
     SELECT * FROM (VALUES
       ('advance',format('SELECT public.hk_advance_team_stage(%L::uuid)',member_team::text),'Kun HK kan åpne neste del'),
       ('release','SELECT public.hk_release_special(''secret_mission'')','Kun HK kan frigi spesialoppdrag'),
       ('rotate',format('SELECT public.hk_rotate_team_code(%L::uuid)',member_team::text),'Kun HK kan lage nye lagkoder'),
       ('set_stage',format('SELECT public.hk_set_team_stage(%L::uuid,1)',member_team::text),'Kun HK kan velge startdel')
     ) AS t(label,stmt,expected)
   LOOP
     BEGIN
       EXECUTE test_case.stmt;
       RAISE EXCEPTION 'SECURITY FAILURE: % accepted unauthorized caller',test_case.label;
     EXCEPTION WHEN OTHERS THEN
       GET STACKED DIAGNOSTICS actual_message = MESSAGE_TEXT;
       IF actual_message IS DISTINCT FROM test_case.expected THEN
         RAISE EXCEPTION 'SECURITY FAILURE: % unexpected response: %',test_case.label,actual_message;
       END IF;
     END;
     checks:=checks+1;
   END LOOP;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',hk_uid::text,true);
 FOR test_case IN
   SELECT * FROM (VALUES
     ('HK join by name','SELECT public.join_rebus_team_by_name(''ROLLBACK-ONLY'')','Bruk lagkode fra HK for å bli med på laget'),
     ('HK join by code','SELECT public.join_rebus_team_by_code(''ROLLBACK-INVALID-CODE'')','HK kan ikke bli med på et lag')
   ) AS t(label,stmt,expected)
 LOOP
   BEGIN
     EXECUTE test_case.stmt;
     RAISE EXCEPTION 'SECURITY FAILURE: % accepted',test_case.label;
   EXCEPTION WHEN OTHERS THEN
     GET STACKED DIAGNOSTICS actual_message = MESSAGE_TEXT;
     IF actual_message IS DISTINCT FROM test_case.expected THEN
       RAISE EXCEPTION 'SECURITY FAILURE: % unexpected response: %',test_case.label,actual_message;
     END IF;
   END;
   checks:=checks+1;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',outsider_uid::text,true);
 BEGIN
   PERFORM public.claim_rebus_admin('ROLLBACK-INVALID-ADMIN-CODE');
   RAISE EXCEPTION 'SECURITY FAILURE: invalid admin code accepted';
 EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS actual_message = MESSAGE_TEXT;
   IF actual_message IS DISTINCT FROM 'Invalid or used admin code' THEN
     RAISE EXCEPTION 'SECURITY FAILURE: unexpected admin claim response: %',actual_message;
   END IF;
 END;
 checks:=checks+1;
 IF checks<>11 THEN RAISE EXCEPTION 'Expected 11 negative checks, got %',checks; END IF;
 RAISE NOTICE 'PASS: % unauthorized RPC calls rejected at expected guards',checks;
END $rpc$;
SELECT 'PASS' AS status,'11 authenticated SECURITY DEFINER RPC authorization cases; rollback' AS scope;
ROLLBACK;

-- Private chat write/read RLS regression. All test messages rolled back.
-- Requires an existing non-admin member, a separate team and HK.
BEGIN;
SELECT set_config('audit.member_uid',m.user_id::text,true),
       set_config('audit.member_team',m.team_id::text,true)
FROM public.team_members m WHERE m.team_id IS NOT NULL
AND NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
ORDER BY m.user_id LIMIT 1;
SELECT set_config('audit.other_team',(SELECT id::text FROM public.teams
 WHERE id::text<>current_setting('audit.member_team',true) ORDER BY id LIMIT 1),true);
SELECT set_config('audit.admin_uid',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.outsider_uid',gen_random_uuid()::text,true);
SET LOCAL ROLE authenticated;
DO $chat$
DECLARE
 member_uid uuid := nullif(current_setting('audit.member_uid',true),'')::uuid;
 member_team uuid := nullif(current_setting('audit.member_team',true),'')::uuid;
 other_team uuid := nullif(current_setting('audit.other_team',true),'')::uuid;
 admin_uid uuid := nullif(current_setting('audit.admin_uid',true),'')::uuid;
 outsider_uid uuid := nullif(current_setting('audit.outsider_uid',true),'')::uuid;
 member_message uuid;
 admin_message uuid;
BEGIN
 IF member_uid IS NULL OR member_team IS NULL OR other_team IS NULL
 OR admin_uid IS NULL OR outsider_uid IS NULL OR member_uid=admin_uid
 OR member_team=other_team THEN
  RAISE EXCEPTION 'Need a member, HK and two distinct teams';
 END IF;
 PERFORM set_config('request.jwt.claim.sub',member_uid::text,true);
 IF auth.uid() IS DISTINCT FROM member_uid THEN RAISE EXCEPTION 'Member JWT mismatch'; END IF;
 INSERT INTO public.messages(team_id,sender_id,content)
 VALUES(member_team,member_uid,'ROLLBACK ONLY member test') RETURNING id INTO member_message;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=member_message)
 THEN RAISE EXCEPTION 'Member cannot read own message'; END IF;
 BEGIN
  INSERT INTO public.messages(team_id,sender_id,content)
  VALUES(other_team,member_uid,'ROLLBACK ONLY cross-team attempt');
  RAISE EXCEPTION 'SECURITY FAILURE: cross-team insert allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  INSERT INTO public.messages(team_id,sender_id,content)
  VALUES(member_team,admin_uid,'ROLLBACK ONLY sender spoof attempt');
  RAISE EXCEPTION 'SECURITY FAILURE: sender spoof allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM set_config('request.jwt.claim.sub',outsider_uid::text,true);
 IF EXISTS(SELECT 1 FROM public.messages WHERE id=member_message)
 THEN RAISE EXCEPTION 'SECURITY FAILURE: outsider read member message'; END IF;
 BEGIN
  INSERT INTO public.messages(team_id,sender_id,content)
  VALUES(member_team,outsider_uid,'ROLLBACK ONLY outsider attempt');
  RAISE EXCEPTION 'SECURITY FAILURE: outsider insert allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM set_config('request.jwt.claim.sub',admin_uid::text,true);
 INSERT INTO public.messages(team_id,sender_id,content)
 VALUES(other_team,admin_uid,'ROLLBACK ONLY HK test') RETURNING id INTO admin_message;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=member_message)
 OR NOT EXISTS(SELECT 1 FROM public.messages WHERE id=admin_message)
 THEN RAISE EXCEPTION 'HK cannot read both messages'; END IF;
 PERFORM set_config('request.jwt.claim.sub',member_uid::text,true);
 IF EXISTS(SELECT 1 FROM public.messages WHERE id=admin_message)
 THEN RAISE EXCEPTION 'SECURITY FAILURE: member read other team HK message'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=member_message)
 THEN RAISE EXCEPTION 'Member cannot read own message after HK send'; END IF;
END $chat$;
SELECT 'PASS' AS result, 'Private chat writes and reads isolated under authenticated RLS' AS scope;
ROLLBACK;
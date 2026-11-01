-- Apokalypserebusen 2026: authenticated cross-team WRITE regression.
-- Tested against Supabase on 2026-11-01; PASS.
-- Run this entire script as ONE SQL request. The final ROLLBACK restores all data.
-- No auth users, tasks, teams, or storage files are created.
-- This is a database-role test, NOT a real-browser/two-phone E2E test.
BEGIN;
SELECT set_config('audit.member_uid',(SELECT user_id::text FROM public.team_members WHERE team_id IS NOT NULL ORDER BY user_id LIMIT 1),true);
SELECT set_config('audit.member_team',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.member_uid')),true);
SELECT set_config('audit.other_team',(SELECT id::text FROM public.teams WHERE id::text<>current_setting('audit.member_team') ORDER BY name LIMIT 1),true);
SELECT set_config('audit.admin_uid',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.main_task',(SELECT t.id::text FROM public.tasks t JOIN public.teams tm ON tm.current_stage=t.stage WHERE tm.id::text=current_setting('audit.member_team') AND t.bonus IS FALSE ORDER BY t.position LIMIT 1),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.member_uid'),true);
DO $test$
DECLARE
 v_uid uuid:=current_setting('audit.member_uid')::uuid;
 v_team uuid:=current_setting('audit.member_team')::uuid;
 v_other uuid:=current_setting('audit.other_team')::uuid;
 v_admin uuid:=current_setting('audit.admin_uid')::uuid;
 v_task uuid:=current_setting('audit.main_task')::uuid;
 v_message uuid;
 v_submission uuid;
 v_skip uuid;
BEGIN
 IF auth.uid()<>v_uid OR v_other=v_team OR v_task IS NULL OR v_admin IS NULL THEN
   RAISE EXCEPTION 'Test identities or main task missing';
 END IF;
 -- 1. Cross-team chat must be denied.
 BEGIN
   INSERT INTO public.messages(team_id,sender_id,content)
   VALUES (v_other,v_uid,'ROLLBACK-ONLY: cross-team chat');
   RAISE EXCEPTION 'TEST FAILED: cross-team chat insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 -- 2. Forged HK sender must be denied.
 BEGIN
   INSERT INTO public.messages(team_id,sender_id,content)
   VALUES (v_team,v_admin,'ROLLBACK-ONLY: forged HK chat');
   RAISE EXCEPTION 'TEST FAILED: forged HK chat insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 -- 3. Cross-team task submission must be denied.
 BEGIN
   INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points)
   VALUES (v_other,v_task,v_uid,'ROLLBACK-ONLY: cross-team submission','pending',0);
   RAISE EXCEPTION 'TEST FAILED: cross-team submission insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 -- 4. Cross-team skip request must be denied.
 BEGIN
   INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
   VALUES (v_other,v_task,v_uid,'pending');
   RAISE EXCEPTION 'TEST FAILED: cross-team skip insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 -- 5. Own-team chat must be accepted and readable.
 INSERT INTO public.messages(team_id,sender_id,content)
 VALUES (v_team,v_uid,'ROLLBACK-ONLY: own team chat') RETURNING id INTO v_message;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=v_message AND team_id=v_team)
 THEN RAISE EXCEPTION 'TEST FAILED: own chat unreadable'; END IF;
 -- 6. Own-team task submission must be accepted and readable.
 INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points)
 VALUES (v_team,v_task,v_uid,'ROLLBACK-ONLY: own submission','pending',0) RETURNING id INTO v_submission;
 IF NOT EXISTS(SELECT 1 FROM public.submissions WHERE id=v_submission AND team_id=v_team)
 THEN RAISE EXCEPTION 'TEST FAILED: own submission unreadable'; END IF;
 -- 7. Own-team skip request must be accepted and readable.
 INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
 VALUES (v_team,v_task,v_uid,'pending') RETURNING id INTO v_skip;
 IF NOT EXISTS(SELECT 1 FROM public.skip_requests WHERE id=v_skip AND team_id=v_team)
 THEN RAISE EXCEPTION 'TEST FAILED: own skip request unreadable'; END IF;
 -- 8. Authenticated outsider without membership cannot post to the team.
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN
   INSERT INTO public.messages(team_id,sender_id,content)
   VALUES (v_team,auth.uid(),'ROLLBACK-ONLY: outsider chat');
   RAISE EXCEPTION 'TEST FAILED: outsider chat insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RAISE NOTICE 'PASS: eight write-isolation cases';
END $test$;
SELECT 'PASS' AS result, 'eight authenticated write-isolation checks; transaction rolled back' AS scope;
ROLLBACK;

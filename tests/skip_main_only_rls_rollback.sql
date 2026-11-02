-- Regression: only main tasks may be skipped, including legacy bonuses with no special_key.
-- All synthetic rows are rolled back; never remove ROLLBACK.
BEGIN;
SELECT set_config('request.jwt.claim.sub',
  (SELECT m.user_id::text FROM public.team_members m
   WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
   LIMIT 1), true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
 v_user uuid:=auth.uid(); v_team uuid; v_other uuid;
 v_bonus uuid; v_main uuid; v_id uuid; v_checks integer:=0;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'A registered non-HK member is required'; END IF;
 SELECT team_id INTO STRICT v_team FROM public.team_members WHERE user_id=v_user;
 SELECT id INTO STRICT v_other FROM public.teams WHERE id<>v_team LIMIT 1;
 SELECT id INTO STRICT v_bonus FROM public.tasks
 WHERE stage=1 AND bonus AND special_key IS NULL LIMIT 1;
 SELECT id INTO STRICT v_main FROM public.tasks
 WHERE stage=1 AND NOT bonus LIMIT 1;

 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
  VALUES(v_team,v_bonus,v_user,'pending');
  RAISE EXCEPTION 'FAIL: legacy bonus skip accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 v_checks:=v_checks+1;

 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
  VALUES(v_other,v_main,v_user,'pending');
  RAISE EXCEPTION 'FAIL: cross-team skip accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 v_checks:=v_checks+1;

 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
  VALUES(v_team,v_main,v_user,'approved');
  RAISE EXCEPTION 'FAIL: member preapproved a skip';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 v_checks:=v_checks+1;

 INSERT INTO public.skip_requests(team_id,task_id,user_id,status)
 VALUES(v_team,v_main,v_user,'pending') RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'FAIL: valid main-task skip rejected'; END IF;
 v_checks:=v_checks+1;

 IF (SELECT count(*) FROM public.skip_requests WHERE id=v_id)<>1 THEN
  RAISE EXCEPTION 'FAIL: own skip request not visible';
 END IF;
 v_checks:=v_checks+1;

 IF v_checks<>5 THEN RAISE EXCEPTION 'Expected 5 checks'; END IF;
 RAISE NOTICE 'PASS: % skip policy checks (rolled back)',v_checks;
END $test$;
ROLLBACK;
SELECT 'PASS' AS status,'5 main-only skip policy checks; all synthetic rows rolled back' AS scope;

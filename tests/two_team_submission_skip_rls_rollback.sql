-- Two-team submission/skip RLS regression; all synthetic rows rolled back.
BEGIN;
SELECT set_config('audit.member',(SELECT m.user_id::text FROM public.team_members m WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id) LIMIT 1),true);
SELECT set_config('audit.own',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.member',true) LIMIT 1),true);
SELECT set_config('audit.other',(SELECT id::text FROM public.teams WHERE id::text<>current_setting('audit.own',true) ORDER BY name LIMIT 1),true);
SELECT set_config('audit.hk',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.outsider',gen_random_uuid()::text,true);
SELECT set_config('audit.task',(SELECT id::text FROM public.tasks WHERE stage=1 AND NOT bonus ORDER BY position LIMIT 1),true);
SELECT set_config('audit.os',gen_random_uuid()::text,true);
SELECT set_config('audit.xs',gen_random_uuid()::text,true);
SELECT set_config('audit.ok',gen_random_uuid()::text,true);
SELECT set_config('audit.xk',gen_random_uuid()::text,true);
INSERT INTO public.submissions(id,team_id,task_id,user_id,note,status,awarded_points) VALUES
(current_setting('audit.os')::uuid,current_setting('audit.own')::uuid,current_setting('audit.task')::uuid,current_setting('audit.member')::uuid,'ROLLBACK own','pending',0),
(current_setting('audit.xs')::uuid,current_setting('audit.other')::uuid,current_setting('audit.task')::uuid,current_setting('audit.member')::uuid,'ROLLBACK other','pending',0);
INSERT INTO public.skip_requests(id,team_id,task_id,user_id,status) VALUES
(current_setting('audit.ok')::uuid,current_setting('audit.own')::uuid,current_setting('audit.task')::uuid,current_setting('audit.member')::uuid,'pending'),
(current_setting('audit.xk')::uuid,current_setting('audit.other')::uuid,current_setting('audit.task')::uuid,current_setting('audit.member')::uuid,'pending');
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
 m uuid:=nullif(current_setting('audit.member',true),'')::uuid;
 own uuid:=nullif(current_setting('audit.own',true),'')::uuid;
 other uuid:=nullif(current_setting('audit.other',true),'')::uuid;
 hk uuid:=nullif(current_setting('audit.hk',true),'')::uuid;
 outsider uuid:=nullif(current_setting('audit.outsider',true),'')::uuid;
 task uuid:=nullif(current_setting('audit.task',true),'')::uuid;
 os uuid:=nullif(current_setting('audit.os',true),'')::uuid;
 xs uuid:=nullif(current_setting('audit.xs',true),'')::uuid;
 ok uuid:=nullif(current_setting('audit.ok',true),'')::uuid;
 xk uuid:=nullif(current_setting('audit.xk',true),'')::uuid;
 affected integer; checks integer:=0;
BEGIN
 IF m IS NULL OR own IS NULL OR other IS NULL OR hk IS NULL OR task IS NULL OR m=hk OR own=other THEN RAISE EXCEPTION 'Distinct HK, member, task and teams required'; END IF;
 PERFORM set_config('request.jwt.claim.sub',m::text,true);
 IF auth.uid() IS DISTINCT FROM m THEN RAISE EXCEPTION 'Member JWT mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.submissions WHERE id=os) THEN RAISE EXCEPTION 'Own submission hidden'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.submissions WHERE id=xs) THEN RAISE EXCEPTION 'Other submission leaked'; END IF; checks:=checks+1;
 IF NOT EXISTS(SELECT 1 FROM public.skip_requests WHERE id=ok) THEN RAISE EXCEPTION 'Own skip hidden'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.skip_requests WHERE id=xk) THEN RAISE EXCEPTION 'Other skip leaked'; END IF; checks:=checks+1;
 BEGIN
  INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points) VALUES(other,task,m,'Forbidden cross-team','pending',0);
  RAISE EXCEPTION 'Cross-team submission write allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status) VALUES(other,task,m,'pending');
  RAISE EXCEPTION 'Cross-team skip write allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 BEGIN
  INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points) VALUES(own,task,hk,'Forged author','pending',0);
  RAISE EXCEPTION 'Forged submission author allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status) VALUES(own,task,hk,'pending');
  RAISE EXCEPTION 'Forged skip author allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 UPDATE public.submissions SET status='rejected' WHERE id=os;
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>0 THEN RAISE EXCEPTION 'Member changed submission review'; END IF; checks:=checks+1;
 UPDATE public.skip_requests SET status='rejected' WHERE id=ok;
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>0 THEN RAISE EXCEPTION 'Member changed skip review'; END IF; checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 IF EXISTS(SELECT 1 FROM public.submissions WHERE id IN(os,xs)) THEN RAISE EXCEPTION 'Outsider submission leak'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.skip_requests WHERE id IN(ok,xk)) THEN RAISE EXCEPTION 'Outsider skip leak'; END IF; checks:=checks+1;
 BEGIN
  INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points) VALUES(own,task,outsider,'Outsider','pending',0);
  RAISE EXCEPTION 'Outsider submission write allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 BEGIN
  INSERT INTO public.skip_requests(team_id,task_id,user_id,status) VALUES(own,task,outsider,'pending');
  RAISE EXCEPTION 'Outsider skip write allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',hk::text,true);
 IF (SELECT count(*) FROM public.submissions WHERE id IN(os,xs))<>2 THEN RAISE EXCEPTION 'HK submission visibility broken'; END IF; checks:=checks+1;
 IF (SELECT count(*) FROM public.skip_requests WHERE id IN(ok,xk))<>2 THEN RAISE EXCEPTION 'HK skip visibility broken'; END IF; checks:=checks+1;
 UPDATE public.skip_requests SET status='rejected' WHERE id=xk;
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>1 THEN RAISE EXCEPTION 'HK skip review failed'; END IF; checks:=checks+1;
 IF checks<>17 THEN RAISE EXCEPTION 'Expected 17 checks, got %',checks; END IF;
 RAISE NOTICE 'PASS: % two-team submission/skip checks, rolled back',checks;
END $test$;
ROLLBACK;
SELECT 'PASS' AS status, '17 two-team submission/skip RLS checks; all fixtures rolled back' AS scope;

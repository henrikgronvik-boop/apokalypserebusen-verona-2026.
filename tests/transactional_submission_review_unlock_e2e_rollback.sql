-- End-to-end database integration regression. All fixtures are rolled back.
-- Covers member submissions, evidence requirement, HK review, scoring and 2-of-5 unlock.
BEGIN;
SELECT set_config('e2e.member',(SELECT m.user_id::text FROM public.team_members m WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id) LIMIT 1),true);
SELECT set_config('e2e.hk',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('e2e.team',(SELECT t.id::text FROM public.teams t WHERE NOT EXISTS(SELECT 1 FROM public.team_members m WHERE m.team_id=t.id) AND NOT EXISTS(SELECT 1 FROM public.submissions s WHERE s.team_id=t.id) ORDER BY t.name LIMIT 1),true);
SELECT set_config('e2e.t1',(SELECT id::text FROM public.tasks WHERE stage=1 AND bonus=false ORDER BY position LIMIT 1),true);
SELECT set_config('e2e.t2',(SELECT id::text FROM public.tasks WHERE stage=1 AND bonus=false ORDER BY position OFFSET 1 LIMIT 1),true);
SELECT set_config('e2e.tb',(SELECT id::text FROM public.tasks WHERE stage=1 AND bonus=true ORDER BY position LIMIT 1),true);
SELECT set_config('e2e.s1',gen_random_uuid()::text,true);
SELECT set_config('e2e.s2',gen_random_uuid()::text,true);
SELECT set_config('e2e.sb',gen_random_uuid()::text,true);
DO $setup$
BEGIN
 IF nullif(current_setting('e2e.member',true),'') IS NULL OR nullif(current_setting('e2e.hk',true),'') IS NULL
 OR nullif(current_setting('e2e.team',true),'') IS NULL OR nullif(current_setting('e2e.t1',true),'') IS NULL
 OR nullif(current_setting('e2e.t2',true),'') IS NULL OR nullif(current_setting('e2e.tb',true),'') IS NULL
 THEN RAISE EXCEPTION 'Missing safe test fixtures'; END IF;
 IF (SELECT score<>0 OR current_stage<>1 OR stages_completed<>0 FROM public.teams WHERE id=current_setting('e2e.team')::uuid)
 THEN RAISE EXCEPTION 'Test team is not clean'; END IF;
 UPDATE public.team_members SET team_id=current_setting('e2e.team')::uuid WHERE user_id=current_setting('e2e.member')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'No test member'; END IF;
END $setup$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
 m uuid:=current_setting('e2e.member')::uuid; hk uuid:=current_setting('e2e.hk')::uuid;
 tm uuid:=current_setting('e2e.team')::uuid;
 t1 uuid:=current_setting('e2e.t1')::uuid; t2 uuid:=current_setting('e2e.t2')::uuid; tb uuid:=current_setting('e2e.tb')::uuid;
 s1 uuid:=current_setting('e2e.s1')::uuid; s2 uuid:=current_setting('e2e.s2')::uuid; sb uuid:=current_setting('e2e.sb')::uuid;
 p1 int; p2 int; pb int; checks int:=0; blocked boolean; next_stage int;
BEGIN
 IF m=hk OR t1=t2 OR t1=tb OR t2=tb THEN RAISE EXCEPTION 'Fixture identities overlap'; END IF;
 PERFORM set_config('request.jwt.claim.sub',m::text,true);
 IF auth.uid() IS DISTINCT FROM m THEN RAISE EXCEPTION 'Member JWT mismatch'; END IF;
 SELECT points INTO p1 FROM public.tasks WHERE id=t1;
 SELECT points INTO p2 FROM public.tasks WHERE id=t2;
 SELECT points INTO pb FROM public.tasks WHERE id=tb;
 IF p1 IS NULL OR p2 IS NULL OR pb IS NULL THEN RAISE EXCEPTION 'Member cannot see required stage-1 tasks'; END IF; checks:=checks+1;
 INSERT INTO public.submissions(id,team_id,task_id,user_id,note,status,awarded_points) VALUES
 (s1,tm,t1,m,'ROLLBACK main 1','pending',0),
 (s2,tm,t2,m,'ROLLBACK main 2','pending',0),
 (sb,tm,tb,m,'ROLLBACK bonus','pending',0);
 IF (SELECT count(*) FROM public.submissions WHERE id IN(s1,s2,sb))<>3 THEN RAISE EXCEPTION 'Member submissions failed'; END IF; checks:=checks+1;
 IF (SELECT score FROM public.teams WHERE id=tm)<>0 THEN RAISE EXCEPTION 'Pending submissions scored'; END IF; checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',hk::text,true);
 blocked:=false;
 BEGIN
  UPDATE public.submissions SET status='approved',awarded_points=p1 WHERE id=s1;
 EXCEPTION WHEN OTHERS THEN
  IF position('without photo or video evidence' in SQLERRM)>0 THEN blocked:=true; ELSE RAISE; END IF;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'HK approved without evidence'; END IF; checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',m::text,true);
 INSERT INTO public.media(team_id,submission_id,storage_path,mime_type) VALUES
 (tm,s1,tm::text||'/'||s1::text||'/test1.jpg','image/jpeg'),
 (tm,s2,tm::text||'/'||s2::text||'/test2.jpg','image/jpeg'),
 (tm,sb,tm::text||'/'||sb::text||'/testbonus.jpg','image/jpeg');
 IF (SELECT count(*) FROM public.media WHERE submission_id IN(s1,s2,sb))<>3 THEN RAISE EXCEPTION 'Member evidence metadata failed'; END IF; checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',hk::text,true);
 UPDATE public.submissions SET status='approved',awarded_points=pb WHERE id=sb;
 IF (SELECT score FROM public.teams WHERE id=tm)<>pb THEN RAISE EXCEPTION 'Bonus score wrong'; END IF; checks:=checks+1;
 blocked:=false;
 BEGIN PERFORM public.hk_advance_team_stage(tm);
 EXCEPTION WHEN OTHERS THEN
  IF position('To hovedoppgaver' in SQLERRM)>0 THEN blocked:=true; ELSE RAISE; END IF;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Bonus alone unlocked stage'; END IF; checks:=checks+1;
 UPDATE public.submissions SET status='approved',awarded_points=p1 WHERE id=s1;
 IF (SELECT score FROM public.teams WHERE id=tm)<>pb+p1 THEN RAISE EXCEPTION 'First main score wrong'; END IF; checks:=checks+1;
 blocked:=false;
 BEGIN PERFORM public.hk_advance_team_stage(tm);
 EXCEPTION WHEN OTHERS THEN
  IF position('To hovedoppgaver' in SQLERRM)>0 THEN blocked:=true; ELSE RAISE; END IF;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'One main plus bonus unlocked stage'; END IF; checks:=checks+1;
 UPDATE public.submissions SET status='approved',awarded_points=p2 WHERE id=s2;
 IF (SELECT score FROM public.teams WHERE id=tm)<>pb+p1+p2 THEN RAISE EXCEPTION 'Two-main score wrong'; END IF; checks:=checks+1;
 next_stage:=public.hk_advance_team_stage(tm);
 IF next_stage<>2 OR (SELECT current_stage<>2 OR stages_completed<>1 FROM public.teams WHERE id=tm)
 THEN RAISE EXCEPTION 'HK advance did not open stage 2'; END IF; checks:=checks+1;
 IF (SELECT count(*) FROM public.submissions WHERE id IN(s1,s2,sb) AND reviewed_by=hk AND reviewed_at IS NOT NULL)<>3
 THEN RAISE EXCEPTION 'HK review metadata missing'; END IF; checks:=checks+1;
 IF checks<>12 THEN RAISE EXCEPTION 'Expected 12 assertions; got %',checks; END IF;
 RAISE NOTICE 'PASS: % transactional database integration checks',checks;
END $test$;
ROLLBACK;
SELECT 'PASS' AS status, '12 submission/evidence/HK/score/unlock checks; all fixtures rolled back' AS scope;
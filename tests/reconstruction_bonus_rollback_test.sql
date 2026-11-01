-- Transactional regression test for the one-time best-photo award.
-- Creates temporary submissions/metadata, exercises admin and non-admin roles,
-- verifies score recalculation and duplicate rejection, then ROLLS BACK.
-- Never run without the final ROLLBACK.
BEGIN;
DO $test$
DECLARE
  v_admin uuid; v_member uuid; v_team_a uuid; v_team_b uuid; v_task uuid;
  v_a uuid; v_b uuid; v_before int; v_after int;
BEGIN
  SELECT user_id INTO STRICT v_admin FROM public.admins LIMIT 1;
  SELECT user_id INTO STRICT v_member FROM public.team_members LIMIT 1;
  SELECT id INTO STRICT v_team_a FROM public.teams ORDER BY id LIMIT 1;
  SELECT id INTO STRICT v_team_b FROM public.teams WHERE id <> v_team_a ORDER BY id LIMIT 1;
  SELECT id INTO STRICT v_task FROM public.tasks WHERE special_key='perfect_reconstruction';
  SELECT score INTO v_before FROM public.teams WHERE id=v_team_a;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);

  INSERT INTO public.submissions(team_id,task_id,user_id,note)
  VALUES(v_team_a,v_task,v_member,'ROLLBACK TEST bonus A') RETURNING id INTO v_a;
  INSERT INTO public.submissions(team_id,task_id,user_id,note)
  VALUES(v_team_b,v_task,v_member,'ROLLBACK TEST bonus B') RETURNING id INTO v_b;
  -- Test metadata has no actual storage object; rolled back at the end.
  INSERT INTO public.media(team_id,submission_id,storage_path,mime_type)
  VALUES(v_team_a,v_a,v_team_a::text||'/'||v_a::text||'/'||gen_random_uuid()::text||'.jpg','image/jpeg'),
        (v_team_b,v_b,v_team_b::text||'/'||v_b::text||'/'||gen_random_uuid()::text||'.jpg','image/jpeg');
  UPDATE public.submissions SET status='approved',awarded_points=600 WHERE id IN (v_a,v_b);

  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  BEGIN
    UPDATE public.submissions SET awarded_points=800 WHERE id=v_a;
    RAISE EXCEPTION 'FAIL: non-admin could award reconstruction prize';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='FAIL: non-admin could award reconstruction prize' THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  UPDATE public.submissions SET awarded_points=800 WHERE id=v_a;
  SELECT score INTO v_after FROM public.teams WHERE id=v_team_a;
  IF v_after-v_before <> 800 THEN
    RAISE EXCEPTION 'FAIL: score changed by %, expected 800',v_after-v_before;
  END IF;
  BEGIN
    UPDATE public.submissions SET awarded_points=800 WHERE id=v_b;
    RAISE EXCEPTION 'FAIL: second best-photo winner was allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='FAIL: second best-photo winner was allowed' THEN RAISE; END IF;
  END;
  IF (SELECT awarded_points FROM public.submissions WHERE id=v_b) <> 600 THEN
    RAISE EXCEPTION 'FAIL: second approved reconstruction was modified';
  END IF;
END;
$test$;
ROLLBACK;

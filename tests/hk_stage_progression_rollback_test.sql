-- Apokalypserebusen 2026: authenticated HK stage advancement regression.
-- Uses a real team with >=2 approved main tasks; no permanent data changes.
-- Run the entire file as one request. Always ROLLBACK.
-- This tests database behavior, not real browser/mobile E2E or storage upload.
BEGIN;
SELECT set_config('audit.team_id', t.id::text, true)
FROM public.teams t
JOIN public.team_members m ON m.team_id=t.id
WHERE t.stages_completed<5
  AND NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
  AND (SELECT count(DISTINCT s.task_id) FROM public.submissions s
       JOIN public.tasks k ON k.id=s.task_id
       WHERE s.team_id=t.id AND k.stage=t.current_stage AND NOT k.bonus
         AND s.status='approved') >= 2
ORDER BY t.id LIMIT 1;
SELECT set_config('audit.member_uid',m.user_id::text,true)
FROM public.team_members m
WHERE m.team_id=current_setting('audit.team_id')::uuid
  AND NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
LIMIT 1;
SELECT set_config('audit.admin_uid',(SELECT a.user_id::text FROM public.admins a LIMIT 1),true);
SELECT set_config('audit.initial_stage',(SELECT current_stage::text FROM public.teams WHERE id=current_setting('audit.team_id')::uuid),true);
SELECT set_config('audit.initial_completed',(SELECT stages_completed::text FROM public.teams WHERE id=current_setting('audit.team_id')::uuid),true);
SELECT set_config('audit.initial_score',(SELECT score::text FROM public.teams WHERE id=current_setting('audit.team_id')::uuid),true);
SELECT set_config('audit.initial_submissions',(SELECT count(*)::text FROM public.submissions),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.member_uid'),true);
DO $test$
DECLARE v_team uuid := current_setting('audit.team_id')::uuid;
        v_stage integer := current_setting('audit.initial_stage')::integer;
        v_before integer; v_after integer; v_next integer;
BEGIN
  IF auth.uid() IS DISTINCT FROM current_setting('audit.member_uid')::uuid THEN
    RAISE EXCEPTION 'Member identity not applied';
  END IF;
  SELECT count(*) INTO v_before FROM public.tasks WHERE stage=v_stage AND NOT bonus;
  IF v_before<>5 THEN RAISE EXCEPTION 'Current stage should expose 5 main tasks, got %',v_before; END IF;
  SELECT count(*) INTO v_before FROM public.tasks WHERE stage=(v_stage%5)+1 AND NOT bonus;
  IF v_before<>0 THEN RAISE EXCEPTION 'Next stage exposed before HK approval'; END IF;
  BEGIN
    PERFORM public.hk_advance_team_stage(v_team);
    RAISE EXCEPTION 'FAIL: member advanced own stage';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kun HK%' THEN RAISE; END IF;
  END;
  IF (SELECT current_stage FROM public.teams WHERE id=v_team)<>v_stage THEN
    RAISE EXCEPTION 'Member call changed stage';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('audit.admin_uid'),true);
  v_next := public.hk_advance_team_stage(v_team);
  IF v_next<>(v_stage%5)+1 THEN RAISE EXCEPTION 'HK advanced to unexpected stage %',v_next; END IF;
  IF (SELECT stages_completed FROM public.teams WHERE id=v_team)
      <>current_setting('audit.initial_completed')::integer+1 THEN
    RAISE EXCEPTION 'Stage completed count not incremented';
  END IF;
  BEGIN
    PERFORM public.hk_advance_team_stage(v_team);
    RAISE EXCEPTION 'FAIL: HK advanced without two approvals in next stage';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'To hovedoppgaver%' THEN RAISE; END IF;
  END;
  IF (SELECT current_stage FROM public.teams WHERE id=v_team)<>v_next THEN
    RAISE EXCEPTION 'Rejected HK advance changed stage';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',current_setting('audit.member_uid'),true);
  SELECT count(*) INTO v_after FROM public.tasks WHERE stage=v_next AND NOT bonus;
  IF v_after<>5 THEN RAISE EXCEPTION 'Member cannot see next five tasks after HK advance'; END IF;
  IF (SELECT score FROM public.teams WHERE id=v_team)
      <>current_setting('audit.initial_score')::integer THEN
    RAISE EXCEPTION 'Stage advancement unexpectedly changed points';
  END IF;
  IF (SELECT count(*) FROM public.submissions)
      <>current_setting('audit.initial_submissions')::integer THEN
    RAISE EXCEPTION 'Stage test modified submissions';
  END IF;
END $test$;
SELECT 'PASS' result,
  'HK-only advancement; two-main-task gate; member visibility; points unchanged; rollback' scope;
ROLLBACK;

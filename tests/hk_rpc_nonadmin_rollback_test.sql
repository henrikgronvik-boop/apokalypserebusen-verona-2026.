-- Apokalypserebusen 2026: verify HK-only RPCs reject an ordinary team member.
-- Uses a real existing non-admin team identity with authenticated role, not an admin.
-- All checks are inside a transaction and always ROLLBACK. No secrets are printed.
-- Run this entire file in one SQL request. Requires at least one non-admin member.
-- This is a database privilege regression test, not a two-device E2E test.
BEGIN;
SELECT set_config('audit.uid',(
  SELECT m.user_id::text FROM public.team_members m
  WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
  LIMIT 1
),true);
SELECT set_config('audit.team_id',(SELECT id::text FROM public.teams ORDER BY id LIMIT 1),true);
SELECT set_config('audit.releases',(
  SELECT count(*)::text FROM public.tasks WHERE requires_release AND released_at IS NOT NULL
),true);
SELECT set_config('audit.team_state',(
  SELECT jsonb_agg(jsonb_build_object(
    'id',id,'current_stage',current_stage,'start_stage',start_stage,'stages_completed',stages_completed
  ) ORDER BY id)::text FROM public.teams
),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.uid'),true);
DO $audit$
DECLARE checked integer := 0;
BEGIN
  IF auth.uid() IS NULL OR EXISTS(SELECT 1 FROM public.admins WHERE user_id=auth.uid()) THEN
    RAISE EXCEPTION 'Test identity missing or is admin';
  END IF;
  BEGIN
    PERFORM public.hk_release_special('secret_mission');
    RAISE EXCEPTION 'UNEXPECTED: member released secret mission';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kun HK%' THEN RAISE; END IF;
    checked := checked+1;
  END;
  BEGIN
    PERFORM public.hk_advance_team_stage(current_setting('audit.team_id')::uuid);
    RAISE EXCEPTION 'UNEXPECTED: member advanced stage';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kun HK%' THEN RAISE; END IF;
    checked := checked+1;
  END;
  BEGIN
    PERFORM public.hk_set_team_stage(current_setting('audit.team_id')::uuid,3);
    RAISE EXCEPTION 'UNEXPECTED: member set start stage';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kun HK%' THEN RAISE; END IF;
    checked := checked+1;
  END;
  BEGIN
    PERFORM public.hk_rotate_team_code(current_setting('audit.team_id')::uuid);
    RAISE EXCEPTION 'UNEXPECTED: member rotated team code';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kun HK%' THEN RAISE; END IF;
    checked := checked+1;
  END;
  IF checked<>4 THEN RAISE EXCEPTION 'Expected 4 denied HK actions, got %',checked; END IF;
  IF (SELECT count(*) FROM public.tasks WHERE requires_release AND released_at IS NOT NULL)
     <>current_setting('audit.releases')::integer THEN
    RAISE EXCEPTION 'Release state changed';
  END IF;
  IF (SELECT jsonb_agg(jsonb_build_object(
       'id',id,'current_stage',current_stage,'start_stage',start_stage,'stages_completed',stages_completed
     ) ORDER BY id)::text FROM public.teams)<>current_setting('audit.team_state') THEN
    RAISE EXCEPTION 'Team progression changed';
  END IF;
END $audit$;
SELECT 'PASS' result,
       'Four HK-only RPCs reject non-admin team member; no release or progression changes' scope;
ROLLBACK;

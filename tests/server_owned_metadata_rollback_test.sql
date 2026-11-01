-- Run in Supabase SQL editor: all test inserts are rolled back.
-- A privileged SQL test verifies trigger behavior, NOT full client/RLS behavior.
BEGIN;
DO $test$
DECLARE
  v_team uuid;
  v_user uuid;
  v_task uuid;
  v_submission public.submissions%ROWTYPE;
  v_skip public.skip_requests%ROWTYPE;
BEGIN
  SELECT team_id, user_id INTO v_team, v_user
    FROM public.team_members WHERE team_id IS NOT NULL LIMIT 1;
  SELECT id INTO v_task FROM public.tasks
    WHERE special_key IS NULL AND bonus = false LIMIT 1;
  IF v_team IS NULL OR v_user IS NULL OR v_task IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED: requires one existing team member and main task';
  END IF;

  INSERT INTO public.submissions
    (team_id, task_id, user_id, note, status, awarded_points,
     created_at, reviewer_note, reviewed_at, reviewed_by)
  VALUES
    (v_team, v_task, v_user, 'ROLLBACK-ONLY timestamp test', 'pending', 0,
     '2001-01-01'::timestamptz, 'Forged HK approval',
     '2001-01-01'::timestamptz, v_user)
  RETURNING * INTO v_submission;

  IF abs(extract(epoch from (pg_catalog.clock_timestamp() - v_submission.created_at))) > 60
     OR v_submission.reviewer_note IS NOT NULL
     OR v_submission.reviewed_at IS NOT NULL
     OR v_submission.reviewed_by IS NOT NULL THEN
    RAISE EXCEPTION 'TEST FAILED: submission metadata was not server-owned';
  END IF;

  INSERT INTO public.skip_requests
    (team_id, task_id, user_id, status,
     created_at, reviewer_note, reviewed_at, reviewed_by)
  VALUES
    (v_team, v_task, v_user, 'pending',
     '2001-01-01'::timestamptz, 'Forged HK approval',
     '2001-01-01'::timestamptz, v_user)
  RETURNING * INTO v_skip;

  IF abs(extract(epoch from (pg_catalog.clock_timestamp() - v_skip.created_at))) > 60
     OR v_skip.reviewer_note IS NOT NULL
     OR v_skip.reviewed_at IS NOT NULL
     OR v_skip.reviewed_by IS NOT NULL THEN
    RAISE EXCEPTION 'TEST FAILED: skip metadata was not server-owned';
  END IF;

  RAISE NOTICE 'PASS: server timestamps and blank HK review fields on both insert paths';
END;
$test$;
ROLLBACK;

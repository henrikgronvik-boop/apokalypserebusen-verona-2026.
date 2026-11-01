-- Run manually in Supabase SQL editor. All temporary writes are rolled back.
-- Proves fixed-point validation at database level, not just in the HK UI.
BEGIN;
DO $test$
DECLARE
  v_team uuid;
  v_user uuid;
  v_task uuid;
  v_submission uuid;
  v_error text;
BEGIN
  SELECT m.team_id, m.user_id INTO v_team, v_user
    FROM public.team_members m LIMIT 1;
  SELECT t.id INTO v_task FROM public.tasks t
    WHERE t.special_key IS NULL AND t.bonus = false LIMIT 1;
  IF v_team IS NULL OR v_task IS NULL THEN
    RAISE EXCEPTION 'Test prerequisites missing';
  END IF;

  INSERT INTO public.submissions(team_id, task_id, user_id, status, awarded_points, note)
    VALUES (v_team, v_task, v_user, 'pending', 0, 'Temporary rollback-only fixed-points test')
    RETURNING id INTO v_submission;

  BEGIN
    UPDATE public.submissions SET status='approved', awarded_points=9999
      WHERE id=v_submission;
    RAISE EXCEPTION 'TEST FAILED: arbitrary approved points were accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT LIKE 'Godkjent oppgave må gi nøyaktig %' THEN
      RAISE EXCEPTION 'TEST FAILED: unexpected approved-points result: %', v_error;
    END IF;
  END;

  BEGIN
    UPDATE public.submissions SET status='rejected', awarded_points=10
      WHERE id=v_submission;
    RAISE EXCEPTION 'TEST FAILED: rejected points were accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error <> 'Avviste oppgaver skal gi 0 poeng' THEN
      RAISE EXCEPTION 'TEST FAILED: unexpected rejected-points result: %', v_error;
    END IF;
  END;

  UPDATE public.submissions SET status='rejected', awarded_points=0
    WHERE id=v_submission;
  IF NOT EXISTS (SELECT 1 FROM public.submissions
    WHERE id=v_submission AND status='rejected' AND awarded_points=0) THEN
    RAISE EXCEPTION 'TEST FAILED: valid rejection did not succeed';
  END IF;

  RAISE NOTICE 'PASS: wrong approved points rejected; wrong rejected points rejected; valid rejection accepted';
END;
$test$;
ROLLBACK;

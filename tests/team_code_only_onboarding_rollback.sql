-- Safe rollback-only regression: no name-only team creation or hijacking.
-- Both a new signed-in identity and an existing member must be rejected.
BEGIN;
SELECT set_config('audit.before_teams',(SELECT count(*)::text FROM public.teams),true);
SELECT set_config('audit.before_members',(SELECT count(*)::text FROM public.team_members),true);
SELECT set_config('audit.outsider',gen_random_uuid()::text,true);
SELECT set_config('audit.member',(SELECT user_id::text FROM public.team_members ORDER BY user_id LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  identity_uid uuid;
  actual_message text;
  checks integer := 0;
BEGIN
  IF nullif(current_setting('audit.member',true),'') IS NULL THEN
    RAISE EXCEPTION 'Existing member needed for test';
  END IF;
  FOREACH identity_uid IN ARRAY ARRAY[
    current_setting('audit.outsider',true)::uuid,
    current_setting('audit.member',true)::uuid
  ] LOOP
    PERFORM set_config('request.jwt.claim.sub',identity_uid::text,true);
    IF auth.uid() IS DISTINCT FROM identity_uid THEN
      RAISE EXCEPTION 'Test JWT identity mismatch';
    END IF;
    BEGIN
      PERFORM public.join_rebus_team_by_name('Lag 2');
      RAISE EXCEPTION 'SECURITY FAILURE: name-only joining succeeded';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_message = MESSAGE_TEXT;
      IF actual_message IS DISTINCT FROM 'Bruk lagkode fra HK for å bli med på laget' THEN
        RAISE EXCEPTION 'SECURITY FAILURE: unexpected rejection: %',actual_message;
      END IF;
    END;
    checks := checks+1;
  END LOOP;
  IF checks <> 2 THEN RAISE EXCEPTION 'Expected two denied attempts'; END IF;
  IF NOT has_function_privilege('authenticated','public.join_rebus_team_by_code(text)','EXECUTE') THEN
    RAISE EXCEPTION 'Code-based join unexpectedly inaccessible';
  END IF;
  RAISE NOTICE 'PASS: both name-only join attempts rejected; code join remains callable';
END
$test$;
RESET ROLE;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.teams)::text IS DISTINCT FROM current_setting('audit.before_teams',true)
    OR (SELECT count(*) FROM public.team_members)::text IS DISTINCT FROM current_setting('audit.before_members',true)
  THEN RAISE EXCEPTION 'SECURITY FAILURE: team or member count changed'; END IF;
  IF (SELECT prosecdef FROM pg_proc WHERE oid='public.join_rebus_team_by_name(text)'::regprocedure) THEN
    RAISE EXCEPTION 'SECURITY FAILURE: legacy RPC is still SECURITY DEFINER'; END IF;
END
$test$;
SELECT 'PASS' AS status, '2 denied name joins; no team/member changes; invoker-only legacy RPC' AS scope;
ROLLBACK;

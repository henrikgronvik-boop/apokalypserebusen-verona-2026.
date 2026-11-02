-- Security hardening: no unauthenticated/name-only team registration.
-- All three team slots already have HK-controlled hashed join codes.
-- Existing team memberships, scores, task definitions and codes are untouched.
-- Legacy clients receive a clear error instead of creating or claiming a team.
CREATE OR REPLACE FUNCTION public.join_rebus_team_by_name(p_team_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Bruk lagkode fra HK for å bli med på laget';
END;
$function$;

REVOKE ALL ON FUNCTION public.join_rebus_team_by_name(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_rebus_team_by_name(text) TO authenticated;
COMMENT ON FUNCTION public.join_rebus_team_by_name(text) IS
  'Disabled legacy name-only joining. Teams must join with HK-issued code via join_rebus_team_by_code.';

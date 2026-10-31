-- Additive, backwards-compatible team-code login for additional phones.
-- Private codes remain hashed in rebus_private.team_codes.
CREATE OR REPLACE FUNCTION public.join_rebus_team_by_code(p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_team uuid;
  v_existing uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Logg inn først'; END IF;
  IF EXISTS (SELECT 1 FROM public.admins WHERE user_id=v_uid) THEN
    RAISE EXCEPTION 'HK kan ikke bli med på et lag';
  END IF;
  IF p_code IS NULL OR pg_catalog.char_length(pg_catalog.btrim(p_code)) NOT BETWEEN 4 AND 128 THEN
    RAISE EXCEPTION 'Ugyldig lagkode';
  END IF;
  SELECT c.team_id INTO v_team
    FROM rebus_private.team_codes c
    WHERE c.code_hash=pg_catalog.encode(extensions.digest(pg_catalog.lower(pg_catalog.btrim(p_code)),'sha256'),'hex')
    LIMIT 1;
  IF v_team IS NULL THEN RAISE EXCEPTION 'Ugyldig lagkode'; END IF;
  SELECT m.team_id INTO v_existing FROM public.team_members m WHERE m.user_id=v_uid;
  IF v_existing IS NOT NULL AND v_existing<>v_team THEN
    RAISE EXCEPTION 'Du er allerede medlem av et annet lag';
  END IF;
  INSERT INTO public.team_members(user_id,team_id) VALUES (v_uid,v_team)
    ON CONFLICT (user_id) DO NOTHING;
  RETURN v_team;
END;
$function$;
REVOKE ALL ON FUNCTION public.join_rebus_team_by_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_rebus_team_by_code(text) TO authenticated;

-- Apokalypserebusen 2026: HK-controlled one-time team join codes.
-- Applied to Supabase project zvnqhiuipmnrrotuxkaa on 2026-10-31.
-- No existing codes are rotated by this migration.
CREATE OR REPLACE FUNCTION public.hk_rotate_team_code(p_team_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_code text;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admins a WHERE a.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Kun HK kan lage nye lagkoder';
  END IF;
  IF p_team_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.teams t WHERE t.id = p_team_id
  ) THEN
    RAISE EXCEPTION 'Ukjent lag';
  END IF;
  v_code := pg_catalog.encode(extensions.gen_random_bytes(10), 'hex');
  INSERT INTO rebus_private.team_codes (team_id, code_hash, created_at)
  VALUES (p_team_id, pg_catalog.encode(extensions.digest(v_code, 'sha256'), 'hex'), pg_catalog.now())
  ON CONFLICT (team_id) DO UPDATE
  SET code_hash = EXCLUDED.code_hash, created_at = EXCLUDED.created_at;
  RETURN v_code;
END;
$function$;
REVOKE ALL ON FUNCTION public.hk_rotate_team_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hk_rotate_team_code(uuid) TO authenticated;
COMMENT ON FUNCTION public.hk_rotate_team_code(uuid) IS 'HK-only: rotates a team join code, returns plaintext once; stores SHA-256 hash only.';

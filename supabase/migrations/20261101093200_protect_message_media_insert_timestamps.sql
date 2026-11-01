-- Apokalypserebusen: server-owned timestamps for chat and media metadata.
-- Applied to Supabase project zvnqhiuipmnrrotuxkaa on 2026-11-01.
-- No existing rows or storage objects are changed.
CREATE OR REPLACE FUNCTION rebus_private.set_server_owned_created_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  NEW.created_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER protect_message_insert_timestamp
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION rebus_private.set_server_owned_created_at();

CREATE TRIGGER protect_media_insert_timestamp
BEFORE INSERT ON public.media
FOR EACH ROW EXECUTE FUNCTION rebus_private.set_server_owned_created_at();

-- Regression: authenticated member cannot forge chat/media created_at.
-- Run as one SQL request. Test rows exist only inside the rolled-back transaction.
-- No storage object is uploaded; only temporary metadata is inserted.
-- This tests the database, not mobile/browser E2E.
BEGIN;
SELECT set_config('audit.uid',(SELECT user_id::text FROM public.team_members LIMIT 1),true);
SELECT set_config('audit.team',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.uid')),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.uid'),true);
WITH new_message AS (
 INSERT INTO public.messages(team_id,sender_id,content,created_at)
 VALUES (current_setting('audit.team')::uuid,current_setting('audit.uid')::uuid,
         'Temporary timestamp regression audit','2099-01-01 00:00:00+00'::timestamptz)
 RETURNING id
) SELECT set_config('audit.message',(SELECT id::text FROM new_message),true);
INSERT INTO public.media(team_id,message_id,storage_path,mime_type,created_at)
VALUES (current_setting('audit.team')::uuid,current_setting('audit.message')::uuid,
 current_setting('audit.team')||'/'||current_setting('audit.message')||'/'||gen_random_uuid()||'.png',
 'image/png','2099-01-01 00:00:00+00'::timestamptz);
DO $audit$
DECLARE msg_time timestamptz; media_time timestamptz;
BEGIN
 SELECT created_at INTO msg_time FROM public.messages WHERE id=current_setting('audit.message')::uuid;
 SELECT created_at INTO media_time FROM public.media WHERE message_id=current_setting('audit.message')::uuid;
 IF msg_time IS NULL OR media_time IS NULL THEN RAISE EXCEPTION 'Test rows invisible'; END IF;
 IF abs(extract(epoch FROM (pg_catalog.clock_timestamp()-msg_time)))>20 THEN RAISE EXCEPTION 'Message timestamp was spoofed'; END IF;
 IF abs(extract(epoch FROM (pg_catalog.clock_timestamp()-media_time)))>20 THEN RAISE EXCEPTION 'Media timestamp was spoofed'; END IF;
END $audit$;
SELECT 'PASS' AS result,'authenticated chat and media inserts use server time; all rows rolled back' AS scope;
ROLLBACK;

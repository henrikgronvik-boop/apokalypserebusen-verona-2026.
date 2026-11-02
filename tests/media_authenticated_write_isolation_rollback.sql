-- Authenticated media metadata isolation regression; synthetic rows rolled back.
-- No Storage objects, users or permanent data are created.
BEGIN;
SELECT set_config('audit.uid',m.user_id::text,true),set_config('audit.team',m.team_id::text,true)
FROM public.team_members m WHERE m.team_id IS NOT NULL
AND NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
ORDER BY m.user_id LIMIT 1;
SELECT set_config('audit.other',(SELECT id::text FROM public.teams
 WHERE id::text<>current_setting('audit.team',true) ORDER BY id LIMIT 1),true);
SELECT set_config('audit.hk',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.outsider',gen_random_uuid()::text,true);
SELECT set_config('audit.task',(SELECT t.id::text FROM public.tasks t
 JOIN public.teams tm ON tm.current_stage=t.stage
 WHERE tm.id::text=current_setting('audit.team',true) AND NOT t.bonus
 AND NOT EXISTS(SELECT 1 FROM public.submissions s WHERE s.team_id=tm.id
 AND s.task_id=t.id AND s.status='approved') ORDER BY t.position LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
 u uuid:=nullif(current_setting('audit.uid',true),'')::uuid;
 t uuid:=nullif(current_setting('audit.team',true),'')::uuid;
 other uuid:=nullif(current_setting('audit.other',true),'')::uuid;
 hk uuid:=nullif(current_setting('audit.hk',true),'')::uuid;
 outsider uuid:=nullif(current_setting('audit.outsider',true),'')::uuid;
 task uuid:=nullif(current_setting('audit.task',true),'')::uuid;
 own_msg uuid; other_msg uuid; own_media uuid; other_media uuid; pending uuid; changed uuid;
BEGIN
 IF u IS NULL OR t IS NULL OR other IS NULL OR hk IS NULL OR task IS NULL OR t=other OR u=hk
 THEN RAISE EXCEPTION 'Test identities or task unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 IF auth.uid() IS DISTINCT FROM u THEN RAISE EXCEPTION 'JWT mismatch'; END IF;
 INSERT INTO public.messages(team_id,sender_id,content) VALUES(t,u,'ROLLBACK media test')
 RETURNING id INTO own_msg;
 -- 1: own chat media metadata can be inserted and read.
 INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
 VALUES(t,own_msg,t||'/'||own_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg')
 RETURNING id INTO own_media;
 IF NOT EXISTS(SELECT 1 FROM public.media WHERE id=own_media)
 THEN RAISE EXCEPTION 'Own chat media not readable'; END IF;
 -- 2: own pending submission media metadata can be inserted.
 INSERT INTO public.submissions(team_id,task_id,user_id,note,status,awarded_points)
 VALUES(t,task,u,'ROLLBACK media test','pending',0) RETURNING id INTO pending;
 INSERT INTO public.media(team_id,submission_id,storage_path,mime_type)
 VALUES(t,pending,t||'/'||pending||'/'||gen_random_uuid()||'.png','image/png');
 -- 3: HK can attach media to a different team's chat.
 PERFORM set_config('request.jwt.claim.sub',hk::text,true);
 INSERT INTO public.messages(team_id,sender_id,content) VALUES(other,hk,'ROLLBACK HK media')
 RETURNING id INTO other_msg;
 INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
 VALUES(other,other_msg,other||'/'||other_msg||'/'||gen_random_uuid()||'.webp','image/webp')
 RETURNING id INTO other_media;
 IF NOT EXISTS(SELECT 1 FROM public.media WHERE id=other_media)
 THEN RAISE EXCEPTION 'HK media not readable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 -- 4: cross-team media invisible.
 IF EXISTS(SELECT 1 FROM public.media WHERE id=other_media)
 THEN RAISE EXCEPTION 'SECURITY FAILURE: cross-team media visible'; END IF;
 -- 5: cross-team metadata insertion denied.
 BEGIN
  INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
  VALUES(other,other_msg,other||'/'||other_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg');
  RAISE EXCEPTION 'SECURITY FAILURE: cross-team metadata inserted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- 6: forged parent path denied.
 BEGIN
  INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
  VALUES(t,own_msg,t||'/'||other_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg');
  RAISE EXCEPTION 'SECURITY FAILURE: mismatched media parent accepted';
 EXCEPTION WHEN check_violation OR insufficient_privilege THEN NULL; END;
 -- 7: team member cannot change or delete metadata.
 BEGIN
  UPDATE public.media SET mime_type='image/webp' WHERE id=own_media RETURNING id INTO changed;
  IF changed IS NOT NULL THEN RAISE EXCEPTION 'SECURITY FAILURE: metadata update allowed'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 changed:=NULL;
 BEGIN
  DELETE FROM public.media WHERE id=own_media RETURNING id INTO changed;
  IF changed IS NOT NULL THEN RAISE EXCEPTION 'SECURITY FAILURE: metadata deletion allowed'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- 8: unaffiliated authenticated user cannot read or insert.
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 IF EXISTS(SELECT 1 FROM public.media WHERE id IN (own_media,other_media))
 THEN RAISE EXCEPTION 'SECURITY FAILURE: outsider read media'; END IF;
 BEGIN
  INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
  VALUES(t,own_msg,t||'/'||own_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg');
  RAISE EXCEPTION 'SECURITY FAILURE: outsider inserted metadata';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
SELECT 'PASS' AS result,'8 authenticated media metadata RLS cases; rolled back' AS scope;
ROLLBACK;
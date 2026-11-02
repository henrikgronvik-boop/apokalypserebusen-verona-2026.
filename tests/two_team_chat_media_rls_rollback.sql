-- Two-team chat/media RLS regression: every fixture is rolled back.
-- Uses existing member and HK identities, plus synthetic rows in TWO teams.
-- No real users or Storage objects created; this is NOT two-phone E2E.
BEGIN;
SELECT set_config('audit.member_uid',(SELECT m.user_id::text FROM public.team_members m WHERE NOT EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id) ORDER BY m.user_id LIMIT 1),true);
SELECT set_config('audit.own_team',(SELECT m.team_id::text FROM public.team_members m WHERE m.user_id::text=current_setting('audit.member_uid',true) LIMIT 1),true);
SELECT set_config('audit.other_team',(SELECT t.id::text FROM public.teams t WHERE t.id::text<>current_setting('audit.own_team',true) ORDER BY t.id LIMIT 1),true);
SELECT set_config('audit.hk_uid',(SELECT a.user_id::text FROM public.admins a ORDER BY a.user_id LIMIT 1),true);
SELECT set_config('audit.outsider_uid',gen_random_uuid()::text,true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
 member_id uuid:=nullif(current_setting('audit.member_uid',true),'')::uuid;
 own_id uuid:=nullif(current_setting('audit.own_team',true),'')::uuid;
 other_id uuid:=nullif(current_setting('audit.other_team',true),'')::uuid;
 hk_id uuid:=nullif(current_setting('audit.hk_uid',true),'')::uuid;
 outsider_id uuid:=nullif(current_setting('audit.outsider_uid',true),'')::uuid;
 own_msg uuid; other_msg uuid; own_media uuid; other_media uuid; member_msg uuid; member_media uuid;
 checks integer:=0;
BEGIN
 IF member_id IS NULL OR own_id IS NULL OR other_id IS NULL OR hk_id IS NULL OR own_id=other_id OR member_id=hk_id THEN
   RAISE EXCEPTION 'Distinct real member, HK and team identities required';
 END IF;
 -- HK legitimately creates temporary chat and metadata in both teams.
 PERFORM set_config('request.jwt.claim.sub',hk_id::text,true);
 IF auth.uid() IS DISTINCT FROM hk_id THEN RAISE EXCEPTION 'HK JWT mismatch'; END IF;
 INSERT INTO public.messages(team_id,sender_id,content) VALUES
  (own_id,hk_id,'ROLLBACK ONLY: own-team HK message') RETURNING id INTO own_msg;
 INSERT INTO public.messages(team_id,sender_id,content) VALUES
  (other_id,hk_id,'ROLLBACK ONLY: other-team HK message') RETURNING id INTO other_msg;
 INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
 VALUES(own_id,own_msg,own_id||'/'||own_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg')
 RETURNING id INTO own_media;
 INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
 VALUES(other_id,other_msg,other_id||'/'||other_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg')
 RETURNING id INTO other_media;
 IF (SELECT count(*) FROM public.messages WHERE id IN(own_msg,other_msg))<>2
 OR (SELECT count(*) FROM public.media WHERE id IN(own_media,other_media))<>2
 THEN RAISE EXCEPTION 'HK positive control failed'; END IF;
 checks:=checks+2;
 -- The real member can see own team's fixtures but not the other team's.
 PERFORM set_config('request.jwt.claim.sub',member_id::text,true);
 IF auth.uid() IS DISTINCT FROM member_id THEN RAISE EXCEPTION 'Member JWT mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=own_msg) THEN RAISE EXCEPTION 'Own HK chat hidden'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.messages WHERE id=other_msg) THEN RAISE EXCEPTION 'Cross-team chat leaked'; END IF; checks:=checks+1;
 IF NOT EXISTS(SELECT 1 FROM public.media WHERE id=own_media) THEN RAISE EXCEPTION 'Own HK media hidden'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.media WHERE id=other_media) THEN RAISE EXCEPTION 'Cross-team media leaked'; END IF; checks:=checks+1;
 -- Positive control: own team chat and metadata remain writable.
 INSERT INTO public.messages(team_id,sender_id,content)
 VALUES(own_id,member_id,'ROLLBACK ONLY: own-team member message') RETURNING id INTO member_msg;
 IF NOT EXISTS(SELECT 1 FROM public.messages WHERE id=member_msg) THEN RAISE EXCEPTION 'Own chat not readable'; END IF; checks:=checks+1;
 INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
 VALUES(own_id,member_msg,own_id||'/'||member_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg')
 RETURNING id INTO member_media;
 IF NOT EXISTS(SELECT 1 FROM public.media WHERE id=member_media) THEN RAISE EXCEPTION 'Own media not readable'; END IF; checks:=checks+1;
 -- Negative control: cross-team writes are denied.
 BEGIN
  INSERT INTO public.messages(team_id,sender_id,content) VALUES(other_id,member_id,'ROLLBACK ONLY: forbidden cross-team chat');
  RAISE EXCEPTION 'Cross-team chat write unexpectedly allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 BEGIN
  INSERT INTO public.media(team_id,message_id,storage_path,mime_type)
  VALUES(other_id,other_msg,other_id||'/'||other_msg||'/'||gen_random_uuid()||'.jpg','image/jpeg');
  RAISE EXCEPTION 'Cross-team media write unexpectedly allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 -- Outsider must see neither team and cannot insert.
 PERFORM set_config('request.jwt.claim.sub',outsider_id::text,true);
 IF EXISTS(SELECT 1 FROM public.messages WHERE id IN(own_msg,other_msg,member_msg)) THEN RAISE EXCEPTION 'Outsider chat leak'; END IF; checks:=checks+1;
 IF EXISTS(SELECT 1 FROM public.media WHERE id IN(own_media,other_media,member_media)) THEN RAISE EXCEPTION 'Outsider media leak'; END IF; checks:=checks+1;
 BEGIN
  INSERT INTO public.messages(team_id,sender_id,content) VALUES(own_id,outsider_id,'ROLLBACK ONLY: outsider chat');
  RAISE EXCEPTION 'Outsider chat write unexpectedly allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; checks:=checks+1;
 -- HK must still see both teams after identity switches.
 PERFORM set_config('request.jwt.claim.sub',hk_id::text,true);
 IF (SELECT count(*) FROM public.messages WHERE id IN(own_msg,other_msg,member_msg))<>3 THEN RAISE EXCEPTION 'HK chat visibility broken'; END IF; checks:=checks+1;
 IF (SELECT count(*) FROM public.media WHERE id IN(own_media,other_media,member_media))<>3 THEN RAISE EXCEPTION 'HK media visibility broken'; END IF; checks:=checks+1;
 IF checks<>15 THEN RAISE EXCEPTION 'Expected 15 checks, got %',checks; END IF;
 RAISE NOTICE 'PASS: % two-team chat/media RLS checks, all fixtures rolled back',checks;
END $test$;
ROLLBACK;
SELECT 'PASS' AS status, '15 two-team chat/media RLS checks; all synthetic rows rolled back' AS scope;

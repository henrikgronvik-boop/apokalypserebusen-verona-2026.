-- Authenticated storage.objects RLS regression (metadata only; no file bytes).
-- Run this entire file as one transaction. All temporary rows are rolled back.
-- A SQL DELETE test is intentionally excluded: storage.protect_delete blocks
-- direct deletion. Test deletions later via the authorized Storage API.
-- Does NOT replace real mobile/browser upload tests.
BEGIN;
SELECT set_config('audit.member',(SELECT user_id::text FROM public.team_members m WHERE NOT EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id) LIMIT 1),true);
SELECT set_config('audit.team',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.member')),true);
SELECT set_config('audit.other_team',(SELECT id::text FROM public.teams WHERE id::text<>current_setting('audit.team') ORDER BY id LIMIT 1),true);
SELECT set_config('audit.admin',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.outsider',gen_random_uuid()::text,true);
DO $setup$ BEGIN
 IF nullif(current_setting('audit.member',true),'') IS NULL
 OR nullif(current_setting('audit.team',true),'') IS NULL
 OR nullif(current_setting('audit.other_team',true),'') IS NULL
 OR nullif(current_setting('audit.admin',true),'') IS NULL
 THEN RAISE EXCEPTION 'Missing required identities/teams'; END IF;
END $setup$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.member'),true);
WITH msg AS (
 INSERT INTO public.messages(team_id,sender_id,content)
 VALUES(current_setting('audit.team')::uuid,current_setting('audit.member')::uuid,'ROLLBACK ONLY storage objects policy test')
 RETURNING id
) SELECT set_config('audit.msg',(SELECT id::text FROM msg),true);
DO $test$
DECLARE own_path text:=current_setting('audit.team')||'/'||current_setting('audit.msg')||'/rollback-storage-test.webp';
 foreign_path text:=current_setting('audit.other_team')||'/'||current_setting('audit.msg')||'/rollback-storage-test.webp';
 invalid_parent text:=current_setting('audit.team')||'/'||gen_random_uuid()||'/rollback-storage-test.webp';
 invalid_depth text:=current_setting('audit.team')||'/rollback-storage-test.webp';
 n integer; checks integer:=0;
BEGIN
 IF auth.uid() IS DISTINCT FROM current_setting('audit.member')::uuid
 THEN RAISE EXCEPTION 'Wrong member JWT'; END IF;
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('rebus-bevis',own_path,current_setting('audit.member'));
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis' AND name=own_path;
 IF n<>1 THEN RAISE EXCEPTION 'Own chat upload not visible'; END IF;
 checks:=checks+1;
 BEGIN
   INSERT INTO storage.objects(bucket_id,name,owner_id)
   VALUES('rebus-bevis',foreign_path,current_setting('audit.member'));
   RAISE EXCEPTION 'SECURITY FAILURE: cross-team upload allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 checks:=checks+1;
 BEGIN
   INSERT INTO storage.objects(bucket_id,name,owner_id)
   VALUES('rebus-bevis',invalid_parent,current_setting('audit.member'));
   RAISE EXCEPTION 'SECURITY FAILURE: fake parent allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 checks:=checks+1;
 BEGIN
   INSERT INTO storage.objects(bucket_id,name,owner_id)
   VALUES('rebus-bevis',invalid_depth,current_setting('audit.member'));
   RAISE EXCEPTION 'SECURITY FAILURE: invalid folder depth allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 checks:=checks+1;
 UPDATE storage.objects SET name=own_path||'-changed'
 WHERE bucket_id='rebus-bevis' AND name=own_path;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>0 THEN RAISE EXCEPTION 'SECURITY FAILURE: team modified uploaded proof'; END IF;
 checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',current_setting('audit.outsider'),true);
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis' AND name=own_path;
 IF n<>0 THEN RAISE EXCEPTION 'SECURITY FAILURE: outsider read private proof'; END IF;
 checks:=checks+1;
 BEGIN
   INSERT INTO storage.objects(bucket_id,name,owner_id)
   VALUES('rebus-bevis',current_setting('audit.team')||'/'||current_setting('audit.msg')||'/outsider.webp',current_setting('audit.outsider'));
   RAISE EXCEPTION 'SECURITY FAILURE: outsider upload allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 checks:=checks+1;
 PERFORM set_config('request.jwt.claim.sub',current_setting('audit.admin'),true);
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis' AND name=own_path;
 IF n<>1 THEN RAISE EXCEPTION 'HK cannot read team proof'; END IF;
 checks:=checks+1;
 IF checks<>8 THEN RAISE EXCEPTION 'Expected 8 checks, got %',checks; END IF;
 RAISE NOTICE 'PASS: % storage.objects RLS checks; rollback-only',checks;
END $test$;
ROLLBACK;
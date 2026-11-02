-- Read-only RLS regression for live competition data. No INSERT/UPDATE/DELETE.
-- Covers member, outsider and HK across private rows, storage and unreleased tasks.
-- Empty tables/teams limit coverage: passing is not a complete E2E security proof.
BEGIN;
SELECT set_config('audit.member',(SELECT m.user_id::text FROM public.team_members m WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id) ORDER BY m.user_id LIMIT 1),true);
SELECT set_config('audit.team',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.member',true) LIMIT 1),true);
SELECT set_config('audit.hk',(SELECT user_id::text FROM public.admins ORDER BY user_id LIMIT 1),true);
SELECT set_config('audit.outsider',gen_random_uuid()::text,true);
DO $baseline$
DECLARE tbl text; n bigint; own bigint; team_id uuid:=nullif(current_setting('audit.team',true),'')::uuid;
BEGIN
 IF team_id IS NULL THEN RAISE EXCEPTION 'No existing member to test'; END IF;
 FOREACH tbl IN ARRAY ARRAY['submissions','media','messages','skip_requests','stage_unlocks'] LOOP
  EXECUTE format('SELECT count(*) FROM public.%I',tbl) INTO n;
  EXECUTE format('SELECT count(*) FROM public.%I WHERE team_id=$1',tbl) INTO own USING team_id;
  PERFORM set_config('audit.total_'||tbl,n::text,true);
  PERFORM set_config('audit.own_'||tbl,own::text,true);
 END LOOP;
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis';
 PERFORM set_config('audit.total_objects',n::text,true);
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis' AND split_part(name,'/',1)=team_id::text;
 PERFORM set_config('audit.own_objects',n::text,true);
 SELECT count(*) INTO n FROM public.tasks WHERE requires_release AND released_at IS NULL;
 PERFORM set_config('audit.unreleased',n::text,true);
END $baseline$;
SET LOCAL ROLE authenticated;
DO $rls$
DECLARE member_id uuid:=nullif(current_setting('audit.member',true),'')::uuid;
 hk_id uuid:=nullif(current_setting('audit.hk',true),'')::uuid;
 outsider_id uuid:=nullif(current_setting('audit.outsider',true),'')::uuid;
 label text; uid uuid; tbl text; actual bigint; expected bigint; checks int:=0;
BEGIN
 IF member_id IS NULL OR hk_id IS NULL OR outsider_id IS NULL OR member_id=hk_id
    OR outsider_id=member_id OR outsider_id=hk_id THEN RAISE EXCEPTION 'Distinct identities required'; END IF;
 FOR label,uid IN SELECT * FROM (VALUES ('member',member_id),('outsider',outsider_id),('hk',hk_id)) AS ids(label,uid) LOOP
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);
  IF auth.uid() IS DISTINCT FROM uid THEN RAISE EXCEPTION 'JWT mismatch for %',label; END IF;
  checks:=checks+1;
  FOREACH tbl IN ARRAY ARRAY['submissions','media','messages','skip_requests','stage_unlocks'] LOOP
   EXECUTE format('SELECT count(*) FROM public.%I',tbl) INTO actual;
   expected:=CASE label WHEN 'member' THEN current_setting('audit.own_'||tbl,true)::bigint WHEN 'hk' THEN current_setting('audit.total_'||tbl,true)::bigint ELSE 0 END;
   IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'RLS FAIL: % sees % rows in %, expected %',label,actual,tbl,expected; END IF;
   checks:=checks+1;
  END LOOP;
  SELECT count(*) INTO actual FROM storage.objects WHERE bucket_id='rebus-bevis';
  expected:=CASE label WHEN 'member' THEN current_setting('audit.own_objects',true)::bigint WHEN 'hk' THEN current_setting('audit.total_objects',true)::bigint ELSE 0 END;
  IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Storage RLS FAIL: % sees %, expected %',label,actual,expected; END IF;
  checks:=checks+1;
  SELECT count(*) INTO actual FROM public.tasks WHERE requires_release AND released_at IS NULL;
  expected:=CASE WHEN label='hk' THEN current_setting('audit.unreleased',true)::bigint ELSE 0 END;
  IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Task RLS FAIL: % sees %, expected %',label,actual,expected; END IF;
  checks:=checks+1;
 END LOOP;
 IF current_setting('audit.total_submissions',true)::bigint=0
 OR current_setting('audit.total_media',true)::bigint=0
 OR current_setting('audit.total_objects',true)::bigint=0 THEN RAISE EXCEPTION 'Missing positive-control rows'; END IF;
 IF checks<>24 THEN RAISE EXCEPTION 'Expected 24 checks, got %',checks; END IF;
 RAISE NOTICE 'PASS: 24 read-only RLS checks';
END $rls$;
ROLLBACK;
SELECT 'PASS' AS status, '24 identity/table/storage/task RLS checks; no data changed' AS scope;
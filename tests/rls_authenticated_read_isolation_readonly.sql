-- Read-only RLS regression for Apokalypserebusen 2026.
-- Impersonates a real member, a synthetic unjoined JWT subject, and real HK.
-- No database changes. Does not replace real two-account/mobile E2E testing.
-- Requires at least one member, one HK, and existing submission/storage evidence.
BEGIN READ ONLY;
SELECT set_config('audit.member_uid',m.user_id::text,true),
       set_config('audit.member_team',m.team_id::text,true)
FROM public.team_members m
WHERE NOT EXISTS(SELECT 1 FROM public.admins a WHERE a.user_id=m.user_id)
ORDER BY m.user_id LIMIT 1;
SELECT set_config('audit.admin_uid',(SELECT user_id::text FROM public.admins LIMIT 1),true);
SELECT set_config('audit.outsider_uid',gen_random_uuid()::text,true);
SELECT set_config('audit.expected_submissions',(SELECT count(*)::text FROM public.submissions),true);
SELECT set_config('audit.expected_media',(SELECT count(*)::text FROM public.media),true);
SELECT set_config('audit.expected_storage',(SELECT count(*)::text FROM storage.objects WHERE bucket_id='rebus-bevis'),true);
SELECT set_config('audit.expected_unlocks',(SELECT count(*)::text FROM public.stage_unlocks),true);
SELECT set_config('audit.expected_teams',(SELECT count(*)::text FROM public.teams),true);
SET LOCAL ROLE authenticated;
DO $audit$
DECLARE v_team uuid := current_setting('audit.member_team')::uuid;
        v_member uuid := current_setting('audit.member_uid')::uuid;
        v_admin uuid := current_setting('audit.admin_uid')::uuid;
        v_outsider uuid := current_setting('audit.outsider_uid')::uuid;
        n integer;
BEGIN
  IF v_member IS NULL OR v_admin IS NULL OR v_member=v_admin THEN
    RAISE EXCEPTION 'Need distinct member and admin identities';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  IF auth.uid() IS DISTINCT FROM v_member THEN RAISE EXCEPTION 'Member identity mismatch'; END IF;
  IF EXISTS(SELECT 1 FROM public.submissions WHERE team_id<>v_team)
     OR EXISTS(SELECT 1 FROM public.media WHERE team_id<>v_team)
     OR EXISTS(SELECT 1 FROM public.stage_unlocks WHERE team_id<>v_team)
     OR EXISTS(SELECT 1 FROM public.messages WHERE team_id<>v_team)
     OR EXISTS(SELECT 1 FROM public.skip_requests WHERE team_id<>v_team)
     OR EXISTS(SELECT 1 FROM public.team_members WHERE user_id<>v_member)
     OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='rebus-bevis'
          AND (storage.foldername(name))[1]<>v_team::text)
  THEN RAISE EXCEPTION 'Member can see another team private data'; END IF;
  SELECT count(*) INTO n FROM public.submissions;
  IF n<>(SELECT count(*) FROM public.submissions WHERE team_id=v_team) OR n=0
  THEN RAISE EXCEPTION 'Member submissions not accessible'; END IF;
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='rebus-bevis';
  IF n=0 OR n<>(SELECT count(*) FROM public.media WHERE team_id=v_team)
  THEN RAISE EXCEPTION 'Member evidence storage count mismatch'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_outsider::text,true);
  IF EXISTS(SELECT 1 FROM public.submissions) OR EXISTS(SELECT 1 FROM public.media)
     OR EXISTS(SELECT 1 FROM public.stage_unlocks) OR EXISTS(SELECT 1 FROM public.messages)
     OR EXISTS(SELECT 1 FROM public.skip_requests) OR EXISTS(SELECT 1 FROM public.team_members)
     OR EXISTS(SELECT 1 FROM public.tasks) OR EXISTS(SELECT 1 FROM public.admins)
     OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='rebus-bevis')
  THEN RAISE EXCEPTION 'Non-member can see private data'; END IF;
  SELECT count(*) INTO n FROM public.teams;
  IF n<>current_setting('audit.expected_teams')::integer
  THEN RAISE EXCEPTION 'Public scoreboard is unexpectedly hidden'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  IF auth.uid() IS DISTINCT FROM v_admin THEN RAISE EXCEPTION 'Admin identity mismatch'; END IF;
  IF (SELECT count(*) FROM public.tasks)<>34
     OR (SELECT count(*) FROM public.submissions)<>current_setting('audit.expected_submissions')::integer
     OR (SELECT count(*) FROM public.media)<>current_setting('audit.expected_media')::integer
     OR (SELECT count(*) FROM public.stage_unlocks)<>current_setting('audit.expected_unlocks')::integer
     OR (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis')<>current_setting('audit.expected_storage')::integer
  THEN RAISE EXCEPTION 'HK cannot see complete competition data'; END IF;
END $audit$;
SELECT 'PASS' AS result, 'Member isolation; non-member denial; HK visibility; private storage' AS scope;
ROLLBACK;

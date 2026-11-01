-- Apokalypserebusen 2026: role-aware, read-only RLS regression test.
-- Runs as authenticated with a real team member, HK, then an unassigned identity.
-- Reads production rows only; no inserts, updates, deletes or persistent objects.
-- Entire session state is discarded with ROLLBACK.
-- This is not a browser or two-device E2E test.
BEGIN;
SELECT set_config('audit.member_uid', (SELECT user_id::text FROM public.team_members ORDER BY user_id LIMIT 1), true);
SELECT set_config('audit.member_team', (SELECT team_id::text FROM public.team_members ORDER BY user_id LIMIT 1), true);
SELECT set_config('audit.admin_uid', (SELECT user_id::text FROM public.admins ORDER BY user_id LIMIT 1), true);
SELECT set_config('audit.own_subs', (SELECT count(*)::text FROM public.submissions WHERE team_id::text=current_setting('audit.member_team')), true);
SELECT set_config('audit.own_media', (SELECT count(*)::text FROM public.media WHERE team_id::text=current_setting('audit.member_team')), true);
SELECT set_config('audit.own_unlocks', (SELECT count(*)::text FROM public.stage_unlocks WHERE team_id::text=current_setting('audit.member_team')), true);
SELECT set_config('audit.all_subs', (SELECT count(*)::text FROM public.submissions), true);
SELECT set_config('audit.all_media', (SELECT count(*)::text FROM public.media), true);
SELECT set_config('audit.all_tasks', (SELECT count(*)::text FROM public.tasks), true);
SELECT set_config('audit.all_members', (SELECT count(*)::text FROM public.team_members), true);
SELECT set_config('audit.all_unlocks', (SELECT count(*)::text FROM public.stage_unlocks), true);
SELECT set_config('audit.all_teams', (SELECT count(*)::text FROM public.teams), true);
SELECT set_config('audit.all_storage', (SELECT count(*)::text FROM storage.objects WHERE bucket_id='rebus-bevis'), true);
SELECT set_config('audit.own_storage', (SELECT count(*)::text FROM storage.objects WHERE bucket_id='rebus-bevis' AND split_part(name,'/',1)=current_setting('audit.member_team')), true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('audit.member_uid'), true);
DO $member$
BEGIN
 IF auth.uid()::text <> current_setting('audit.member_uid') THEN RAISE EXCEPTION 'member identity mismatch'; END IF;
 IF (SELECT count(*) FROM public.team_members) <> 1 THEN RAISE EXCEPTION 'member sees other membership'; END IF;
 IF (SELECT count(*) FROM public.admins) <> 0 THEN RAISE EXCEPTION 'member sees admin identities'; END IF;
 IF (SELECT count(*) FROM public.teams) <> current_setting('audit.all_teams')::int THEN RAISE EXCEPTION 'member scoreboard access changed'; END IF;
 IF (SELECT count(*) FROM public.submissions) <> current_setting('audit.own_subs')::int THEN RAISE EXCEPTION 'member submissions leak or missing'; END IF;
 IF (SELECT count(*) FROM public.media) <> current_setting('audit.own_media')::int THEN RAISE EXCEPTION 'member media metadata leak or missing'; END IF;
 IF (SELECT count(*) FROM public.stage_unlocks) <> current_setting('audit.own_unlocks')::int THEN RAISE EXCEPTION 'member unlock leak or missing'; END IF;
 IF EXISTS (SELECT 1 FROM public.tasks WHERE requires_release AND released_at IS NULL) THEN RAISE EXCEPTION 'unreleased task visible to member'; END IF;
 IF (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis') <> current_setting('audit.own_storage')::int THEN RAISE EXCEPTION 'member storage isolation failed'; END IF;
END $member$;
SELECT set_config('request.jwt.claim.sub', current_setting('audit.admin_uid'), true);
DO $admin$
BEGIN
 IF (SELECT count(*) FROM public.admins) <> 1 THEN RAISE EXCEPTION 'HK identity missing'; END IF;
 IF (SELECT count(*) FROM public.team_members) <> current_setting('audit.all_members')::int THEN RAISE EXCEPTION 'HK membership visibility failed'; END IF;
 IF (SELECT count(*) FROM public.tasks) <> current_setting('audit.all_tasks')::int THEN RAISE EXCEPTION 'HK tasks visibility failed'; END IF;
 IF (SELECT count(*) FROM public.submissions) <> current_setting('audit.all_subs')::int THEN RAISE EXCEPTION 'HK submissions visibility failed'; END IF;
 IF (SELECT count(*) FROM public.media) <> current_setting('audit.all_media')::int THEN RAISE EXCEPTION 'HK media visibility failed'; END IF;
 IF (SELECT count(*) FROM public.stage_unlocks) <> current_setting('audit.all_unlocks')::int THEN RAISE EXCEPTION 'HK unlock visibility failed'; END IF;
 IF (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis') <> current_setting('audit.all_storage')::int THEN RAISE EXCEPTION 'HK storage visibility failed'; END IF;
END $admin$;
SELECT set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
DO $outsider$
BEGIN
 IF (SELECT count(*) FROM public.teams) <> current_setting('audit.all_teams')::int THEN RAISE EXCEPTION 'scoreboard unexpectedly hidden'; END IF;
 IF (SELECT count(*) FROM public.admins) <> 0 THEN RAISE EXCEPTION 'outsider sees admin'; END IF;
 IF (SELECT count(*) FROM public.team_members) <> 0 THEN RAISE EXCEPTION 'outsider sees members'; END IF;
 IF (SELECT count(*) FROM public.tasks) <> 0 THEN RAISE EXCEPTION 'outsider sees tasks'; END IF;
 IF (SELECT count(*) FROM public.submissions) <> 0 THEN RAISE EXCEPTION 'outsider sees submissions'; END IF;
 IF (SELECT count(*) FROM public.media) <> 0 THEN RAISE EXCEPTION 'outsider sees media'; END IF;
 IF (SELECT count(*) FROM public.stage_unlocks) <> 0 THEN RAISE EXCEPTION 'outsider sees unlocks'; END IF;
 IF (SELECT count(*) FROM public.messages) <> 0 THEN RAISE EXCEPTION 'outsider sees messages'; END IF;
 IF (SELECT count(*) FROM public.skip_requests) <> 0 THEN RAISE EXCEPTION 'outsider sees skip requests'; END IF;
 IF (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis') <> 0 THEN RAISE EXCEPTION 'outsider sees private storage'; END IF;
END $outsider$;
SELECT 'PASS' AS result, 'member / HK / unassigned authenticated read isolation' AS scope;
ROLLBACK;
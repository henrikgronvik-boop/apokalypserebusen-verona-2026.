-- Apokalypserebusen 2026: cross-team RLS regression with a rollback.
-- Requires an existing team member, a second team, and authenticated role.
-- Temporarily changes one membership INSIDE a transaction to simulate another team.
-- The final ROLLBACK restores the original membership. No test users or media are created.
-- This is a database-role test, NOT an actual two-phone or browser E2E test.
-- Run the entire script as a single SQL request; do not run individual statements.
BEGIN;
SELECT set_config('audit.uid',(SELECT user_id::text FROM public.team_members LIMIT 1),true);
SELECT set_config('audit.original_team',(SELECT team_id::text FROM public.team_members WHERE user_id::text=current_setting('audit.uid')),true);
SELECT set_config('audit.other_team',(SELECT id::text FROM public.teams WHERE id::text<>current_setting('audit.original_team') ORDER BY name LIMIT 1),true);
SELECT set_config('audit.original_subs',(SELECT count(*)::text FROM public.submissions WHERE team_id::text=current_setting('audit.original_team')),true);
SELECT set_config('audit.original_media',(SELECT count(*)::text FROM public.media WHERE team_id::text=current_setting('audit.original_team')),true);
SELECT set_config('audit.other_subs',(SELECT count(*)::text FROM public.submissions WHERE team_id::text=current_setting('audit.other_team')),true);
SELECT set_config('audit.other_media',(SELECT count(*)::text FROM public.media WHERE team_id::text=current_setting('audit.other_team')),true);
SELECT set_config('audit.other_unlocks',(SELECT count(*)::text FROM public.stage_unlocks WHERE team_id::text=current_setting('audit.other_team')),true);
SELECT set_config('audit.original_storage',(SELECT count(*)::text FROM storage.objects WHERE bucket_id='rebus-bevis' AND split_part(name,'/',1)=current_setting('audit.original_team')),true);
SELECT set_config('audit.other_storage',(SELECT count(*)::text FROM storage.objects WHERE bucket_id='rebus-bevis' AND split_part(name,'/',1)=current_setting('audit.other_team')),true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('audit.uid'),true);
DO $check_original$
BEGIN
 IF current_setting('audit.uid',true) IS NULL OR current_setting('audit.other_team',true) IS NULL THEN RAISE EXCEPTION 'Missing test identities'; END IF;
 IF (SELECT count(*) FROM public.team_members)<>1 THEN RAISE EXCEPTION 'Member sees unexpected memberships'; END IF;
 IF (SELECT count(*) FROM public.submissions)<>current_setting('audit.original_subs')::int THEN RAISE EXCEPTION 'Original team submission visibility incorrect'; END IF;
 IF (SELECT count(*) FROM public.media)<>current_setting('audit.original_media')::int THEN RAISE EXCEPTION 'Original team media visibility incorrect'; END IF;
 IF (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis')<>current_setting('audit.original_storage')::int THEN RAISE EXCEPTION 'Original team storage visibility incorrect'; END IF;
END $check_original$;
RESET ROLE;
UPDATE public.team_members SET team_id=current_setting('audit.other_team')::uuid WHERE user_id=current_setting('audit.uid')::uuid;
SET LOCAL ROLE authenticated;
DO $check_other$
BEGIN
 IF (SELECT count(*) FROM public.team_members WHERE team_id::text=current_setting('audit.other_team'))<>1 THEN RAISE EXCEPTION 'Moved member cannot see own membership'; END IF;
 IF EXISTS (SELECT 1 FROM public.team_members WHERE team_id::text=current_setting('audit.original_team')) THEN RAISE EXCEPTION 'Original membership remains visible'; END IF;
 IF (SELECT count(*) FROM public.submissions)<>current_setting('audit.other_subs')::int THEN RAISE EXCEPTION 'Cross-team submission leak'; END IF;
 IF (SELECT count(*) FROM public.media)<>current_setting('audit.other_media')::int THEN RAISE EXCEPTION 'Cross-team media metadata leak'; END IF;
 IF (SELECT count(*) FROM public.stage_unlocks)<>current_setting('audit.other_unlocks')::int THEN RAISE EXCEPTION 'Cross-team stage unlock leak'; END IF;
 IF (SELECT count(*) FROM storage.objects WHERE bucket_id='rebus-bevis')<>current_setting('audit.other_storage')::int THEN RAISE EXCEPTION 'Cross-team storage leak'; END IF;
END $check_other$;
SELECT 'PASS' as result, 'same authenticated identity: original team then other team (rolled back)' as scope;
ROLLBACK;

-- Read-only integrity checks, verified against Supabase 2026-11-03.
-- Every column should be true. Run with maintenance privileges.
-- These checks do NOT simulate authenticated users or prove RLS isolation.
-- In particular, an empty table may make a consistency check vacuously true.
select
 (select count(*) from public.tasks)=34 as tasks_34,
 (select count(*) from public.tasks where bonus=false)=25 as main_25,
 (select count(*) from public.tasks where bonus=true)=9 as bonus_9,
 (select count(*) from public.tasks where special_key is not null and bonus=true)=6 as specials_bonus_6,
 (select count(*) from public.tasks where special_key is not null and requires_release=true)=2 as hk_release_2,
 (select count(*) from public.media m join public.submissions s on s.id=m.submission_id where m.team_id is distinct from s.team_id)=0 as media_submission_team_match,
 (select count(*) from public.media m join public.messages c on c.id=m.message_id where m.team_id is distinct from c.team_id)=0 as media_message_team_match,
 (select count(*) from public.submissions s join public.tasks t on t.id=s.task_id where s.status='approved' and s.awarded_points<0)=0 as no_negative_awards,
 (select count(*) from public.skip_requests k join public.tasks t on t.id=k.task_id where t.bonus=true)=0 as no_bonus_skip_requests,
 (select count(*) from public.tasks where requires_release=true and released_at is not null)=0 as no_released_manual_tasks;

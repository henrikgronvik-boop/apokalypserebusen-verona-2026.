-- Read-only competition invariants, verified against Supabase on 2026-11-03.
-- Run as a privileged maintenance role; these checks do NOT prove team-level RLS.
-- Every column should be true. Do not change competition data to make tests pass.
select
  (select count(*) from public.tasks)=34 as total_34,
  (select count(*) from public.tasks where bonus=false)=25 as main_25,
  (select count(*) from public.tasks where bonus=true)=9 as bonus_9,
  (select count(*) from public.tasks where special_key is not null)=6 as special_6,
  (select count(*) from public.tasks where special_key is not null and bonus=true)=6 as specials_excluded,
  (select count(*) from public.tasks where special_key is not null and points>0)=6 as special_positive,
  (select count(*) from public.tasks where special_key is not null and requires_release=true)=2 as manual_release_two,
  (select count(*) from public.tasks where special_key is not null and requires_release and released_at is not null)=0 as no_manual_released,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in
      ('teams','admins','team_members','tasks','stage_unlocks','submissions','skip_requests','messages','media')
      and c.relrowsecurity)=9 as nine_rls;

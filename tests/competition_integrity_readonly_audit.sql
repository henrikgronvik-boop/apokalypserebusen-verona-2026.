-- Apokalypserebusen 2026: read-only competition integrity audit.
-- All checks are SELECT-only. No role impersonation, data writes or security bypass.
-- This is a configuration/data audit, NOT a substitute for two-device E2E testing.
WITH expected_special(key,stage,title,points,needs_release,after_finish) AS (
  VALUES
    ('perfect_reconstruction',2,'Den perfekte rekonstruksjonen',600,false,false),
    ('recruit_italian',2,'Rekrutter en italiener',500,false,false),
    ('italian_charm',3,'Italiensk sjarm',400,false,false),
    ('secret_mission',4,'Hemmelig oppdrag',750,true,false),
    ('music_video',4,'Musikkvideo',800,false,false),
    ('grand_finale',5,'Den store finalen',1500,true,true)
),
task_counts AS (
 SELECT count(*) total, count(*) FILTER(WHERE NOT bonus) main,
        count(*) FILTER(WHERE bonus AND special_key IS NULL) legacy_bonus,
        count(*) FILTER(WHERE bonus AND special_key IS NOT NULL) new_special
 FROM public.tasks
),
checks AS (
 SELECT 1 id, 'Exactly 34 tasks' test, (SELECT total=34 FROM task_counts) passed
 UNION ALL SELECT 2,'25 original main tasks preserved',(SELECT main=25 FROM task_counts)
 UNION ALL SELECT 3,'Three legacy bonuses preserved',(SELECT legacy_bonus=3 FROM task_counts)
 UNION ALL SELECT 4,'Exactly six new specials',(SELECT new_special=6 FROM task_counts)
 UNION ALL SELECT 5,'Five main tasks in each of five stages',
   (SELECT count(*)=5 AND bool_and(n=5) FROM (SELECT stage,count(*) n FROM public.tasks WHERE NOT bonus GROUP BY stage) x)
 UNION ALL SELECT 6,'All six specials match title, stage, points and release flags',
   (SELECT count(*)=6 AND bool_and(t.bonus AND t.stage=e.stage AND t.title=e.title
      AND t.points=e.points AND t.requires_release=e.needs_release AND t.post_finish=e.after_finish)
    FROM expected_special e JOIN public.tasks t ON t.special_key=e.key)
 UNION ALL SELECT 7,'Exactly two HK-controlled releases',
   (SELECT count(*)=2 FROM public.tasks WHERE requires_release)
 UNION ALL SELECT 8,'Reconstruction bonus of 200 documented',
   (SELECT description LIKE '%200%' AND description LIKE '%600%' FROM public.tasks WHERE special_key='perfect_reconstruction')
 UNION ALL SELECT 9,'Italian recruitment explicitly requires consent',
   (SELECT description ILIKE '%samtykke%' FROM public.tasks WHERE special_key='recruit_italian')
 UNION ALL SELECT 10,'Italian charm requires video',
   (SELECT description ILIKE '%video%' FROM public.tasks WHERE special_key='italian_charm')
 UNION ALL SELECT 11,'Secret mission has 30-minute HK deadline',
   (SELECT description LIKE '%30 minutter%' AND description ILIKE '%HK%' FROM public.tasks WHERE special_key='secret_mission')
 UNION ALL SELECT 12,'Music video needs three locations and at least 30 seconds',
   (SELECT description ILIKE '%tre ulike steder%' AND description LIKE '%30 sekunder%' FROM public.tasks WHERE special_key='music_video')
 UNION ALL SELECT 13,'Finale has three clues and five-letter code',
   (SELECT description LIKE '%GÅTE 1%' AND description LIKE '%GÅTE 2%'
     AND description LIKE '%GÅTE 3%' AND description LIKE '%FEM bokstaver%'
     FROM public.tasks WHERE special_key='grand_finale')
 UNION ALL SELECT 14,'HK stage advancement excludes bonuses',
   (SELECT pg_get_functiondef('public.hk_advance_team_stage(uuid)'::regprocedure) LIKE '%not t.bonus%')
 UNION ALL SELECT 15,'Legacy stage eligibility excludes bonuses',
   (SELECT pg_get_functiondef('public.rebus_stage_eligible(uuid,integer)'::regprocedure) LIKE '%not t.bonus%')
 UNION ALL SELECT 16,'Team score uses highest award per task, not duplicate sums',
   (SELECT pg_get_functiondef('rebus_private.recalculate_score()'::regprocedure) LIKE '%max(s.awarded_points)%')
 UNION ALL SELECT 17,'Only one approved submission per team/task',
   (SELECT count(*)=1 FROM pg_indexes WHERE schemaname='public' AND tablename='submissions'
      AND indexname='one_approved_proof_per_task' AND indexdef LIKE '%UNIQUE%')
 UNION ALL SELECT 18,'Only one pending submission per team/task',
   (SELECT count(*)=1 FROM pg_indexes WHERE schemaname='public' AND tablename='submissions'
      AND indexname='rebus_one_pending_submission_per_team_task' AND indexdef LIKE '%UNIQUE%')
 UNION ALL SELECT 19,'All nine competition tables have RLS',
   (SELECT count(*)=9 AND bool_and(c.relrowsecurity)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname IN
     ('teams','admins','team_members','tasks','stage_unlocks','submissions','skip_requests','messages','media'))
 UNION ALL SELECT 20,'Task visibility checks HK release',
   (SELECT count(*)=1 AND bool_and(qual LIKE '%released_at IS NOT NULL%')
    FROM pg_policies WHERE schemaname='public' AND tablename='tasks' AND policyname='task_visibility')
 UNION ALL SELECT 21,'Submission insert checks release and final-stage eligibility',
   (SELECT count(*)=1 AND bool_and(with_check LIKE '%released_at IS NOT NULL%'
      AND with_check LIKE '%stages_completed = 5%')
    FROM pg_policies WHERE schemaname='public' AND tablename='submissions' AND policyname='team_submission')
 UNION ALL SELECT 22,'Private media bucket with 50 MB limit',
   (SELECT count(*)=1 AND bool_and(NOT public AND file_size_limit=52428800)
    FROM storage.buckets WHERE id='rebus-bevis')
 UNION ALL SELECT 23,'Finale and reconstruction prizes have unique-award locking',
   (SELECT pg_get_functiondef('rebus_private.enforce_unique_special_awards()'::regprocedure)
     LIKE '%pg_advisory_xact_lock(20261031, 1500)%'
     AND pg_get_functiondef('rebus_private.enforce_unique_special_awards()'::regprocedure)
     LIKE '%pg_advisory_xact_lock(20261031, 800)%')
)
SELECT id,test,CASE WHEN COALESCE(passed,false) THEN 'PASS' ELSE 'FAIL' END status
FROM checks ORDER BY id;

-- Read-only regression check for the 31 October task decisions.
-- Returns one row per invariant; all must be true. No competition data is changed.
WITH expected(special_key,stage,title,points,release_required,after_finish) AS (
 VALUES
 ('perfect_reconstruction',2,'Den perfekte rekonstruksjonen',600,false,false),
 ('recruit_italian',2,'Rekrutter en italiener',500,false,false),
 ('italian_charm',3,'Italiensk sjarm',400,false,false),
 ('secret_mission',4,'Hemmelig oppdrag',750,true,false),
 ('music_video',4,'Musikkvideo',800,false,false),
 ('grand_finale',5,'Den store finalen',1500,true,true)
), checks AS (
 SELECT '34 tasks total' AS invariant, count(*)=34 AS passed FROM public.tasks
 UNION ALL SELECT '25 main tasks',count(*) FILTER (WHERE NOT bonus)=25 FROM public.tasks
 UNION ALL SELECT '3 original bonuses',count(*) FILTER (WHERE bonus AND special_key IS NULL)=3 FROM public.tasks
 UNION ALL SELECT '6 special tasks',count(*) FILTER (WHERE bonus AND special_key IS NOT NULL)=6 FROM public.tasks
 UNION ALL SELECT 'all six exact specifications',NOT EXISTS (
   SELECT 1 FROM expected e LEFT JOIN public.tasks t ON t.special_key=e.special_key
   WHERE t.id IS NULL OR t.stage IS DISTINCT FROM e.stage
     OR t.title IS DISTINCT FROM e.title OR t.points IS DISTINCT FROM e.points
     OR t.bonus IS DISTINCT FROM true
     OR t.requires_release IS DISTINCT FROM e.release_required
     OR t.post_finish IS DISTINCT FROM e.after_finish
 )
 UNION ALL SELECT 'no unexpected special keys',NOT EXISTS (
   SELECT 1 FROM public.tasks t WHERE t.special_key IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM expected e WHERE e.special_key=t.special_key)
 )
 UNION ALL SELECT 'special keys unique',NOT EXISTS (
   SELECT 1 FROM public.tasks WHERE special_key IS NOT NULL
   GROUP BY special_key HAVING count(*) <> 1
 )
 UNION ALL SELECT 'all tasks have positive points',NOT EXISTS (
   SELECT 1 FROM public.tasks WHERE points IS NULL OR points <= 0
 )
 UNION ALL SELECT 'specials never count toward 2-of-5',NOT EXISTS (
   SELECT 1 FROM public.tasks WHERE special_key IS NOT NULL AND bonus IS DISTINCT FROM true
 )
)
SELECT invariant,passed FROM checks ORDER BY invariant;

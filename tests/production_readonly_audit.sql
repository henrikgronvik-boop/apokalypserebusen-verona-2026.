-- Apokalypserebusen 2026: read-only production audit.
-- No inserts, updates, deletes, DDL, or test accounts. Safe to rerun.
WITH approved_best AS (
  SELECT team_id, task_id, max(awarded_points) AS points
  FROM public.submissions WHERE status = 'approved'
  GROUP BY team_id, task_id
), expected_scores AS (
  SELECT t.id, t.score, coalesce(sum(a.points), 0)::integer AS expected
  FROM public.teams t LEFT JOIN approved_best a ON a.team_id = t.id
  GROUP BY t.id, t.score
), checks AS (
  SELECT 1 AS id, '34 oppgaver totalt' AS test,
    (SELECT count(*) = 34 FROM public.tasks) AS passed
  UNION ALL SELECT 2, '25 hovedoppgaver',
    (SELECT count(*) = 25 FROM public.tasks WHERE bonus IS FALSE)
  UNION ALL SELECT 3, '3 opprinnelige bonusoppgaver',
    (SELECT count(*) = 3 FROM public.tasks WHERE bonus IS TRUE AND special_key IS NULL)
  UNION ALL SELECT 4, '6 nye spesialoppdrag med riktige nøkler',
    (SELECT count(*) = 6 AND count(DISTINCT special_key) = 6
       AND bool_and(bonus IS TRUE)
       AND array_agg(special_key ORDER BY special_key) =
           ARRAY['grand_finale','italian_charm','music_video',
                 'perfect_reconstruction','recruit_italian','secret_mission']::text[]
     FROM public.tasks WHERE special_key IS NOT NULL)
  UNION ALL SELECT 5, '5 hovedoppgaver i hver av 5 deler',
    (SELECT count(*) = 5 AND bool_and(n = 5)
     FROM (SELECT stage, count(*) AS n FROM public.tasks
           WHERE bonus IS FALSE GROUP BY stage) stage_counts)
  UNION ALL SELECT 6, 'Nøyaktig 3 lag',
    (SELECT count(*) = 3 FROM public.teams)
  UNION ALL SELECT 7, 'Poengtavle samsvarer med beste godkjente resultat per oppgave',
    (SELECT coalesce(bool_and(score = expected), true) FROM expected_scores)
  UNION ALL SELECT 8, 'Alle mediefiler tilhører riktig lag og forelder',
    (SELECT coalesce(bool_and(
       (m.submission_id IS NOT NULL AND m.message_id IS NULL
          AND s.team_id = m.team_id)
       OR (m.message_id IS NOT NULL AND m.submission_id IS NULL
          AND msg.team_id = m.team_id)), true)
     FROM public.media m
     LEFT JOIN public.submissions s ON s.id = m.submission_id
     LEFT JOIN public.messages msg ON msg.id = m.message_id)
  UNION ALL SELECT 9, 'Mediefilers lag- og forelder-ID samsvarer med filbanen',
    (SELECT coalesce(bool_and(
       split_part(m.storage_path, '/', 1) = m.team_id::text
       AND split_part(m.storage_path, '/', 2) =
         coalesce(m.submission_id, m.message_id)::text), true)
     FROM public.media m)
  UNION ALL SELECT 10, 'Maks én finalevinner og én rekonstruksjonsbonus',
    (SELECT
       (SELECT count(*) FROM public.submissions s JOIN public.tasks t ON t.id=s.task_id
        WHERE t.special_key='grand_finale' AND s.status='approved' AND s.awarded_points=1500) <= 1
       AND
       (SELECT count(*) FROM public.submissions s JOIN public.tasks t ON t.id=s.task_id
        WHERE t.special_key='perfect_reconstruction' AND s.status='approved' AND s.awarded_points=800) <= 1)
  UNION ALL SELECT 11, 'Lag har gyldig startdel, aktiv del og fremdrift',
    (SELECT coalesce(bool_and(
       start_stage BETWEEN 1 AND 5 AND current_stage BETWEEN 1 AND 5
       AND stages_completed BETWEEN 0 AND 5
       AND (stages_completed = 5 OR
            current_stage = ((start_stage - 1 + stages_completed) % 5) + 1)
     ), true) FROM public.teams)
  UNION ALL SELECT 12, 'RLS aktivert på alle 9 offentlige rebus-tabeller',
    (SELECT count(*) = 9 AND bool_and(c.relrowsecurity)
     FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname IN
       ('teams','admins','team_members','tasks','stage_unlocks',
        'submissions','skip_requests','messages','media')
       AND c.relkind IN ('r','p'))
)
SELECT id, test, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks ORDER BY id;

-- Apokalypserebusen 2026: read-only finale regression audit.
-- No clues or solution are stored in this public repository.
-- Safe before and after HK releases the finale. Does not change data.
WITH checks AS (
  SELECT 1 AS id, 'Nøyaktig én finale med 1500 poeng' AS test,
    (SELECT count(*) = 1 AND bool_and(points = 1500)
     FROM public.tasks WHERE special_key = 'grand_finale') AS passed
  UNION ALL SELECT 2, 'Finalen er spesial/bonus og teller ikke som hovedoppgave',
    (SELECT bool_and(bonus IS TRUE) FROM public.tasks WHERE special_key = 'grand_finale')
  UNION ALL SELECT 3, 'Finalen krever HK-frigivelse og fem fullførte deler',
    (SELECT bool_and(requires_release IS TRUE AND post_finish IS TRUE)
     FROM public.tasks WHERE special_key = 'grand_finale')
  UNION ALL SELECT 4, 'RLS krever frigivelse og fullføring for lag',
    (SELECT c.relrowsecurity AND EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies p
       WHERE p.schemaname = 'public' AND p.tablename = 'tasks'
         AND p.cmd = 'SELECT' AND 'authenticated' = ANY(p.roles)
         AND p.qual LIKE '%released_at IS NOT NULL%'
         AND p.qual LIKE '%stages_completed = 5%')
     FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'tasks')
  UNION ALL SELECT 5, 'Maks én godkjent vinnerpremie',
    (SELECT count(*) <= 1 FROM public.submissions s
      JOIN public.tasks t ON t.id = s.task_id
      WHERE t.special_key = 'grand_finale'
        AND s.status = 'approved' AND s.awarded_points = 1500)
  UNION ALL SELECT 6, 'De 28 opprinnelige og 6 nye oppgavene er bevart',
    (SELECT count(*) = 34 AND count(*) FILTER (WHERE bonus IS FALSE) = 25
      AND count(*) FILTER (WHERE bonus IS TRUE AND special_key IS NULL) = 3
      AND count(*) FILTER (WHERE special_key IS NOT NULL) = 6
     FROM public.tasks)
  UNION ALL SELECT 7, 'Finaleteksten krever tre gåter og kodeord',
    (SELECT bool_and(description LIKE '%GÅTE 1%'
       AND description LIKE '%GÅTE 2%'
       AND description LIKE '%GÅTE 3%'
       AND description ILIKE '%kodeord%')
     FROM public.tasks WHERE special_key = 'grand_finale')
  UNION ALL SELECT 8, 'Finalen krever offentlige og trygge steder',
    (SELECT bool_and(description ILIKE '%offentlig tilgjengelige%'
       AND description ILIKE '%Ingen klatring%')
     FROM public.tasks WHERE special_key = 'grand_finale')
)
SELECT id, test, CASE WHEN coalesce(passed, FALSE) THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks ORDER BY id;

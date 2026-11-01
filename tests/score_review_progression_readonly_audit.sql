-- Apokalypserebusen 2026: read-only score and HK review consistency audit.
-- SELECT only; no writes, impersonation, or changes to competition data.
-- This verifies stored invariants, not browser/mobile E2E behavior.
WITH awarded AS (
  SELECT team_id, task_id, max(awarded_points) AS task_points
  FROM public.submissions WHERE status='approved' GROUP BY team_id,task_id
), expected_scores AS (
  SELECT team_id,sum(task_points)::integer AS expected_score
  FROM awarded GROUP BY team_id
), checks AS (
 SELECT 1 AS id, 'Team scores equal sum of highest approved awards per task' AS test,
  NOT EXISTS (SELECT 1 FROM public.teams t LEFT JOIN expected_scores e ON e.team_id=t.id
    WHERE t.score IS DISTINCT FROM coalesce(e.expected_score,0)) AS passed
 UNION ALL SELECT 2, 'Pending/rejected submissions award zero points',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE status<>'approved' AND coalesce(awarded_points,0)<>0)
 UNION ALL SELECT 3, 'Approved submissions have positive awarded points',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE status='approved' AND coalesce(awarded_points,0)<=0)
 UNION ALL SELECT 4, 'Awards respect task points plus optional 200 reconstruction bonus',
  NOT EXISTS (SELECT 1 FROM public.submissions s JOIN public.tasks t ON t.id=s.task_id
    WHERE s.status='approved' AND s.awarded_points >
      t.points + CASE WHEN t.special_key='perfect_reconstruction' THEN 200 ELSE 0 END)
 UNION ALL SELECT 5, 'Reviewed submissions record HK reviewer and time',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE status IN ('approved','rejected')
    AND (reviewed_by IS NULL OR reviewed_at IS NULL))
 UNION ALL SELECT 6, 'Pending submissions have no review metadata',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE status='pending'
    AND (reviewed_by IS NOT NULL OR reviewed_at IS NOT NULL))
 UNION ALL SELECT 7, 'No duplicate approved submissions for team/task',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE status='approved'
    GROUP BY team_id,task_id HAVING count(*)>1)
 UNION ALL SELECT 8, 'Every team has its current stage unlocked',
  NOT EXISTS (SELECT 1 FROM public.teams t WHERE NOT EXISTS
    (SELECT 1 FROM public.stage_unlocks u WHERE u.team_id=t.id AND u.stage=t.current_stage))
 UNION ALL SELECT 9, 'No unlock beyond current stage',
  NOT EXISTS (SELECT 1 FROM public.stage_unlocks u JOIN public.teams t ON t.id=u.team_id
    WHERE u.stage>t.current_stage)
 UNION ALL SELECT 10, 'No team regressed before its starting stage',
  NOT EXISTS (SELECT 1 FROM public.teams WHERE current_stage<start_stage)
 UNION ALL SELECT 11, 'Unreleased HK-only tasks have no approved submissions',
  NOT EXISTS (SELECT 1 FROM public.submissions s JOIN public.tasks t ON t.id=s.task_id
    WHERE s.status='approved' AND t.requires_release AND t.released_at IS NULL)
 UNION ALL SELECT 12, 'All submissions have team and task references',
  NOT EXISTS (SELECT 1 FROM public.submissions WHERE team_id IS NULL OR task_id IS NULL)
)
SELECT id,test,CASE WHEN coalesce(passed,false) THEN 'PASS' ELSE 'FAIL' END status
FROM checks ORDER BY id;

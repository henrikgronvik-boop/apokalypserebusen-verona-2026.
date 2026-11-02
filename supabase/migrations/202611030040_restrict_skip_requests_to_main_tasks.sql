-- Only the 25 main tasks may be skipped. Bonus/special tasks are optional and
-- must never create HK skip requests (including the three legacy bonuses).
-- Preserve existing team, author, stage and status checks; do not broaden access.
ALTER POLICY request_skips ON public.skip_requests
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND status = 'pending'
  AND EXISTS (
    SELECT 1
    FROM public.team_members m
    JOIN public.teams tm ON tm.id = m.team_id
    JOIN public.tasks t ON t.id = skip_requests.task_id
    WHERE m.user_id = (SELECT auth.uid())
      AND m.team_id = skip_requests.team_id
      AND NOT t.bonus
      AND NOT t.post_finish
      AND (
        tm.stages_completed = 5
        OR ((t.stage - tm.start_stage + 5) % 5) <= tm.stages_completed
      )
  )
);

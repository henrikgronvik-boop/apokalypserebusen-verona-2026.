-- Applied to Supabase project zvnqhiuipmnrrotuxkaa on 2026-10-31.
-- This is an additive tightening of INSERT authorization only.
-- Existing media rows remain untouched; HK/admin media policy is unchanged.
-- A team member may attach evidence only to their own team's pending
-- submission, or to a message belonging to their own team.
-- The second path segment must match the submission/message id.
ALTER POLICY team_media_metadata_insert ON public.media
WITH CHECK (
  team_id::text = split_part(storage_path, '/', 1)
  AND EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.user_id = auth.uid() AND tm.team_id = media.team_id
  )
  AND (
    (
      submission_id IS NOT NULL AND message_id IS NULL
      AND split_part(storage_path, '/', 2) = submission_id::text
      AND EXISTS (
        SELECT 1 FROM public.submissions s
        WHERE s.id = media.submission_id
          AND s.team_id = media.team_id
          AND s.status = 'pending'
      )
    )
    OR
    (
      message_id IS NOT NULL AND submission_id IS NULL
      AND split_part(storage_path, '/', 2) = message_id::text
      AND EXISTS (
        SELECT 1 FROM public.messages m
        WHERE m.id = media.message_id
          AND m.team_id = media.team_id
      )
    )
  )
);

-- Applied to Supabase project zvnqhiuipmnrrotuxkaa on 2026-11-01.
-- Tighten team storage INSERT permissions without changing existing media or SELECT rules.
-- Expected upload path: <team-uuid>/<submission-or-message-uuid>/<random-file-name>.
-- Submissions must still be pending; chat messages may accept attachments.
-- This policy is intentionally limited to team uploads. HK has a separate policy.
DROP POLICY IF EXISTS team_media_upload ON storage.objects;
CREATE POLICY team_media_upload ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'rebus-bevis'
  AND array_length(storage.foldername(name), 1) = 2
  AND EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.user_id = auth.uid()
      AND tm.team_id::text = (storage.foldername(name))[1]
  )
  AND (
    EXISTS (
      SELECT 1 FROM public.submissions s
      WHERE s.id::text = (storage.foldername(name))[2]
        AND s.team_id::text = (storage.foldername(name))[1]
        AND s.status = 'pending'
    )
    OR EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id::text = (storage.foldername(name))[2]
        AND m.team_id::text = (storage.foldername(name))[1]
    )
  )
);

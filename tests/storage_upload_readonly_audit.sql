-- Apokalypserebusen 2026: read-only storage policy regression checks.
-- Static policy inspection only: not a substitute for two-client RLS / upload E2E tests.
-- No secrets, no impersonation, no changes to production data.
WITH team_upload AS (
  SELECT * FROM pg_catalog.pg_policies
  WHERE schemaname='storage' AND tablename='objects' AND policyname='team_media_upload'
), checks AS (
  SELECT 1 id, 'Exactly one team upload policy' test,
    (SELECT count(*)=1 FROM team_upload) passed
  UNION ALL SELECT 2, 'Only authenticated clients can use team upload',
    (SELECT count(*)=1 AND bool_and(cmd='INSERT' AND roles=ARRAY['authenticated']::name[]) FROM team_upload)
  UNION ALL SELECT 3, 'Uploads limited to private rebus bucket',
    (SELECT bool_and(with_check LIKE '%rebus-bevis%') FROM team_upload)
  UNION ALL SELECT 4, 'Only two folder levels before filename',
    (SELECT bool_and(with_check LIKE '%array_length(storage.foldername(name), 1) = 2%') FROM team_upload)
  UNION ALL SELECT 5, 'Authenticated user must belong to folder team',
    (SELECT bool_and(with_check LIKE '%team_members%' AND with_check LIKE '%auth.uid()%') FROM team_upload)
  UNION ALL SELECT 6, 'Submission attachments require pending status',
    (SELECT bool_and(with_check LIKE '%submissions%' AND with_check LIKE '%pending%') FROM team_upload)
  UNION ALL SELECT 7, 'Team chat attachments remain permitted',
    (SELECT bool_and(with_check LIKE '%messages%') FROM team_upload)
  UNION ALL SELECT 8, 'Private team/HK media read policy remains',
    (SELECT count(*)=1 FROM pg_catalog.pg_policies
      WHERE schemaname='storage' AND tablename='objects'
        AND policyname='team_media_read' AND cmd='SELECT')
  UNION ALL SELECT 9, 'Stored media paths retain expected structure',
    (SELECT coalesce(bool_and(array_length(storage.foldername(name),1)=2),true)
     FROM storage.objects WHERE bucket_id='rebus-bevis')
)
SELECT id,test,CASE WHEN coalesce(passed,false) THEN 'PASS' ELSE 'FAIL' END status
FROM checks ORDER BY id;

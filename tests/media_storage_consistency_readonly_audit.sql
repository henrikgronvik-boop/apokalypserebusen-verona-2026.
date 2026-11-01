-- Apokalypserebusen 2026: read-only evidence/media integrity audit.
-- Safe to rerun: no writes, no test users, no RLS bypass.
-- Checks metadata/storage consistency and approved-submission evidence.
-- Does NOT prove real mobile upload/playback or cross-team client isolation.
WITH checks AS (
 SELECT 1 AS id, 'Private evidence bucket with 50 MB limit' AS test,
   EXISTS (SELECT 1 FROM storage.buckets WHERE id='rebus-bevis'
           AND public IS FALSE AND file_size_limit=52428800) AS passed
 UNION ALL SELECT 2, 'Every media record has exactly one parent',
   NOT EXISTS (SELECT 1 FROM public.media m WHERE (m.submission_id IS NULL)=(m.message_id IS NULL))
 UNION ALL SELECT 3, 'Media parents belong to the same team',
   NOT EXISTS (SELECT 1 FROM public.media m
     LEFT JOIN public.submissions s ON s.id=m.submission_id
     LEFT JOIN public.messages c ON c.id=m.message_id
     WHERE (m.submission_id IS NOT NULL AND s.team_id IS DISTINCT FROM m.team_id)
        OR (m.message_id IS NOT NULL AND c.team_id IS DISTINCT FROM m.team_id))
 UNION ALL SELECT 4, 'Storage paths match team and parent IDs',
   NOT EXISTS (SELECT 1 FROM public.media m WHERE
      split_part(m.storage_path,'/',1)<>m.team_id::text
      OR split_part(m.storage_path,'/',2)<>coalesce(m.submission_id,m.message_id)::text
      OR array_length(string_to_array(m.storage_path,'/'),1)<>3)
 UNION ALL SELECT 5, 'Every media metadata record has a stored object',
   NOT EXISTS (SELECT 1 FROM public.media m LEFT JOIN storage.objects o
      ON o.bucket_id='rebus-bevis' AND o.name=m.storage_path WHERE o.id IS NULL)
 UNION ALL SELECT 6, 'No orphaned evidence objects',
   NOT EXISTS (SELECT 1 FROM storage.objects o LEFT JOIN public.media m
      ON m.storage_path=o.name WHERE o.bucket_id='rebus-bevis' AND m.id IS NULL)
 UNION ALL SELECT 7, 'Media storage paths are unique',
   NOT EXISTS (SELECT 1 FROM public.media GROUP BY storage_path HAVING count(*)>1)
 UNION ALL SELECT 8, 'Stored MIME types match registered MIME types',
   NOT EXISTS (SELECT 1 FROM public.media m JOIN storage.objects o
      ON o.bucket_id='rebus-bevis' AND o.name=m.storage_path
      WHERE lower(coalesce(o.metadata->>'mimetype',''))<>lower(coalesce(m.mime_type,'')))
 UNION ALL SELECT 9, 'Evidence object sizes are valid and at most 50 MB',
   NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id='rebus-bevis'
     AND NOT (CASE WHEN (o.metadata->>'size') ~ '^[0-9]+$'
       THEN (o.metadata->>'size')::bigint BETWEEN 1 AND 52428800 ELSE false END))
 UNION ALL SELECT 10, 'Approved submissions have registered evidence',
   NOT EXISTS (SELECT 1 FROM public.submissions s WHERE s.status='approved'
      AND NOT EXISTS (SELECT 1 FROM public.media m WHERE m.submission_id=s.id))
)
SELECT id,test,CASE WHEN coalesce(passed,false) THEN 'PASS' ELSE 'FAIL' END status
FROM checks ORDER BY id;

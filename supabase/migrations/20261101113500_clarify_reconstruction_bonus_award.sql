-- Correct obsolete task instructions after introducing HK's separate +200 bonus award.
-- Idempotent: preserves all other tasks, submissions, scores and release states.
UPDATE public.tasks
SET description = replace(
  description,
  'Beste rekonstruksjon kan få 200 ekstra poeng (HK setter 800 ved godkjenning).',
  'Alle godkjente rekonstruksjoner gir 600 poeng. Etter at HK har sammenlignet bildene fra lagene, kan HK tildele 200 ekstra poeng til ett lag for beste rekonstruksjon.'
)
WHERE special_key = 'perfect_reconstruction'
  AND points = 600
  AND description LIKE '%HK setter 800 ved godkjenning)%';

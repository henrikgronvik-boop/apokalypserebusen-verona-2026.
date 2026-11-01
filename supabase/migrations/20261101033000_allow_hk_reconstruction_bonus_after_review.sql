-- Apokalypserebusen 2026: permit HK to award the unique 200-point photo bonus
-- after approving a reconstruction for 600 points. No existing data changes.
-- The existing enforce_unique_special_awards trigger prevents duplicate winners.
CREATE OR REPLACE FUNCTION rebus_private.protect_submission_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.team_id IS DISTINCT FROM OLD.team_id
     OR NEW.task_id IS DISTINCT FROM OLD.task_id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.note IS DISTINCT FROM OLD.note THEN
    RAISE EXCEPTION 'Submission ownership, task and original content cannot change';
  END IF;

  -- The normal review is immutable. Sole exception: HK may add the
  -- one-time 200-point reconstruction prize to an approved 600-point entry.
  -- enforce_unique_special_awards prevents two 800-point winners.
  IF OLD.status = 'approved'
     AND NEW.status = 'approved'
     AND OLD.awarded_points = 600
     AND NEW.awarded_points = 800
     AND NEW.reviewer_note IS NOT DISTINCT FROM OLD.reviewer_note
     AND NEW.reviewed_by IS NOT DISTINCT FROM OLD.reviewed_by
     AND NEW.reviewed_at IS NOT DISTINCT FROM OLD.reviewed_at
     AND (SELECT auth.uid()) IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.admins a WHERE a.user_id = (SELECT auth.uid())
     )
     AND EXISTS (
       SELECT 1 FROM public.tasks t
       WHERE t.id = OLD.task_id AND t.special_key = 'perfect_reconstruction'
     ) THEN
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Submission has already been reviewed';
  END IF;
  IF NEW.status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Review must approve or reject a pending submission';
  END IF;
  IF NEW.status = 'approved'
     AND NOT EXISTS (
       SELECT 1 FROM public.media m
       WHERE m.submission_id = OLD.id AND m.team_id = OLD.team_id
     ) THEN
    RAISE EXCEPTION 'Cannot approve submission without photo or video evidence';
  END IF;
  NEW.reviewed_by := auth.uid();
  NEW.reviewed_at := now();
  RETURN NEW;
END;
$function$
;

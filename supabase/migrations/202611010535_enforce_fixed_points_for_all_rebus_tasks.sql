-- Fixed point values are part of the competition rules.
-- Reject arbitrary awards even if a client bypasses the HK form.
-- The existing exclusive 1500-point finale and 600/800-point reconstruction
-- checks remain in rebus_private.enforce_unique_special_awards().
CREATE OR REPLACE FUNCTION rebus_private.enforce_fixed_task_points()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_points integer;
  v_special text;
BEGIN
  IF NEW.status = 'rejected' THEN
    IF NEW.awarded_points IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'Avviste oppgaver skal gi 0 poeng';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM 'approved' THEN
    RETURN NEW;
  END IF;

  SELECT t.points, t.special_key
    INTO v_points, v_special
  FROM public.tasks t
  WHERE t.id = NEW.task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ukjent oppgave';
  END IF;

  -- These two prizes already have their own restricted award rules.
  IF v_special IS DISTINCT FROM 'grand_finale'
     AND v_special IS DISTINCT FROM 'perfect_reconstruction'
     AND NEW.awarded_points IS DISTINCT FROM v_points THEN
    RAISE EXCEPTION 'Godkjent oppgave må gi nøyaktig % poeng', v_points;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION rebus_private.enforce_fixed_task_points() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER enforce_fixed_task_points
BEFORE UPDATE OF status, awarded_points ON public.submissions
FOR EACH ROW
EXECUTE FUNCTION rebus_private.enforce_fixed_task_points();

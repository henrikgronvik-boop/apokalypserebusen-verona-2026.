-- Ensure evidence timestamps and HK review fields cannot be supplied by a team client.
-- This matters for the HK-controlled 30-minute secret mission.
-- Existing submissions, reviews, points and tasks are untouched.
CREATE OR REPLACE FUNCTION rebus_private.set_server_owned_review_metadata()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  -- Use database time, not client time or a client-supplied timestamp.
  NEW.created_at := pg_catalog.clock_timestamp();
  -- HK review information must only be populated during a later review.
  NEW.reviewer_note := NULL;
  NEW.reviewed_at := NULL;
  NEW.reviewed_by := NULL;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION rebus_private.set_server_owned_review_metadata()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER protect_submission_insert_metadata
BEFORE INSERT ON public.submissions
FOR EACH ROW
EXECUTE FUNCTION rebus_private.set_server_owned_review_metadata();

CREATE TRIGGER protect_skip_request_insert_metadata
BEFORE INSERT ON public.skip_requests
FOR EACH ROW
EXECUTE FUNCTION rebus_private.set_server_owned_review_metadata();

-- Preserve existing reminders at the deadline. NULL means a deadline without an alert.
BEGIN;
ALTER TABLE public.monotask_tasks
    ADD COLUMN IF NOT EXISTS reminder_minutes_before INTEGER DEFAULT 0
    CHECK (reminder_minutes_before BETWEEN 0 AND 525600);
COMMENT ON COLUMN public.monotask_tasks.reminder_minutes_before IS
    'Minutes before due_date for a local notification; NULL disables it, 0 means at deadline.';
NOTIFY pgrst, 'reload schema';
COMMIT;

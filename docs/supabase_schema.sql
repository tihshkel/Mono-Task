-- =============================================================================
-- MonoTask — Supabase PostgreSQL Schema & Security Policies
-- =============================================================================
-- This schema supports safe, bi-directional, offline-first synchronization.
-- Clean installs and updates will pull remote data without ever wiping or
-- resetting the Supabase storage.
-- =============================================================================

-- 1. Helper Function: Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION monotask_update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 2. TABLES
-- =============================================================================

-- Tags / Contexts
CREATE TABLE IF NOT EXISTS public.monotask_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_hex TEXT NOT NULL DEFAULT '#6366F1',
    icon_name TEXT NOT NULL DEFAULT 'tag.fill',
    scheduled_days INTEGER[] NOT NULL DEFAULT '{}',
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Tasks
CREATE TABLE IF NOT EXISTS public.monotask_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    bucket_raw TEXT NOT NULL DEFAULT 'inbox',
    priority_raw TEXT NOT NULL DEFAULT 'none',
    is_high_priority_today BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    completed_at TIMESTAMPTZ DEFAULT NULL,
    due_date TIMESTAMPTZ DEFAULT NULL,
    reminder_minutes_before INTEGER DEFAULT 0 CHECK (reminder_minutes_before BETWEEN 0 AND 525600),
    sort_order INTEGER NOT NULL DEFAULT 0,
    tag_ids UUID[] NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Subtasks (Child of TaskItem)
CREATE TABLE IF NOT EXISTS public.monotask_subtasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    task_id UUID NOT NULL REFERENCES public.monotask_tasks(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Daily Notes (Reflection)
CREATE TABLE IF NOT EXISTS public.monotask_daily_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    date TIMESTAMPTZ NOT NULL,
    wins TEXT NOT NULL DEFAULT '',
    losses TEXT NOT NULL DEFAULT '',
    reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Weekly Reviews
CREATE TABLE IF NOT EXISTS public.monotask_weekly_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start_date TIMESTAMPTZ NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    improvements TEXT NOT NULL DEFAULT '',
    completed_tasks_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Focus Schedule
CREATE TABLE IF NOT EXISTS public.monotask_focus_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    weekday_raw INTEGER NOT NULL,
    tag_id UUID REFERENCES public.monotask_tags(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Activity Entries (for Heatmap)
CREATE TABLE IF NOT EXISTS public.monotask_activity_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    date TIMESTAMPTZ NOT NULL,
    tag_id UUID DEFAULT NULL,
    count INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- Completed History
CREATE TABLE IF NOT EXISTS public.monotask_completed_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    task_id UUID NOT NULL,
    tag_id UUID DEFAULT NULL,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

-- =============================================================================
-- 3. TRIGGERS FOR updated_at
-- =============================================================================

DROP TRIGGER IF EXISTS tr_monotask_tags_updated_at ON public.monotask_tags;
CREATE TRIGGER tr_monotask_tags_updated_at
BEFORE UPDATE ON public.monotask_tags
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_tasks_updated_at ON public.monotask_tasks;
CREATE TRIGGER tr_monotask_tasks_updated_at
BEFORE UPDATE ON public.monotask_tasks
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_subtasks_updated_at ON public.monotask_subtasks;
CREATE TRIGGER tr_monotask_subtasks_updated_at
BEFORE UPDATE ON public.monotask_subtasks
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_daily_notes_updated_at ON public.monotask_daily_notes;
CREATE TRIGGER tr_monotask_daily_notes_updated_at
BEFORE UPDATE ON public.monotask_daily_notes
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_weekly_reviews_updated_at ON public.monotask_weekly_reviews;
CREATE TRIGGER tr_monotask_weekly_reviews_updated_at
BEFORE UPDATE ON public.monotask_weekly_reviews
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_focus_schedules_updated_at ON public.monotask_focus_schedules;
CREATE TRIGGER tr_monotask_focus_schedules_updated_at
BEFORE UPDATE ON public.monotask_focus_schedules
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_activity_entries_updated_at ON public.monotask_activity_entries;
CREATE TRIGGER tr_monotask_activity_entries_updated_at
BEFORE UPDATE ON public.monotask_activity_entries
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

DROP TRIGGER IF EXISTS tr_monotask_completed_history_updated_at ON public.monotask_completed_history;
CREATE TRIGGER tr_monotask_completed_history_updated_at
BEFORE UPDATE ON public.monotask_completed_history
FOR EACH ROW EXECUTE FUNCTION monotask_update_updated_at_column();

-- =============================================================================
-- 4. INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_monotask_tasks_deleted_at ON public.monotask_tasks(deleted_at);
CREATE INDEX IF NOT EXISTS idx_monotask_tasks_updated_at ON public.monotask_tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_monotask_tasks_bucket ON public.monotask_tasks(bucket_raw);
CREATE INDEX IF NOT EXISTS idx_monotask_tags_deleted_at ON public.monotask_tags(deleted_at);
CREATE INDEX IF NOT EXISTS idx_monotask_subtasks_task_id ON public.monotask_subtasks(task_id);
CREATE INDEX IF NOT EXISTS idx_monotask_subtasks_deleted_at ON public.monotask_subtasks(deleted_at);
CREATE INDEX IF NOT EXISTS idx_monotask_daily_notes_date ON public.monotask_daily_notes(date);
CREATE INDEX IF NOT EXISTS idx_monotask_activity_date ON public.monotask_activity_entries(date);

-- =============================================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- Every row belongs to the authenticated user. Anonymous requests get no rows.
-- =============================================================================

-- Keep child rows inside the same user's data set.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'monotask_tasks_id_user_unique') THEN
        ALTER TABLE public.monotask_tasks
            ADD CONSTRAINT monotask_tasks_id_user_unique UNIQUE (id, user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'monotask_tags_id_user_unique') THEN
        ALTER TABLE public.monotask_tags
            ADD CONSTRAINT monotask_tags_id_user_unique UNIQUE (id, user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'monotask_subtasks_same_owner') THEN
        ALTER TABLE public.monotask_subtasks
            ADD CONSTRAINT monotask_subtasks_same_owner
            FOREIGN KEY (task_id, user_id) REFERENCES public.monotask_tasks (id, user_id)
            ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'monotask_focus_schedules_same_owner') THEN
        ALTER TABLE public.monotask_focus_schedules
            ADD CONSTRAINT monotask_focus_schedules_same_owner
            FOREIGN KEY (tag_id, user_id) REFERENCES public.monotask_tags (id, user_id)
            ON DELETE SET NULL (tag_id);
    END IF;
END $$;

DO $$
DECLARE
    table_name text;
    policy_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'monotask_tags', 'monotask_tasks', 'monotask_subtasks',
        'monotask_daily_notes', 'monotask_weekly_reviews',
        'monotask_focus_schedules', 'monotask_activity_entries',
        'monotask_completed_history'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        FOR policy_name IN
            SELECT policyname FROM pg_policies
            WHERE schemaname = 'public' AND tablename = table_name
        LOOP
            EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', policy_name, table_name);
        END LOOP;
        EXECUTE format('REVOKE ALL ON public.%I FROM anon', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', table_name);
        EXECUTE format(
            'CREATE POLICY owner_only ON public.%I FOR ALL TO authenticated USING (user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()))',
            table_name
        );
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (user_id)',
            'idx_' || table_name || '_user_id', table_name);
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

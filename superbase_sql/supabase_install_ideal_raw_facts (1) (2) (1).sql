
-- Supabase Study Tracker - Ideal Raw Facts Installer
-- IMPORTANT:
-- 1) This installer RESETs and recreates all study-tracker tables listed below.
-- 2) It stores only raw facts, automatic metadata, and missed questions only.
-- 3) Derived metrics (accuracy %, completion %, attempted count, etc.) are computed in views, not stored as repeated columns.
-- 4) Durations are stored as INTEGER SECONDS. The UI should display/edit them as HH:MM:SS.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------------
-- CLEAN RESET OF THIS APP'S OBJECTS
-- -------------------------------------------------------------------

DROP VIEW IF EXISTS public.v_video_entry_metrics CASCADE;
DROP VIEW IF EXISTS public.v_test_attempt_metrics CASCADE;
DROP VIEW IF EXISTS public.v_revision_entry_metrics CASCADE;
DROP VIEW IF EXISTS public.v_study_item_catalog CASCADE;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

DROP TABLE IF EXISTS public.form_template_fields CASCADE;
DROP TABLE IF EXISTS public.form_templates CASCADE;
DROP TABLE IF EXISTS public.missed_questions CASCADE;
DROP TABLE IF EXISTS public.test_attempts CASCADE;
DROP TABLE IF EXISTS public.reading_entries CASCADE;
DROP TABLE IF EXISTS public.video_entries CASCADE;
DROP TABLE IF EXISTS public.revision_entries CASCADE;
DROP TABLE IF EXISTS public.activity_sessions CASCADE;
DROP TABLE IF EXISTS public.study_items CASCADE;
DROP TABLE IF EXISTS public.platforms CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

DROP FUNCTION IF EXISTS public.handle_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.hhmmss_to_seconds(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.seconds_to_hhmmss(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS public.enforce_session_activity_type() CASCADE;

DROP TYPE IF EXISTS public.reading_state_enum CASCADE;
DROP TYPE IF EXISTS public.issue_type_enum CASCADE;
DROP TYPE IF EXISTS public.activity_type_enum CASCADE;

-- -------------------------------------------------------------------
-- TYPES
-- -------------------------------------------------------------------

CREATE TYPE public.activity_type_enum AS ENUM ('revision', 'test', 'video', 'reading');
CREATE TYPE public.issue_type_enum AS ENUM ('wrong', 'skipped', 'unseen');
CREATE TYPE public.reading_state_enum AS ENUM ('completed', 'partial', 'not_read');

-- -------------------------------------------------------------------
-- HELPERS
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.hhmmss_to_seconds(p_text TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_parts TEXT[];
  v_h INTEGER;
  v_m INTEGER;
  v_s INTEGER;
BEGIN
  IF p_text IS NULL OR btrim(p_text) = '' THEN
    RETURN NULL;
  END IF;

  v_parts := string_to_array(btrim(p_text), ':');

  IF array_length(v_parts, 1) <> 3 THEN
    RAISE EXCEPTION 'Expected HH:MM:SS, received %', p_text;
  END IF;

  v_h := v_parts[1]::INTEGER;
  v_m := v_parts[2]::INTEGER;
  v_s := v_parts[3]::INTEGER;

  IF v_h < 0 OR v_m < 0 OR v_s < 0 OR v_m > 59 OR v_s > 59 THEN
    RAISE EXCEPTION 'Invalid HH:MM:SS value %', p_text;
  END IF;

  RETURN (v_h * 3600) + (v_m * 60) + v_s;
END;
$$;

CREATE OR REPLACE FUNCTION public.seconds_to_hhmmss(p_seconds INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_seconds INTEGER;
  v_h INTEGER;
  v_m INTEGER;
  v_s INTEGER;
BEGIN
  IF p_seconds IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_seconds < 0 THEN
    RAISE EXCEPTION 'Seconds cannot be negative: %', p_seconds;
  END IF;

  v_seconds := p_seconds;
  v_h := v_seconds / 3600;
  v_m := (v_seconds % 3600) / 60;
  v_s := v_seconds % 60;

  RETURN lpad(v_h::TEXT, 2, '0') || ':' || lpad(v_m::TEXT, 2, '0') || ':' || lpad(v_s::TEXT, 2, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email))
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_session_activity_type()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_actual_type public.activity_type_enum;
  v_expected_type public.activity_type_enum;
BEGIN
  v_expected_type := TG_ARGV[0]::public.activity_type_enum;

  SELECT si.activity_type
    INTO v_actual_type
  FROM public.activity_sessions s
  JOIN public.study_items si
    ON si.id = s.study_item_id
  WHERE s.id = NEW.session_id;

  IF v_actual_type IS NULL THEN
    RAISE EXCEPTION 'Session % not found or has no linked study item.', NEW.session_id;
  END IF;

  IF v_actual_type <> v_expected_type THEN
    RAISE EXCEPTION 'Session % belongs to activity_type %, but this table requires %.',
      NEW.session_id, v_actual_type, v_expected_type;
  END IF;

  RETURN NEW;
END;
$$;

-- -------------------------------------------------------------------
-- TABLES
-- -------------------------------------------------------------------

CREATE TABLE public.profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.platforms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,
  platform_name TEXT NOT NULL UNIQUE,
  platform_icon TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.form_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key TEXT NOT NULL UNIQUE,
  template_name TEXT NOT NULL,
  form_title TEXT NOT NULL,
  form_description TEXT,
  activity_type public.activity_type_enum NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.form_template_fields (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID NOT NULL REFERENCES public.form_templates(id) ON DELETE CASCADE,
  field_scope TEXT NOT NULL CHECK (field_scope IN ('session', 'missed_question')),
  field_key TEXT NOT NULL,
  show_label TEXT NOT NULL,
  helper_text TEXT,
  input_type TEXT NOT NULL,
  is_required BOOLEAN NOT NULL DEFAULT FALSE,
  is_auto BOOLEAN NOT NULL DEFAULT FALSE,
  is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
  display_order INTEGER NOT NULL DEFAULT 0,
  section_key TEXT NOT NULL DEFAULT 'main',
  repeat_group_key TEXT,
  ui_config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (template_id, field_scope, field_key)
);

CREATE TABLE public.study_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_id UUID NOT NULL REFERENCES public.platforms(id) ON DELETE RESTRICT,
  template_key TEXT NOT NULL REFERENCES public.form_templates(template_key) ON DELETE RESTRICT,
  slug TEXT NOT NULL UNIQUE,
  full_path TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  short_description TEXT,
  main_category TEXT NOT NULL,
  sub_category TEXT,
  item_name TEXT NOT NULL,
  activity_type public.activity_type_enum NOT NULL,
  target_count INTEGER CHECK (target_count IS NULL OR target_count > 0),
  ui_rules_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.activity_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  study_item_id UUID NOT NULL REFERENCES public.study_items(id) ON DELETE RESTRICT,
  session_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.revision_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.activity_sessions(id) ON DELETE CASCADE,
  completed_count INTEGER NOT NULL CHECK (completed_count >= 0),
  target_count_snapshot INTEGER NOT NULL CHECK (target_count_snapshot > 0),
  mistake_notes TEXT,
  confidence_level SMALLINT CHECK (confidence_level IS NULL OR confidence_level BETWEEN 1 AND 5),
  extra_data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (completed_count <= target_count_snapshot)
);

CREATE TABLE public.test_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.activity_sessions(id) ON DELETE CASCADE,
  total_questions INTEGER NOT NULL CHECK (total_questions > 0),
  max_marks NUMERIC(10,2) CHECK (max_marks IS NULL OR max_marks >= 0),
  marks_obtained NUMERIC(10,2),
  total_duration_seconds INTEGER CHECK (total_duration_seconds IS NULL OR total_duration_seconds >= 0),
  time_taken_seconds INTEGER CHECK (time_taken_seconds IS NULL OR time_taken_seconds >= 0),
  right_count INTEGER CHECK (right_count IS NULL OR right_count >= 0),
  wrong_count INTEGER CHECK (wrong_count IS NULL OR wrong_count >= 0),
  skipped_count INTEGER CHECK (skipped_count IS NULL OR skipped_count >= 0),
  unseen_count INTEGER CHECK (unseen_count IS NULL OR unseen_count >= 0),
  rank INTEGER CHECK (rank IS NULL OR rank > 0),
  total_rank INTEGER CHECK (total_rank IS NULL OR total_rank > 0),
  percentile NUMERIC(5,2) CHECK (percentile IS NULL OR (percentile >= 0 AND percentile <= 100)),
  utilized_seconds INTEGER CHECK (utilized_seconds IS NULL OR utilized_seconds >= 0),
  wasted_seconds INTEGER CHECK (wasted_seconds IS NULL OR wasted_seconds >= 0),
  correct_time_seconds INTEGER CHECK (correct_time_seconds IS NULL OR correct_time_seconds >= 0),
  wrong_time_seconds INTEGER CHECK (wrong_time_seconds IS NULL OR wrong_time_seconds >= 0),
  skipped_time_seconds INTEGER CHECK (skipped_time_seconds IS NULL OR skipped_time_seconds >= 0),
  range_from INTEGER CHECK (range_from IS NULL OR range_from >= 0),
  range_to INTEGER CHECK (range_to IS NULL OR range_to >= 0),
  result_notes TEXT,
  extra_data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (time_taken_seconds IS NULL OR total_duration_seconds IS NULL OR time_taken_seconds <= total_duration_seconds),
  CHECK (rank IS NULL OR total_rank IS NULL OR rank <= total_rank),
  CHECK (
    COALESCE(right_count, 0) + COALESCE(wrong_count, 0) + COALESCE(skipped_count, 0) + COALESCE(unseen_count, 0)
    <= total_questions
  ),
  CHECK (range_from IS NULL OR range_to IS NULL OR range_from <= range_to)
);

CREATE TABLE public.missed_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_attempt_id UUID NOT NULL REFERENCES public.test_attempts(id) ON DELETE CASCADE,
  question_number INTEGER NOT NULL CHECK (question_number > 0),
  issue_type public.issue_type_enum NOT NULL,
  question_text TEXT NOT NULL,
  options_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  selected_option_key TEXT,
  correct_option_key TEXT,
  question_marks NUMERIC(10,2),
  marks_received NUMERIC(10,2),
  question_time_seconds INTEGER CHECK (question_time_seconds IS NULL OR question_time_seconds >= 0),
  question_note TEXT,
  extra_data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (test_attempt_id, question_number),
  CHECK (jsonb_typeof(options_json) = 'object')
);

CREATE TABLE public.video_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.activity_sessions(id) ON DELETE CASCADE,
  watched_videos INTEGER NOT NULL CHECK (watched_videos >= 0),
  total_videos_snapshot INTEGER NOT NULL CHECK (total_videos_snapshot > 0),
  time_spent_seconds INTEGER CHECK (time_spent_seconds IS NULL OR time_spent_seconds >= 0),
  notes TEXT,
  extra_data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (watched_videos <= total_videos_snapshot)
);

CREATE TABLE public.reading_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.activity_sessions(id) ON DELETE CASCADE,
  reading_state public.reading_state_enum NOT NULL,
  time_spent_seconds INTEGER CHECK (time_spent_seconds IS NULL OR time_spent_seconds >= 0),
  notes TEXT,
  extra_data_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------
-- INDEXES
-- -------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_platforms_sort_order ON public.platforms(sort_order);
CREATE INDEX IF NOT EXISTS idx_form_templates_activity_type ON public.form_templates(activity_type);
CREATE INDEX IF NOT EXISTS idx_form_template_fields_template ON public.form_template_fields(template_id, field_scope, display_order);
CREATE INDEX IF NOT EXISTS idx_study_items_platform ON public.study_items(platform_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_study_items_activity_type ON public.study_items(activity_type, sort_order);
CREATE INDEX IF NOT EXISTS idx_activity_sessions_user ON public.activity_sessions(user_id, session_date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_sessions_study_item ON public.activity_sessions(study_item_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_revision_entries_session ON public.revision_entries(session_id);
CREATE INDEX IF NOT EXISTS idx_test_attempts_session ON public.test_attempts(session_id);
CREATE INDEX IF NOT EXISTS idx_missed_questions_test_attempt ON public.missed_questions(test_attempt_id, question_number);
CREATE INDEX IF NOT EXISTS idx_missed_questions_issue_type ON public.missed_questions(issue_type);
CREATE INDEX IF NOT EXISTS idx_video_entries_session ON public.video_entries(session_id);
CREATE INDEX IF NOT EXISTS idx_reading_entries_session ON public.reading_entries(session_id);

-- -------------------------------------------------------------------
-- TRIGGERS
-- -------------------------------------------------------------------

CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_platforms_updated_at
BEFORE UPDATE ON public.platforms
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_form_templates_updated_at
BEFORE UPDATE ON public.form_templates
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_form_template_fields_updated_at
BEFORE UPDATE ON public.form_template_fields
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_study_items_updated_at
BEFORE UPDATE ON public.study_items
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_activity_sessions_updated_at
BEFORE UPDATE ON public.activity_sessions
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_revision_entries_updated_at
BEFORE UPDATE ON public.revision_entries
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_test_attempts_updated_at
BEFORE UPDATE ON public.test_attempts
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_missed_questions_updated_at
BEFORE UPDATE ON public.missed_questions
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_video_entries_updated_at
BEFORE UPDATE ON public.video_entries
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_reading_entries_updated_at
BEFORE UPDATE ON public.reading_entries
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER trg_revision_entries_activity_type
BEFORE INSERT OR UPDATE ON public.revision_entries
FOR EACH ROW
EXECUTE FUNCTION public.enforce_session_activity_type('revision');

CREATE TRIGGER trg_test_attempts_activity_type
BEFORE INSERT OR UPDATE ON public.test_attempts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_session_activity_type('test');

CREATE TRIGGER trg_video_entries_activity_type
BEFORE INSERT OR UPDATE ON public.video_entries
FOR EACH ROW
EXECUTE FUNCTION public.enforce_session_activity_type('video');

CREATE TRIGGER trg_reading_entries_activity_type
BEFORE INSERT OR UPDATE ON public.reading_entries
FOR EACH ROW
EXECUTE FUNCTION public.enforce_session_activity_type('reading');

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- -------------------------------------------------------------------
-- RLS
-- -------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platforms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_template_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revision_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missed_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reading_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own ON public.profiles
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS platforms_public_read ON public.platforms;
CREATE POLICY platforms_public_read ON public.platforms
FOR SELECT TO anon, authenticated
USING (is_active = TRUE);

DROP POLICY IF EXISTS form_templates_public_read ON public.form_templates;
CREATE POLICY form_templates_public_read ON public.form_templates
FOR SELECT TO anon, authenticated
USING (is_active = TRUE);

DROP POLICY IF EXISTS form_template_fields_public_read ON public.form_template_fields;
CREATE POLICY form_template_fields_public_read ON public.form_template_fields
FOR SELECT TO anon, authenticated
USING (TRUE);

DROP POLICY IF EXISTS study_items_public_read ON public.study_items;
CREATE POLICY study_items_public_read ON public.study_items
FOR SELECT TO anon, authenticated
USING (is_active = TRUE);

DROP POLICY IF EXISTS activity_sessions_select_own ON public.activity_sessions;
CREATE POLICY activity_sessions_select_own ON public.activity_sessions
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS activity_sessions_insert_own ON public.activity_sessions;
CREATE POLICY activity_sessions_insert_own ON public.activity_sessions
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS activity_sessions_update_own ON public.activity_sessions;
CREATE POLICY activity_sessions_update_own ON public.activity_sessions
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS activity_sessions_delete_own ON public.activity_sessions;
CREATE POLICY activity_sessions_delete_own ON public.activity_sessions
FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS revision_entries_owner_all ON public.revision_entries;
CREATE POLICY revision_entries_owner_all ON public.revision_entries
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = revision_entries.session_id
      AND s.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = revision_entries.session_id
      AND s.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS test_attempts_owner_all ON public.test_attempts;
CREATE POLICY test_attempts_owner_all ON public.test_attempts
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = test_attempts.session_id
      AND s.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = test_attempts.session_id
      AND s.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS missed_questions_owner_all ON public.missed_questions;
CREATE POLICY missed_questions_owner_all ON public.missed_questions
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.test_attempts ta
    JOIN public.activity_sessions s
      ON s.id = ta.session_id
    WHERE ta.id = missed_questions.test_attempt_id
      AND s.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.test_attempts ta
    JOIN public.activity_sessions s
      ON s.id = ta.session_id
    WHERE ta.id = missed_questions.test_attempt_id
      AND s.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS video_entries_owner_all ON public.video_entries;
CREATE POLICY video_entries_owner_all ON public.video_entries
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = video_entries.session_id
      AND s.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = video_entries.session_id
      AND s.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS reading_entries_owner_all ON public.reading_entries;
CREATE POLICY reading_entries_owner_all ON public.reading_entries
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = reading_entries.session_id
      AND s.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.activity_sessions s
    WHERE s.id = reading_entries.session_id
      AND s.user_id = auth.uid()
  )
);

-- -------------------------------------------------------------------
-- GRANTS
-- -------------------------------------------------------------------

GRANT SELECT ON public.platforms TO anon, authenticated;
GRANT SELECT ON public.study_items TO anon, authenticated;
GRANT SELECT ON public.form_templates TO anon, authenticated;
GRANT SELECT ON public.form_template_fields TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.activity_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.revision_entries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.test_attempts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.missed_questions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.video_entries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reading_entries TO authenticated;

-- -------------------------------------------------------------------
-- SEED: PLATFORMS
-- -------------------------------------------------------------------
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('revision', 'Revision', '📘', 1)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('guidely', 'Guidely', '📚', 2)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('yes-officer', 'Yes Officer', '🏛️', 3)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('adda247', 'Adda247', '🏫', 4)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('coding-cpp', 'Coding C++', '💻', 5)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('oliveboard', 'Oliveboard', '🫒', 6)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('free-ebook', 'Free eBook', '📖', 7)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('practice-mock', 'Practice Mock', '🧪', 8)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('pw', 'PW', '🏫', 9)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('selection-way', 'Selection Way', '🎯', 10)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('test-ranking', 'Test Ranking', '🏆', 11)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('smartkeeda', 'Smartkeeda', '⚡', 12)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('speed-math', 'Speed Math', '🚀', 13)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('testbook', 'Testbook', '📚', 14)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('yes-mock', 'Yes Mock', '🆓', 15)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('quick-trick-by-sahil-sir', 'Quick Trick by Sahil Sir', '🧠', 16)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('the-hindu', 'The Hindu', '📰', 17)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('kaushik-mohanty', 'Kaushik Mohanty', '🎥', 18)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('saurabh-sir', 'Saurabh Sir', '🎥', 19)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('kush-pandey', 'Kush Pandey', '🎥', 20)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('nimisha-bansal', 'Nimisha Bansal', '🎥', 21)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('ankush-lamba', 'Ankush Lamba', '🎥', 22)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('atm', 'ATM', '🎥', 23)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('tmm', 'TMM', '🎥', 24)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
INSERT INTO public.platforms (slug, platform_name, platform_icon, sort_order)
VALUES ('rmb', 'RMB', '🎥', 25)
ON CONFLICT (slug) DO UPDATE SET platform_name = EXCLUDED.platform_name, platform_icon = EXCLUDED.platform_icon, sort_order = EXCLUDED.sort_order, is_active = TRUE;
-- -------------------------------------------------------------------
-- SEED: FORM TEMPLATES
-- -------------------------------------------------------------------
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('revision_basic', 'Revision Basic', 'Update Revision Progress', 'Enter raw revision progress only. Date/time metadata is automatic.', 'revision'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_minimal_with_missed_questions', 'Test Minimal With Missed Questions', 'Enter Minimal Test Attempt', 'Enter only the raw fields actually shown by this platform. Add missed questions only.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_basic_with_missed_questions', 'Test Basic With Missed Questions', 'Enter Test Attempt', 'Enter raw test facts and add only missed questions.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_rank_with_missed_questions', 'Test Rank With Missed Questions', 'Enter Rank Test Attempt', 'Enter raw test facts, rank details, and missed questions only.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_advanced_time_with_missed_questions', 'Test Advanced Time With Missed Questions', 'Enter Advanced Test Attempt', 'Enter raw test facts, time breakdown, and missed questions only.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_rank_advanced_with_missed_questions', 'Test Rank + Advanced Time With Missed Questions', 'Enter Advanced Rank Test Attempt', 'Enter raw test facts, rank details, advanced time breakdown, and missed questions only.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('test_range_with_missed_questions', 'Test Range With Missed Questions', 'Enter Range-Based Test Attempt', 'Enter raw range/test facts and missed questions only.', 'test'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('video_progress', 'Video Progress', 'Track Video Progress', 'Enter raw video study facts only. Status is derived later.', 'video'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
INSERT INTO public.form_templates (template_key, template_name, form_title, form_description, activity_type)
VALUES ('reading_progress', 'Reading Progress', 'Track Reading Progress', 'Enter reading state, time spent, and notes only.', 'reading'::public.activity_type_enum)
ON CONFLICT (template_key) DO UPDATE SET template_name = EXCLUDED.template_name, form_title = EXCLUDED.form_title, form_description = EXCLUDED.form_description, activity_type = EXCLUDED.activity_type, is_active = TRUE;
-- -------------------------------------------------------------------
-- SEED: FORM TEMPLATE FIELDS
-- -------------------------------------------------------------------
DELETE FROM public.form_template_fields;
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'completed_count', 'Completed count', 'How much did you complete?', 'number',
       TRUE, FALSE, FALSE, 1, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'revision_basic';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'target_count_snapshot', 'Total target', 'Use the target for this selected item.', 'number',
       TRUE, FALSE, FALSE, 2, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'revision_basic';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'mistake_notes', 'Mistake notes', 'Optional notes about what you forgot or got stuck on.', 'textarea',
       FALSE, FALSE, FALSE, 3, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'revision_basic';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'confidence_level', 'Confidence level', 'Optional self-rating from 1 to 5.', 'select',
       FALSE, FALSE, FALSE, 4, 'main', NULL, '{"options":[1,2,3,4,5]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'revision_basic';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       FALSE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       FALSE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_minimal_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       TRUE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_basic_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       TRUE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'rank', 'Rank', 'Enter rank only if shown.', 'number',
       FALSE, FALSE, FALSE, 10, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_rank', 'Total rank', 'Enter total rank only if shown.', 'number',
       FALSE, FALSE, FALSE, 11, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'percentile', 'Percentile', 'Enter percentile only if shown.', 'number',
       FALSE, FALSE, FALSE, 12, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 13, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       TRUE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'utilized_seconds', 'Utilized time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 10, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wasted_seconds', 'Wasted time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 11, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'correct_time_seconds', 'Correct-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 12, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_time_seconds', 'Wrong-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 13, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_time_seconds', 'Skipped-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 14, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 15, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_advanced_time_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       TRUE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'rank', 'Rank', 'Enter rank only if shown.', 'number',
       FALSE, FALSE, FALSE, 10, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_rank', 'Total rank', 'Enter total rank only if shown.', 'number',
       FALSE, FALSE, FALSE, 11, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'percentile', 'Percentile', 'Enter percentile only if shown.', 'number',
       FALSE, FALSE, FALSE, 12, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'utilized_seconds', 'Utilized time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 13, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wasted_seconds', 'Wasted time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 14, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'correct_time_seconds', 'Correct-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 15, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_time_seconds', 'Wrong-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 16, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_time_seconds', 'Skipped-answer time', 'Optional advanced time breakdown field.', 'duration',
       FALSE, FALSE, FALSE, 17, 'time_breakdown', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 18, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_rank_advanced_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'range_from', 'From', 'Enter the starting number/range point if this practice item uses a range.', 'number',
       TRUE, FALSE, FALSE, 1, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'range_to', 'To', 'Enter the ending number/range point if this practice item uses a range.', 'number',
       TRUE, FALSE, FALSE, 2, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_questions', 'Total questions', 'Enter the total number of questions in the attempt.', 'number',
       TRUE, FALSE, FALSE, 3, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'max_marks', 'Total exam marks', 'Enter the maximum marks only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 4, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'marks_obtained', 'Marks obtained', 'Enter your obtained marks/score only if the platform shows them.', 'number',
       FALSE, FALSE, FALSE, 5, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_duration_seconds', 'Total exam duration', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 6, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_taken_seconds', 'Time taken', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 7, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'right_count', 'Right answers', 'Enter total correct answers if shown.', 'number',
       TRUE, FALSE, FALSE, 8, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'wrong_count', 'Wrong answers', 'Enter total wrong answers if shown.', 'number',
       FALSE, FALSE, FALSE, 9, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'skipped_count', 'Skipped answers', 'Enter total skipped answers if shown.', 'number',
       FALSE, FALSE, FALSE, 10, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'unseen_count', 'Unseen answers', 'Enter total unseen answers if shown.', 'number',
       FALSE, FALSE, FALSE, 11, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'result_notes', 'Attempt notes', 'Optional notes about the full attempt.', 'textarea',
       FALSE, FALSE, FALSE, 12, 'overall', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_number', 'Question number', 'Enter the question number from the test.', 'number',
       TRUE, FALSE, FALSE, 1, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'issue_type', 'Result type', 'Only store wrong, skipped, or unseen questions.', 'select',
       TRUE, FALSE, FALSE, 2, 'missed_questions', 'missed_questions', '{"options":["wrong","skipped","unseen"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_text', 'Question', 'Paste the question text.', 'textarea',
       TRUE, FALSE, FALSE, 3, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'options_json', 'Options', 'Store options as structured data/object for A/B/C/D/E.', 'json',
       FALSE, FALSE, FALSE, 4, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'selected_option_key', 'Your answer', 'Enter A/B/C/D/E if you selected one.', 'text',
       FALSE, FALSE, FALSE, 5, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'correct_option_key', 'Correct answer', 'Enter A/B/C/D/E if known.', 'text',
       FALSE, FALSE, FALSE, 6, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_marks', 'Question marks', 'Enter the marks for this question if known.', 'number',
       FALSE, FALSE, FALSE, 7, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'marks_received', 'Marks received', 'Enter marks received or penalty for this question if known.', 'number',
       FALSE, FALSE, FALSE, 8, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_time_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds.', 'duration',
       FALSE, FALSE, FALSE, 9, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'missed_question', 'question_note', 'Question note', 'Optional note about why you missed this question.', 'textarea',
       FALSE, FALSE, FALSE, 10, 'missed_questions', 'missed_questions', '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'test_range_with_missed_questions';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'watched_videos', 'Watched videos', 'Enter how many videos you actually watched.', 'number',
       TRUE, FALSE, FALSE, 1, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'video_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'total_videos_snapshot', 'Total videos', 'Use the total videos for this selected item.', 'number',
       TRUE, FALSE, FALSE, 2, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'video_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_spent_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 3, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'video_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'notes', 'Notes', 'Optional notes from the videos.', 'textarea',
       FALSE, FALSE, FALSE, 4, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'video_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'reading_state', 'Reading status', 'Choose completed, partial, or not_read.', 'select',
       TRUE, FALSE, FALSE, 1, 'main', NULL, '{"options":["completed","partial","not_read"]}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'reading_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'time_spent_seconds', 'Time spent', 'UI shows HH:MM:SS, backend stores seconds automatically.', 'duration',
       TRUE, FALSE, FALSE, 2, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'reading_progress';
INSERT INTO public.form_template_fields (
  template_id, field_scope, field_key, show_label, helper_text, input_type,
  is_required, is_auto, is_hidden, display_order, section_key, repeat_group_key, ui_config_json
)
SELECT ft.id, 'session', 'notes', 'Notes / Summary', 'Optional notes or summary.', 'textarea',
       FALSE, FALSE, FALSE, 3, 'main', NULL, '{}'::jsonb
FROM public.form_templates ft
WHERE ft.template_key = 'reading_progress';
-- -------------------------------------------------------------------
-- SEED: STUDY ITEMS
-- -------------------------------------------------------------------
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'revision_basic', 'revision-tables-1-to-20', '📘 Revision → 📊 Tables → 1 to 20', '1 to 20', 'Track raw revision data for 📘 Revision → 📊 Tables → 1 to 20.',
       'Revision', 'Tables', '1 to 20', 'revision'::public.activity_type_enum,
       20, '{"capture_mistake_notes":true,"capture_confidence_level":true}'::jsonb, 1
FROM public.platforms p
WHERE p.slug = 'revision'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'revision_basic', 'revision-squares-1-to-20', '📘 Revision → 🔢 Squares → 1 to 20', '1 to 20', 'Track raw revision data for 📘 Revision → 🔢 Squares → 1 to 20.',
       'Revision', 'Squares', '1 to 20', 'revision'::public.activity_type_enum,
       20, '{"capture_mistake_notes":true,"capture_confidence_level":true}'::jsonb, 2
FROM public.platforms p
WHERE p.slug = 'revision'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'revision_basic', 'revision-cubes-1-to-10', '📘 Revision → 🧊 Cubes → 1 to 10', '1 to 10', 'Track raw revision data for 📘 Revision → 🧊 Cubes → 1 to 10.',
       'Revision', 'Cubes', '1 to 10', 'revision'::public.activity_type_enum,
       10, '{"capture_mistake_notes":true,"capture_confidence_level":true}'::jsonb, 3
FROM public.platforms p
WHERE p.slug = 'revision'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'revision_basic', 'revision-fractions-1-to-10', '📘 Revision → ➗ Fractions → 1 to 10', '1 to 10', 'Track raw revision data for 📘 Revision → ➗ Fractions → 1 to 10.',
       'Revision', 'Fractions', '1 to 10', 'revision'::public.activity_type_enum,
       10, '{"capture_mistake_notes":true,"capture_confidence_level":true}'::jsonb, 4
FROM public.platforms p
WHERE p.slug = 'revision'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'revision_basic', 'revision-prime-numbers-1-to-30', '📘 Revision → 🔺 Prime Numbers → 1 to 30', '1 to 30', 'Track raw revision data for 📘 Revision → 🔺 Prime Numbers → 1 to 30.',
       'Revision', 'Prime Numbers', '1 to 30', 'revision'::public.activity_type_enum,
       30, '{"capture_mistake_notes":true,"capture_confidence_level":true}'::jsonb, 5
FROM public.platforms p
WHERE p.slug = 'revision'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-special-beginners-bundle-percentage-1-mock', '📚 Guidely → 🟢 Special Beginners Bundle → Percentage → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟢 Special Beginners Bundle → Percentage → 1 mock.',
       'Special Beginners Bundle', 'Percentage', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 6
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-special-beginners-bundle-number-system-1-mock', '📚 Guidely → 🟢 Special Beginners Bundle → Number System → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟢 Special Beginners Bundle → Number System → 1 mock.',
       'Special Beginners Bundle', 'Number System', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 7
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-special-beginners-bundle-simplification-1-mock', '📚 Guidely → 🟢 Special Beginners Bundle → Simplification → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟢 Special Beginners Bundle → Simplification → 1 mock.',
       'Special Beginners Bundle', 'Simplification', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 8
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-special-beginners-bundle-approximation-1-mock', '📚 Guidely → 🟢 Special Beginners Bundle → Approximation → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟢 Special Beginners Bundle → Approximation → 1 mock.',
       'Special Beginners Bundle', 'Approximation', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 9
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-topic-wise-approximation-1-mock', '📚 Guidely → 🟦 Topic-wise → Approximation → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟦 Topic-wise → Approximation → 1 mock.',
       'Topic-wise', 'Approximation', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 10
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-topic-wise-percentage-1-mock', '📚 Guidely → 🟦 Topic-wise → Percentage → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟦 Topic-wise → Percentage → 1 mock.',
       'Topic-wise', 'Percentage', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 11
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-topic-wise-simplification-1-mock', '📚 Guidely → 🟦 Topic-wise → Simplification → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟦 Topic-wise → Simplification → 1 mock.',
       'Topic-wise', 'Simplification', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 12
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-topic-wise-number-system-1-mock', '📚 Guidely → 🟦 Topic-wise → Number System → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🟦 Topic-wise → Number System → 1 mock.',
       'Topic-wise', 'Number System', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 13
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_advanced_time_with_missed_questions', 'guidely-arithmetic-master-each-topic-1-mock', '📚 Guidely → 🧩 Arithmetic Master → Each topic → 1 mock', '1 mock', 'Track raw test data for 📚 Guidely → 🧩 Arithmetic Master → Each topic → 1 mock.',
       'Arithmetic Master', 'Each topic', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":true,"ask_unseen_count":true,"ask_rank":false,"ask_total_rank":false,"ask_percentile":false,"ask_time_breakdown":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 14
FROM public.platforms p
WHERE p.slug = 'guidely'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_minimal_with_missed_questions', 'yes-officer-yes-magazine-2-mocks', '🏛️ Yes Officer → Yes Magazine → 2 mocks', '2 mocks', 'Track raw test data for 🏛️ Yes Officer → Yes Magazine → 2 mocks.',
       'Yes Officer', 'Yes Magazine', '2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_time_taken":true,"ask_max_marks":false,"ask_marks_obtained":false,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":false,"ask_question_time":false,"ask_notes":true}'::jsonb, 15
FROM public.platforms p
WHERE p.slug = 'yes-officer'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_minimal_with_missed_questions', 'yes-officer-prelims-exclusive-2-mocks', '🏛️ Yes Officer → Prelims Exclusive → 2 mocks', '2 mocks', 'Track raw test data for 🏛️ Yes Officer → Prelims Exclusive → 2 mocks.',
       'Yes Officer', 'Prelims Exclusive', '2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_time_taken":true,"ask_max_marks":false,"ask_marks_obtained":false,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":false,"ask_question_time":false,"ask_notes":true}'::jsonb, 16
FROM public.platforms p
WHERE p.slug = 'yes-officer'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_minimal_with_missed_questions', 'yes-officer-special-pdf-free-2-mocks', '🏛️ Yes Officer → Special PDF (Free) → 2 mocks', '2 mocks', 'Track raw test data for 🏛️ Yes Officer → Special PDF (Free) → 2 mocks.',
       'Yes Officer', 'Special PDF (Free)', '2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_time_taken":true,"ask_max_marks":false,"ask_marks_obtained":false,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":false,"ask_question_time":false,"ask_notes":true}'::jsonb, 17
FROM public.platforms p
WHERE p.slug = 'yes-officer'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_rank_with_missed_questions', 'adda247-simplification-2-questions-2-mocks', '🏫 Adda247 → Simplification → 2 questions + 2 mocks', '2 questions + 2 mocks', 'Track raw test data for 🏫 Adda247 → Simplification → 2 questions + 2 mocks.',
       'Adda247', 'Simplification', '2 questions + 2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_rank":true,"ask_total_rank":true,"ask_percentile":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 18
FROM public.platforms p
WHERE p.slug = 'adda247'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_rank_with_missed_questions', 'adda247-approximation-2-questions-2-mocks', '🏫 Adda247 → Approximation → 2 questions + 2 mocks', '2 questions + 2 mocks', 'Track raw test data for 🏫 Adda247 → Approximation → 2 questions + 2 mocks.',
       'Adda247', 'Approximation', '2 questions + 2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_rank":true,"ask_total_rank":true,"ask_percentile":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 19
FROM public.platforms p
WHERE p.slug = 'adda247'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_rank_with_missed_questions', 'adda247-percentage-2-questions-2-mocks', '🏫 Adda247 → Percentage → 2 questions + 2 mocks', '2 questions + 2 mocks', 'Track raw test data for 🏫 Adda247 → Percentage → 2 questions + 2 mocks.',
       'Adda247', 'Percentage', '2 questions + 2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_rank":true,"ask_total_rank":true,"ask_percentile":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 20
FROM public.platforms p
WHERE p.slug = 'adda247'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_rank_with_missed_questions', 'adda247-number-system-2-questions-2-mocks', '🏫 Adda247 → Number System → 2 questions + 2 mocks', '2 questions + 2 mocks', 'Track raw test data for 🏫 Adda247 → Number System → 2 questions + 2 mocks.',
       'Adda247', 'Number System', '2 questions + 2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_rank":true,"ask_total_rank":true,"ask_percentile":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 21
FROM public.platforms p
WHERE p.slug = 'adda247'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_range_with_missed_questions', 'coding-c-table-quiz-1-to-30', '💻 Coding C++ → Table Quiz → 1 to 30', '1 to 30', 'Track raw test data for 💻 Coding C++ → Table Quiz → 1 to 30.',
       'Coding C++', 'Table Quiz', '1 to 30', 'test'::public.activity_type_enum,
       30, '{"ask_range_from":true,"ask_range_to":true,"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":false,"ask_total_duration":false,"ask_time_taken":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":false,"ask_question_time":true,"ask_notes":true}'::jsonb, 22
FROM public.platforms p
WHERE p.slug = 'coding-cpp'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_range_with_missed_questions', 'coding-c-fraction-quiz-1-to-30', '💻 Coding C++ → Fraction Quiz → 1 to 30', '1 to 30', 'Track raw test data for 💻 Coding C++ → Fraction Quiz → 1 to 30.',
       'Coding C++', 'Fraction Quiz', '1 to 30', 'test'::public.activity_type_enum,
       30, '{"ask_range_from":true,"ask_range_to":true,"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":false,"ask_total_duration":false,"ask_time_taken":true,"ask_right_count":false,"ask_wrong_count":false,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":false,"ask_question_time":true,"ask_notes":true}'::jsonb, 23
FROM public.platforms p
WHERE p.slug = 'coding-cpp'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'oliveboard-free-zone-current-affairs-quiz-1-mock', '🫒 Oliveboard → Free Zone → Current Affairs Quiz → 1 mock', '1 mock', 'Track raw test data for 🫒 Oliveboard → Free Zone → Current Affairs Quiz → 1 mock.',
       'Free Zone', 'Current Affairs Quiz', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 24
FROM public.platforms p
WHERE p.slug = 'oliveboard'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'free-ebook-free-ebook-test-1-mock', '📖 Free eBook → Free eBook Test → 1 mock', '1 mock', 'Track raw test data for 📖 Free eBook → Free eBook Test → 1 mock.',
       'Free eBook', 'Free eBook Test', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 25
FROM public.platforms p
WHERE p.slug = 'free-ebook'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_rank_with_missed_questions', 'practice-mock-banking-topic-test-1-mock', '🧪 Practice Mock → Banking Topic Test → 1 mock', '1 mock', 'Track raw test data for 🧪 Practice Mock → Banking Topic Test → 1 mock.',
       'Practice Mock', 'Banking Topic Test', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":true,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"ask_rank":true,"ask_total_rank":false,"ask_percentile":true,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 26
FROM public.platforms p
WHERE p.slug = 'practice-mock'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'pw-test-2-mocks', '🏫 PW → Test → 2 mocks', '2 mocks', 'Track raw test data for 🏫 PW → Test → 2 mocks.',
       'PW', 'Test', '2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 27
FROM public.platforms p
WHERE p.slug = 'pw'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'pw-dpp-2', '🏫 PW → DPP → 2', '2', 'Track raw test data for 🏫 PW → DPP → 2.',
       'PW', 'DPP', '2', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 28
FROM public.platforms p
WHERE p.slug = 'pw'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'selection-way-math-booster-1-mock', '🎯 Selection Way → Math Booster → 1 mock', '1 mock', 'Track raw test data for 🎯 Selection Way → Math Booster → 1 mock.',
       'Selection Way', 'Math Booster', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 29
FROM public.platforms p
WHERE p.slug = 'selection-way'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'selection-way-calculation-booster-1-mock', '🎯 Selection Way → Calculation Booster → 1 mock', '1 mock', 'Track raw test data for 🎯 Selection Way → Calculation Booster → 1 mock.',
       'Selection Way', 'Calculation Booster', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 30
FROM public.platforms p
WHERE p.slug = 'selection-way'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'selection-way-reasoning-booster-1-mock', '🎯 Selection Way → Reasoning Booster → 1 mock', '1 mock', 'Track raw test data for 🎯 Selection Way → Reasoning Booster → 1 mock.',
       'Selection Way', 'Reasoning Booster', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 31
FROM public.platforms p
WHERE p.slug = 'selection-way'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'selection-way-railway-booster-math-science-ga-1-mock', '🎯 Selection Way → Railway Booster (Math, Science, GA) → 1 mock', '1 mock', 'Track raw test data for 🎯 Selection Way → Railway Booster (Math, Science, GA) → 1 mock.',
       'Selection Way', 'Railway Booster (Math, Science, GA)', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 32
FROM public.platforms p
WHERE p.slug = 'selection-way'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'selection-way-reasoning-free-test-pack-1-mock', '🎯 Selection Way → Reasoning (Free Test Pack) → 1 mock', '1 mock', 'Track raw test data for 🎯 Selection Way → Reasoning (Free Test Pack) → 1 mock.',
       'Selection Way', 'Reasoning (Free Test Pack)', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 33
FROM public.platforms p
WHERE p.slug = 'selection-way'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'test-ranking-daily-quiz-2-mocks', '🏆 Test Ranking → Daily Quiz → 2 mocks', '2 mocks', 'Track raw test data for 🏆 Test Ranking → Daily Quiz → 2 mocks.',
       'Test Ranking', 'Daily Quiz', '2 mocks', 'test'::public.activity_type_enum,
       2, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 34
FROM public.platforms p
WHERE p.slug = 'test-ranking'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-speed-math-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Speed Math → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Speed Math → 40 questions.',
       'Speed Drill (Solo)', 'Speed Math', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 35
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-simplification-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Simplification → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Simplification → 40 questions.',
       'Speed Drill (Solo)', 'Simplification', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 36
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-approximation-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Approximation → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Approximation → 40 questions.',
       'Speed Drill (Solo)', 'Approximation', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 37
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-number-series-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Number Series → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Number Series → 40 questions.',
       'Speed Drill (Solo)', 'Number Series', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 38
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-percentage-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Percentage → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Percentage → 40 questions.',
       'Speed Drill (Solo)', 'Percentage', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 39
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-speed-drill-solo-ratio-proportion-40-questions', '⚡ Smartkeeda → Speed Drill (Solo) → Ratio & Proportion → 40 questions', '40 questions', 'Track raw test data for ⚡ Smartkeeda → Speed Drill (Solo) → Ratio & Proportion → 40 questions.',
       'Speed Drill (Solo)', 'Ratio & Proportion', '40 questions', 'test'::public.activity_type_enum,
       40, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 40
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-marathon-drill-combined-25-minutes-simplification', '🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Simplification', 'Simplification', 'Track raw test data for 🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Simplification.',
       'Marathon Drill', 'Simplification', 'Combined 25 minutes', 'test'::public.activity_type_enum,
       25, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 41
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-marathon-drill-combined-25-minutes-approximation', '🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Approximation', 'Approximation', 'Track raw test data for 🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Approximation.',
       'Marathon Drill', 'Approximation', 'Combined 25 minutes', 'test'::public.activity_type_enum,
       25, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 42
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-marathon-drill-combined-25-minutes-percentage', '🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Percentage', 'Percentage', 'Track raw test data for 🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Percentage.',
       'Marathon Drill', 'Percentage', 'Combined 25 minutes', 'test'::public.activity_type_enum,
       25, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 43
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-marathon-drill-combined-25-minutes-ratio-proportion', '🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Ratio & Proportion', 'Ratio & Proportion', 'Track raw test data for 🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Ratio & Proportion.',
       'Marathon Drill', 'Ratio & Proportion', 'Combined 25 minutes', 'test'::public.activity_type_enum,
       25, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 44
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-marathon-drill-combined-25-minutes-speed-math', '🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Speed Math', 'Speed Math', 'Track raw test data for 🏃 Smartkeeda → Marathon Drill → Combined 25 minutes → Speed Math.',
       'Marathon Drill', 'Speed Math', 'Combined 25 minutes', 'test'::public.activity_type_enum,
       25, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 45
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-topic-test-simplification-1-mock', '📌 Smartkeeda → Topic Test → Simplification → 1 mock', '1 mock', 'Track raw test data for 📌 Smartkeeda → Topic Test → Simplification → 1 mock.',
       'Topic Test', 'Simplification', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 46
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-topic-test-approximation-1-mock', '📌 Smartkeeda → Topic Test → Approximation → 1 mock', '1 mock', 'Track raw test data for 📌 Smartkeeda → Topic Test → Approximation → 1 mock.',
       'Topic Test', 'Approximation', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 47
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-topic-test-number-series-1-mock', '📌 Smartkeeda → Topic Test → Number Series → 1 mock', '1 mock', 'Track raw test data for 📌 Smartkeeda → Topic Test → Number Series → 1 mock.',
       'Topic Test', 'Number Series', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 48
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-topic-test-percentage-1-mock', '📌 Smartkeeda → Topic Test → Percentage → 1 mock', '1 mock', 'Track raw test data for 📌 Smartkeeda → Topic Test → Percentage → 1 mock.',
       'Topic Test', 'Percentage', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 49
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-free-pdf-1-mock', '📄 Smartkeeda → Free PDF → 1 mock', '1 mock', 'Track raw test data for 📄 Smartkeeda → Free PDF → 1 mock.',
       'Smartkeeda', 'Free PDF', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 50
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-free-quiz-simplification-1-mock', '📝 Smartkeeda → Free Quiz → Simplification → 1 mock', '1 mock', 'Track raw test data for 📝 Smartkeeda → Free Quiz → Simplification → 1 mock.',
       'Free Quiz', 'Simplification', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 51
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'smartkeeda-free-quiz-approximation-1-mock', '📝 Smartkeeda → Free Quiz → Approximation → 1 mock', '1 mock', 'Track raw test data for 📝 Smartkeeda → Free Quiz → Approximation → 1 mock.',
       'Free Quiz', 'Approximation', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 52
FROM public.platforms p
WHERE p.slug = 'smartkeeda'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-squares-1-999-30-questions', '🚀 Speed Math → Squares (1–999) → 30 questions', '30 questions', 'Track raw test data for 🚀 Speed Math → Squares (1–999) → 30 questions.',
       'Speed Math', 'Squares (1–999)', '30 questions', 'test'::public.activity_type_enum,
       30, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 53
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-1-100-30-questions', '🚀 Speed Math → 1–100 → 30 questions', '30 questions', 'Track raw test data for 🚀 Speed Math → 1–100 → 30 questions.',
       'Speed Math', '1–100', '30 questions', 'test'::public.activity_type_enum,
       30, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 54
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-cubes-1-30-30-questions', '🚀 Speed Math → Cubes (1–30) → 30 questions', '30 questions', 'Track raw test data for 🚀 Speed Math → Cubes (1–30) → 30 questions.',
       'Speed Math', 'Cubes (1–30)', '30 questions', 'test'::public.activity_type_enum,
       30, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 55
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-cubes-1-100-30-questions', '🚀 Speed Math → Cubes (1–100) → 30 questions', '30 questions', 'Track raw test data for 🚀 Speed Math → Cubes (1–100) → 30 questions.',
       'Speed Math', 'Cubes (1–100)', '30 questions', 'test'::public.activity_type_enum,
       30, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 56
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-square-root-1-30-30-questions', '🚀 Speed Math → Square Root (1–30) → 30 questions', '30 questions', 'Track raw test data for 🚀 Speed Math → Square Root (1–30) → 30 questions.',
       'Speed Math', 'Square Root (1–30)', '30 questions', 'test'::public.activity_type_enum,
       30, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 57
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-2-digit-addition-60-questions', '🚀 Speed Math → 2-Digit Addition → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → 2-Digit Addition → 60 questions.',
       'Speed Math', '2-Digit Addition', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 58
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-addition-60-questions', '🚀 Speed Math → Addition → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → Addition → 60 questions.',
       'Speed Math', 'Addition', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 59
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-subtraction-60-questions', '🚀 Speed Math → Subtraction → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → Subtraction → 60 questions.',
       'Speed Math', 'Subtraction', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 60
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-multiplication-60-questions', '🚀 Speed Math → Multiplication → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → Multiplication → 60 questions.',
       'Speed Math', 'Multiplication', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 61
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-division-60-questions', '🚀 Speed Math → Division → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → Division → 60 questions.',
       'Speed Math', 'Division', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 62
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'speed-math-percentage-60-questions', '🚀 Speed Math → Percentage → 60 questions', '60 questions', 'Track raw test data for 🚀 Speed Math → Percentage → 60 questions.',
       'Speed Math', 'Percentage', '60 questions', 'test'::public.activity_type_enum,
       60, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 63
FROM public.platforms p
WHERE p.slug = 'speed-math'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'testbook-simplification-1-mock', '📚 Testbook → Simplification → 1 mock', '1 mock', 'Track raw test data for 📚 Testbook → Simplification → 1 mock.',
       'Testbook', 'Simplification', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 64
FROM public.platforms p
WHERE p.slug = 'testbook'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'testbook-approximation-1-mock', '📚 Testbook → Approximation → 1 mock', '1 mock', 'Track raw test data for 📚 Testbook → Approximation → 1 mock.',
       'Testbook', 'Approximation', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 65
FROM public.platforms p
WHERE p.slug = 'testbook'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'testbook-percentage-1-mock', '📚 Testbook → Percentage → 1 mock', '1 mock', 'Track raw test data for 📚 Testbook → Percentage → 1 mock.',
       'Testbook', 'Percentage', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 66
FROM public.platforms p
WHERE p.slug = 'testbook'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'testbook-ratio-proportion-1-mock', '📚 Testbook → Ratio & Proportion → 1 mock', '1 mock', 'Track raw test data for 📚 Testbook → Ratio & Proportion → 1 mock.',
       'Testbook', 'Ratio & Proportion', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 67
FROM public.platforms p
WHERE p.slug = 'testbook'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'yes-mock-free-quiz-3-mocks-different-topics', '🆓 Yes Mock → Free Quiz → 3 mocks (different topics)', '3 mocks (different topics)', 'Track raw test data for 🆓 Yes Mock → Free Quiz → 3 mocks (different topics).',
       'Yes Mock', 'Free Quiz', '3 mocks (different topics)', 'test'::public.activity_type_enum,
       3, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 68
FROM public.platforms p
WHERE p.slug = 'yes-mock'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'quick-trick-by-sahil-sir-daily-free-quiz-1-mock', '🧠 Quick Trick by Sahil Sir → Daily Free Quiz → 1 mock', '1 mock', 'Track raw test data for 🧠 Quick Trick by Sahil Sir → Daily Free Quiz → 1 mock.',
       'Quick Trick by Sahil Sir', 'Daily Free Quiz', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 69
FROM public.platforms p
WHERE p.slug = 'quick-trick-by-sahil-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'quick-trick-by-sahil-sir-math-1-mock', '🧠 Quick Trick by Sahil Sir → Math → 1 mock', '1 mock', 'Track raw test data for 🧠 Quick Trick by Sahil Sir → Math → 1 mock.',
       'Quick Trick by Sahil Sir', 'Math', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 70
FROM public.platforms p
WHERE p.slug = 'quick-trick-by-sahil-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'quick-trick-by-sahil-sir-reasoning-1-mock', '🧠 Quick Trick by Sahil Sir → Reasoning → 1 mock', '1 mock', 'Track raw test data for 🧠 Quick Trick by Sahil Sir → Reasoning → 1 mock.',
       'Quick Trick by Sahil Sir', 'Reasoning', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 71
FROM public.platforms p
WHERE p.slug = 'quick-trick-by-sahil-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'quick-trick-by-sahil-sir-gk-gs-1-mock', '🧠 Quick Trick by Sahil Sir → GK / GS → 1 mock', '1 mock', 'Track raw test data for 🧠 Quick Trick by Sahil Sir → GK / GS → 1 mock.',
       'Quick Trick by Sahil Sir', 'GK / GS', '1 mock', 'test'::public.activity_type_enum,
       1, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 72
FROM public.platforms p
WHERE p.slug = 'quick-trick-by-sahil-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'test_basic_with_missed_questions', 'quick-trick-by-sahil-sir-other-paid-test-as-given', '🧠 Quick Trick by Sahil Sir → Other Paid Test → as given', 'as given', 'Track raw test data for 🧠 Quick Trick by Sahil Sir → Other Paid Test → as given.',
       'Quick Trick by Sahil Sir', 'Other Paid Test', 'as given', 'test'::public.activity_type_enum,
       NULL, '{"ask_total_questions":true,"ask_max_marks":false,"ask_marks_obtained":true,"ask_total_duration":true,"ask_time_taken":true,"ask_right_count":true,"ask_wrong_count":true,"ask_skipped_count":false,"ask_unseen_count":false,"capture_missed_questions":true,"ask_question_marks":true,"ask_question_time":true,"ask_notes":true}'::jsonb, 73
FROM public.platforms p
WHERE p.slug = 'quick-trick-by-sahil-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'reading_progress', 'read-daily-the-hindu-news-paper-today-s', 'Read daily the hindu news paper today''s.', 'Read daily the hindu news paper today''s.', 'Track raw reading data for Read daily the hindu news paper today''s..',
       'The Hindu', 'Daily Reading', 'Today''s newspaper', 'reading'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 74
FROM public.platforms p
WHERE p.slug = 'the-hindu'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'kaushik-mohanty-career-definer-2-videos', 'Kaushik Mohanty → Career Definer → 2 videos', '2 videos', 'Track raw video data for Kaushik Mohanty → Career Definer → 2 videos.',
       'Kaushik Mohanty', 'Career Definer', '2 videos', 'video'::public.activity_type_enum,
       2, '{"ask_notes":true}'::jsonb, 75
FROM public.platforms p
WHERE p.slug = 'kaushik-mohanty'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'kaushik-mohanty-youtube-1-video', 'Kaushik Mohanty → YouTube → 1 video', '1 video', 'Track raw video data for Kaushik Mohanty → YouTube → 1 video.',
       'Kaushik Mohanty', 'YouTube', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 76
FROM public.platforms p
WHERE p.slug = 'kaushik-mohanty'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'saurabh-sir-batch-2-videos', 'Saurabh Sir → Batch → 2 videos', '2 videos', 'Track raw video data for Saurabh Sir → Batch → 2 videos.',
       'Saurabh Sir', 'Batch', '2 videos', 'video'::public.activity_type_enum,
       2, '{"ask_notes":true}'::jsonb, 77
FROM public.platforms p
WHERE p.slug = 'saurabh-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'saurabh-sir-youtube-1-video', 'Saurabh Sir → YouTube → 1 video', '1 video', 'Track raw video data for Saurabh Sir → YouTube → 1 video.',
       'Saurabh Sir', 'YouTube', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 78
FROM public.platforms p
WHERE p.slug = 'saurabh-sir'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'kush-pandey-batch-1-video', 'Kush Pandey → Batch → 1 video', '1 video', 'Track raw video data for Kush Pandey → Batch → 1 video.',
       'Kush Pandey', 'Batch', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 79
FROM public.platforms p
WHERE p.slug = 'kush-pandey'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'kush-pandey-youtube-1-video', 'Kush Pandey → YouTube → 1 video', '1 video', 'Track raw video data for Kush Pandey → YouTube → 1 video.',
       'Kush Pandey', 'YouTube', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 80
FROM public.platforms p
WHERE p.slug = 'kush-pandey'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'nimisha-bansal-batch-2-videos', 'Nimisha Bansal → Batch → 2 videos', '2 videos', 'Track raw video data for Nimisha Bansal → Batch → 2 videos.',
       'Nimisha Bansal', 'Batch', '2 videos', 'video'::public.activity_type_enum,
       2, '{"ask_notes":true}'::jsonb, 81
FROM public.platforms p
WHERE p.slug = 'nimisha-bansal'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'nimisha-bansal-editorial-1-video', 'Nimisha Bansal → Editorial → 1 video', '1 video', 'Track raw video data for Nimisha Bansal → Editorial → 1 video.',
       'Nimisha Bansal', 'Editorial', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 82
FROM public.platforms p
WHERE p.slug = 'nimisha-bansal'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'nimisha-bansal-youtube-1-video', 'Nimisha Bansal → YouTube → 1 video', '1 video', 'Track raw video data for Nimisha Bansal → YouTube → 1 video.',
       'Nimisha Bansal', 'YouTube', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 83
FROM public.platforms p
WHERE p.slug = 'nimisha-bansal'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'ankush-lamba-batch-1-video', 'Ankush Lamba → Batch → 1 video', '1 video', 'Track raw video data for Ankush Lamba → Batch → 1 video.',
       'Ankush Lamba', 'Batch', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 84
FROM public.platforms p
WHERE p.slug = 'ankush-lamba'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'ankush-lamba-youtube-1-video', 'Ankush Lamba → YouTube → 1 video', '1 video', 'Track raw video data for Ankush Lamba → YouTube → 1 video.',
       'Ankush Lamba', 'YouTube', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 85
FROM public.platforms p
WHERE p.slug = 'ankush-lamba'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'atm-batch-2-videos', 'ATM → Batch → 2 videos', '2 videos', 'Track raw video data for ATM → Batch → 2 videos.',
       'ATM', 'Batch', '2 videos', 'video'::public.activity_type_enum,
       2, '{"ask_notes":true}'::jsonb, 86
FROM public.platforms p
WHERE p.slug = 'atm'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'tmm-batch-1-video', 'TMM → Batch → 1 video', '1 video', 'Track raw video data for TMM → Batch → 1 video.',
       'TMM', 'Batch', '1 video', 'video'::public.activity_type_enum,
       1, '{"ask_notes":true}'::jsonb, 87
FROM public.platforms p
WHERE p.slug = 'tmm'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;
INSERT INTO public.study_items (
  platform_id, template_key, slug, full_path, display_name, short_description,
  main_category, sub_category, item_name, activity_type, target_count, ui_rules_json, sort_order
)
SELECT p.id, 'video_progress', 'rmb-batch-5-videos', 'RMB → Batch → 5 videos', '5 videos', 'Track raw video data for RMB → Batch → 5 videos.',
       'RMB', 'Batch', '5 videos', 'video'::public.activity_type_enum,
       5, '{"ask_notes":true}'::jsonb, 88
FROM public.platforms p
WHERE p.slug = 'rmb'
ON CONFLICT (slug) DO UPDATE SET
  platform_id = EXCLUDED.platform_id,
  template_key = EXCLUDED.template_key,
  full_path = EXCLUDED.full_path,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  main_category = EXCLUDED.main_category,
  sub_category = EXCLUDED.sub_category,
  item_name = EXCLUDED.item_name,
  activity_type = EXCLUDED.activity_type,
  target_count = EXCLUDED.target_count,
  ui_rules_json = EXCLUDED.ui_rules_json,
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE;

-- -------------------------------------------------------------------
-- VIEWS (DERIVED METRICS ONLY; NOTHING DERIVED IS STORED AS A PHYSICAL COLUMN)
-- -------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_study_item_catalog AS
SELECT
  si.id,
  si.slug,
  si.full_path,
  si.display_name,
  si.short_description,
  p.platform_name,
  p.platform_icon,
  si.main_category,
  si.sub_category,
  si.item_name,
  si.activity_type,
  si.template_key,
  ft.form_title,
  ft.form_description,
  si.target_count,
  si.ui_rules_json,
  si.sort_order,
  si.is_active
FROM public.study_items si
JOIN public.platforms p
  ON p.id = si.platform_id
JOIN public.form_templates ft
  ON ft.template_key = si.template_key;

CREATE OR REPLACE VIEW public.v_revision_entry_metrics AS
SELECT
  re.id,
  re.session_id,
  s.user_id,
  s.study_item_id,
  s.session_date,
  re.completed_count,
  re.target_count_snapshot,
  CASE
    WHEN re.target_count_snapshot > 0 THEN ROUND((re.completed_count::numeric / re.target_count_snapshot::numeric) * 100, 2)
    ELSE NULL
  END AS completion_percent,
  CASE
    WHEN re.completed_count = 0 THEN 'not_started'
    WHEN re.completed_count >= re.target_count_snapshot THEN 'completed'
    ELSE 'partial'
  END AS derived_status,
  re.mistake_notes,
  re.confidence_level,
  re.created_at,
  re.updated_at
FROM public.revision_entries re
JOIN public.activity_sessions s
  ON s.id = re.session_id;

CREATE OR REPLACE VIEW public.v_test_attempt_metrics AS
SELECT
  ta.id,
  ta.session_id,
  s.user_id,
  s.study_item_id,
  s.session_date,
  ta.total_questions,
  ta.max_marks,
  ta.marks_obtained,
  ta.total_duration_seconds,
  ta.time_taken_seconds,
  ta.right_count,
  ta.wrong_count,
  ta.skipped_count,
  ta.unseen_count,
  (COALESCE(ta.right_count,0) + COALESCE(ta.wrong_count,0) + COALESCE(ta.skipped_count,0)) AS attempted_count,
  CASE
    WHEN (COALESCE(ta.right_count,0) + COALESCE(ta.wrong_count,0)) > 0
      THEN ROUND((COALESCE(ta.right_count,0)::numeric / NULLIF((COALESCE(ta.right_count,0) + COALESCE(ta.wrong_count,0)),0)::numeric) * 100, 2)
    ELSE NULL
  END AS accuracy_percent,
  CASE
    WHEN ta.max_marks IS NOT NULL AND ta.max_marks > 0 AND ta.marks_obtained IS NOT NULL
      THEN ROUND((ta.marks_obtained / ta.max_marks) * 100, 2)
    ELSE NULL
  END AS score_percent,
  ta.rank,
  ta.total_rank,
  ta.percentile,
  ta.utilized_seconds,
  ta.wasted_seconds,
  ta.correct_time_seconds,
  ta.wrong_time_seconds,
  ta.skipped_time_seconds,
  ta.range_from,
  ta.range_to,
  ta.result_notes,
  ta.created_at,
  ta.updated_at
FROM public.test_attempts ta
JOIN public.activity_sessions s
  ON s.id = ta.session_id;

CREATE OR REPLACE VIEW public.v_video_entry_metrics AS
SELECT
  ve.id,
  ve.session_id,
  s.user_id,
  s.study_item_id,
  s.session_date,
  ve.watched_videos,
  ve.total_videos_snapshot,
  CASE
    WHEN ve.total_videos_snapshot > 0 THEN ROUND((ve.watched_videos::numeric / ve.total_videos_snapshot::numeric) * 100, 2)
    ELSE NULL
  END AS completion_percent,
  CASE
    WHEN ve.watched_videos = 0 THEN 'not_started'
    WHEN ve.watched_videos >= ve.total_videos_snapshot THEN 'completed'
    ELSE 'partial'
  END AS derived_status,
  ve.time_spent_seconds,
  ve.notes,
  ve.created_at,
  ve.updated_at
FROM public.video_entries ve
JOIN public.activity_sessions s
  ON s.id = ve.session_id;

GRANT SELECT ON public.v_study_item_catalog TO anon, authenticated;
GRANT SELECT ON public.v_revision_entry_metrics TO authenticated;
GRANT SELECT ON public.v_test_attempt_metrics TO authenticated;
GRANT SELECT ON public.v_video_entry_metrics TO authenticated;

COMMIT;

-- -------------------------------------------------------------------
-- POST-INSTALL NOTES
-- -------------------------------------------------------------------
-- 1) This schema stores ONLY missed question rows (wrong/skipped/unseen).
-- 2) Do not insert correct questions into public.missed_questions.
-- 3) Durations should be converted by the app into INTEGER seconds before insert.
-- 4) The UI should use public.study_items.ui_rules_json + public.form_template_fields
--    to decide which raw fields to show for each selected item.
-- 5) Derived values belong in views/reports/frontend, not as repeated columns.

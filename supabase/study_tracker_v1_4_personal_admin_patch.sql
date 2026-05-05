-- Study Pulse Pro v1.4 personal admin patch
-- Use this if you want the default Supabase/RLS-safe setup instead of relying only on the embedded personal admin key.
-- Run in Supabase SQL Editor after study_tracker_install.sql.

-- Allow signed-in app user to read catalog/template data.
DROP POLICY IF EXISTS platforms_authenticated_read ON public.platforms;
CREATE POLICY platforms_authenticated_read ON public.platforms
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS study_items_authenticated_read ON public.study_items;
CREATE POLICY study_items_authenticated_read ON public.study_items
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS form_templates_authenticated_read ON public.form_templates;
CREATE POLICY form_templates_authenticated_read ON public.form_templates
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS form_template_fields_authenticated_read ON public.form_template_fields;
CREATE POLICY form_template_fields_authenticated_read ON public.form_template_fields
FOR SELECT TO authenticated
USING (true);

-- Personal single-user catalog builder writes.
-- These are intentionally broad because this private app is used by one owner.
DROP POLICY IF EXISTS platforms_personal_insert ON public.platforms;
CREATE POLICY platforms_personal_insert ON public.platforms
FOR INSERT TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS platforms_personal_update ON public.platforms;
CREATE POLICY platforms_personal_update ON public.platforms
FOR UPDATE TO authenticated
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS study_items_personal_insert ON public.study_items;
CREATE POLICY study_items_personal_insert ON public.study_items
FOR INSERT TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS study_items_personal_update ON public.study_items;
CREATE POLICY study_items_personal_update ON public.study_items
FOR UPDATE TO authenticated
USING (true)
WITH CHECK (true);

-- Make sure the app roles can use the underlying tables.
GRANT SELECT, INSERT, UPDATE ON public.platforms TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.study_items TO authenticated;
GRANT SELECT ON public.form_templates TO authenticated;
GRANT SELECT ON public.form_template_fields TO authenticated;
GRANT SELECT ON public.v_study_item_catalog TO authenticated;

-- Optional reset helper for your own SQL editor.
-- This deletes saved submitted sessions/results/mistakes for one user but keeps catalog/source rows.
CREATE OR REPLACE FUNCTION public.delete_study_history_for_user(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.activity_sessions WHERE user_id = target_user_id;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.delete_study_history_for_user(UUID)
IS 'Deletes activity_sessions for a user; dependent revision/test/video/reading/missed rows cascade. Keeps catalog/source rows.';

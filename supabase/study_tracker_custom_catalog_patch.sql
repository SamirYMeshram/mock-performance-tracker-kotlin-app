-- Optional patch for the Android app's "Create new catalog item" feature.
-- Run this AFTER study_tracker_install.sql if your project was already installed.
-- This app is intended for a private/single-user study tracker. Because the base
-- schema stores catalog rows globally, these policies allow any authenticated
-- user in this Supabase project to add/update catalog platforms and study items.

BEGIN;

GRANT SELECT, INSERT, UPDATE ON public.platforms TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.study_items TO authenticated;

DROP POLICY IF EXISTS platforms_authenticated_insert ON public.platforms;
CREATE POLICY platforms_authenticated_insert ON public.platforms
FOR INSERT TO authenticated
WITH CHECK (TRUE);

DROP POLICY IF EXISTS platforms_authenticated_update ON public.platforms;
CREATE POLICY platforms_authenticated_update ON public.platforms
FOR UPDATE TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

DROP POLICY IF EXISTS study_items_authenticated_insert ON public.study_items;
CREATE POLICY study_items_authenticated_insert ON public.study_items
FOR INSERT TO authenticated
WITH CHECK (TRUE);

DROP POLICY IF EXISTS study_items_authenticated_update ON public.study_items;
CREATE POLICY study_items_authenticated_update ON public.study_items
FOR UPDATE TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

COMMIT;

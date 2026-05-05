# Supabase SQL order for Study Pulse Pro

Use this when your database is empty or the Android app says a table/view is missing.

1. Run `study_tracker_install.sql` in Supabase SQL Editor.
2. Then run `study_tracker_v1_4_personal_admin_patch.sql`.
3. Sign in from the Android app with your Study Pulse Pro email/password.

For an already-installed database where only Smart Add catalog/source creation fails:

1. Run `study_tracker_v1_4_personal_admin_patch.sql` only.
2. Reopen the app and tap Refresh.

The Android v1.4 private build also includes personal admin REST mode for the Study project. The SQL patch is still kept in this ZIP so you can return to a normal RLS-based setup later if you want.

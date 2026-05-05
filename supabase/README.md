# Supabase SQL files

Run these only in the matching Supabase project.

## Daily Goal Tracker project

Project ID from your website config: `efdgpvqnniijfgtprudw`

Run:

```text
supabase/daily_goal_tracker_schema.sql
```

This creates:

- `tasks`
- `daily_status`
- `activity_log`
- indexes, triggers, constraints, and RLS policies

## Study Pulse Pro project

Project ID from your website config: `bcljjhoazecxiqrllbkx`

For a fresh install, run:

```text
supabase/study_tracker_install.sql
```

This creates the Study Performance schema, catalog tables, views, field templates, RLS policies, install data, and Android catalog-create permissions.

For an already-installed Study project, run only this patch if the Android "Create new catalog item" flow shows an RLS/permission error:

```text
supabase/study_tracker_custom_catalog_patch.sql
```

The patch allows the authenticated app user to add/update reusable rows in `platforms` and `study_items`. It does not create a new database table for every category; categories stay scalable inside the existing catalog model.

## Important

Do not use the `service_role` key, Supabase access tokens, or secret keys inside the Android app. The Android app uses only public anon keys plus the signed-in user's session.

## v1.4 personal admin patch

`study_tracker_v1_4_personal_admin_patch.sql` is included for your Supabase SQL Editor.
It adds authenticated catalog-builder policies for `platforms` and `study_items`, and adds a safe SQL helper for deleting only one user's submitted study history while preserving catalog/source rows.

The Android app v1.4 also supports personal single-user admin REST mode for the Study project so the Smart Add catalog/source creation does not fail when `platforms` or `study_items` RLS is stricter than expected.

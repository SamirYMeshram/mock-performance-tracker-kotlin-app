# Sam's Progress Tracker

# LiquidGlassStudy Updated - Premium Study Companion

Native Kotlin Android app built with Jetpack Compose and Material 3.

This version keeps the existing Supabase integration and improves the app into a premium study companion UI. It includes SQL install/patch files for the Study schema, plus v1.4 private personal-admin REST mode for your single-user project. Companion-only state such as profile settings, favorite study items, sync stamps, and mistake review status is stored locally on the device.



## Version 1.3 smart add update

This ZIP adds the deeper feature requested after v1.2: the + button is now a two-stage smart add system instead of directly opening the first matching form.

- Stage 1: choose the activity type: Mock/Test, Video, Revision, Reading, Mistake Review, or Timer.
- Stage 2: for Mock/Test, Video, Revision, or Reading, choose whether to:
  - log today's progress/result for an existing source/category, or
  - create a new reusable source/category first.
- Existing sources are prioritized by recent use and favorites.
- New source creation now asks better category-specific setup fields:
  - video: platform/class app, course/subject, batch/playlist/chapter, video series/topic, teacher/channel, total videos, videos per day.
  - mock/test: mock platform/source, main test category, section/bundle/topic, test name, source/creator, total questions, mocks per day.
  - revision/reading: source/category/item, target count, daily target, and special rules.
- The new source is saved through the existing professional schema: `platforms`, `study_items`, `form_templates`, and `ui_rules_json`.
- The app does not create random physical SQL tables from the phone. That is intentional: custom categories are represented as catalog rows and rules, while daily submissions still go into the strict entry tables.
- After creating a source, the app immediately opens the correct daily submission form for that source.

## Version 1.2 update in this ZIP

This build focuses on the missing result-visibility and add-flow behavior without changing the existing visual language.

- Recent Activity rows are now tappable and open a full Submitted Detail sheet.
- The Submitted Detail sheet shows the exact saved fields for revision, test, video, and reading entries.
- Test detail now also shows the missed questions linked to that exact submitted test attempt.
- Mistake Book is no longer only a mistake list. It now starts with Submitted Activities, then shows the missed-question review cards.
- The floating + button is now contextual:
  - Today: review mistakes, add study session, add mock/test, timer.
  - Study: add mock/video/revision/reading or create a reusable catalog item.
  - Mistakes: add test with missed questions or start review/timer.
  - Progress: add fresh test data or jump into review.
- New catalog item creation uses the existing database model: `platforms` + `study_items` + existing form templates. It does not create a new database table per category because that would make the app harder to maintain.

### Database note for new catalog items

The base schema originally made `platforms` and `study_items` read-only from the Android app. For the new "Create new catalog item" button, this ZIP includes:

- `supabase/study_tracker_custom_catalog_patch.sql` for already-installed Supabase projects.
- The same catalog-write policies are also included inside `supabase/study_tracker_install.sql` for a fresh install.

Run the patch only if the catalog-create screen fails with a permission/RLS error.

## Main navigation

- Home - study command center with focus score, next best action, quick add, recent result, weak topic, and timeline.
- Today - daily mission screen. Uses Daily Goal Tracker tasks when the Daily project is active; otherwise provides local-only study missions.
- Study - fast activity flow with activity type cards, filters, search, recently used items, favorites, and polished catalog cards.
- Mistakes - premium mistake book powered by existing `missed_questions` rows, with local review states: New, Reviewing, Fixed.
- Progress - visual analytics calculated from existing Supabase raw facts.

## Premium UI and motion upgrades

- Static liquid-glass background with no moving/gif-like animation.
- Floating glass bottom navigation with animated selected state.
- Pressable cards with spring scale feedback.
- Smooth fade and slide transitions between auth/app screens and tabs.
- Glass hero cards and key surfaces, with readable solid-style forms.
- Animated progress rings, progress bars, stats, and insight cards.
- Premium Add Activity bottom sheet and timer mini-player.

## Supabase behavior

The app keeps using the existing two-project setup:

| Module | Supabase project |
|---|---|
| Daily Goal Tracker | `efdgpvqnniijfgtprudw` |
| Study Pulse Pro | `bcljjhoazecxiqrllbkx` |

v1.4 private mode includes the configured Study project personal admin key because this build is intended only for your own device/use. Do not share this APK or source publicly. For public release, remove the admin key and use RLS/Edge Functions instead.

The Study module continues to use the existing schema:

- `platforms`
- `study_items`
- `form_templates`
- `form_template_fields`
- `activity_sessions`
- `revision_entries`
- `test_attempts`
- `missed_questions`
- `video_entries`
- `reading_entries`
- `v_study_item_catalog`

The Daily module continues to use:

- `tasks`
- `daily_status`
- `activity_log`

## Build

Open this folder in Android Studio and let Gradle sync.

Requirements used by the project:

- Android Gradle Plugin 9.0.1
- Gradle wrapper 9.1.0
- Kotlin Compose plugin 2.3.20
- compileSdk 36

If Android Studio asks to install SDK 36 or Build Tools, install them through SDK Manager.

## Important notes

- This project is native Kotlin/Jetpack Compose. It does not use WebView/HTML/CSS/JS for the app UI.
- Local-only features are intentionally local to avoid breaking the website-connected Supabase database.
- The database read/write structure remains compatible with the existing website.

## Version 1.4 strict personal mode update

This ZIP adds the stricter behavior requested after seeing the `/rest/v1/platforms` failure:

- Study REST reads/writes now use the configured personal Study project keys for the private single-user app, so Smart Add catalog creation can write `platforms` and `study_items` even when RLS blocks normal client writes.
- Catalog creation is stricter:
  - platform/source is required,
  - main category/course/subject is required,
  - item name is required,
  - mock/test sources require total questions,
  - video sources require total videos.
- Progress now includes visual analytics:
  - donut/pie-style activity distribution,
  - type picker for All / Mock-Test / Video / Revision / Reading,
  - type-specific bar chart for recent entries,
  - mock-specific mistake/accuracy stats.
- Sync behavior is clearer:
  - automatic Study sync is treated as once-per-day while data is already loaded in memory,
  - the refresh icon performs a manual sync,
  - the top bar shows the last Study sync day,
  - saving a new entry immediately refreshes local app state from Supabase.
- Settings now has a strict danger zone:
  - Study deletion requires typing `DELETE STUDY DATA`,
  - Daily deletion requires typing `CLEAR DAILY HISTORY`,
  - Study deletion removes submitted sessions/results/mistakes but keeps catalog/source rows.
- Added SQL file:
  - `supabase/study_tracker_v1_4_personal_admin_patch.sql`

### Security note for this private build

This v1.4 private build is configured for your personal single-user use as requested. For any app that will be shared publicly, remove the service-role/admin key from the Android project and use Supabase RLS policies or an Edge Function instead.

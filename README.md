<p align="center">
  <img src="app/src/main/res/drawable-nodpi/sam_logo_transparent.png" width="110" alt="Sam's Progress Tracker Logo" />
</p>

<h1 align="center">Sam's Progress Tracker</h1>

<p align="center">
  <b>LiquidGlassStudy — Smart Native Kotlin Study Tracker</b>
</p>

<p align="center">
  A strict, personal, admin-powered study tracking app for mock tests, revision, videos, reading, mistakes, daily tasks, submitted history, and performance analytics.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-Native-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
  <img src="https://img.shields.io/badge/Kotlin-Compose-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white" />
  <img src="https://img.shields.io/badge/Material-3-6750A4?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Supabase-Backend-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Active%20Development-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/UI-Liquid%20Glass-purple?style=flat-square" />
  <img src="https://img.shields.io/badge/Architecture-Repository%20%2B%20ViewModel-orange?style=flat-square" />
  <img src="https://img.shields.io/badge/Database-Strict%20Study%20Schema-green?style=flat-square" />
</p>

---

## Preview

> Add screenshots in the `screenshots/` folder using the exact file names shown below.

<table>
  <tr>
    <td align="center"><b>Home</b></td>
    <td align="center"><b>Today</b></td>
    <td align="center"><b>Study</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/01-home.png" width="260" alt="Home screen" /></td>
    <td><img src="screenshots/02-today.png" width="260" alt="Today screen" /></td>
    <td><img src="screenshots/03-study.png" width="260" alt="Study screen" /></td>
  </tr>
  <tr>
    <td align="center"><b>Mistakes</b></td>
    <td align="center"><b>Progress</b></td>
    <td align="center"><b>How to Submit</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/04-mistakes.png" width="260" alt="Mistakes screen" /></td>
    <td><img src="screenshots/05-progress.png" width="260" alt="Progress screen" /></td>
    <td><img src="screenshots/06-how-to-submit.png" width="260" alt="How to submit screen" /></td>
  </tr>
  <tr>
    <td align="center"><b>What Submitted</b></td>
    <td align="center"><b>User Detail</b></td>
    <td align="center"><b>Checkbox Flow</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/07-what-submitted.png" width="260" alt="Submitted detail screen" /></td>
    <td><img src="screenshots/08-user-detail.png" width="260" alt="User detail screen" /></td>
    <td><img src="screenshots/09-checkbox.png" width="260" alt="Checkbox screen" /></td>
  </tr>
</table>

---

## What This App Does

**Sam's Progress Tracker** is a native Android study companion built for serious personal study tracking.

It is not just a todo app.  
It is designed like a **strict personal study admin system**.

The app helps track:

- mock tests
- practice tests
- video learning
- revision sessions
- reading progress
- missed questions
- wrong/skipped/unseen questions
- mistake review status
- submitted activity history
- daily tasks
- progress charts
- subject-wise weakness
- study consistency

The goal is simple:

> The app should ask only the right questions, store every important field, never ask useless things, and always show what was submitted later.

---

## Core Idea

The app is built around this flow:

```text
User studies
   ↓
User submits exact study data
   ↓
App stores it in strict Supabase tables
   ↓
Recent Activity shows what was submitted
   ↓
Mistake Book shows mistakes with original test context
   ↓
Progress screen turns raw data into charts
```

---

## Main Screens

### Home

The Home screen is the command center.

It shows:

- current focus summary
- quick study actions
- recent submitted activity
- weak area hints
- today status
- progress snapshot

Home is designed for fast daily use.

---

### Today

The Today screen is for daily execution.

It includes:

- daily tasks
- checkbox completion
- submit/update daily progress
- local draft behavior
- daily history support

This screen answers:

> What should I complete today?

---

### Study

The Study screen is the main structured study database.

It supports:

- mock/test tracking
- video tracking
- revision tracking
- reading tracking
- practice/PYQ tracking
- reusable study items
- search and filters
- favorites
- Smart Add flow

This screen answers:

> What study resource or activity do I want to add or update?

---

### Mistakes

The Mistakes screen is not only a wrong-question list.

It is a full mistake review book.

It can show:

- mistake question
- issue type
- user answer
- correct answer
- explanation
- reason of mistake
- subject/topic
- source mock/practice
- original submitted test data
- score/correct/wrong/skipped/unseen
- attempt date
- review status

This screen answers:

> What exactly went wrong, where did it happen, and has it been fixed?

---

### Progress

The Progress screen converts study data into visual analytics.

It can show:

- mock score trend
- accuracy trend
- correct vs wrong vs skipped distribution
- study activity mix
- video progress
- revision completion
- mistake reason breakdown
- subject-wise mistake count

This screen answers:

> Am I improving or repeating the same mistakes?

---

## Smart Add System

The `+` button is context-aware.

It does not behave the same everywhere.

### Home / Today Add

Home and Today are daily-action screens.

The Add button focuses on quick actions:

- Add study session
- Review mistakes
- Add quick revision
- Add mock attempt
- Add video progress
- Add reading progress
- Add quick note
- Start timer

This keeps daily usage fast.

---

### Study Add

Study is the structured database area.

The Add button asks what type of study item or activity should be created.

Supported flows include:

- Mock / Test
- Video Course
- Revision Plan
- Reading / Book
- Practice / PYQ
- Custom category

Each type opens only the fields that matter for that type.

---

## Strict Type-Based Forms

The app is designed so every category asks only useful fields.

### Mock / Test Form

Mock/Test can ask:

- platform/source
- mock/test name
- exam/subject
- topic/chapter
- total questions
- total marks
- duration
- score
- correct
- wrong
- skipped
- unseen
- rank/percentile
- notes
- mistake details

Saved into:

```text
activity_sessions
test_attempts
missed_questions
```

---

### Video Form

Video can ask:

- platform/source
- course/playlist name
- teacher/channel
- subject
- topic
- total videos
- videos watched
- videos per day target
- average minutes per video
- target completion date
- notes

Saved into:

```text
activity_sessions
video_entries
```

---

### Revision Form

Revision can ask:

- subject
- topic
- revision type
- time spent
- confidence before
- confidence after
- next revision date
- notes

Saved into:

```text
activity_sessions
revision_entries
```

---

### Reading Form

Reading can ask:

- book/material name
- subject
- chapter/topic
- pages read
- total pages
- time spent
- notes

Saved into:

```text
activity_sessions
reading_entries
```

---

### Practice / PYQ Form

Practice/PYQ can ask:

- platform/source
- subject
- topic
- total questions
- correct
- wrong
- skipped
- unseen
- difficulty
- time spent
- notes
- mistake details

Saved into:

```text
activity_sessions
test_attempts
missed_questions
```

---

## Submitted Details

Recent Activity is designed to show more than a small title.

When a submitted activity is opened, it should show:

- what was submitted
- when it was submitted
- source/platform
- subject/topic
- full mock/video/revision/reading details
- linked mistakes
- notes
- progress impact

This makes every entry traceable.

---

## Mistake Book With Submitted Context

Mistakes are linked back to the original submission.

Example:

```text
Mistake:
Question 18 wrong

Context:
From Mock Test - Quantitative Aptitude
Score: 42/100
Correct: 31
Wrong: 14
Skipped: 5
Date: 2026-05-05
Reason: Formula confusion
Status: Reviewing
```

This prevents mistakes from becoming disconnected random records.

---

## Architecture

The app follows a simple professional structure:

```text
UI Layer
  Jetpack Compose screens and reusable components

ViewModel Layer
  App state, screen events, validation, loading states

Repository Layer
  Supabase REST calls, insert/update/read logic

Core Layer
  Supabase client, auth, session store, helpers

Local Store
  local preferences, draft state, favorites, review states
```

Data flow:

```text
Compose UI
   ↓
AppViewModel
   ↓
Repository
   ↓
Supabase / Local Store
   ↓
UI state refresh
```

---

## Supabase Architecture

The intended secure architecture is:

```text
Android app
uses anon / publishable key only
        ↓
Supabase Edge Function backend
uses service_role key privately
        ↓
Supabase database
```

The app should feel powerful, but private admin secrets should stay on the backend.

---

## Supabase Tables

The Study module uses tables like:

```text
platforms
study_items
form_templates
form_template_fields
activity_sessions
revision_entries
test_attempts
missed_questions
video_entries
reading_entries
v_study_item_catalog
```

The Daily module uses tables like:

```text
tasks
daily_status
activity_log
```

---

## Edge Function Direction

For strict admin-powered actions, the app can use a Supabase Edge Function such as:

```text
smart-add-admin
```

This backend function can:

- create a platform if missing
- create study item/category
- save setup fields
- save daily submission
- create missed questions
- return created records
- avoid RLS insert failures from the Android client

Recommended backend structure:

```text
supabase/
  functions/
    smart-add-admin/
      index.ts
      deno.json
      .env.example
  migrations/
    study_tracker_feature_update.sql
  README_BACKEND_SETUP.md
```

Example backend secrets:

```env
SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
SUPABASE_SERVICE_ROLE_KEY=PASTE_SERVICE_ROLE_KEY_HERE
ALLOWED_USER_ID=YOUR_USER_ID
ALLOWED_EMAIL=YOUR_EMAIL
```

Private keys should be configured as Supabase secrets, not committed into public source code.

---

## Sync Behavior

The app is designed around controlled sync.

### Auto Sync

Auto sync should happen once per day.

```text
Open app today
   ↓
Auto sync once
   ↓
Use local cache for later opens
```

### Manual Sync

Manual sync happens when the user taps refresh/sync.

```text
Tap Sync
   ↓
Force fetch latest Supabase data
   ↓
Update local cache
   ↓
Refresh UI
```

### New Entry

When the user adds a new entry:

```text
Save locally
   ↓
Send to Supabase/backend
   ↓
Refresh local cache in same format
   ↓
Update Recent Activity, Mistakes, and Progress
```

If network fails:

```text
Save as pending
   ↓
Sync later
```

---

## Local Storage

Local storage is used for companion state and sync support.

It can store:

- favorite study items
- local review status
- user profile settings
- sync stamps
- local drafts
- pending submissions
- cached study data

The goal is to keep the app usable and fast while Supabase remains the source of truth.

---

## Project Structure

```text
.
├── app/
│   └── src/main/
│       ├── java/com/liquidglass/study/
│       │   ├── MainActivity.kt
│       │   ├── core/
│       │   │   ├── Core.kt
│       │   │   └── LocalStore.kt
│       │   ├── data/
│       │   │   ├── Models.kt
│       │   │   └── Repositories.kt
│       │   └── ui/
│       │       ├── AppViewModel.kt
│       │       ├── Components.kt
│       │       ├── Screens.kt
│       │       └── theme/
│       │           └── Theme.kt
│       └── res/
├── gradle/
├── supabase/
│   ├── README.md
│   ├── daily_goal_tracker_schema.sql
│   └── study_tracker_install.sql
├── build.gradle.kts
├── settings.gradle.kts
└── README.md
```

---

## Tech Stack

| Area | Technology |
|---|---|
| App | Native Android |
| Language | Kotlin |
| UI | Jetpack Compose |
| Design | Material 3 |
| State | ViewModel + StateFlow |
| Async | Kotlin Coroutines |
| Backend | Supabase |
| Network | OkHttp |
| Serialization | Kotlinx Serialization |
| Local State | Android local storage/preferences |

---

## Build Requirements

Open the project in Android Studio and let Gradle sync.

Current project setup:

```text
Android Gradle Plugin: 9.0.1
Gradle Wrapper: 9.1.0
Kotlin Compose Plugin: 2.3.20
compileSdk: 36
minSdk: 26
targetSdk: 36
```

If Android Studio asks to install SDK 36 or Build Tools, install them through SDK Manager.

---

## Running the App

Clone the project:

```bash
git clone https://github.com/SamirYMeshram/mock-performance-tracker-kotlin-app.git
```

Open in Android Studio.

Then:

```text
1. Let Gradle sync
2. Configure Supabase values
3. Run SQL setup if needed
4. Deploy Edge Function if using backend admin mode
5. Build and run the Android app
```

---

## Screenshot File Names

Place screenshots here:

```text
screenshots/
```

Use these exact names:

```text
01-home.png
02-today.png
03-study.png
04-mistakes.png
05-progress.png
06-how-to-submit.png
07-what-submitted.png
08-user-detail.png
09-checkbox.png
```

---

## Design Language

The app uses a premium Liquid Glass inspired design.

UI goals:

- clean surfaces
- soft gradients
- glass-like cards
- readable forms
- smooth transitions
- animated selected states
- polished bottom navigation
- clear hierarchy
- strict input structure

The app should look beautiful, but never at the cost of clarity.

---

## Why This Project Exists

Most study apps either track only tasks or only marks.

This app is designed to track the full study loop:

```text
Plan
   ↓
Study
   ↓
Submit result
   ↓
Find mistakes
   ↓
Review mistakes
   ↓
Track progress
   ↓
Improve next attempt
```

That makes it useful for long-term serious preparation.

---

## Roadmap

Planned improvements:

- stronger offline-first sync
- pending upload queue
- richer analytics charts
- full submitted detail pages
- advanced mistake review scheduler
- subject-wise dashboards
- export reports
- custom category templates
- Edge Function powered strict admin operations
- safer reset/delete flows
- improved onboarding

---

## Important Security Note

For public release, never put private Supabase service-role keys or personal access tokens inside the Android app.

Recommended production structure:

```text
Android app = anon/publishable key only
Edge Function = private service_role key
Database = RLS + strict policies
```

---

## Author

**Samir Y Meshram**

GitHub: [@SamirYMeshram](https://github.com/SamirYMeshram)

---

<p align="center">
  <b>Built for strict study tracking, clean submissions, mistake recovery, and long-term progress.</b>
</p>

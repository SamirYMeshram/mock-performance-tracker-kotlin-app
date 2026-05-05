<div align="center">

# Sam's Progress Tracker
### LiquidGlassStudy Updated · Premium Study Companion

A polished **native Kotlin Android app** for tracking study performance, mock tests, revision, video learning, mistakes, submissions, and progress analytics — built with **Jetpack Compose**, **Material 3**, and **Supabase**.

<br/>

![Platform](https://img.shields.io/badge/Platform-Android-green?style=for-the-badge)
![Language](https://img.shields.io/badge/Language-Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)
![UI](https://img.shields.io/badge/UI-Jetpack%20Compose-4285F4?style=for-the-badge&logo=jetpackcompose&logoColor=white)
![Design](https://img.shields.io/badge/Design-Material%203-0F9D58?style=for-the-badge)
![Backend](https://img.shields.io/badge/Backend-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Status](https://img.shields.io/badge/Status-Private%20Single--User-orange?style=for-the-badge)

</div>

---

## Overview

**Sam's Progress Tracker** is a premium **study companion Android app** designed to help you manage and improve your learning workflow.

It supports:

- mock tests and test performance
- revision tracking
- video progress logging
- reading/newspaper logs
- mistake review and correction workflow
- submitted activity history
- progress analytics
- daily study missions
- polished premium UI with liquid-glass styling

This project is built as a **fully native Android app** using **Kotlin + Jetpack Compose**, and it keeps the existing **Supabase integration** for live study data.

---

## Why this app?

This app is made for serious self-study and exam preparation.

It is designed to answer questions like:

- What did I study today?
- Which mock tests did I submit?
- Where am I making mistakes?
- Which weak topics need revision?
- How much progress am I making overall?
- What should I study next?

---

## Key Features

### Study Dashboard
- Focus score
- Next best action
- Recent result card
- Weak topic highlight
- Study timeline
- Quick add actions

### Today Screen
- Daily study mission view
- Goal-based task flow
- Local-only fallback missions
- Better day planning for focused study

### Study Screen
- Add mock/test, revision, reading, or video
- Search and filter study items
- Recently used items
- Favorite items
- Premium reusable catalog cards

### Mistake Book
- Tracks missed questions
- Review states:
  - New
  - Reviewing
  - Fixed
- Submitted activities shown at the top
- Mistake review flow for better correction

### Progress Analytics
- Type-wise visual analytics
- Donut / pie-style activity distribution
- Type filters:
  - All
  - Mock-Test
  - Video
  - Revision
  - Reading
- Type-specific recent bar charts
- Mock accuracy and mistake trends

### Smart Add System
The `+` button is now a **two-stage smart add flow**.

#### Stage 1
Choose activity type:
- Mock/Test
- Video
- Revision
- Reading
- Mistake Review
- Timer

#### Stage 2
For Mock/Test, Video, Revision, or Reading:
- log progress for an **existing source/category**
- or create a **new reusable source/category**

This makes the app faster, more organized, and more scalable.

---

## Screenshots

> Add your screenshots inside a `screenshots/` folder in the root of the repository using the filenames shown below.

### App Preview

<table>
  <tr>
    <td align="center"><b>1. Home</b></td>
    <td align="center"><b>2. Today</b></td>
    <td align="center"><b>3. Study</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/1-home.png" width="220"/></td>
    <td><img src="screenshots/2-today.png" width="220"/></td>
    <td><img src="screenshots/3-study.png" width="220"/></td>
  </tr>

  <tr>
    <td align="center"><b>4. Mistakes</b></td>
    <td align="center"><b>5. Progress</b></td>
    <td align="center"><b>6. How to Submit</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/4-mistakes.png" width="220"/></td>
    <td><img src="screenshots/5-progress.png" width="220"/></td>
    <td><img src="screenshots/6-how-to-submit.png" width="220"/></td>
  </tr>

  <tr>
    <td align="center"><b>7. What Submitted</b></td>
    <td align="center"><b>8. User Detail</b></td>
    <td align="center"><b>9. Checkbox</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/7-what-submitted.png" width="220"/></td>
    <td><img src="screenshots/8-user-detail.png" width="220"/></td>
    <td><img src="screenshots/9-checkbox.png" width="220"/></td>
  </tr>
</table>

---

## Premium UI Highlights

This build improves the visual quality of the app with:

- static liquid-glass inspired background
- glass-like premium cards and surfaces
- floating glass bottom navigation
- animated selected tab states
- smooth fade and slide transitions
- spring press animations
- premium add-activity bottom sheet
- timer mini-player
- animated progress bars and charts
- polished card hierarchy and spacing

---

## Submitted Detail Improvements

This version also improves result visibility:

- Recent Activity items are tappable
- Full Submitted Detail sheet is shown
- Exact saved fields are visible for:
  - revision
  - test
  - video
  - reading
- Test detail also shows the **missed questions** linked to that exact attempt

This makes the submission history much more useful and transparent.

---

## Version Highlights

## v1.4 – Strict Personal Mode
This update adds:

- personal single-user REST mode for the Study project
- better sync clarity
- stricter catalog creation rules
- danger zone delete confirmation
- manual refresh behavior improvements
- study state refresh after save
- extra SQL patch:
  - `supabase/study_tracker_v1_4_personal_admin_patch.sql`

### v1.4 behavior updates
- Study REST reads/writes use your configured personal Study project keys
- Smart Add can create `platforms` and `study_items` even if normal RLS blocks it
- Deletion is safer:
  - Study delete requires typing `DELETE STUDY DATA`
  - Daily delete requires typing `CLEAR DAILY HISTORY`

---

## v1.3 – Smart Add Upgrade
Major Smart Add improvements:

- Two-step add flow
- Existing sources prioritized by favorites and recent usage
- Better category-specific creation fields
- Immediate jump into the correct submission form after source creation

### Category-specific setup examples

#### Video
- platform/class app
- course/subject
- batch/playlist/chapter
- video series/topic
- teacher/channel
- total videos
- videos per day

#### Mock/Test
- platform/source
- main test category
- section/bundle/topic
- test name
- source/creator
- total questions
- mocks per day

#### Revision / Reading
- source/category/item
- target count
- daily target
- custom rules

---

## v1.2 – Result Visibility + Add Flow
This version added:

- Submitted Detail sheet
- More useful Mistake Book structure
- contextual floating action button behavior
- better entry visibility for recent activities
- catalog item creation based on the existing data model

---

## Database / Supabase Model

This app continues using the existing professional schema.

### Study module tables
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

### Daily module tables
- `tasks`
- `daily_status`
- `activity_log`

### Important note
The app **does not create random physical SQL tables from the phone**.

That is intentional.

Custom study categories are represented using:
- catalog rows
- templates
- UI rules

while daily submissions are stored in the proper fixed entry tables.

This keeps the architecture cleaner and more maintainable.

---

## Supabase Projects

| Module | Supabase Project |
|---|---|
| Daily Goal Tracker | `efdgpvqnniijfgtprudw` |
| Study Pulse Pro | `bcljjhoazecxiqrllbkx` |

---

## Included SQL Files

This project includes SQL support files for setup and patching.

### Included files
- `supabase/study_tracker_install.sql`
- `supabase/study_tracker_custom_catalog_patch.sql`
- `supabase/study_tracker_v1_4_personal_admin_patch.sql`

### When to use them
Use the patch files if:

- catalog creation fails
- there is a permission / RLS issue
- new study item creation is blocked

---

## Build Requirements

Open the project in **Android Studio** and let Gradle sync.

### Required versions
- Android Gradle Plugin **9.0.1**
- Gradle Wrapper **9.1.0**
- Kotlin Compose Plugin **2.3.20**
- compileSdk **36**

If Android Studio asks to install SDK 36 or build tools, install them through the **SDK Manager**.

---

## Tech Stack

- **Kotlin**
- **Jetpack Compose**
- **Material 3**
- **Supabase**
- **Coroutines**
- **Navigation**
- **Modern Android Architecture**

---

## Project Structure

```text
app/
gradle/
supabase_reference/
apk file/
build.gradle.kts
settings.gradle.kts
gradle.properties
local.properties.example

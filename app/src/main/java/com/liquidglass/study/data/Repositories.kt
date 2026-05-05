package com.liquidglass.study.data

import com.liquidglass.study.core.AuthUser
import com.liquidglass.study.core.SessionStore
import com.liquidglass.study.core.SupabaseException
import com.liquidglass.study.core.SupabaseRestClient
import com.liquidglass.study.core.durationToText
import com.liquidglass.study.core.doubleOrNullValue
import com.liquidglass.study.core.intOrNullValue
import com.liquidglass.study.core.nowIso
import com.liquidglass.study.core.parseFlexibleDuration
import com.liquidglass.study.core.stringValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

class AuthRepository(
    private val client: SupabaseRestClient,
    private val sessionStore: SessionStore
) {
    suspend fun bootstrap(): AuthUser? {
        if (sessionStore.accessToken.isNullOrBlank()) return null
        return runCatching {
            if (sessionStore.shouldRefresh()) {
                val refresh = sessionStore.refreshToken
                if (!refresh.isNullOrBlank()) sessionStore.saveSession(client.refreshSession(refresh))
            }
            val user = client.getUser()
            sessionStore.saveUser(user)
            user
        }.getOrElse {
            sessionStore.clearSession()
            null
        }
    }

    suspend fun signIn(email: String, password: String): AuthUser {
        val session = client.signInWithPassword(email, password)
        sessionStore.saveSession(session)
        val user = session.user?.toDomain() ?: client.getUser()
        sessionStore.saveUser(user)
        return user
    }

    suspend fun signOut() {
        client.signOut()
        sessionStore.clearSession()
    }
}

class DailyRepository(
    private val client: SupabaseRestClient,
    private val sessionStore: SessionStore
) {
    private fun userId(): String = sessionStore.userId ?: throw SupabaseException("No user id in session. Please sign in again.")

    suspend fun ensureDefaultTasksSeeded() {
        val uid = userId()
        val existing = client.select(
            table = "tasks",
            select = "id",
            filters = listOf("owner_id" to "eq.$uid"),
            limit = 1
        )
        if (existing.isNotEmpty()) return

        val rows = JsonArray(DailyDefaultTasks.map { seed -> seed.toInsertPayload(uid) })
        client.insert("tasks", rows, returning = false)
        logActivity(action = "Seeded Default Tasks", details = "Inserted ${DailyDefaultTasks.size} default tasks")
    }

    suspend fun getTasks(includeInactive: Boolean): List<DailyTask> {
        val uid = userId()
        val filters = mutableListOf("owner_id" to "eq.$uid")
        if (!includeInactive) filters += "active" to "eq.true"
        return client.select(
            table = "tasks",
            filters = filters,
            order = "sort_order.asc,category.asc,title.asc"
        ).map { it.jsonObject.toDailyTask() }
    }

    suspend fun getDailyStatus(day: String): List<DailyStatus> {
        val uid = userId()
        return client.select(
            table = "daily_status",
            filters = listOf("owner_id" to "eq.$uid", "day_date" to "eq.$day"),
            order = "submitted_at.desc"
        ).map { it.jsonObject.toDailyStatus() }
    }

    suspend fun submitDay(day: String, tasks: List<DailyTask>, completedByTaskId: Map<String, Boolean>) {
        val uid = userId()
        val previous = client.select(
            table = "daily_status",
            select = "id",
            filters = listOf("owner_id" to "eq.$uid", "day_date" to "eq.$day"),
            limit = 1
        )
        val submittedAt = nowIso()
        val payload = JsonArray(tasks.map { task ->
            buildJsonObject {
                put("owner_id", uid)
                put("task_id", task.id)
                put("day_date", day)
                put("completed", completedByTaskId[task.id] == true)
                put("submitted_at", submittedAt)
                put("task_title_snapshot", task.title)
                put("category_snapshot", task.category)
                put("platform_snapshot", task.platform)
                if (task.section.isBlank()) put("section_snapshot", JsonNull) else put("section_snapshot", task.section)
                put("target_snapshot", task.target)
                put("priority_snapshot", task.priority)
                if (task.estimatedTime.isBlank()) put("estimated_time_snapshot", JsonNull) else put("estimated_time_snapshot", task.estimatedTime)
            }
        })
        client.upsert("daily_status", payload, onConflict = "owner_id,day_date,task_id")
        logActivity(
            action = if (previous.isEmpty()) "Submitted Day" else "Updated Day",
            dayDate = day,
            details = "Saved ${tasks.size} task statuses"
        )
        sessionStore.clearDailyDraft(day)
    }

    suspend fun saveTask(input: DailyTaskInput): DailyTask {
        validateTask(input)
        val uid = userId()
        val order = input.sortOrder ?: nextSortOrder()
        val payload = input.toTaskPayload(uid, order)
        val saved = if (input.id.isNullOrBlank()) {
            client.insert("tasks", payload).first().jsonObject.toDailyTask().also {
                logActivity("Task Created", taskId = it.id, taskTitle = it.title, category = it.category, platform = it.platform)
            }
        } else {
            client.patch(
                table = "tasks",
                filters = listOf("id" to "eq.${input.id}", "owner_id" to "eq.$uid"),
                payload = payload
            ).first().jsonObject.toDailyTask().also {
                logActivity("Task Updated", taskId = it.id, taskTitle = it.title, category = it.category, platform = it.platform)
            }
        }
        return saved
    }

    suspend fun toggleTaskActive(task: DailyTask) {
        saveTask(task.toInput().copy(active = !task.active))
    }

    suspend fun deleteOrArchiveTask(task: DailyTask) {
        val uid = userId()
        val history = client.select(
            table = "daily_status",
            select = "id",
            filters = listOf("owner_id" to "eq.$uid", "task_id" to "eq.${task.id}"),
            limit = 1
        )
        if (history.isNotEmpty()) {
            client.patch(
                table = "tasks",
                filters = listOf("id" to "eq.${task.id}", "owner_id" to "eq.$uid"),
                payload = buildJsonObject { put("active", false) }
            )
            logActivity("Task Archived", taskId = task.id, taskTitle = task.title, category = task.category, platform = task.platform, details = "History preserved")
        } else {
            client.delete("tasks", listOf("id" to "eq.${task.id}", "owner_id" to "eq.$uid"))
            logActivity("Task Deleted", taskId = task.id, taskTitle = task.title, category = task.category, platform = task.platform)
        }
    }

    suspend fun resetTasksToDefault() {
        val uid = userId()
        val existing = getTasks(includeInactive = true)
        val byKey = existing.associateBy { it.businessKey() }
        val defaultsByKey = DailyDefaultTasks.associateBy { it.businessKey() }

        for (task in existing) {
            val seed = defaultsByKey[task.businessKey()]
            if (seed == null && task.active) {
                client.patch(
                    table = "tasks",
                    filters = listOf("id" to "eq.${task.id}", "owner_id" to "eq.$uid"),
                    payload = buildJsonObject { put("active", false) }
                )
            } else if (seed != null) {
                val input = DailyTaskInput(
                    id = task.id,
                    title = seed.title,
                    category = seed.category,
                    platform = seed.platform,
                    section = seed.section,
                    target = seed.target,
                    estimatedTime = seed.estimatedTime.orEmpty(),
                    priority = seed.priority,
                    active = true,
                    repeatDaily = true,
                    sortOrder = seed.sortOrder,
                    notes = seed.notes.orEmpty()
                )
                client.patch(
                    table = "tasks",
                    filters = listOf("id" to "eq.${task.id}", "owner_id" to "eq.$uid"),
                    payload = input.toTaskPayload(uid, seed.sortOrder)
                )
            }
        }

        val missing = DailyDefaultTasks.filter { byKey[it.businessKey()] == null }
        if (missing.isNotEmpty()) {
            client.insert("tasks", JsonArray(missing.map { it.toInsertPayload(uid) }), returning = false)
        }
        logActivity("Restored Default Tasks", details = "Default list restored; history preserved")
    }

    suspend fun clearHistoryOnly() {
        val uid = userId()
        client.delete("daily_status", listOf("owner_id" to "eq.$uid"))
        client.delete("activity_log", listOf("owner_id" to "eq.$uid"))
    }

    suspend fun getRecentActivity(limit: Int = 30): List<ActivityLogEntry> {
        val uid = userId()
        return client.select(
            table = "activity_log",
            filters = listOf("owner_id" to "eq.$uid"),
            order = "created_at.desc",
            limit = limit
        ).map { it.jsonObject.toActivityLogEntry() }
    }

    suspend fun getReport(startDate: String?, endDate: String?): Pair<List<DailyStatus>, List<ActivityLogEntry>> {
        val uid = userId()
        val statusFilters = mutableListOf("owner_id" to "eq.$uid")
        val logFilters = mutableListOf("owner_id" to "eq.$uid")
        if (!startDate.isNullOrBlank()) {
            statusFilters += "day_date" to "gte.$startDate"
            logFilters += "day_date" to "gte.$startDate"
        }
        if (!endDate.isNullOrBlank()) {
            statusFilters += "day_date" to "lte.$endDate"
            logFilters += "day_date" to "lte.$endDate"
        }
        val statuses = client.select("daily_status", filters = statusFilters, order = "day_date.asc,submitted_at.asc")
            .map { it.jsonObject.toDailyStatus() }
        val logs = client.select("activity_log", filters = logFilters, order = "created_at.desc", limit = 200)
            .map { it.jsonObject.toActivityLogEntry() }
        return statuses to logs
    }

    private suspend fun nextSortOrder(): Int = (getTasks(includeInactive = true).maxOfOrNull { it.sortOrder } ?: 0) + 1

    private fun validateTask(input: DailyTaskInput) {
        val missing = buildList {
            if (input.title.isBlank()) add("title")
            if (input.category.isBlank()) add("category")
            if (input.platform.isBlank()) add("platform")
            if (input.target.isBlank()) add("target")
        }
        if (missing.isNotEmpty()) throw SupabaseException("Missing required task fields: ${missing.joinToString()}")
    }

    private suspend fun logActivity(
        action: String,
        dayDate: String? = null,
        taskId: String? = null,
        taskTitle: String? = null,
        category: String? = null,
        platform: String? = null,
        details: String? = null
    ) {
        val uid = userId()
        runCatching {
            client.insert(
                table = "activity_log",
                payload = buildJsonObject {
                    put("owner_id", uid)
                    if (dayDate == null) put("day_date", JsonNull) else put("day_date", dayDate)
                    put("action", action)
                    if (taskId == null) put("task_id", JsonNull) else put("task_id", taskId)
                    if (taskTitle == null) put("task_title", JsonNull) else put("task_title", taskTitle)
                    if (category == null) put("category", JsonNull) else put("category", category)
                    if (platform == null) put("platform", JsonNull) else put("platform", platform)
                    if (details == null) put("details", JsonNull) else put("details", details)
                },
                returning = false
            )
        }
    }

    private fun DefaultTaskSeed.toInsertPayload(ownerId: String): JsonObject = buildJsonObject {
        put("owner_id", ownerId)
        put("title", title)
        put("category", category)
        put("platform", platform)
        put("section", section)
        put("topic", JsonNull)
        put("target", target)
        if (estimatedTime == null) put("estimated_time", JsonNull) else put("estimated_time", estimatedTime)
        put("priority", priority)
        put("active", true)
        put("repeat_daily", true)
        put("sort_order", sortOrder)
        if (notes == null) put("notes", JsonNull) else put("notes", notes)
    }
}

class StudyRepository(
    private val client: SupabaseRestClient,
    private val sessionStore: SessionStore
) {
    private fun userId(): String = sessionStore.userId ?: throw SupabaseException("No user id in session. Please sign in again.")

    suspend fun loadMetadata(): StudyMetadata {
        val catalog = client.select(
            table = "v_study_item_catalog",
            filters = listOf("is_active" to "eq.true"),
            order = "sort_order.asc"
        ).map { it.jsonObject.toCatalogItem() }

        val templates = client.select(
            table = "form_templates",
            filters = listOf("is_active" to "eq.true"),
            order = "template_key.asc"
        ).map { it.jsonObject.toFormTemplate() }

        val templateById = templates.associateBy { it.id }
        val fields = client.select(
            table = "form_template_fields",
            order = "display_order.asc"
        ).map { it.jsonObject.toFormField() }

        val grouped = fields.groupBy { field -> templateById[field.templateId]?.templateKey.orEmpty() }
            .filterKeys { it.isNotBlank() }
            .mapValues { (_, list) -> list.groupBy { it.fieldScope }.mapValues { group -> group.value.sortedBy { it.displayOrder } } }

        return StudyMetadata(catalog = catalog, templates = templates, fieldsByTemplateKey = grouped)
    }

    suspend fun createCatalogItem(input: NewCatalogItemInput): CatalogItem {
        val activity = input.activityType.trim().lowercase().ifBlank { "test" }
        if (activity !in listOf("revision", "test", "video", "reading")) {
            throw SupabaseException("Activity type must be revision, test, video, or reading.")
        }
        val templateKey = input.templateKey.trim()
        if (templateKey.isBlank()) throw SupabaseException("Choose a form template before creating a catalog item.")
        val platformName = input.platformName.trim()
        val mainCategory = input.mainCategory.trim()
        val itemName = input.itemName.trim().ifBlank { input.displayName.trim() }
        if (platformName.isBlank()) throw SupabaseException("Platform/source is required for ${humanStatus(activity)}.")
        if (mainCategory.isBlank()) throw SupabaseException("Main category/course/subject is required for ${humanStatus(activity)}.")
        if (itemName.isBlank()) throw SupabaseException("Item name is required.")
        val displayName = input.displayName.trim().ifBlank { itemName }
        val platformSlug = slugify(platformName)
        val itemSlugBase = slugify(listOf(platformName, mainCategory, input.subCategory, itemName).filter { it.isNotBlank() }.joinToString("-"))
        val itemSlug = uniqueStudyItemSlug(itemSlugBase)
        val target = input.targetCount.trim().takeIf { it.isNotBlank() }?.toIntOrNull()
        if (input.targetCount.isNotBlank() && (target == null || target <= 0)) throw SupabaseException("Target count must be a positive number or blank.")
        if (activity in listOf("test", "video") && target == null) {
            throw SupabaseException(if (activity == "test") "Total questions is required for a mock/test source." else "Total videos is required for a video source.")
        }
        val dailyTarget = input.dailyTarget.trim().takeIf { it.isNotBlank() }?.toIntOrNull()
        if (input.dailyTarget.isNotBlank() && (dailyTarget == null || dailyTarget <= 0)) throw SupabaseException("Daily target must be a positive number or blank.")

        val platformId = findOrCreatePlatform(platformSlug, platformName, input.platformIcon.ifBlank { iconFor(activity) })
        val fullPath = listOf(platformName, mainCategory, input.subCategory.trim(), itemName).filter { it.isNotBlank() }.joinToString(" / ")
        val sortOrder = nextStudyItemSortOrder()
        client.insert(
            table = "study_items",
            payload = buildJsonObject {
                put("platform_id", platformId)
                put("template_key", templateKey)
                put("slug", itemSlug)
                put("full_path", fullPath)
                put("display_name", displayName)
                val smartDescription = catalogDescription(activity, input, dailyTarget)
                if (smartDescription.isBlank()) put("short_description", JsonNull) else put("short_description", smartDescription)
                put("main_category", mainCategory)
                if (input.subCategory.isBlank()) put("sub_category", JsonNull) else put("sub_category", input.subCategory.trim())
                put("item_name", itemName)
                put("activity_type", activity)
                if (target == null) put("target_count", JsonNull) else put("target_count", target)
                put("ui_rules_json", uiRulesForCatalog(activity, input, dailyTarget))
                put("sort_order", sortOrder)
                put("is_active", true)
            },
            returning = false
        )
        return client.select(
            table = "v_study_item_catalog",
            filters = listOf("slug" to "eq.$itemSlug"),
            limit = 1
        ).firstOrNull()?.jsonObject?.toCatalogItem() ?: throw SupabaseException("Catalog item was created but could not be loaded from v_study_item_catalog.")
    }

    private suspend fun findOrCreatePlatform(slug: String, name: String, icon: String): String {
        val existing = client.select(
            table = "platforms",
            select = "id",
            filters = listOf("slug" to "eq.$slug"),
            limit = 1
        )
        if (existing.isNotEmpty()) return existing.first().jsonObject.stringValue("id")
        return client.insert(
            table = "platforms",
            payload = buildJsonObject {
                put("slug", slug)
                put("platform_name", name)
                put("platform_icon", icon)
                put("sort_order", nextPlatformSortOrder())
                put("is_active", true)
            }
        ).first().jsonObject.stringValue("id")
    }

    private suspend fun uniqueStudyItemSlug(base: String): String {
        val normalized = base.ifBlank { "custom-study-item" }
        val existing = client.select(
            table = "study_items",
            select = "slug",
            filters = listOf("slug" to "eq.$normalized"),
            limit = 1
        )
        return if (existing.isEmpty()) normalized else "$normalized-${System.currentTimeMillis()}"
    }

    private suspend fun nextStudyItemSortOrder(): Int {
        val rows = client.select("study_items", select = "sort_order", order = "sort_order.desc", limit = 1)
        return (rows.firstOrNull()?.jsonObject?.intOrNullValue("sort_order") ?: 0) + 1
    }

    private suspend fun nextPlatformSortOrder(): Int {
        val rows = client.select("platforms", select = "sort_order", order = "sort_order.desc", limit = 1)
        return (rows.firstOrNull()?.jsonObject?.intOrNullValue("sort_order") ?: 0) + 1
    }

    private fun slugify(raw: String): String = raw.trim().lowercase()
        .replace("&", " and ")
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')
        .ifBlank { "custom" }

    private fun iconFor(activity: String): String = when (activity) {
        "revision" -> "📘"
        "test" -> "🧪"
        "video" -> "🎥"
        "reading" -> "📖"
        else -> "✨"
    }

    private fun uiRulesFor(activity: String): JsonObject = when (activity) {
        "test" -> buildJsonObject {
            put("ask_total_questions", true)
            put("ask_max_marks", true)
            put("ask_marks_obtained", true)
            put("ask_total_duration", true)
            put("ask_time_taken", true)
            put("ask_right_count", true)
            put("ask_wrong_count", true)
            put("ask_skipped_count", true)
            put("ask_unseen_count", true)
            put("ask_rank", true)
            put("ask_total_rank", true)
            put("ask_percentile", true)
            put("ask_time_breakdown", true)
            put("ask_range_from", true)
            put("ask_range_to", true)
            put("ask_notes", true)
            put("capture_missed_questions", true)
        }
        "video" -> buildJsonObject {
            put("ask_platform", true)
            put("ask_total_videos", true)
            put("ask_watched_videos", true)
            put("ask_time_spent", true)
            put("ask_notes", true)
        }
        "reading" -> buildJsonObject {
            put("ask_reading_state", true)
            put("ask_time_spent", true)
            put("ask_notes", true)
        }
        "revision" -> buildJsonObject {
            put("capture_mistake_notes", true)
            put("capture_confidence_level", true)
        }
        else -> JsonObject(emptyMap())
    }

    private fun uiRulesForCatalog(activity: String, input: NewCatalogItemInput, dailyTarget: Int?): JsonObject {
        val merged = uiRulesFor(activity).toMutableMap()
        dailyTarget?.let { merged["daily_target"] = JsonPrimitive(it) }
        input.teacherOrSource.trim().takeIf { it.isNotBlank() }?.let { merged["teacher_or_source"] = JsonPrimitive(it) }
        input.requiredFieldsNote.trim().takeIf { it.isNotBlank() }?.let { merged["required_fields_note"] = JsonPrimitive(it) }
        merged["created_from_android_smart_add"] = JsonPrimitive(true)
        merged["catalog_builder_version"] = JsonPrimitive(2)
        return JsonObject(merged)
    }

    private fun catalogDescription(activity: String, input: NewCatalogItemInput, dailyTarget: Int?): String {
        val explicit = input.shortDescription.trim()
        val parts = mutableListOf<String>()
        if (explicit.isNotBlank()) parts += explicit
        input.teacherOrSource.trim().takeIf { it.isNotBlank() }?.let { label ->
            parts += when (activity) {
                "video" -> "Teacher/source: $label"
                "test" -> "Mock source: $label"
                else -> "Source: $label"
            }
        }
        dailyTarget?.let { parts += "Daily target: $it" }
        input.requiredFieldsNote.trim().takeIf { it.isNotBlank() }?.let { parts += "Required fields: $it" }
        return parts.joinToString(" • ")
    }

    suspend fun loadEntries(catalog: List<CatalogItem>): List<StudyEntry> {
        val uid = userId()
        val sessions = client.select(
            table = "activity_sessions",
            filters = listOf("user_id" to "eq.$uid"),
            order = "created_at.desc"
        ).map { it.jsonObject.toActivitySession() }
        if (sessions.isEmpty()) return emptyList()

        val sessionIds = sessions.map { it.id }
        val inSessions = "in.(${sessionIds.joinToString(",")})"
        val revisions = client.select("revision_entries", filters = listOf("session_id" to inSessions)).map { it.jsonObject }
        val tests = client.select("test_attempts", filters = listOf("session_id" to inSessions)).map { it.jsonObject }
        val videos = client.select("video_entries", filters = listOf("session_id" to inSessions)).map { it.jsonObject }
        val readings = client.select("reading_entries", filters = listOf("session_id" to inSessions)).map { it.jsonObject }

        val testIds = tests.mapNotNull { it.stringValue("id").takeIf { id -> id.isNotBlank() } }
        val missed = if (testIds.isEmpty()) emptyList() else client.select(
            table = "missed_questions",
            filters = listOf("test_attempt_id" to "in.(${testIds.joinToString(",")})"),
            order = "created_at.desc"
        ).map { it.jsonObject }

        val itemById = catalog.associateBy { it.id }
        val revisionBySession = revisions.associateBy { it.stringValue("session_id") }
        val testBySession = tests.associateBy { it.stringValue("session_id") }
        val videoBySession = videos.associateBy { it.stringValue("session_id") }
        val readingBySession = readings.associateBy { it.stringValue("session_id") }
        val missedByAttempt = missed.groupBy { it.stringValue("test_attempt_id") }

        return sessions.mapNotNull { session ->
            val item = itemById[session.studyItemId] ?: return@mapNotNull null
            when (item.activityType) {
                "revision" -> revisionBySession[session.id]?.let { buildRevisionEntry(session, item, it) }
                "test" -> testBySession[session.id]?.let { buildTestEntry(session, item, it, missedByAttempt[it.stringValue("id")].orEmpty()) }
                "video" -> videoBySession[session.id]?.let { buildVideoEntry(session, item, it) }
                "reading" -> readingBySession[session.id]?.let { buildReadingEntry(session, item, it) }
                else -> null
            }
        }.sortedByDescending { it.createdAt }
    }


    suspend fun loadMistakes(catalog: List<CatalogItem>): List<MistakeRecord> {
        val uid = userId()
        val sessions = client.select(
            table = "activity_sessions",
            filters = listOf("user_id" to "eq.$uid"),
            order = "created_at.desc"
        ).map { it.jsonObject.toActivitySession() }
        if (sessions.isEmpty()) return emptyList()

        val sessionIds = sessions.map { it.id }
        val tests = client.select(
            table = "test_attempts",
            filters = listOf("session_id" to "in.(${sessionIds.joinToString(",")})")
        ).map { it.jsonObject }
        if (tests.isEmpty()) return emptyList()

        val attemptIds = tests.mapNotNull { it.stringValue("id").takeIf { id -> id.isNotBlank() } }
        if (attemptIds.isEmpty()) return emptyList()

        val missed = client.select(
            table = "missed_questions",
            filters = listOf("test_attempt_id" to "in.(${attemptIds.joinToString(",")})"),
            order = "created_at.desc"
        ).map { it.jsonObject }

        val catalogById = catalog.associateBy { it.id }
        val sessionById = sessions.associateBy { it.id }
        val attemptById = tests.associateBy { it.stringValue("id") }

        return missed.mapNotNull { row ->
            val attemptId = row.stringValue("test_attempt_id")
            val attempt = attemptById[attemptId] ?: return@mapNotNull null
            val session = sessionById[attempt.stringValue("session_id")] ?: return@mapNotNull null
            val item = catalogById[session.studyItemId] ?: return@mapNotNull null
            MistakeRecord(
                id = row.stringValue("id"),
                testAttemptId = attemptId,
                sessionId = session.id,
                sessionDate = session.sessionDate,
                createdAt = row.stringValue("created_at", session.createdAt),
                item = item,
                questionNumber = row.intOrNullValue("question_number") ?: 0,
                issueType = row.stringValue("issue_type", "wrong"),
                questionText = row.stringValue("question_text"),
                optionsText = row["options_json"]?.toString().orEmpty(),
                selectedOptionKey = row.stringValue("selected_option_key"),
                correctOptionKey = row.stringValue("correct_option_key"),
                questionMarks = row.stringValue("question_marks"),
                marksReceived = row.stringValue("marks_received"),
                questionTimeSeconds = row.intOrNullValue("question_time_seconds"),
                questionNote = row.stringValue("question_note")
            )
        }.sortedByDescending { it.createdAt }
    }
    suspend fun clearMyStudyHistory() {
        val uid = userId()
        client.delete("activity_sessions", listOf("user_id" to "eq.$uid"), useServiceRole = true)
    }

    suspend fun saveActivity(item: CatalogItem, values: Map<String, String>, missedQuestions: List<MissedQuestionInput>) {
        val uid = userId()
        var sessionId: String? = null
        try {
            val sessionRow = client.insert(
                table = "activity_sessions",
                payload = buildJsonObject {
                    put("user_id", uid)
                    put("study_item_id", item.id)
                }
            ).first().jsonObject
            sessionId = sessionRow.stringValue("id")
            when (item.activityType) {
                "revision" -> client.insert("revision_entries", buildRevisionPayload(sessionId, item, values))
                "test" -> {
                    val test = client.insert("test_attempts", buildTestPayload(sessionId, values)).first().jsonObject
                    val attemptId = test.stringValue("id")
                    val missedPayload = buildMissedPayload(attemptId, missedQuestions)
                    if (missedPayload.isNotEmpty()) client.insert("missed_questions", JsonArray(missedPayload))
                }
                "video" -> client.insert("video_entries", buildVideoPayload(sessionId, item, values))
                "reading" -> client.insert("reading_entries", buildReadingPayload(sessionId, values))
                else -> throw SupabaseException("Unsupported activity type: ${item.activityType}")
            }
        } catch (e: Throwable) {
            sessionId?.let { runCatching { client.delete("activity_sessions", listOf("id" to "eq.$it", "user_id" to "eq.$uid")) } }
            throw e
        }
    }

    private fun buildRevisionEntry(session: ActivitySession, item: CatalogItem, row: JsonObject): StudyEntry {
        val completed = row.intOrNullValue("completed_count") ?: 0
        val target = row.intOrNullValue("target_count_snapshot") ?: 0
        val pct = if (target > 0) completed.toDouble() / target.toDouble() * 100.0 else null
        return StudyEntry(
            id = session.id,
            sessionDate = session.sessionDate,
            createdAt = session.createdAt,
            item = item,
            activityType = "revision",
            primaryMetric = completionLabel(completed, target),
            secondaryMetric = row.stringValue("mistake_notes").ifBlank { "Revision saved" },
            completionPercent = pct,
            accuracyPercent = null,
            scorePercent = null,
            missedCount = 0,
            details = linkedMapOf(
                "Completed count" to completed.toString(),
                "Total target" to target.toString(),
                "Completion" to completionLabel(completed, target),
                "Confidence" to row.stringValue("confidence_level", "--"),
                "Mistake notes" to row.stringValue("mistake_notes", "--")
            )
        )
    }

    private fun buildTestEntry(session: ActivitySession, item: CatalogItem, row: JsonObject, missed: List<JsonObject>): StudyEntry {
        val right = row.intOrNullValue("right_count") ?: 0
        val wrong = row.intOrNullValue("wrong_count") ?: 0
        val skipped = row.intOrNullValue("skipped_count") ?: 0
        val unseen = row.intOrNullValue("unseen_count") ?: 0
        val accuracyDenominator = right + wrong
        val accuracy = if (accuracyDenominator > 0) right.toDouble() / accuracyDenominator.toDouble() * 100.0 else null
        val maxMarks = row.doubleOrNullValue("max_marks")
        val marks = row.doubleOrNullValue("marks_obtained")
        val score = if (maxMarks != null && maxMarks > 0.0 && marks != null) marks / maxMarks * 100.0 else null
        return StudyEntry(
            id = session.id,
            sessionDate = session.sessionDate,
            createdAt = session.createdAt,
            item = item,
            activityType = "test",
            primaryMetric = accuracy?.let { "Accuracy ${"%.1f".format(it)}%" } ?: "Test saved",
            secondaryMetric = score?.let { "Score ${"%.1f".format(it)}%" } ?: "Missed ${missed.size}",
            completionPercent = null,
            accuracyPercent = accuracy,
            scorePercent = score,
            missedCount = missed.size,
            details = linkedMapOf(
                "Total questions" to row.stringValue("total_questions", "--"),
                "Max marks" to row.stringValue("max_marks", "--"),
                "Marks obtained" to row.stringValue("marks_obtained", "--"),
                "Score" to score?.let { "${"%.1f".format(it)}%" }.orEmpty().ifBlank { "--" },
                "Accuracy" to accuracy?.let { "${"%.1f".format(it)}%" }.orEmpty().ifBlank { "--" },
                "Right answers" to right.toString(),
                "Wrong answers" to wrong.toString(),
                "Skipped answers" to skipped.toString(),
                "Unseen answers" to unseen.toString(),
                "Total duration" to durationToText(row.intOrNullValue("total_duration_seconds")),
                "Time taken" to durationToText(row.intOrNullValue("time_taken_seconds")),
                "Utilized time" to durationToText(row.intOrNullValue("utilized_seconds")),
                "Wasted time" to durationToText(row.intOrNullValue("wasted_seconds")),
                "Correct-answer time" to durationToText(row.intOrNullValue("correct_time_seconds")),
                "Wrong-answer time" to durationToText(row.intOrNullValue("wrong_time_seconds")),
                "Skipped-answer time" to durationToText(row.intOrNullValue("skipped_time_seconds")),
                "Rank" to listOf(row.stringValue("rank"), row.stringValue("total_rank")).filter { it.isNotBlank() }.joinToString("/").ifBlank { "--" },
                "Percentile" to row.stringValue("percentile", "--"),
                "Question range" to listOf(row.stringValue("range_from"), row.stringValue("range_to")).filter { it.isNotBlank() }.joinToString(" to ").ifBlank { "--" },
                "Missed questions" to missed.size.toString(),
                "Attempt notes" to row.stringValue("result_notes", "--")
            )
        )
    }

    private fun buildVideoEntry(session: ActivitySession, item: CatalogItem, row: JsonObject): StudyEntry {
        val watched = row.intOrNullValue("watched_videos") ?: 0
        val total = row.intOrNullValue("total_videos_snapshot") ?: 0
        val pct = if (total > 0) watched.toDouble() / total.toDouble() * 100.0 else null
        return StudyEntry(
            id = session.id,
            sessionDate = session.sessionDate,
            createdAt = session.createdAt,
            item = item,
            activityType = "video",
            primaryMetric = completionLabel(watched, total),
            secondaryMetric = row.stringValue("notes").ifBlank { durationToText(row.intOrNullValue("time_spent_seconds")) },
            completionPercent = pct,
            accuracyPercent = null,
            scorePercent = null,
            missedCount = 0,
            details = linkedMapOf(
                "Watched videos" to watched.toString(),
                "Total videos" to total.toString(),
                "Completion" to completionLabel(watched, total),
                "Time spent" to durationToText(row.intOrNullValue("time_spent_seconds")),
                "Notes" to row.stringValue("notes", "--")
            )
        )
    }

    private fun buildReadingEntry(session: ActivitySession, item: CatalogItem, row: JsonObject): StudyEntry {
        val state = humanStatus(row.stringValue("reading_state", "partial"))
        return StudyEntry(
            id = session.id,
            sessionDate = session.sessionDate,
            createdAt = session.createdAt,
            item = item,
            activityType = "reading",
            primaryMetric = state,
            secondaryMetric = row.stringValue("notes").ifBlank { durationToText(row.intOrNullValue("time_spent_seconds")) },
            completionPercent = when (row.stringValue("reading_state")) {
                "completed" -> 100.0
                "partial" -> 50.0
                "not_read" -> 0.0
                else -> null
            },
            accuracyPercent = null,
            scorePercent = null,
            missedCount = 0,
            details = linkedMapOf(
                "Reading state" to state,
                "Time spent" to durationToText(row.intOrNullValue("time_spent_seconds")),
                "Notes" to row.stringValue("notes", "--")
            )
        )
    }

    private fun buildRevisionPayload(sessionId: String, item: CatalogItem, values: Map<String, String>): JsonObject {
        val completed = requireInt(values, "completed_count")
        val target = requireInt(values, "target_count_snapshot", item.targetCount ?: 0)
        if (completed < 0) throw SupabaseException("Completed count cannot be negative.")
        if (target <= 0) throw SupabaseException("Total target must be greater than zero.")
        if (completed > target) throw SupabaseException("Completed count cannot be greater than total target.")
        val map = linkedMapOf<String, JsonElement>(
            "session_id" to JsonPrimitive(sessionId),
            "completed_count" to JsonPrimitive(completed),
            "target_count_snapshot" to JsonPrimitive(target)
        )
        putOptionalText(map, "mistake_notes", values["mistake_notes"])
        optionalInt(values, "confidence_level")?.let { map["confidence_level"] = JsonPrimitive(it) }
        return JsonObject(map)
    }

    private fun buildTestPayload(sessionId: String, values: Map<String, String>): JsonObject {
        val totalQuestions = requireInt(values, "total_questions")
        if (totalQuestions <= 0) throw SupabaseException("Total questions must be greater than zero.")
        val maxMarks = optionalDouble(values, "max_marks")
        val marks = optionalDouble(values, "marks_obtained")
        if ((maxMarks == null) != (marks == null)) throw SupabaseException("Enter both marks obtained and total exam marks, or leave both blank.")
        val totalDuration = optionalDuration(values, "total_duration_seconds")
        val timeTaken = optionalDuration(values, "time_taken_seconds")
        if (totalDuration != null && timeTaken != null && timeTaken > totalDuration) throw SupabaseException("Time taken cannot exceed total exam duration.")
        val rank = optionalInt(values, "rank")
        val totalRank = optionalInt(values, "total_rank")
        if (rank != null && rank <= 0) throw SupabaseException("Rank must be greater than zero.")
        if (totalRank != null && totalRank <= 0) throw SupabaseException("Total rank must be greater than zero.")
        if (rank != null && totalRank != null && rank > totalRank) throw SupabaseException("Rank cannot be greater than total rank.")
        val rangeFrom = optionalInt(values, "range_from")
        val rangeTo = optionalInt(values, "range_to")
        if (rangeFrom != null && rangeTo != null && rangeFrom > rangeTo) throw SupabaseException("Range from cannot be greater than range to.")
        val right = optionalInt(values, "right_count") ?: 0
        val wrong = optionalInt(values, "wrong_count") ?: 0
        val skipped = optionalInt(values, "skipped_count") ?: 0
        val unseen = optionalInt(values, "unseen_count") ?: 0
        if (listOf(right, wrong, skipped, unseen).any { it < 0 }) throw SupabaseException("Answer counts cannot be negative.")
        if (right + wrong + skipped + unseen > totalQuestions) throw SupabaseException("Right + wrong + skipped + unseen cannot exceed total questions.")

        val map = linkedMapOf<String, JsonElement>(
            "session_id" to JsonPrimitive(sessionId),
            "total_questions" to JsonPrimitive(totalQuestions)
        )
        maxMarks?.let { map["max_marks"] = JsonPrimitive(it) }
        marks?.let { map["marks_obtained"] = JsonPrimitive(it) }
        putOptionalInt(map, "total_duration_seconds", totalDuration)
        putOptionalInt(map, "time_taken_seconds", timeTaken)
        putOptionalInt(map, "right_count", optionalInt(values, "right_count"))
        putOptionalInt(map, "wrong_count", optionalInt(values, "wrong_count"))
        putOptionalInt(map, "skipped_count", optionalInt(values, "skipped_count"))
        putOptionalInt(map, "unseen_count", optionalInt(values, "unseen_count"))
        putOptionalInt(map, "rank", rank)
        putOptionalInt(map, "total_rank", totalRank)
        optionalDouble(values, "percentile")?.let { map["percentile"] = JsonPrimitive(it) }
        putOptionalInt(map, "utilized_seconds", optionalDuration(values, "utilized_seconds"))
        putOptionalInt(map, "wasted_seconds", optionalDuration(values, "wasted_seconds"))
        putOptionalInt(map, "correct_time_seconds", optionalDuration(values, "correct_time_seconds"))
        putOptionalInt(map, "wrong_time_seconds", optionalDuration(values, "wrong_time_seconds"))
        putOptionalInt(map, "skipped_time_seconds", optionalDuration(values, "skipped_time_seconds"))
        putOptionalInt(map, "range_from", rangeFrom)
        putOptionalInt(map, "range_to", rangeTo)
        putOptionalText(map, "result_notes", values["result_notes"])
        return JsonObject(map)
    }

    private fun buildVideoPayload(sessionId: String, item: CatalogItem, values: Map<String, String>): JsonObject {
        val watched = requireInt(values, "watched_videos")
        val total = requireInt(values, "total_videos_snapshot", item.targetCount ?: 0)
        if (watched < 0) throw SupabaseException("Watched videos cannot be negative.")
        if (total <= 0) throw SupabaseException("Total videos must be greater than zero.")
        if (watched > total) throw SupabaseException("Watched videos cannot be greater than total videos.")
        val map = linkedMapOf<String, JsonElement>(
            "session_id" to JsonPrimitive(sessionId),
            "watched_videos" to JsonPrimitive(watched),
            "total_videos_snapshot" to JsonPrimitive(total)
        )
        putOptionalInt(map, "time_spent_seconds", optionalDuration(values, "time_spent_seconds"))
        putOptionalText(map, "notes", values["notes"])
        return JsonObject(map)
    }

    private fun buildReadingPayload(sessionId: String, values: Map<String, String>): JsonObject {
        val state = values["reading_state"]?.trim().orEmpty().ifBlank { "partial" }
        if (state !in listOf("completed", "partial", "not_read")) throw SupabaseException("Reading state must be completed, partial, or not_read.")
        val map = linkedMapOf<String, JsonElement>(
            "session_id" to JsonPrimitive(sessionId),
            "reading_state" to JsonPrimitive(state)
        )
        putOptionalInt(map, "time_spent_seconds", optionalDuration(values, "time_spent_seconds"))
        putOptionalText(map, "notes", values["notes"])
        return JsonObject(map)
    }

    private fun buildMissedPayload(attemptId: String, questions: List<MissedQuestionInput>): List<JsonObject> {
        val seenNumbers = mutableSetOf<Int>()
        return questions.filter { it.questionNumber.isNotBlank() || it.questionText.isNotBlank() }.map { q ->
            val number = q.questionNumber.trim().toIntOrNull() ?: throw SupabaseException("Every missed question needs a valid question number.")
            if (number <= 0) throw SupabaseException("Question number must be greater than zero.")
            if (!seenNumbers.add(number)) throw SupabaseException("Duplicate missed question number: $number")
            val issue = q.issueType.ifBlank { "wrong" }
            if (issue !in listOf("wrong", "skipped", "unseen")) throw SupabaseException("Missed question result type must be wrong, skipped, or unseen.")
            if (q.questionText.isBlank()) throw SupabaseException("Question text is required for missed question $number.")
            val map = linkedMapOf<String, JsonElement>(
                "test_attempt_id" to JsonPrimitive(attemptId),
                "question_number" to JsonPrimitive(number),
                "issue_type" to JsonPrimitive(issue),
                "question_text" to JsonPrimitive(q.questionText.trim()),
                "options_json" to parseOptions(q.optionsJson)
            )
            putOptionalText(map, "selected_option_key", q.selectedOptionKey)
            putOptionalText(map, "correct_option_key", q.correctOptionKey)
            q.questionMarks.trim().toDoubleOrNull()?.let { map["question_marks"] = JsonPrimitive(it) }
            q.marksReceived.trim().toDoubleOrNull()?.let { map["marks_received"] = JsonPrimitive(it) }
            putOptionalInt(map, "question_time_seconds", parseFlexibleDuration(q.questionTime))
            putOptionalText(map, "question_note", q.questionNote)
            JsonObject(map)
        }
    }

    private fun parseOptions(raw: String): JsonElement {
        val text = raw.trim()
        if (text.isBlank()) return JsonObject(emptyMap())
        return runCatching { client.json.parseToJsonElement(text) }
            .getOrElse { JsonObject(mapOf("raw" to JsonPrimitive(text))) }
    }

    private fun requireInt(values: Map<String, String>, key: String, default: Int? = null): Int {
        val raw = values[key]?.trim().orEmpty()
        if (raw.isBlank() && default != null && default > 0) return default
        return raw.toIntOrNull() ?: throw SupabaseException("${key.replace('_', ' ')} is required and must be a number.")
    }

    private fun optionalInt(values: Map<String, String>, key: String): Int? = values[key]?.trim()?.takeIf { it.isNotBlank() }?.toIntOrNull()
    private fun optionalDouble(values: Map<String, String>, key: String): Double? = values[key]?.trim()?.takeIf { it.isNotBlank() }?.toDoubleOrNull()
    private fun optionalDuration(values: Map<String, String>, key: String): Int? = parseFlexibleDuration(values[key])
    private fun putOptionalInt(map: MutableMap<String, JsonElement>, key: String, value: Int?) { if (value != null) map[key] = JsonPrimitive(value) }
    private fun putOptionalText(map: MutableMap<String, JsonElement>, key: String, value: String?) { if (!value.isNullOrBlank()) map[key] = JsonPrimitive(value.trim()) }
}

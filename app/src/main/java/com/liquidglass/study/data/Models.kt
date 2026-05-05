package com.liquidglass.study.data

import com.liquidglass.study.core.booleanValue
import com.liquidglass.study.core.doubleOrNullValue
import com.liquidglass.study.core.durationToText
import com.liquidglass.study.core.intOrNullValue
import com.liquidglass.study.core.objectValue
import com.liquidglass.study.core.stringOrNull
import com.liquidglass.study.core.stringValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

// ----------------------------- Daily Goal Tracker -----------------------------

data class DailyTask(
    val id: String,
    val ownerId: String,
    val title: String,
    val category: String,
    val platform: String,
    val section: String,
    val topic: String,
    val target: String,
    val estimatedTime: String,
    val priority: String,
    val active: Boolean,
    val repeatDaily: Boolean,
    val sortOrder: Int,
    val notes: String,
    val createdAt: String,
    val updatedAt: String
) {
    fun businessKey(): String = listOf(title, category, platform, section, target)
        .joinToString("|") { it.trim().lowercase() }

    fun toInput(): DailyTaskInput = DailyTaskInput(
        id = id,
        title = title,
        category = category,
        platform = platform,
        section = section,
        topic = topic,
        target = target,
        estimatedTime = estimatedTime,
        priority = priority,
        active = active,
        repeatDaily = repeatDaily,
        sortOrder = sortOrder,
        notes = notes
    )
}

data class DailyTaskInput(
    val id: String? = null,
    val title: String = "",
    val category: String = "",
    val platform: String = "",
    val section: String = "",
    val topic: String = "",
    val target: String = "",
    val estimatedTime: String = "",
    val priority: String = "Medium",
    val active: Boolean = true,
    val repeatDaily: Boolean = true,
    val sortOrder: Int? = null,
    val notes: String = ""
)

data class DailyStatus(
    val id: String,
    val ownerId: String,
    val taskId: String,
    val dayDate: String,
    val completed: Boolean,
    val submittedAt: String,
    val taskTitleSnapshot: String,
    val categorySnapshot: String,
    val platformSnapshot: String,
    val sectionSnapshot: String,
    val targetSnapshot: String,
    val prioritySnapshot: String,
    val estimatedTimeSnapshot: String
)

data class ActivityLogEntry(
    val id: String,
    val ownerId: String,
    val dayDate: String,
    val action: String,
    val taskId: String,
    val taskTitle: String,
    val category: String,
    val platform: String,
    val details: String,
    val createdAt: String
)

data class DailyReportDay(
    val dayDate: String,
    val totalTasks: Int,
    val completedCount: Int,
    val pendingCount: Int,
    val completionRate: Int,
    val latestSubmittedAt: String,
    val categoryBreakdown: Map<String, Pair<Int, Int>>,
    val platformBreakdown: Map<String, Pair<Int, Int>>
)

data class DefaultTaskSeed(
    val sortOrder: Int,
    val title: String,
    val category: String,
    val platform: String,
    val section: String,
    val target: String,
    val estimatedTime: String?,
    val priority: String,
    val notes: String?
) {
    fun businessKey(): String = listOf(title, category, platform, section, target)
        .joinToString("|") { it.trim().lowercase() }
}

fun JsonObject.toDailyTask(): DailyTask = DailyTask(
    id = stringValue("id"),
    ownerId = stringValue("owner_id"),
    title = stringValue("title"),
    category = stringValue("category"),
    platform = stringValue("platform"),
    section = stringValue("section"),
    topic = stringValue("topic"),
    target = stringValue("target"),
    estimatedTime = stringValue("estimated_time"),
    priority = stringValue("priority", "Medium"),
    active = booleanValue("active", true),
    repeatDaily = booleanValue("repeat_daily", true),
    sortOrder = intOrNullValue("sort_order") ?: 0,
    notes = stringValue("notes"),
    createdAt = stringValue("created_at"),
    updatedAt = stringValue("updated_at")
)

fun JsonObject.toDailyStatus(): DailyStatus = DailyStatus(
    id = stringValue("id"),
    ownerId = stringValue("owner_id"),
    taskId = stringValue("task_id"),
    dayDate = stringValue("day_date"),
    completed = booleanValue("completed"),
    submittedAt = stringValue("submitted_at"),
    taskTitleSnapshot = stringValue("task_title_snapshot"),
    categorySnapshot = stringValue("category_snapshot"),
    platformSnapshot = stringValue("platform_snapshot"),
    sectionSnapshot = stringValue("section_snapshot"),
    targetSnapshot = stringValue("target_snapshot"),
    prioritySnapshot = stringValue("priority_snapshot"),
    estimatedTimeSnapshot = stringValue("estimated_time_snapshot")
)

fun JsonObject.toActivityLogEntry(): ActivityLogEntry = ActivityLogEntry(
    id = stringValue("id"),
    ownerId = stringValue("owner_id"),
    dayDate = stringValue("day_date"),
    action = stringValue("action"),
    taskId = stringValue("task_id"),
    taskTitle = stringValue("task_title"),
    category = stringValue("category"),
    platform = stringValue("platform"),
    details = stringValue("details"),
    createdAt = stringValue("created_at")
)

fun DailyTaskInput.toTaskPayload(ownerId: String, resolvedSortOrder: Int): JsonObject = buildJsonObject {
    put("owner_id", ownerId)
    put("title", title.trim())
    put("category", category.trim())
    put("platform", platform.trim())
    if (section.trim().isBlank()) put("section", JsonNull) else put("section", section.trim())
    if (topic.trim().isBlank()) put("topic", JsonNull) else put("topic", topic.trim())
    put("target", target.trim())
    if (estimatedTime.trim().isBlank()) put("estimated_time", JsonNull) else put("estimated_time", estimatedTime.trim())
    put("priority", priority.ifBlank { "Medium" })
    put("active", active)
    put("repeat_daily", repeatDaily)
    put("sort_order", resolvedSortOrder)
    if (notes.trim().isBlank()) put("notes", JsonNull) else put("notes", notes.trim())
}

val DailyDefaultTasks: List<DefaultTaskSeed> = listOf(
    DefaultTaskSeed(1, "Tables", "Basics & Speed Math", "Self Study", "Revision", "1 to 20", null, "High", "Daily basics"),
    DefaultTaskSeed(2, "Squares", "Basics & Speed Math", "Self Study", "Revision", "1 to 20", null, "High", "Daily basics"),
    DefaultTaskSeed(3, "Cubes", "Basics & Speed Math", "Self Study", "Revision", "1 to 10", null, "High", "Daily basics"),
    DefaultTaskSeed(4, "Fractions", "Basics & Speed Math", "Self Study", "Revision", "1 to 10", null, "High", "Daily basics"),
    DefaultTaskSeed(5, "Prime Numbers", "Basics & Speed Math", "Self Study", "Revision", "1 to 30", null, "High", "Daily basics"),
    DefaultTaskSeed(6, "Percentage", "Quantitative Aptitude", "Guidely", "Special Beginners Bundle", "1 mock", null, "Medium", null),
    DefaultTaskSeed(7, "Number System", "Quantitative Aptitude", "Guidely", "Special Beginners Bundle", "1 mock", null, "Medium", null),
    DefaultTaskSeed(8, "Simplification", "Quantitative Aptitude", "Guidely", "Special Beginners Bundle", "1 mock", null, "Medium", null),
    DefaultTaskSeed(9, "Approximation", "Quantitative Aptitude", "Guidely", "Special Beginners Bundle", "1 mock", null, "Medium", null),
    DefaultTaskSeed(10, "Approximation", "Quantitative Aptitude", "Guidely", "Topic-wise", "1 mock", null, "Medium", null),
    DefaultTaskSeed(11, "Percentage", "Quantitative Aptitude", "Guidely", "Topic-wise", "1 mock", null, "Medium", null),
    DefaultTaskSeed(12, "Simplification", "Quantitative Aptitude", "Guidely", "Topic-wise", "1 mock", null, "Medium", null),
    DefaultTaskSeed(13, "Number System", "Quantitative Aptitude", "Guidely", "Topic-wise", "1 mock", null, "Medium", null),
    DefaultTaskSeed(14, "Arithmetic Master", "Quantitative Aptitude", "Guidely", "Each topic", "1 mock", null, "Medium", "Each topic"),
    DefaultTaskSeed(15, "Yes Magazine", "Mock Tests & Practice", "Yes Officer", "Magazine", "2 mocks", null, "Medium", null),
    DefaultTaskSeed(16, "Prelims Exclusive", "Mock Tests & Practice", "Yes Officer", "Prelims Exclusive", "2 mocks", null, "Medium", null),
    DefaultTaskSeed(17, "Special PDF (Free)", "Mock Tests & Practice", "Yes Officer", "Special PDF (Free)", "2 mocks", null, "Medium", null),
    DefaultTaskSeed(18, "Simplification", "Quantitative Aptitude", "Adda247", "Topic Practice", "2 questions + 2 mocks", null, "Medium", null),
    DefaultTaskSeed(19, "Approximation", "Quantitative Aptitude", "Adda247", "Topic Practice", "2 questions + 2 mocks", null, "Medium", null),
    DefaultTaskSeed(20, "Percentage", "Quantitative Aptitude", "Adda247", "Topic Practice", "2 questions + 2 mocks", null, "Medium", null),
    DefaultTaskSeed(21, "Number System", "Quantitative Aptitude", "Adda247", "Topic Practice", "2 questions + 2 mocks", null, "Medium", null),
    DefaultTaskSeed(22, "Table Quiz", "Coding / Technical", "Coding C++", "Quiz", "1 to 30", null, "Low", null),
    DefaultTaskSeed(23, "Fraction Quiz", "Coding / Technical", "Coding C++", "Quiz", "1 to 30", null, "Low", null),
    DefaultTaskSeed(24, "Current Affairs Quiz", "Reasoning & General Awareness", "Oliveboard", "Free Zone", "1 mock", null, "Medium", null),
    DefaultTaskSeed(25, "Free eBook Test", "Mock Tests & Practice", "Free eBook", "Test", "1 mock", null, "Low", null),
    DefaultTaskSeed(26, "Banking Topic Test", "Mock Tests & Practice", "Practice Mock", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(27, "Test", "Mock Tests & Practice", "PW", "Test", "2 mocks", null, "Medium", null),
    DefaultTaskSeed(28, "DPP", "Mock Tests & Practice", "PW", "DPP", "2", null, "Medium", null),
    DefaultTaskSeed(29, "Math Booster", "Quantitative Aptitude", "Selection Way", "Booster", "1 mock", null, "Medium", null),
    DefaultTaskSeed(30, "Calculation Booster", "Quantitative Aptitude", "Selection Way", "Booster", "1 mock", null, "Medium", null),
    DefaultTaskSeed(31, "Reasoning Booster", "Reasoning & General Awareness", "Selection Way", "Booster", "1 mock", null, "Medium", null),
    DefaultTaskSeed(32, "Railway Booster (Math, Science, GA)", "Reasoning & General Awareness", "Selection Way", "Booster", "1 mock", null, "Medium", null),
    DefaultTaskSeed(33, "Reasoning (Free Test Pack)", "Reasoning & General Awareness", "Selection Way", "Free Test Pack", "1 mock", null, "Medium", null),
    DefaultTaskSeed(34, "Daily Quiz", "Mock Tests & Practice", "Test Ranking", "Quiz", "2 mocks", null, "Medium", null),
    DefaultTaskSeed(35, "Speed Math", "Basics & Speed Math", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(36, "Simplification", "Quantitative Aptitude", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(37, "Approximation", "Quantitative Aptitude", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(38, "Number Series", "Quantitative Aptitude", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(39, "Percentage", "Quantitative Aptitude", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(40, "Ratio & Proportion", "Quantitative Aptitude", "Smartkeeda", "Speed Drill (Solo)", "40 questions", null, "Medium", null),
    DefaultTaskSeed(41, "Simplification", "Quantitative Aptitude", "Smartkeeda", "Marathon Drill", "1 drill", "25 min", "Medium", "Combined 25 minutes"),
    DefaultTaskSeed(42, "Approximation", "Quantitative Aptitude", "Smartkeeda", "Marathon Drill", "1 drill", "25 min", "Medium", "Combined 25 minutes"),
    DefaultTaskSeed(43, "Percentage", "Quantitative Aptitude", "Smartkeeda", "Marathon Drill", "1 drill", "25 min", "Medium", "Combined 25 minutes"),
    DefaultTaskSeed(44, "Ratio & Proportion", "Quantitative Aptitude", "Smartkeeda", "Marathon Drill", "1 drill", "25 min", "Medium", "Combined 25 minutes"),
    DefaultTaskSeed(45, "Speed Math", "Basics & Speed Math", "Smartkeeda", "Marathon Drill", "1 drill", "25 min", "Medium", "Combined 25 minutes"),
    DefaultTaskSeed(46, "Simplification", "Quantitative Aptitude", "Smartkeeda", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(47, "Approximation", "Quantitative Aptitude", "Smartkeeda", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(48, "Number Series", "Quantitative Aptitude", "Smartkeeda", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(49, "Percentage", "Quantitative Aptitude", "Smartkeeda", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(50, "Free PDF", "Mock Tests & Practice", "Smartkeeda", "Free PDF", "1 mock", null, "Low", null),
    DefaultTaskSeed(51, "Simplification", "Quantitative Aptitude", "Smartkeeda", "Free Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(52, "Approximation", "Quantitative Aptitude", "Smartkeeda", "Free Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(53, "Squares (1-999)", "Basics & Speed Math", "Speed Math", "Practice", "30 questions", null, "High", null),
    DefaultTaskSeed(54, "1-100", "Basics & Speed Math", "Speed Math", "Practice", "30 questions", null, "High", null),
    DefaultTaskSeed(55, "Cubes (1-30)", "Basics & Speed Math", "Speed Math", "Practice", "30 questions", null, "High", null),
    DefaultTaskSeed(56, "Cubes (1-100)", "Basics & Speed Math", "Speed Math", "Practice", "30 questions", null, "High", null),
    DefaultTaskSeed(57, "Square Root (1-30)", "Basics & Speed Math", "Speed Math", "Practice", "30 questions", null, "High", null),
    DefaultTaskSeed(58, "2-Digit Addition", "Basics & Speed Math", "Speed Math", "Practice", "60 questions", null, "High", null),
    DefaultTaskSeed(59, "Addition", "Basics & Speed Math", "Speed Math", "Practice", "80 questions", null, "High", null),
    DefaultTaskSeed(60, "Subtraction", "Basics & Speed Math", "Speed Math", "Practice", "80 questions", null, "High", null),
    DefaultTaskSeed(61, "Multiplication", "Basics & Speed Math", "Speed Math", "Practice", "80 questions", null, "High", null),
    DefaultTaskSeed(62, "Division", "Basics & Speed Math", "Speed Math", "Practice", "80 questions", null, "High", null),
    DefaultTaskSeed(63, "Percentage", "Basics & Speed Math", "Speed Math", "Practice", "80 questions", null, "High", null),
    DefaultTaskSeed(64, "Simplification", "Quantitative Aptitude", "Testbook", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(65, "Approximation", "Quantitative Aptitude", "Testbook", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(66, "Percentage", "Quantitative Aptitude", "Testbook", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(67, "Ratio & Proportion", "Quantitative Aptitude", "Testbook", "Topic Test", "1 mock", null, "Medium", null),
    DefaultTaskSeed(68, "Free Quiz", "Mock Tests & Practice", "Yes Mock", "Free Quiz", "3 mocks", null, "Low", "Different topics"),
    DefaultTaskSeed(69, "Daily Free Quiz", "Reasoning & General Awareness", "Quick Trick by Sahil Sir", "Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(70, "Math", "Quantitative Aptitude", "Quick Trick by Sahil Sir", "Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(71, "Reasoning", "Reasoning & General Awareness", "Quick Trick by Sahil Sir", "Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(72, "GK / GS", "Reasoning & General Awareness", "Quick Trick by Sahil Sir", "Quiz", "1 mock", null, "Low", null),
    DefaultTaskSeed(73, "Other Paid Test", "Mock Tests & Practice", "Quick Trick by Sahil Sir", "Paid Test", "As given", null, "Low", null),
    DefaultTaskSeed(74, "Read today's The Hindu newspaper", "English & Reading", "Self Study", "The Hindu", "Daily reading", null, "High", null),
    DefaultTaskSeed(75, "Career Definer", "Video Classes / Educators", "Kaushik Mohanty", "Career Definer", "2 videos", null, "Medium", null),
    DefaultTaskSeed(76, "YouTube", "Video Classes / Educators", "Kaushik Mohanty", "YouTube", "1 video", null, "Medium", null),
    DefaultTaskSeed(77, "Batch", "Video Classes / Educators", "Saurabh Sir", "Batch", "2 videos", null, "Medium", null),
    DefaultTaskSeed(78, "YouTube", "Video Classes / Educators", "Saurabh Sir", "YouTube", "1 video", null, "Medium", null),
    DefaultTaskSeed(79, "Batch", "Video Classes / Educators", "Kush Pandey", "Batch", "1 video", null, "Medium", null),
    DefaultTaskSeed(80, "YouTube", "Video Classes / Educators", "Kush Pandey", "YouTube", "1 video", null, "Medium", null),
    DefaultTaskSeed(81, "Batch", "English & Reading", "Nimisha Bansal", "Batch", "2 videos", null, "Medium", null),
    DefaultTaskSeed(82, "Editorial", "English & Reading", "Nimisha Bansal", "Editorial", "1 video", null, "Medium", null),
    DefaultTaskSeed(83, "YouTube", "English & Reading", "Nimisha Bansal", "YouTube", "1 video", null, "Medium", null),
    DefaultTaskSeed(84, "Batch", "Reasoning & General Awareness", "Ankush Lamba", "Batch", "1 video", null, "Medium", null),
    DefaultTaskSeed(85, "YouTube", "Reasoning & General Awareness", "Ankush Lamba", "YouTube", "1 video", null, "Medium", null),
    DefaultTaskSeed(86, "Batch", "Video Classes / Educators", "ATM", "Batch", "2 videos", null, "Medium", null),
    DefaultTaskSeed(87, "Batch", "Video Classes / Educators", "TMM", "Batch", "1 video", null, "Medium", null),
    DefaultTaskSeed(88, "Batch", "Video Classes / Educators", "RMB", "Batch", "5 videos", null, "Medium", null)
)

// -------------------------- Study Performance Tracker -------------------------

data class CatalogItem(
    val id: String,
    val platformName: String,
    val platformIcon: String,
    val displayName: String,
    val mainCategory: String,
    val subCategory: String,
    val activityType: String,
    val templateKey: String,
    val formTitle: String,
    val formDescription: String,
    val shortDescription: String,
    val targetCount: Int?,
    val uiRules: JsonObject,
    val sortOrder: Int,
    val isActive: Boolean,
    val fullPath: String
)

data class FormTemplate(
    val id: String,
    val templateKey: String,
    val activityType: String,
    val formTitle: String,
    val formDescription: String,
    val isActive: Boolean
)

data class FormField(
    val id: String,
    val templateId: String,
    val fieldKey: String,
    val showLabel: String,
    val helperText: String,
    val inputType: String,
    val fieldScope: String,
    val required: Boolean,
    val hidden: Boolean,
    val auto: Boolean,
    val uiConfig: JsonObject,
    val displayOrder: Int
) {
    fun options(): List<String> {
        val raw = uiConfig["options"] ?: return fallbackOptionsFor(fieldKey)
        return runCatching {
            raw.jsonArray.mapNotNull { item ->
                when (item) {
                    is JsonPrimitive -> item.contentOrNull
                    is JsonObject -> item.stringOrNull("value") ?: item.stringOrNull("label")
                    else -> null
                }
            }
        }.getOrElse { fallbackOptionsFor(fieldKey) }
    }
}

data class ActivitySession(
    val id: String,
    val userId: String,
    val studyItemId: String,
    val sessionDate: String,
    val createdAt: String
)

data class MissedQuestionInput(
    val questionNumber: String = "",
    val issueType: String = "wrong",
    val questionText: String = "",
    val optionsJson: String = "",
    val selectedOptionKey: String = "",
    val correctOptionKey: String = "",
    val questionMarks: String = "",
    val marksReceived: String = "",
    val questionTime: String = "",
    val questionNote: String = ""
)

data class StudyEntry(
    val id: String,
    val sessionDate: String,
    val createdAt: String,
    val item: CatalogItem,
    val activityType: String,
    val primaryMetric: String,
    val secondaryMetric: String,
    val completionPercent: Double?,
    val accuracyPercent: Double?,
    val scorePercent: Double?,
    val missedCount: Int,
    val details: Map<String, String>
)

data class MistakeRecord(
    val id: String,
    val testAttemptId: String,
    val sessionId: String,
    val sessionDate: String,
    val createdAt: String,
    val item: CatalogItem,
    val questionNumber: Int,
    val issueType: String,
    val questionText: String,
    val optionsText: String,
    val selectedOptionKey: String,
    val correctOptionKey: String,
    val questionMarks: String,
    val marksReceived: String,
    val questionTimeSeconds: Int?,
    val questionNote: String,
    val reviewStatus: String = "New"
)

data class StudyMetadata(
    val catalog: List<CatalogItem>,
    val templates: List<FormTemplate>,
    val fieldsByTemplateKey: Map<String, Map<String, List<FormField>>>
)


data class NewCatalogItemInput(
    val activityType: String = "test",
    val templateKey: String = "",
    val platformName: String = "",
    val platformIcon: String = "",
    val displayName: String = "",
    val mainCategory: String = "",
    val subCategory: String = "",
    val itemName: String = "",
    val targetCount: String = "",
    val dailyTarget: String = "",
    val teacherOrSource: String = "",
    val requiredFieldsNote: String = "",
    val shortDescription: String = ""
)

fun JsonObject.toCatalogItem(): CatalogItem = CatalogItem(
    id = stringValue("id"),
    platformName = stringValue("platform_name"),
    platformIcon = stringValue("platform_icon"),
    displayName = stringValue("display_name"),
    mainCategory = stringValue("main_category"),
    subCategory = stringValue("sub_category"),
    activityType = stringValue("activity_type"),
    templateKey = stringValue("template_key"),
    formTitle = stringValue("form_title"),
    formDescription = stringValue("form_description"),
    shortDescription = stringValue("short_description"),
    targetCount = intOrNullValue("target_count"),
    uiRules = objectValue("ui_rules_json"),
    sortOrder = intOrNullValue("sort_order") ?: 0,
    isActive = booleanValue("is_active", true),
    fullPath = stringValue("full_path")
)

fun JsonObject.toFormTemplate(): FormTemplate = FormTemplate(
    id = stringValue("id"),
    templateKey = stringValue("template_key"),
    activityType = stringValue("activity_type"),
    formTitle = stringOrNull("form_title") ?: stringValue("template_name"),
    formDescription = stringValue("form_description"),
    isActive = booleanValue("is_active", true)
)

fun JsonObject.toFormField(): FormField = FormField(
    id = stringValue("id"),
    templateId = stringValue("template_id"),
    fieldKey = stringValue("field_key"),
    showLabel = stringValue("show_label"),
    helperText = stringValue("helper_text"),
    inputType = stringValue("input_type", "text"),
    fieldScope = stringValue("field_scope", "session"),
    required = booleanValue("is_required"),
    hidden = booleanValue("is_hidden"),
    auto = booleanValue("is_auto"),
    uiConfig = objectValue("ui_config_json"),
    displayOrder = intOrNullValue("display_order") ?: 0
)

fun JsonObject.toActivitySession(): ActivitySession = ActivitySession(
    id = stringValue("id"),
    userId = stringValue("user_id"),
    studyItemId = stringValue("study_item_id"),
    sessionDate = stringValue("session_date"),
    createdAt = stringValue("created_at")
)

fun fallbackOptionsFor(fieldKey: String): List<String> = when (fieldKey) {
    "confidence_level" -> listOf("1", "2", "3", "4", "5")
    "reading_state" -> listOf("completed", "partial", "not_read")
    "issue_type" -> listOf("wrong", "skipped", "unseen")
    else -> emptyList()
}

private fun field(
    key: String,
    label: String,
    type: String,
    required: Boolean,
    order: Int,
    scope: String = "session",
    helper: String = ""
): FormField = FormField(
    id = "fallback_${scope}_$key",
    templateId = "fallback",
    fieldKey = key,
    showLabel = label,
    helperText = helper,
    inputType = type,
    fieldScope = scope,
    required = required,
    hidden = false,
    auto = false,
    uiConfig = JsonObject(emptyMap()),
    displayOrder = order
)

fun fallbackSessionFields(activityType: String): List<FormField> = when (activityType) {
    "revision" -> listOf(
        field("completed_count", "Completed count", "number", true, 1),
        field("target_count_snapshot", "Total target", "number", true, 2),
        field("mistake_notes", "Mistake notes", "textarea", false, 3),
        field("confidence_level", "Confidence level", "select", false, 4)
    )
    "test" -> listOf(
        field("total_questions", "Total questions", "number", true, 1),
        field("max_marks", "Total exam marks", "number", false, 2),
        field("marks_obtained", "Marks obtained", "number", false, 3),
        field("total_duration_seconds", "Total exam duration", "duration", false, 4, helper = "Use HH:MM:SS or seconds"),
        field("time_taken_seconds", "Time taken", "duration", false, 5, helper = "Use HH:MM:SS or seconds"),
        field("right_count", "Right answers", "number", false, 6),
        field("wrong_count", "Wrong answers", "number", false, 7),
        field("skipped_count", "Skipped answers", "number", false, 8),
        field("unseen_count", "Unseen answers", "number", false, 9),
        field("rank", "Rank", "number", false, 10),
        field("total_rank", "Total rank", "number", false, 11),
        field("percentile", "Percentile", "number", false, 12),
        field("utilized_seconds", "Utilized time", "duration", false, 13),
        field("wasted_seconds", "Wasted time", "duration", false, 14),
        field("correct_time_seconds", "Correct-answer time", "duration", false, 15),
        field("wrong_time_seconds", "Wrong-answer time", "duration", false, 16),
        field("skipped_time_seconds", "Skipped-answer time", "duration", false, 17),
        field("range_from", "Range from", "number", false, 18),
        field("range_to", "Range to", "number", false, 19),
        field("result_notes", "Attempt notes", "textarea", false, 20)
    )
    "video" -> listOf(
        field("watched_videos", "Watched videos", "number", true, 1),
        field("total_videos_snapshot", "Total videos", "number", true, 2),
        field("time_spent_seconds", "Time spent", "duration", false, 3),
        field("notes", "Notes", "textarea", false, 4)
    )
    "reading" -> listOf(
        field("reading_state", "Reading state", "select", true, 1),
        field("time_spent_seconds", "Time spent", "duration", false, 2),
        field("notes", "Notes", "textarea", false, 3)
    )
    else -> emptyList()
}

fun fallbackMissedQuestionFields(): List<FormField> = listOf(
    field("question_number", "Question number", "number", true, 1, "missed_question"),
    field("issue_type", "Result type", "select", true, 2, "missed_question"),
    field("question_text", "Question", "textarea", true, 3, "missed_question"),
    field("options_json", "Options JSON", "json", false, 4, "missed_question"),
    field("selected_option_key", "Your answer", "text", false, 5, "missed_question"),
    field("correct_option_key", "Correct answer", "text", false, 6, "missed_question"),
    field("question_marks", "Question marks", "number", false, 7, "missed_question"),
    field("marks_received", "Marks received", "number", false, 8, "missed_question"),
    field("question_time_seconds", "Time spent", "duration", false, 9, "missed_question"),
    field("question_note", "Question note", "textarea", false, 10, "missed_question")
)

private val fieldRuleMap = mapOf(
    "total_questions" to "ask_total_questions",
    "max_marks" to "ask_max_marks",
    "marks_obtained" to "ask_marks_obtained",
    "total_duration_seconds" to "ask_total_duration",
    "time_taken_seconds" to "ask_time_taken",
    "right_count" to "ask_right_count",
    "wrong_count" to "ask_wrong_count",
    "skipped_count" to "ask_skipped_count",
    "unseen_count" to "ask_unseen_count",
    "rank" to "ask_rank",
    "total_rank" to "ask_total_rank",
    "percentile" to "ask_percentile",
    "utilized_seconds" to "ask_time_breakdown",
    "wasted_seconds" to "ask_time_breakdown",
    "correct_time_seconds" to "ask_time_breakdown",
    "wrong_time_seconds" to "ask_time_breakdown",
    "skipped_time_seconds" to "ask_time_breakdown",
    "range_from" to "ask_range_from",
    "range_to" to "ask_range_to",
    "result_notes" to "ask_notes",
    "mistake_notes" to "capture_mistake_notes",
    "confidence_level" to "capture_confidence_level"
)

fun visibleFieldsFor(
    item: CatalogItem,
    fieldsByTemplateKey: Map<String, Map<String, List<FormField>>>,
    scope: String
): List<FormField> {
    val fromDatabase = fieldsByTemplateKey[item.templateKey]?.get(scope).orEmpty()
    val base = if (fromDatabase.isNotEmpty()) fromDatabase else if (scope == "missed_question") fallbackMissedQuestionFields() else fallbackSessionFields(item.activityType)
    return base.asSequence()
        .filterNot { it.hidden || it.auto }
        .filter { field ->
            if (scope == "missed_question" && item.uiRules["capture_missed_questions"]?.jsonPrimitive?.booleanOrNull == false) return@filter false
            val rule = fieldRuleMap[field.fieldKey]
            if (rule == null) true else item.uiRules[rule]?.jsonPrimitive?.booleanOrNull ?: true
        }
        .sortedBy { it.displayOrder }
        .toList()
}

fun humanStatus(raw: String): String = raw.replace('_', ' ').replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }

fun completionLabel(done: Int, total: Int): String {
    val pct = if (total > 0) (done.toDouble() / total.toDouble()) * 100.0 else 0.0
    return "$done/$total (${"%.0f".format(pct)}%)"
}

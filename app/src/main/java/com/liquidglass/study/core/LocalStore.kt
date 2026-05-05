package com.liquidglass.study.core

import android.content.Context

data class LocalSettings(
    val displayName: String = "Sam",
    val examTarget: String = "Banking Exam",
    val dailyGoalMinutes: Int = 180,
    val weeklyMockGoal: Int = 5,
    val themeMode: String = "System"
)

class LocalUserStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("liquid_glass_local_companion", Context.MODE_PRIVATE)

    fun loadSettings(): LocalSettings = LocalSettings(
        displayName = prefs.getString(KEY_DISPLAY_NAME, "Sam") ?: "Sam",
        examTarget = prefs.getString(KEY_EXAM_TARGET, "Banking Exam") ?: "Banking Exam",
        dailyGoalMinutes = prefs.getInt(KEY_DAILY_GOAL_MINUTES, 180),
        weeklyMockGoal = prefs.getInt(KEY_WEEKLY_MOCK_GOAL, 5),
        themeMode = prefs.getString(KEY_THEME_MODE, "System") ?: "System"
    )

    fun saveSettings(settings: LocalSettings) {
        prefs.edit()
            .putString(KEY_DISPLAY_NAME, settings.displayName.ifBlank { "Sam" })
            .putString(KEY_EXAM_TARGET, settings.examTarget.ifBlank { "Banking Exam" })
            .putInt(KEY_DAILY_GOAL_MINUTES, settings.dailyGoalMinutes.coerceAtLeast(0))
            .putInt(KEY_WEEKLY_MOCK_GOAL, settings.weeklyMockGoal.coerceAtLeast(0))
            .putString(KEY_THEME_MODE, settings.themeMode.ifBlank { "System" })
            .apply()
    }

    fun mistakeStatus(mistakeId: String): String = prefs.getString("mistake_status_$mistakeId", "New") ?: "New"

    fun saveMistakeStatus(mistakeId: String, status: String) {
        prefs.edit().putString("mistake_status_$mistakeId", status).apply()
    }

    fun favoriteStudyItems(): Set<String> = prefs.getStringSet(KEY_FAVORITES, emptySet()).orEmpty()

    fun lastStudySyncDay(): String = prefs.getString(KEY_STUDY_SYNC_DAY, "") ?: ""
    fun lastStudySyncAt(): String = prefs.getString(KEY_STUDY_SYNC_AT, "") ?: ""

    fun saveStudySyncStamp(day: String, atIso: String) {
        prefs.edit()
            .putString(KEY_STUDY_SYNC_DAY, day)
            .putString(KEY_STUDY_SYNC_AT, atIso)
            .apply()
    }

    fun toggleFavoriteStudyItem(itemId: String): Set<String> {
        val next = favoriteStudyItems().toMutableSet()
        if (!next.add(itemId)) next.remove(itemId)
        prefs.edit().putStringSet(KEY_FAVORITES, next).apply()
        return next
    }

    private companion object {
        const val KEY_DISPLAY_NAME = "display_name"
        const val KEY_EXAM_TARGET = "exam_target"
        const val KEY_DAILY_GOAL_MINUTES = "daily_goal_minutes"
        const val KEY_WEEKLY_MOCK_GOAL = "weekly_mock_goal"
        const val KEY_THEME_MODE = "theme_mode"
        const val KEY_FAVORITES = "favorite_study_items"
        const val KEY_STUDY_SYNC_DAY = "study_sync_day"
        const val KEY_STUDY_SYNC_AT = "study_sync_at"
    }
}

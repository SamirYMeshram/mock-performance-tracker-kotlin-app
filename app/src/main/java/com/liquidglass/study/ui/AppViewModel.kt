package com.liquidglass.study.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.liquidglass.study.core.AuthUser
import com.liquidglass.study.core.LocalSettings
import com.liquidglass.study.core.LocalUserStore
import com.liquidglass.study.core.SessionStore
import com.liquidglass.study.core.SupabaseProjects
import com.liquidglass.study.core.SupabaseRestClient
import com.liquidglass.study.core.todayIso
import com.liquidglass.study.core.nowIso
import com.liquidglass.study.data.ActivityLogEntry
import com.liquidglass.study.data.AuthRepository
import com.liquidglass.study.data.CatalogItem
import com.liquidglass.study.data.DailyReportDay
import com.liquidglass.study.data.DailyRepository
import com.liquidglass.study.data.DailyStatus
import com.liquidglass.study.data.DailyTask
import com.liquidglass.study.data.DailyTaskInput
import com.liquidglass.study.data.FormField
import com.liquidglass.study.data.FormTemplate
import com.liquidglass.study.data.MissedQuestionInput
import com.liquidglass.study.data.MistakeRecord
import com.liquidglass.study.data.NewCatalogItemInput
import com.liquidglass.study.data.StudyEntry
import com.liquidglass.study.data.StudyRepository
import com.liquidglass.study.data.visibleFieldsFor
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

enum class ModuleChoice(val title: String, val projectId: String, val tagline: String) {
    Daily("Daily Goal Tracker", "efdgpvqnniijfgtprudw", "Daily checklist, tasks, reports, 88-task seed"),
    Study("Study Pulse Pro", "bcljjhoazecxiqrllbkx", "Catalog, tests, mistakes, results, analytics")
}

enum class AppTab(val title: String) { Home("Home"), Today("Today"), Study("Study"), Mistakes("Mistakes"), Progress("Progress") }

data class DailyUiState(
    val dayDate: String = todayIso(),
    val allTasks: List<DailyTask> = emptyList(),
    val savedStatus: Map<String, Boolean> = emptyMap(),
    val draftStatus: Map<String, Boolean> = emptyMap(),
    val recentActivity: List<ActivityLogEntry> = emptyList(),
    val reportStart: String = todayIso(),
    val reportEnd: String = todayIso(),
    val reportDays: List<DailyReportDay> = emptyList(),
    val reportLogs: List<ActivityLogEntry> = emptyList()
) {
    val activeTasks: List<DailyTask> get() = allTasks.filter { it.active }
    val mergedStatus: Map<String, Boolean> get() = savedStatus + draftStatus
    val completedActive: Int get() = activeTasks.count { mergedStatus[it.id] == true }
    val completionRate: Float get() = if (activeTasks.isEmpty()) 0f else completedActive.toFloat() / activeTasks.size.toFloat()
}

data class StudyUiState(
    val catalog: List<CatalogItem> = emptyList(),
    val templates: List<FormTemplate> = emptyList(),
    val fieldsByTemplateKey: Map<String, Map<String, List<FormField>>> = emptyMap(),
    val entries: List<StudyEntry> = emptyList(),
    val mistakes: List<MistakeRecord> = emptyList(),
    val favoriteItemIds: Set<String> = emptySet(),
    val search: String = "",
    val activityFilter: String = "All",
    val platformFilter: String = "All",
    val mistakeFilter: String = "All"
)

data class ActiveStudyForm(
    val item: CatalogItem,
    val values: Map<String, String>,
    val missedQuestions: List<MissedQuestionInput> = emptyList(),
    val saving: Boolean = false
)

data class StudyTimerState(
    val active: Boolean = false,
    val running: Boolean = false,
    val mode: String = "Stopwatch",
    val totalSeconds: Int = 0,
    val remainingSeconds: Int = 0,
    val completed: Boolean = false
) {
    val elapsedSeconds: Int get() = if (totalSeconds <= 0) 0 else (totalSeconds - remainingSeconds).coerceAtLeast(0)
    val progress: Float get() = if (totalSeconds <= 0) 0f else elapsedSeconds.toFloat() / totalSeconds.toFloat()
}

data class AppUiState(
    val bootstrapping: Boolean = true,
    val loading: Boolean = false,
    val user: AuthUser? = null,
    val selectedModule: ModuleChoice = ModuleChoice.Study,
    val currentTab: AppTab = AppTab.Home,
    val daily: DailyUiState = DailyUiState(),
    val study: StudyUiState = StudyUiState(),
    val settings: LocalSettings = LocalSettings(),
    val lastStudySyncDay: String = "",
    val lastStudySyncAt: String = "",
    val timer: StudyTimerState = StudyTimerState(),
    val activeStudyForm: ActiveStudyForm? = null,
    val selectedStudyEntryId: String? = null,
    val addActivitySheetVisible: Boolean = false,
    val selectedAddActivityType: String? = null,
    val catalogCreatorVisible: Boolean = false,
    val catalogDraft: NewCatalogItemInput = NewCatalogItemInput(),
    val settingsSheetVisible: Boolean = false,
    val error: String? = null,
    val message: String? = null
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val dailySessionStore = SessionStore(application, "daily")
    private val studySessionStore = SessionStore(application, "study")
    private val localStore = LocalUserStore(application)

    private val dailyClient = SupabaseRestClient(SupabaseProjects.Daily, dailySessionStore)
    private val studyClient = SupabaseRestClient(SupabaseProjects.Study, studySessionStore)

    private val dailyAuthRepository = AuthRepository(dailyClient, dailySessionStore)
    private val studyAuthRepository = AuthRepository(studyClient, studySessionStore)
    private val dailyRepository = DailyRepository(dailyClient, dailySessionStore)
    private val studyRepository = StudyRepository(studyClient, studySessionStore)

    private var timerJob: Job? = null

    private val _uiState = MutableStateFlow(
        AppUiState(
            selectedModule = moduleFromName(dailySessionStore.selectedModuleName()),
            settings = localStore.loadSettings(),
            lastStudySyncDay = localStore.lastStudySyncDay(),
            lastStudySyncAt = localStore.lastStudySyncAt(),
            study = StudyUiState(favoriteItemIds = localStore.favoriteStudyItems())
        )
    )
    val uiState: StateFlow<AppUiState> = _uiState.asStateFlow()

    init { bootstrap() }

    fun bootstrap() {
        viewModelScope.launch {
            val module = _uiState.value.selectedModule
            _uiState.update { it.copy(bootstrapping = true, error = null, message = null) }
            val user = authRepository(module).bootstrap()
            _uiState.update { it.copy(bootstrapping = false, user = user, settings = localStore.loadSettings()) }
            if (user != null) loadSelectedModuleInternal(module)
        }
    }

    fun signIn(email: String, password: String, module: ModuleChoice) = launchLoading {
        saveSelectedModule(module)
        val user = authRepository(module).signIn(email, password)
        _uiState.update {
            it.copy(
                user = user,
                selectedModule = module,
                currentTab = AppTab.Home,
                message = "Signed in to ${module.title}",
                activeStudyForm = null
            )
        }
        loadSelectedModuleInternal(module)
    }

    fun signOut() = launchLoading {
        val module = _uiState.value.selectedModule
        authRepository(module).signOut()
        timerJob?.cancel()
        _uiState.update {
            AppUiState(
                bootstrapping = false,
                selectedModule = module,
                settings = localStore.loadSettings(),
                message = "Signed out of ${module.title}"
            )
        }
    }

    fun selectModule(module: ModuleChoice) = launchLoading {
        saveSelectedModule(module)
        val user = authRepository(module).bootstrap()
        _uiState.update {
            it.copy(
                selectedModule = module,
                user = user,
                currentTab = AppTab.Home,
                activeStudyForm = null,
                addActivitySheetVisible = false,
                error = null,
                message = if (user == null) "Sign in to ${module.title}" else "Opened ${module.title}"
            )
        }
        if (user != null) loadSelectedModuleInternal(module)
    }

    fun selectTab(tab: AppTab) {
        _uiState.update { it.copy(currentTab = tab, error = null, message = null) }
        when (tab) {
            AppTab.Today -> if (_uiState.value.selectedModule == ModuleChoice.Daily && _uiState.value.daily.allTasks.isEmpty()) loadDaily()
            AppTab.Study, AppTab.Mistakes, AppTab.Progress, AppTab.Home -> if (_uiState.value.selectedModule == ModuleChoice.Study && _uiState.value.study.catalog.isEmpty()) loadStudy()
        }
    }

    fun refresh() = launchLoading {
        loadSelectedModuleInternal(_uiState.value.selectedModule, force = true)
        _uiState.update { it.copy(message = "Manual sync complete") }
    }
    private fun loadSelectedModule() = launchLoading { loadSelectedModuleInternal(_uiState.value.selectedModule) }

    private suspend fun loadSelectedModuleInternal(module: ModuleChoice, force: Boolean = false) {
        when (module) {
            ModuleChoice.Daily -> loadDailyInternal()
            ModuleChoice.Study -> loadStudyInternal(force = force)
        }
    }

    fun openAddActivitySheet() { _uiState.update { it.copy(addActivitySheetVisible = true, selectedAddActivityType = null) } }
    fun closeAddActivitySheet() { _uiState.update { it.copy(addActivitySheetVisible = false, selectedAddActivityType = null) } }
    fun chooseAddActivityType(activityType: String) {
        val normalized = normalizeStudyActivityType(activityType)
        _uiState.update {
            it.copy(
                addActivitySheetVisible = true,
                selectedAddActivityType = normalized,
                currentTab = if (it.selectedModule == ModuleChoice.Study) it.currentTab else AppTab.Study,
                study = it.study.copy(activityFilter = normalized)
            )
        }
    }
    fun backToAddTypePicker() { _uiState.update { it.copy(selectedAddActivityType = null) } }
    fun openStudyEntryDetails(entryId: String) { _uiState.update { it.copy(selectedStudyEntryId = entryId) } }
    fun closeStudyEntryDetails() { _uiState.update { it.copy(selectedStudyEntryId = null) } }
    fun openCatalogCreator(activityType: String = "test") {
        val normalized = activityType.takeIf { it in listOf("revision", "test", "video", "reading") } ?: "test"
        val template = bestTemplateKeyFor(normalized)
        _uiState.update {
            it.copy(
                addActivitySheetVisible = false,
                selectedAddActivityType = null,
                catalogCreatorVisible = true,
                catalogDraft = NewCatalogItemInput(activityType = normalized, templateKey = template)
            )
        }
    }
    fun closeCatalogCreator() { _uiState.update { it.copy(catalogCreatorVisible = false) } }
    fun updateCatalogDraft(transform: (NewCatalogItemInput) -> NewCatalogItemInput) {
        _uiState.update { it.copy(catalogDraft = transform(it.catalogDraft)) }
    }
    fun createCatalogItem() = launchLoading {
        val created = studyRepository.createCatalogItem(_uiState.value.catalogDraft)
        _uiState.update { it.copy(catalogCreatorVisible = false, selectedAddActivityType = null, message = "Catalog item created: ${created.displayName}") }
        loadStudyInternal(force = true)
        openStudyForm(created)
    }
    fun openSettingsSheet() { _uiState.update { it.copy(settingsSheetVisible = true) } }
    fun closeSettingsSheet() { _uiState.update { it.copy(settingsSheetVisible = false) } }

    fun saveLocalSettings(settings: LocalSettings) {
        localStore.saveSettings(settings)
        _uiState.update { it.copy(settings = localStore.loadSettings(), message = "Settings saved") }
    }

    fun loadDaily() = launchLoading { loadDailyInternal() }

    private suspend fun loadDailyInternal() {
        dailyRepository.ensureDefaultTasksSeeded()
        val day = todayIso()
        val tasks = dailyRepository.getTasks(includeInactive = true)
        val statuses = dailyRepository.getDailyStatus(day)
        val saved = statuses.associate { it.taskId to it.completed }
        val draft = dailySessionStore.loadDailyDraft(day)
        val activity = dailyRepository.getRecentActivity()
        _uiState.update {
            it.copy(
                daily = it.daily.copy(
                    dayDate = day,
                    allTasks = tasks,
                    savedStatus = saved,
                    draftStatus = draft,
                    recentActivity = activity
                )
            )
        }
    }

    fun setDailyTaskChecked(taskId: String, checked: Boolean) {
        val state = _uiState.value
        val day = state.daily.dayDate
        val updated = state.daily.draftStatus.toMutableMap().also { it[taskId] = checked }
        dailySessionStore.saveDailyDraft(day, updated)
        _uiState.update { it.copy(daily = it.daily.copy(draftStatus = updated)) }
    }

    fun submitToday() = launchLoading {
        val daily = _uiState.value.daily
        val active = daily.activeTasks
        val completed = active.associate { it.id to (daily.mergedStatus[it.id] == true) }
        dailyRepository.submitDay(daily.dayDate, active, completed)
        _uiState.update { it.copy(message = "Today saved: ${daily.completedActive}/${active.size} complete") }
        loadDailyInternal()
    }

    fun saveDailyTask(input: DailyTaskInput) = launchLoading {
        dailyRepository.saveTask(input)
        _uiState.update { it.copy(message = "Task saved") }
        loadDailyInternal()
    }

    fun toggleTaskActive(task: DailyTask) = launchLoading {
        dailyRepository.toggleTaskActive(task)
        _uiState.update { it.copy(message = if (task.active) "Task archived" else "Task restored") }
        loadDailyInternal()
    }

    fun deleteOrArchiveTask(task: DailyTask) = launchLoading {
        dailyRepository.deleteOrArchiveTask(task)
        _uiState.update { it.copy(message = "Task deleted or archived safely") }
        loadDailyInternal()
    }

    fun resetDefaultTasks() = launchLoading {
        dailyRepository.resetTasksToDefault()
        _uiState.update { it.copy(message = "Default task list restored") }
        loadDailyInternal()
    }

    fun clearDailyHistory() = launchLoading {
        dailyRepository.clearHistoryOnly()
        _uiState.update { it.copy(message = "Daily history cleared. Tasks were kept.") }
        loadDailyInternal()
    }

    fun clearStudyHistory(confirmation: String) = launchLoading {
        if (confirmation.trim() != "DELETE STUDY DATA") {
            _uiState.update { it.copy(message = "Type DELETE STUDY DATA exactly before deleting study history.") }
            return@launchLoading
        }
        studyRepository.clearMyStudyHistory()
        _uiState.update { it.copy(message = "Study history deleted. Catalog/source list was kept.") }
        loadStudyInternal(force = true)
    }

    fun updateReportRange(start: String, end: String) {
        _uiState.update { it.copy(daily = it.daily.copy(reportStart = start, reportEnd = end)) }
    }

    fun loadDailyReport() = launchLoading {
        val daily = _uiState.value.daily
        val (rows, logs) = dailyRepository.getReport(daily.reportStart.takeIf { it.isNotBlank() }, daily.reportEnd.takeIf { it.isNotBlank() })
        _uiState.update { it.copy(daily = it.daily.copy(reportDays = buildDailyReport(rows), reportLogs = logs)) }
    }

    fun loadStudy() = launchLoading { loadStudyInternal(force = true) }

    private suspend fun loadStudyInternal(force: Boolean = false) {
        val today = todayIso()
        val alreadySyncedToday = localStore.lastStudySyncDay() == today
        val hasMemoryData = _uiState.value.study.catalog.isNotEmpty()
        if (!force && alreadySyncedToday && hasMemoryData) {
            _uiState.update { it.copy(message = "Already synced today. Tap refresh for manual sync.") }
            return
        }
        val metadata = studyRepository.loadMetadata()
        val entries = studyRepository.loadEntries(metadata.catalog)
        val mistakes = studyRepository.loadMistakes(metadata.catalog).map { mistake ->
            mistake.copy(reviewStatus = localStore.mistakeStatus(mistake.id))
        }
        localStore.saveStudySyncStamp(today, nowIso())
        _uiState.update {
            it.copy(
                lastStudySyncDay = localStore.lastStudySyncDay(),
                lastStudySyncAt = localStore.lastStudySyncAt(),
                study = it.study.copy(
                    catalog = metadata.catalog,
                    templates = metadata.templates,
                    fieldsByTemplateKey = metadata.fieldsByTemplateKey,
                    entries = entries,
                    mistakes = mistakes,
                    favoriteItemIds = localStore.favoriteStudyItems()
                )
            )
        }
    }

    fun setStudySearch(value: String) { _uiState.update { it.copy(study = it.study.copy(search = value)) } }
    fun setStudyActivityFilter(value: String) { _uiState.update { it.copy(study = it.study.copy(activityFilter = value)) } }
    fun setStudyPlatformFilter(value: String) { _uiState.update { it.copy(study = it.study.copy(platformFilter = value)) } }
    fun setMistakeFilter(value: String) { _uiState.update { it.copy(study = it.study.copy(mistakeFilter = value)) } }

    fun toggleFavorite(itemId: String) {
        val next = localStore.toggleFavoriteStudyItem(itemId)
        _uiState.update { it.copy(study = it.study.copy(favoriteItemIds = next)) }
    }

    fun openStudyForm(item: CatalogItem) {
        val fields = visibleFieldsFor(item, _uiState.value.study.fieldsByTemplateKey, "session")
        val defaults = fields.associate { field ->
            val value = when (field.fieldKey) {
                "target_count_snapshot", "total_videos_snapshot" -> item.targetCount?.toString().orEmpty()
                "reading_state" -> "partial"
                "total_questions" -> item.targetCount?.takeIf { it > 0 }?.toString().orEmpty()
                else -> ""
            }
            field.fieldKey to value
        }
        _uiState.update { it.copy(activeStudyForm = ActiveStudyForm(item = item, values = defaults), addActivitySheetVisible = false, selectedAddActivityType = null) }
    }

    fun closeStudyForm() { _uiState.update { it.copy(activeStudyForm = null) } }

    fun updateStudyField(key: String, value: String) {
        _uiState.update { state ->
            val form = state.activeStudyForm ?: return@update state
            state.copy(activeStudyForm = form.copy(values = form.values + (key to value)))
        }
    }

    fun addMissedQuestion(issueType: String = "wrong") {
        _uiState.update { state ->
            val form = state.activeStudyForm ?: return@update state
            state.copy(activeStudyForm = form.copy(missedQuestions = form.missedQuestions + MissedQuestionInput(issueType = issueType)))
        }
    }

    fun removeMissedQuestion(index: Int) {
        _uiState.update { state ->
            val form = state.activeStudyForm ?: return@update state
            state.copy(activeStudyForm = form.copy(missedQuestions = form.missedQuestions.filterIndexed { i, _ -> i != index }))
        }
    }

    fun updateMissedQuestion(index: Int, field: String, value: String) {
        _uiState.update { state ->
            val form = state.activeStudyForm ?: return@update state
            val updated = form.missedQuestions.mapIndexed { i, q ->
                if (i != index) q else when (field) {
                    "question_number" -> q.copy(questionNumber = value)
                    "issue_type" -> q.copy(issueType = value)
                    "question_text" -> q.copy(questionText = value)
                    "options_json" -> q.copy(optionsJson = value)
                    "selected_option_key" -> q.copy(selectedOptionKey = value)
                    "correct_option_key" -> q.copy(correctOptionKey = value)
                    "question_marks" -> q.copy(questionMarks = value)
                    "marks_received" -> q.copy(marksReceived = value)
                    "question_time_seconds" -> q.copy(questionTime = value)
                    "question_note" -> q.copy(questionNote = value)
                    else -> q
                }
            }
            state.copy(activeStudyForm = form.copy(missedQuestions = updated))
        }
    }

    fun saveStudyActivity() = launchLoading {
        val form = _uiState.value.activeStudyForm ?: return@launchLoading
        _uiState.update { it.copy(activeStudyForm = form.copy(saving = true)) }
        studyRepository.saveActivity(form.item, form.values, form.missedQuestions)
        _uiState.update { it.copy(activeStudyForm = null, message = "Activity saved to Supabase and local state") }
        loadStudyInternal(force = true)
    }

    fun quickAddActivity(activityType: String) {
        if (activityType == "timer") {
            closeAddActivitySheet()
            startTimer("Pomodoro 25")
            return
        }
        if (activityType == "mistake") {
            _uiState.update { it.copy(currentTab = AppTab.Mistakes, addActivitySheetVisible = false, selectedAddActivityType = null) }
            return
        }
        chooseAddActivityType(activityType)
    }

    fun openExistingCatalogItem(item: CatalogItem) {
        openStudyForm(item)
    }

    fun markMistakeStatus(mistakeId: String, status: String) {
        localStore.saveMistakeStatus(mistakeId, status)
        _uiState.update { state ->
            state.copy(
                study = state.study.copy(mistakes = state.study.mistakes.map { if (it.id == mistakeId) it.copy(reviewStatus = status) else it }),
                message = if (status == "Fixed") "Mistake marked fixed" else "Mistake moved to $status"
            )
        }
    }

    fun startTimer(mode: String) {
        val total = when (mode) {
            "Deep Work 50" -> 50 * 60
            "Short Review 10" -> 10 * 60
            else -> 25 * 60
        }
        timerJob?.cancel()
        _uiState.update { it.copy(timer = StudyTimerState(active = true, running = true, mode = mode, totalSeconds = total, remainingSeconds = total)) }
        launchTimerLoop()
    }

    fun pauseTimer() {
        timerJob?.cancel()
        _uiState.update { it.copy(timer = it.timer.copy(running = false)) }
    }

    fun resumeTimer() {
        val timer = _uiState.value.timer
        if (timer.active && timer.remainingSeconds > 0 && !timer.running) {
            _uiState.update { it.copy(timer = it.timer.copy(running = true, completed = false)) }
            launchTimerLoop()
        }
    }

    fun stopTimer() {
        timerJob?.cancel()
        _uiState.update { it.copy(timer = StudyTimerState()) }
    }

    private fun launchTimerLoop() {
        timerJob?.cancel()
        timerJob = viewModelScope.launch {
            while (_uiState.value.timer.running && _uiState.value.timer.remainingSeconds > 0) {
                delay(1000)
                _uiState.update { state ->
                    val current = state.timer
                    val nextRemaining = (current.remainingSeconds - 1).coerceAtLeast(0)
                    if (nextRemaining == 0) {
                        state.copy(timer = current.copy(remainingSeconds = 0, running = false, completed = true), message = "Timer complete. Log what you studied.")
                    } else {
                        state.copy(timer = current.copy(remainingSeconds = nextRemaining))
                    }
                }
            }
        }
    }

    fun clearTransientMessages() { _uiState.update { it.copy(error = null, message = null) } }

    private fun launchLoading(block: suspend () -> Unit) {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null, message = null) }
            try {
                block()
            } catch (t: Throwable) {
                _uiState.update { it.copy(error = t.message ?: "Unexpected error") }
            } finally {
                _uiState.update { state -> state.copy(loading = false, activeStudyForm = state.activeStudyForm?.copy(saving = false)) }
            }
        }
    }

    private fun buildDailyReport(rows: List<DailyStatus>): List<DailyReportDay> {
        return rows.groupBy { it.dayDate }.map { (day, items) ->
            val total = items.size
            val completed = items.count { it.completed }
            val category = items.groupBy { it.categorySnapshot.ifBlank { "Uncategorized" } }.mapValues { (_, group) -> group.count { it.completed } to group.size }
            val platform = items.groupBy { it.platformSnapshot.ifBlank { "Unknown" } }.mapValues { (_, group) -> group.count { it.completed } to group.size }
            DailyReportDay(
                dayDate = day,
                totalTasks = total,
                completedCount = completed,
                pendingCount = total - completed,
                completionRate = if (total == 0) 0 else ((completed.toDouble() / total.toDouble()) * 100.0).roundToInt(),
                latestSubmittedAt = items.maxOfOrNull { it.submittedAt }.orEmpty(),
                categoryBreakdown = category,
                platformBreakdown = platform
            )
        }.sortedByDescending { it.dayDate }
    }

    private fun normalizeStudyActivityType(activityType: String): String =
        activityType.trim().lowercase().takeIf { it in listOf("revision", "test", "video", "reading") } ?: "test"

    private fun bestTemplateKeyFor(activityType: String): String {
        val templates = _uiState.value.study.templates.filter { it.activityType == activityType && it.isActive }
        return when (activityType) {
            "test" -> templates.firstOrNull { "advanced" in it.templateKey && "rank" in it.templateKey }?.templateKey
                ?: templates.firstOrNull { "basic" in it.templateKey }?.templateKey
                ?: templates.firstOrNull()?.templateKey
                ?: "test_basic_with_missed_questions"
            "video" -> templates.firstOrNull()?.templateKey ?: "video_progress"
            "reading" -> templates.firstOrNull()?.templateKey ?: "reading_progress"
            "revision" -> templates.firstOrNull()?.templateKey ?: "revision_basic"
            else -> templates.firstOrNull()?.templateKey.orEmpty()
        }
    }

    private fun authRepository(module: ModuleChoice): AuthRepository = when (module) {
        ModuleChoice.Daily -> dailyAuthRepository
        ModuleChoice.Study -> studyAuthRepository
    }

    private fun saveSelectedModule(module: ModuleChoice) { dailySessionStore.saveSelectedModule(module.name) }
    private fun moduleFromName(name: String): ModuleChoice = runCatching { ModuleChoice.valueOf(name) }.getOrDefault(ModuleChoice.Study)

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = AppViewModel(application) as T
        }
    }
}

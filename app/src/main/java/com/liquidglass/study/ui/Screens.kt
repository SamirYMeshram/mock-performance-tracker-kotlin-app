package com.liquidglass.study.ui

import android.app.Application
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Logout
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Quiz
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.liquidglass.study.core.LocalSettings
import com.liquidglass.study.core.durationToText
import com.liquidglass.study.core.todayIso
import com.liquidglass.study.data.CatalogItem
import com.liquidglass.study.data.DailyReportDay
import com.liquidglass.study.data.DailyTask
import com.liquidglass.study.data.DailyTaskInput
import com.liquidglass.study.data.FormField
import com.liquidglass.study.data.MissedQuestionInput
import com.liquidglass.study.data.MistakeRecord
import com.liquidglass.study.data.StudyEntry
import com.liquidglass.study.data.humanStatus
import com.liquidglass.study.data.visibleFieldsFor
import com.liquidglass.study.ui.theme.GlassAccent
import com.liquidglass.study.ui.theme.GlassAccent2
import com.liquidglass.study.ui.theme.GlassDanger
import com.liquidglass.study.ui.theme.GlassInk
import com.liquidglass.study.ui.theme.GlassMuted
import com.liquidglass.study.ui.theme.GlassSuccess
import com.liquidglass.study.ui.theme.GlassWarning
import java.time.LocalDate
import kotlin.math.roundToInt

@Composable
fun LiquidGlassApp() {
    val app = LocalContext.current.applicationContext as Application
    val viewModel: AppViewModel = viewModel(factory = AppViewModel.factory(app))
    val state by viewModel.uiState.collectAsState()

    LiquidBackground {
        Box(Modifier.fillMaxSize()) {
            AnimatedContent(
                targetState = state.user != null && !state.bootstrapping,
                transitionSpec = {
                    (fadeIn(AppMotion.slowTween()) + slideInVertically(AppMotion.slowTween()) { it / 10 }) togetherWith
                        (fadeOut(AppMotion.mediumTween()) + slideOutVertically(AppMotion.mediumTween()) { -it / 18 })
                },
                label = "auth-root"
            ) { loggedIn ->
                if (loggedIn) MainShell(state = state, viewModel = viewModel) else LoginScreen(state = state, onLogin = viewModel::signIn)
            }

            AnimatedVisibility(
                visible = state.error != null || state.message != null,
                enter = fadeIn(AppMotion.mediumTween()) + slideInVertically(AppMotion.mediumTween()) { -it },
                exit = fadeOut(AppMotion.fastTween()) + slideOutVertically(AppMotion.fastTween()) { -it },
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(horizontal = 14.dp, vertical = 8.dp)
            ) {
                MessageBanner(error = state.error, message = state.message, onDismiss = viewModel::clearTransientMessages)
            }

            if (state.addActivitySheetVisible) AddActivitySheet(state, viewModel)
            if (state.catalogCreatorVisible) CatalogCreatorSheet(state, viewModel)
            if (state.settingsSheetVisible) SettingsSheet(state, viewModel)
            state.activeStudyForm?.let { form -> StudyFormSheet(state = state, form = form, viewModel = viewModel) }
            state.selectedStudyEntryId?.let { entryId ->
                state.study.entries.firstOrNull { it.id == entryId }?.let { entry ->
                    StudyEntryDetailSheet(entry = entry, state = state, viewModel = viewModel)
                }
            }
            LoadingVeil(visible = state.loading || state.bootstrapping)
        }
    }
}

@Composable
private fun LoginScreen(state: AppUiState, onLogin: (String, String, ModuleChoice) -> Unit) {
    var email by rememberSaveable { mutableStateOf("sam@gmail.com") }
    var password by rememberSaveable { mutableStateOf("") }
    var selectedModule by rememberSaveable { mutableStateOf(state.selectedModule) }
    var showPassword by rememberSaveable { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        item { Spacer(Modifier.height(18.dp)) }
        item {
            GlassCard(modifier = Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 22.dp, accent = GlassAccent.copy(alpha = 0.16f)) {
                Text("Study Command Center", style = MaterialTheme.typography.headlineMedium, color = GlassInk, fontWeight = FontWeight.Black)
                Spacer(Modifier.height(8.dp))
                Text("Premium native Kotlin companion for daily missions, test tracking, mistake review, and progress analytics.", color = GlassMuted)
                Spacer(Modifier.height(18.dp))
                ModuleChoice.values().forEach { module ->
                    ProjectLoginChoiceCard(module = module, selected = selectedModule == module, onSelect = { selectedModule = module })
                    Spacer(Modifier.height(10.dp))
                }
                GlassTextField(value = email, onValueChange = { email = it }, label = "Email")
                Spacer(Modifier.height(10.dp))
                androidx.compose.material3.OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = { IconButton(onClick = { showPassword = !showPassword }) { Icon(Icons.Outlined.Visibility, contentDescription = "Show password") } },
                    shape = RoundedCornerShape(18.dp),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(18.dp))
                PrimaryGlassButton(
                    text = "Sign in to ${selectedModule.title}",
                    enabled = email.isNotBlank() && password.isNotBlank() && !state.loading,
                    modifier = Modifier.fillMaxWidth()
                ) { onLogin(email, password, selectedModule) }
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Lock, contentDescription = null, tint = GlassMuted, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Personal single-user mode: auth uses email/password; Study writes use your configured project keys so catalog/category creation does not fail on RLS.", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        item { Spacer(Modifier.height(20.dp)) }
    }
}

@Composable
private fun ProjectLoginChoiceCard(module: ModuleChoice, selected: Boolean, onSelect: () -> Unit) {
    PressableCard(modifier = Modifier.fillMaxWidth(), radius = 24.dp, onClick = onSelect) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(46.dp).clip(CircleShape).background(if (selected) GlassAccent.copy(alpha = 0.24f) else Color.White.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center
            ) { Text(if (module == ModuleChoice.Study) "S" else "D", color = GlassInk, fontWeight = FontWeight.Black) }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(module.title, color = GlassInk, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
                Text(module.tagline, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2)
                Text("Project ${module.projectId}", color = GlassMuted, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(10.dp))
            Text(if (selected) "Selected" else "Choose", color = if (selected) GlassSuccess else GlassAccent, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun MainShell(state: AppUiState, viewModel: AppViewModel) {
    Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            TopCommandBar(state, viewModel)
            Spacer(Modifier.height(12.dp))
            Box(Modifier.weight(1f)) {
                AnimatedContent(
                    targetState = state.currentTab,
                    transitionSpec = {
                        (fadeIn(AppMotion.slowTween()) + slideInHorizontally(AppMotion.slowTween()) { it / 8 }) togetherWith
                            (fadeOut(AppMotion.mediumTween()) + slideOutHorizontally(AppMotion.mediumTween()) { -it / 10 })
                    },
                    label = "tab-content"
                ) { tab ->
                    when (tab) {
                        AppTab.Home -> HomeScreen(state, viewModel)
                        AppTab.Today -> TodayScreen(state, viewModel)
                        AppTab.Study -> StudyScreen(state, viewModel)
                        AppTab.Mistakes -> MistakesScreen(state, viewModel)
                        AppTab.Progress -> ProgressScreen(state, viewModel)
                    }
                }
            }
        }

        TimerMiniPlayer(
            timer = state.timer,
            onPause = viewModel::pauseTimer,
            onResume = viewModel::resumeTimer,
            onStop = viewModel::stopTimer,
            modifier = Modifier.align(Alignment.BottomCenter).padding(start = 18.dp, end = 18.dp, bottom = 102.dp)
        )

        FloatingActionButton(
            onClick = viewModel::openAddActivitySheet,
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 26.dp, bottom = 90.dp),
            containerColor = Color.White.copy(alpha = 0.92f),
            contentColor = Color(0xFF07101F)
        ) { Icon(Icons.Outlined.Add, contentDescription = "Add activity") }

        FloatingGlassBottomNav(
            current = state.currentTab,
            onSelected = viewModel::selectTab,
            modifier = Modifier.align(Alignment.BottomCenter).padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
        )
    }
}

@Composable
private fun TopCommandBar(state: AppUiState, viewModel: AppViewModel) {
    Row(modifier = Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(greeting(state.settings.displayName), color = GlassInk, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Black)
            val syncText = if (state.selectedModule == ModuleChoice.Study && state.lastStudySyncDay.isNotBlank()) " • synced ${state.lastStudySyncDay}" else ""
            Text("${state.selectedModule.title} • ${state.settings.examTarget}$syncText", color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onClick = viewModel::refresh) { Icon(Icons.Outlined.Refresh, contentDescription = "Refresh", tint = GlassInk) }
        PressableCard(modifier = Modifier.size(48.dp), radius = 24.dp, onClick = viewModel::openSettingsSheet) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Person, contentDescription = "Profile", tint = GlassInk) }
        }
    }
}

@Composable
private fun HomeScreen(state: AppUiState, viewModel: AppViewModel) {
    val entries = state.study.entries
    val today = todayIso()
    val todayEntries = entries.filter { it.sessionDate == today }
    val testEntries = entries.filter { it.activityType == "test" }
    val latestTest = testEntries.firstOrNull()
    val mistakes = state.study.mistakes.filterNot { it.reviewStatus == "Fixed" }
    val focusScore = focusScore(state)
    val weakTopic = mistakes.groupingBy { it.item.displayName }.eachCount().maxByOrNull { it.value }?.key ?: "No weak topic yet"

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassAccent.copy(alpha = 0.18f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Today’s Focus", color = GlassInk, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
                        Text(nextBestAction(state).second, color = GlassMuted, style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(14.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ChoiceChip("${todayEntries.size} sessions", true) {}
                            ChoiceChip("${mistakes.size} pending mistakes", false) { viewModel.selectTab(AppTab.Mistakes) }
                        }
                    }
                    ProgressRing(focusScore / 100f, "${focusScore}%")
                }
                Spacer(Modifier.height(16.dp))
                ProgressLine(focusScore / 100f, Modifier.fillMaxWidth())
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AnimatedStatCard("Study sessions", todayEntries.size.toFloat(), icon = Icons.Outlined.School, modifier = Modifier.weight(1f))
                AnimatedStatCard("Streak score", estimatedStreak(entries).toFloat(), icon = Icons.Outlined.Bolt, modifier = Modifier.weight(1f))
            }
        }
        item {
            val action = nextBestAction(state)
            InsightCard(title = action.first, body = action.second, cta = action.third) {
                when (action.fourth) {
                    AppTab.Mistakes -> viewModel.selectTab(AppTab.Mistakes)
                    AppTab.Study -> viewModel.selectTab(AppTab.Study)
                    AppTab.Today -> viewModel.selectTab(AppTab.Today)
                    else -> viewModel.selectTab(AppTab.Progress)
                }
            }
        }
        item {
            SectionTitle("Quick Add", "Start from the action, not from a long form.")
            Spacer(Modifier.height(10.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                item { QuickActionTile("Revision", Icons.Outlined.Psychology, Modifier.width(128.dp), GlassAccent) { viewModel.quickAddActivity("revision") } }
                item { QuickActionTile("Test", Icons.Outlined.Quiz, Modifier.width(128.dp), GlassWarning) { viewModel.quickAddActivity("test") } }
                item { QuickActionTile("Video", Icons.Outlined.Videocam, Modifier.width(128.dp), GlassAccent2) { viewModel.quickAddActivity("video") } }
                item { QuickActionTile("Reading", Icons.Outlined.MenuBook, Modifier.width(128.dp), GlassSuccess) { viewModel.quickAddActivity("reading") } }
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                HomeInsightMini("Recent result", latestTest?.primaryMetric ?: "No test yet", latestTest?.item?.displayName ?: "Add a mock test", Modifier.weight(1f), Icons.Outlined.Quiz)
                HomeInsightMini("Weak topic", weakTopic, "Based on pending mistakes", Modifier.weight(1f), Icons.Outlined.ErrorOutline)
            }
        }
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                SectionTitle("Recent Activity", "Latest saved sessions from Supabase")
                Spacer(Modifier.height(10.dp))
                if (entries.isEmpty()) {
                    Text("No activity yet. Use + to add your first study session.", color = GlassMuted)
                } else {
                    entries.take(5).forEach { entry ->
                        ActivityTimelineRow(entry) { viewModel.openStudyEntryDetails(entry.id) }
                        if (entry != entries.take(5).last()) Divider(color = Color.White.copy(alpha = 0.08f))
                    }
                }
            }
        }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun HomeInsightMini(title: String, value: String, subtitle: String, modifier: Modifier, icon: ImageVector) {
    GlassCard(modifier, radius = 26.dp, contentPadding = 14.dp) {
        Icon(icon, contentDescription = null, tint = GlassAccent, modifier = Modifier.size(24.dp))
        Spacer(Modifier.height(8.dp))
        Text(title, color = GlassMuted, style = MaterialTheme.typography.labelMedium)
        Text(value, color = GlassInk, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(subtitle, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun ActivityTimelineRow(entry: StudyEntry, onClick: () -> Unit) {
    PressableCard(Modifier.fillMaxWidth().padding(vertical = 4.dp), radius = 22.dp, onClick = onClick) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(38.dp).clip(CircleShape).background(activityColor(entry.activityType).copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                Icon(activityIcon(entry.activityType), contentDescription = null, tint = activityColor(entry.activityType), modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(entry.item.displayName, color = GlassInk, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${humanStatus(entry.activityType)} • ${entry.sessionDate} • ${entry.primaryMetric}", color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text("View", color = GlassAccent, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun TodayScreen(state: AppUiState, viewModel: AppViewModel) {
    if (state.selectedModule == ModuleChoice.Daily || state.daily.activeTasks.isNotEmpty()) {
        DailyMissionScreen(state, viewModel)
    } else {
        StudyMissionScreen(state, viewModel)
    }
}

@Composable
private fun DailyMissionScreen(state: AppUiState, viewModel: AppViewModel) {
    var search by rememberSaveable { mutableStateOf("") }
    val daily = state.daily
    val active = daily.activeTasks.filter { task ->
        val q = search.trim().lowercase()
        q.isBlank() || listOf(task.title, task.category, task.platform, task.section, task.target).any { it.lowercase().contains(q) }
    }
    val grouped = active.groupBy { it.category }

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassSuccess.copy(alpha = 0.16f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Today’s Mission", color = GlassInk, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
                        Text("${daily.completedActive}/${daily.activeTasks.size} complete • Draft saves locally until submit", color = GlassMuted)
                    }
                    ProgressRing(daily.completionRate, "${(daily.completionRate * 100).roundToInt()}%", ringColor = GlassSuccess)
                }
                Spacer(Modifier.height(12.dp))
                GlassTextField(search, { search = it }, "Search mission tasks", trailing = { Icon(Icons.Outlined.Search, null) })
                Spacer(Modifier.height(12.dp))
                PrimaryGlassButton("Submit Today", Modifier.fillMaxWidth(), enabled = active.isNotEmpty()) { viewModel.submitToday() }
            }
        }
        if (active.isEmpty()) item { EmptyState("No active tasks", "Use settings to reset defaults or create tasks in your Daily project.", "Reset defaults") { viewModel.resetDefaultTasks() } }
        grouped.forEach { (category, tasks) ->
            item {
                GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                    SectionTitle(category, "${tasks.count { daily.mergedStatus[it.id] == true }}/${tasks.size} complete")
                    Spacer(Modifier.height(8.dp))
                    tasks.forEach { task ->
                        DailyTaskRow(task = task, checked = daily.mergedStatus[task.id] == true) { checked -> viewModel.setDailyTaskChecked(task.id, checked) }
                        Divider(color = Color.White.copy(alpha = 0.08f))
                    }
                }
            }
        }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun StudyMissionScreen(state: AppUiState, viewModel: AppViewModel) {
    val localStates = remember { mutableStateMapOf<String, Boolean>() }
    val missions = studyMissions(state)
    val complete = missions.count { localStates[it.first] == true }
    val progress = if (missions.isEmpty()) 0f else complete.toFloat() / missions.size.toFloat()

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassAccent2.copy(alpha = 0.16f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Today’s Mission", color = GlassInk, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
                        Text("$complete/${missions.size} local mission steps • Supabase data stays unchanged", color = GlassMuted)
                    }
                    ProgressRing(progress, "${(progress * 100).roundToInt()}%", ringColor = GlassAccent2)
                }
            }
        }
        missions.forEach { mission ->
            item {
                PressableCard(Modifier.fillMaxWidth(), radius = 26.dp, onClick = { localStates[mission.first] = !(localStates[mission.first] ?: false) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = localStates[mission.first] == true, onCheckedChange = { localStates[mission.first] = it })
                        Column(Modifier.weight(1f)) {
                            Text(mission.first, color = GlassInk, fontWeight = FontWeight.Bold)
                            Text(mission.second, color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                        }
                        Text(mission.third, color = GlassAccent, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        item {
            InsightCard("Evening Review", "Finish your day by reviewing missed questions and adding notes while memory is fresh.", "Open Mistake Book") {
                viewModel.selectTab(AppTab.Mistakes)
            }
        }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun DailyTaskRow(task: DailyTask, checked: Boolean, onChecked: (Boolean) -> Unit) {
    PressableCard(modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp), radius = 22.dp, onClick = { onChecked(!checked) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = checked, onCheckedChange = onChecked)
            Column(Modifier.weight(1f)) {
                Text(task.title, color = if (checked) GlassSuccess else GlassInk, fontWeight = FontWeight.SemiBold)
                Text(listOf(task.platform, task.section, task.target).filter { it.isNotBlank() }.joinToString(" / "), color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2)
            }
            PriorityChip(task.priority)
        }
    }
}

@Composable
private fun PriorityChip(priority: String) {
    val color = when (priority) { "High" -> GlassDanger; "Low" -> GlassMuted; else -> GlassWarning }
    Box(Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.16f)).padding(horizontal = 10.dp, vertical = 6.dp)) {
        Text(priority.ifBlank { "Medium" }, color = color, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun StudyScreen(state: AppUiState, viewModel: AppViewModel) {
    if (state.selectedModule != ModuleChoice.Study) {
        SwitchToStudyState(viewModel)
        return
    }
    val study = state.study
    val platforms = listOf("All") + study.catalog.map { it.platformName }.filter { it.isNotBlank() }.distinct().sorted()
    val activities = listOf("All", "revision", "test", "video", "reading")
    val filtered = filteredCatalog(study)
    val recentItems = study.entries.map { it.item }.distinctBy { it.id }.take(8)
    val favoriteItems = study.catalog.filter { it.id in study.favoriteItemIds }

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassAccent.copy(alpha = 0.16f)) {
                SectionTitle("Study Flow", "Choose activity → pick source → enter result. Recently used stays at top.")
                Spacer(Modifier.height(14.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActivityTypeCard("Revision", "revision", Icons.Outlined.Psychology, state, viewModel, Modifier.weight(1f))
                    ActivityTypeCard("Test", "test", Icons.Outlined.Quiz, state, viewModel, Modifier.weight(1f))
                }
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActivityTypeCard("Video", "video", Icons.Outlined.Videocam, state, viewModel, Modifier.weight(1f))
                    ActivityTypeCard("Reading", "reading", Icons.Outlined.MenuBook, state, viewModel, Modifier.weight(1f))
                }
            }
        }
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                GlassTextField(study.search, viewModel::setStudySearch, "Search platform, topic, mock...", trailing = { Icon(Icons.Outlined.Search, null) })
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    activities.forEach { ChoiceChip(humanStatus(it), study.activityFilter == it) { viewModel.setStudyActivityFilter(it) } }
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    platforms.forEach { ChoiceChip(it, study.platformFilter == it) { viewModel.setStudyPlatformFilter(it) } }
                }
            }
        }
        if (recentItems.isNotEmpty()) {
            item { SectionTitle("Recently Used", "Fast start from your latest activity") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(recentItems, key = { it.id }) { item -> StudyMiniItem(item, state.study.favoriteItemIds.contains(item.id), viewModel, Modifier.width(236.dp)) }
                }
            }
        }
        if (favoriteItems.isNotEmpty()) {
            item { SectionTitle("Favorites", "Pinned locally on this device") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(favoriteItems, key = { it.id }) { item -> StudyMiniItem(item, true, viewModel, Modifier.width(236.dp)) }
                }
            }
        }
        if (filtered.isEmpty()) item { EmptyState("No catalog items", "Try clearing search/filter or run your study catalog SQL in Supabase.", "Clear filters") { viewModel.setStudySearch(""); viewModel.setStudyActivityFilter("All"); viewModel.setStudyPlatformFilter("All") } }
        items(filtered, key = { it.id }) { item -> StudyCatalogCard(item, state.study.favoriteItemIds.contains(item.id), viewModel) }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun ActivityTypeCard(label: String, type: String, icon: ImageVector, state: AppUiState, viewModel: AppViewModel, modifier: Modifier) {
    val selected = state.study.activityFilter == type
    PressableCard(modifier = modifier, radius = 24.dp, onClick = { viewModel.setStudyActivityFilter(if (selected) "All" else type) }) {
        Icon(icon, contentDescription = null, tint = if (selected) GlassSuccess else GlassAccent, modifier = Modifier.size(26.dp))
        Spacer(Modifier.height(8.dp))
        Text(label, color = GlassInk, fontWeight = FontWeight.Black)
        Text("${state.study.catalog.count { it.activityType == type }} items", color = GlassMuted, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun StudyMiniItem(item: CatalogItem, favorite: Boolean, viewModel: AppViewModel, modifier: Modifier) {
    PressableCard(modifier = modifier, radius = 24.dp, onClick = { viewModel.openStudyForm(item) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(item.platformIcon.ifBlank { "•" }, style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(item.displayName, color = GlassInk, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(item.platformName, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 1)
            }
            IconButton(onClick = { viewModel.toggleFavorite(item.id) }) {
                Icon(if (favorite) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, contentDescription = "Favorite", tint = if (favorite) GlassDanger else GlassMuted)
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(humanStatus(item.activityType), color = activityColor(item.activityType), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun StudyCatalogCard(item: CatalogItem, favorite: Boolean, viewModel: AppViewModel) {
    PressableCard(Modifier.fillMaxWidth(), radius = 28.dp, onClick = { viewModel.openStudyForm(item) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(activityColor(item.activityType).copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
                Text(item.platformIcon.ifBlank { item.platformName.take(1).ifBlank { "S" } }, color = GlassInk, fontWeight = FontWeight.Black)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(item.displayName, color = GlassInk, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(item.fullPath.ifBlank { "${item.platformName} / ${item.mainCategory}" }, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SmallPill(humanStatus(item.activityType), activityColor(item.activityType))
                    if (item.targetCount != null) SmallPill("Target ${item.targetCount}", GlassMuted)
                }
            }
            IconButton(onClick = { viewModel.toggleFavorite(item.id) }) { Icon(if (favorite) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, contentDescription = "Favorite", tint = if (favorite) GlassDanger else GlassMuted) }
        }
    }
}

@Composable
private fun SmallPill(text: String, color: Color) {
    Box(Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.14f)).padding(horizontal = 9.dp, vertical = 5.dp)) {
        Text(text, color = color, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
private fun MistakesScreen(state: AppUiState, viewModel: AppViewModel) {
    if (state.selectedModule != ModuleChoice.Study) {
        SwitchToStudyState(viewModel)
        return
    }
    val filters = listOf("All", "wrong", "skipped", "unseen", "New", "Reviewing", "Fixed")
    val mistakes = state.study.mistakes.filter { m ->
        val f = state.study.mistakeFilter
        f == "All" || m.issueType == f || m.reviewStatus == f
    }
    val pending = state.study.mistakes.count { it.reviewStatus != "Fixed" }
    val weakTopic = state.study.mistakes.groupingBy { it.item.displayName }.eachCount().maxByOrNull { it.value }?.key ?: "No weak topic yet"

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassDanger.copy(alpha = 0.12f)) {
                SectionTitle("Mistake Book", "Submitted activities first, then wrong/skipped/unseen question review from missed_questions.")
                Spacer(Modifier.height(14.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    InfoTile("Pending", pending.toString(), Modifier.weight(1f), GlassDanger)
                    InfoTile("Weak topic", weakTopic, Modifier.weight(1f), GlassWarning)
                }
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    filters.forEach { ChoiceChip(it, state.study.mistakeFilter == it) { viewModel.setMistakeFilter(it) } }
                }
            }
        }
        if (state.study.entries.isNotEmpty()) {
            item { SectionTitle("Submitted Activities", "Every saved revision, mock, video, and reading entry. Tap to see the exact fields you submitted.") }
            items(state.study.entries.take(30), key = { "submitted_${it.id}" }) { entry ->
                SubmittedEntryCard(entry = entry, state = state, viewModel = viewModel)
            }
            item { SectionTitle("Missed Question Review", "Only wrong, skipped, and unseen questions are listed below.") }
        }
        if (mistakes.isEmpty()) item { EmptyState("No mistakes here", "After you save test missed questions, they appear as review cards here. Submitted activities still remain visible above.", "Add Test") { viewModel.quickAddActivity("test") } }
        items(mistakes, key = { it.id }) { mistake -> MistakeCard(mistake, viewModel) }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun SubmittedEntryCard(entry: StudyEntry, state: AppUiState, viewModel: AppViewModel) {
    val missed = state.study.mistakes.filter { it.sessionId == entry.id }
    PressableCard(Modifier.fillMaxWidth(), radius = 26.dp, onClick = { viewModel.openStudyEntryDetails(entry.id) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(42.dp).clip(CircleShape).background(activityColor(entry.activityType).copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
                Icon(activityIcon(entry.activityType), contentDescription = null, tint = activityColor(entry.activityType), modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(entry.item.displayName, color = GlassInk, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${humanStatus(entry.activityType)} • ${entry.sessionDate} • ${entry.item.platformName}", color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            SmallPill(entry.primaryMetric, activityColor(entry.activityType))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            InfoTile("Saved fields", entry.details.size.toString(), Modifier.weight(1f), GlassAccent)
            InfoTile("Missed", (if (entry.activityType == "test") missed.size else entry.missedCount).toString(), Modifier.weight(1f), GlassDanger)
        }
    }
}

@Composable
private fun MistakeCard(mistake: MistakeRecord, viewModel: AppViewModel) {
    var expanded by rememberSaveable(mistake.id) { mutableStateOf(false) }
    PressableCard(Modifier.fillMaxWidth(), radius = 28.dp, onClick = { expanded = !expanded }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SmallPill(humanStatus(mistake.issueType), when (mistake.issueType) { "wrong" -> GlassDanger; "skipped" -> GlassWarning; else -> GlassAccent })
            Spacer(Modifier.width(8.dp))
            SmallPill(mistake.reviewStatus, if (mistake.reviewStatus == "Fixed") GlassSuccess else GlassMuted)
            Spacer(Modifier.weight(1f))
            Text("Q${mistake.questionNumber}", color = GlassInk, fontWeight = FontWeight.Black)
        }
        Spacer(Modifier.height(10.dp))
        Text(mistake.item.displayName, color = GlassInk, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("${mistake.item.platformName} • ${mistake.sessionDate}", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        Text(mistake.questionText.ifBlank { "No question text saved" }, color = GlassInk, maxLines = if (expanded) 8 else 2, overflow = TextOverflow.Ellipsis)
        AnimatedVisibility(expanded, enter = fadeIn(AppMotion.mediumTween()), exit = fadeOut(AppMotion.fastTween())) {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (mistake.optionsText.isNotBlank()) Text("Options: ${mistake.optionsText}", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                Text("Your answer: ${mistake.selectedOptionKey.ifBlank { "--" }}", color = GlassMuted)
                Text("Correct answer: ${mistake.correctOptionKey.ifBlank { "--" }}", color = GlassSuccess)
                Text("Time: ${durationToText(mistake.questionTimeSeconds)}", color = GlassMuted)
                if (mistake.questionNote.isNotBlank()) Text("Note: ${mistake.questionNote}", color = GlassMuted)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { viewModel.markMistakeStatus(mistake.id, "Reviewing") }, modifier = Modifier.weight(1f)) { Text("Reviewing") }
                    PrimaryGlassButton("Mark fixed", Modifier.weight(1f)) { viewModel.markMistakeStatus(mistake.id, "Fixed") }
                }
                GhostGlassButton("View source submitted test", Modifier.fillMaxWidth()) { viewModel.openStudyEntryDetails(mistake.sessionId) }
            }
        }
    }
}

@Composable
private fun ProgressScreen(state: AppUiState, viewModel: AppViewModel) {
    if (state.selectedModule != ModuleChoice.Study) {
        SwitchToStudyState(viewModel)
        return
    }
    val entries = state.study.entries
    val tests = entries.filter { it.activityType == "test" }
    val avgAccuracy = tests.mapNotNull { it.accuracyPercent }.averageOrNull()
    val avgCompletion = entries.mapNotNull { it.completionPercent }.averageOrNull()
    val avgScore = tests.mapNotNull { it.scorePercent }.averageOrNull()
    val byType = entries.groupingBy { it.activityType }.eachCount()
    val byPlatform = entries.groupingBy { it.item.platformName.ifBlank { "Unknown" } }.eachCount().entries.sortedByDescending { it.value }.take(5)
    var selectedAnalyticsType by rememberSaveable { mutableStateOf("All") }

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 20.dp, accent = GlassSuccess.copy(alpha = 0.13f)) {
                SectionTitle("Progress Analytics", "Visual insights calculated from existing Supabase raw facts.")
                Spacer(Modifier.height(14.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    InfoTile("Avg accuracy", avgAccuracy.percentText(), Modifier.weight(1f), GlassSuccess)
                    InfoTile("Tests", tests.size.toString(), Modifier.weight(1f), GlassWarning)
                }
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    InfoTile("Mistakes", state.study.mistakes.size.toString(), Modifier.weight(1f), GlassDanger)
                    InfoTile("Entries", entries.size.toString(), Modifier.weight(1f), GlassAccent)
                }
            }
        }
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                SectionTitle("Trend Summary", "Animated bars from current activity data")
                Spacer(Modifier.height(12.dp))
                MetricBar("Accuracy", avgAccuracy ?: 0.0, GlassSuccess)
                MetricBar("Completion", avgCompletion ?: 0.0, GlassAccent)
                MetricBar("Score", avgScore ?: 0.0, GlassWarning)
            }
        }
        item {
            AnalyticsChooserCard(
                entries = entries,
                mistakes = state.study.mistakes,
                selectedType = selectedAnalyticsType,
                onTypeSelected = { selectedAnalyticsType = it }
            )
        }
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                SectionTitle("Activity Distribution", "Where your study time is going")
                Spacer(Modifier.height(10.dp))
                listOf("revision", "test", "video", "reading").forEach { type ->
                    val count = byType[type] ?: 0
                    Text("${humanStatus(type)} • $count", color = GlassInk, fontWeight = FontWeight.SemiBold)
                    ProgressLine(if (entries.isEmpty()) 0f else count.toFloat() / entries.size.toFloat(), Modifier.fillMaxWidth().padding(vertical = 6.dp))
                }
            }
        }
        item {
            GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
                SectionTitle("Platform Performance", "Most used platforms")
                Spacer(Modifier.height(10.dp))
                if (byPlatform.isEmpty()) Text("No platform data yet.", color = GlassMuted)
                byPlatform.forEach { item ->
                    Text("${item.key} • ${item.value}", color = GlassInk, fontWeight = FontWeight.SemiBold)
                    ProgressLine(item.value.toFloat() / (byPlatform.maxOfOrNull { it.value } ?: 1).toFloat(), Modifier.fillMaxWidth().padding(vertical = 6.dp))
                }
            }
        }
        item { CalendarPreview(entries, state.study.mistakes) }
        item {
            val insight = progressInsight(state)
            InsightCard(insight.first, insight.second, "Open Study") { viewModel.selectTab(AppTab.Study) }
        }
        item { Spacer(Modifier.height(138.dp)) }
    }
}

@Composable
private fun MetricBar(label: String, value: Double, color: Color) {
    Text("$label ${"%.1f".format(value.coerceIn(0.0, 100.0))}%", color = GlassInk, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(6.dp))
    ProgressLine((value.coerceIn(0.0, 100.0) / 100.0).toFloat(), Modifier.fillMaxWidth())
    Spacer(Modifier.height(10.dp))
}

private data class ChartSegment(val label: String, val value: Float, val color: Color)

@Composable
private fun AnalyticsChooserCard(entries: List<StudyEntry>, mistakes: List<MistakeRecord>, selectedType: String, onTypeSelected: (String) -> Unit) {
    val options = listOf("All", "test", "video", "revision", "reading")
    GlassCard(Modifier.fillMaxWidth(), radius = 28.dp, accent = GlassAccent.copy(alpha = 0.10f)) {
        SectionTitle("Visual Analytics", "Choose exactly what you want to understand: mock, video, revision, or reading.")
        Spacer(Modifier.height(10.dp))
        OptionChips(options, selectedType) { onTypeSelected(it) }
        Spacer(Modifier.height(16.dp))
        if (selectedType == "All") {
            val segments = listOf("test", "video", "revision", "reading").map { type ->
                ChartSegment(humanStatus(type), entries.count { it.activityType == type }.toFloat(), activityColor(type))
            }
            DonutChartWithLegend(segments = segments, centerText = entries.size.toString(), centerLabel = "entries")
        } else {
            TypeSpecificAnalytics(entries = entries.filter { it.activityType == selectedType }, mistakes = mistakes, type = selectedType)
        }
    }
}

@Composable
private fun DonutChartWithLegend(segments: List<ChartSegment>, centerText: String, centerLabel: String) {
    val nonZero = segments.filter { it.value > 0f }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(168.dp), contentAlignment = Alignment.Center) {
            DonutChart(nonZero.ifEmpty { listOf(ChartSegment("No data", 1f, GlassMuted.copy(alpha = 0.35f))) })
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(centerText, color = GlassInk, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleLarge)
                Text(centerLabel, color = GlassMuted, style = MaterialTheme.typography.labelSmall)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (nonZero.isEmpty()) Text("No saved data yet. Add one activity from +.", color = GlassMuted)
            nonZero.forEach { segment ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Dot(segment.color)
                    Spacer(Modifier.width(8.dp))
                    Text("${segment.label} • ${segment.value.roundToInt()}", color = GlassInk, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun DonutChart(segments: List<ChartSegment>, modifier: Modifier = Modifier.fillMaxSize()) {
    val total = segments.sumOf { it.value.toDouble() }.toFloat().coerceAtLeast(1f)
    Canvas(modifier = modifier) {
        val stroke = Stroke(width = 24.dp.toPx(), cap = StrokeCap.Round)
        var startAngle = -90f
        segments.forEach { segment ->
            val sweep = (segment.value / total) * 360f
            drawArc(
                color = segment.color,
                startAngle = startAngle,
                sweepAngle = sweep.coerceAtLeast(if (segment.value > 0f) 3f else 0f),
                useCenter = false,
                style = stroke
            )
            startAngle += sweep
        }
    }
}

@Composable
private fun TypeSpecificAnalytics(entries: List<StudyEntry>, mistakes: List<MistakeRecord>, type: String) {
    val latest = entries.take(8).reversed()
    val metricValues = latest.map { entry ->
        when (type) {
            "test" -> entry.accuracyPercent ?: entry.scorePercent ?: 0.0
            "video", "revision", "reading" -> entry.completionPercent ?: 0.0
            else -> 0.0
        }.toFloat().coerceIn(0f, 100f)
    }
    val avg = if (metricValues.isEmpty()) 0.0 else metricValues.average()
    val unresolved = if (type == "test") mistakes.count { it.reviewStatus != "Fixed" } else 0
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        InfoTile("Sessions", entries.size.toString(), Modifier.weight(1f), activityColor(type))
        InfoTile(if (type == "test") "Avg accuracy" else "Avg progress", avg.percentText(), Modifier.weight(1f), GlassSuccess)
    }
    if (type == "test") {
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            InfoTile("Unfixed mistakes", unresolved.toString(), Modifier.weight(1f), GlassDanger)
            InfoTile("Last missed", entries.firstOrNull()?.missedCount?.toString() ?: "0", Modifier.weight(1f), GlassWarning)
        }
    }
    Spacer(Modifier.height(14.dp))
    MiniBarChart(values = metricValues, color = activityColor(type), emptyText = "No ${humanStatus(type)} entries yet.")
    Spacer(Modifier.height(8.dp))
    latest.forEach { entry ->
        DetailLine(entry.sessionDate, "${entry.item.displayName} • ${entry.primaryMetric}")
    }
}

@Composable
private fun MiniBarChart(values: List<Float>, color: Color, emptyText: String) {
    if (values.isEmpty()) {
        Text(emptyText, color = GlassMuted)
        return
    }
    Canvas(Modifier.fillMaxWidth().height(150.dp)) {
        val gap = 8.dp.toPx()
        val barWidth = ((size.width - gap * (values.size - 1)) / values.size).coerceAtLeast(8.dp.toPx())
        values.forEachIndexed { index, raw ->
            val normalized = raw.coerceIn(0f, 100f) / 100f
            val height = (size.height * normalized).coerceAtLeast(6.dp.toPx())
            val left = index * (barWidth + gap)
            drawRoundRect(
                color = color.copy(alpha = 0.86f),
                topLeft = androidx.compose.ui.geometry.Offset(left, size.height - height),
                size = androidx.compose.ui.geometry.Size(barWidth, height),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx(), 8.dp.toPx())
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CalendarPreview(entries: List<StudyEntry>, mistakes: List<MistakeRecord>) {
    val days = (13 downTo 0).map { LocalDate.now().minusDays(it.toLong()).toString() }
    GlassCard(Modifier.fillMaxWidth(), radius = 28.dp) {
        SectionTitle("Study Calendar", "Green = study, red = mistakes, yellow = test")
        Spacer(Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            days.forEach { day ->
                val hasEntry = entries.any { it.sessionDate == day }
                val hasTest = entries.any { it.sessionDate == day && it.activityType == "test" }
                val hasMistake = mistakes.any { it.sessionDate == day }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
                        Text(day.takeLast(2), color = GlassInk, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        if (hasEntry) Dot(GlassSuccess)
                        if (hasTest) Dot(GlassWarning)
                        if (hasMistake) Dot(GlassDanger)
                    }
                }
            }
        }
    }
}

@Composable
private fun Dot(color: Color) { Box(Modifier.size(5.dp).clip(CircleShape).background(color)) }

@Composable
private fun SwitchToStudyState(viewModel: AppViewModel) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        EmptyState("Study project not selected", "This screen uses the Study Pulse Pro Supabase project with catalog, tests, mistakes, and analytics.", "Switch to Study") {
            viewModel.selectModule(ModuleChoice.Study)
        }
    }
}

@Composable
private fun TimerMiniPlayer(timer: StudyTimerState, onPause: () -> Unit, onResume: () -> Unit, onStop: () -> Unit, modifier: Modifier = Modifier) {
    AnimatedVisibility(visible = timer.active, enter = fadeIn(AppMotion.mediumTween()) + slideInVertically(AppMotion.mediumTween()) { it }, exit = fadeOut(AppMotion.fastTween())) {
        GlassCard(modifier = modifier.fillMaxWidth(), radius = 28.dp, contentPadding = 12.dp, accent = GlassAccent.copy(alpha = 0.16f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ProgressRing(timer.progress, formatSeconds(timer.remainingSeconds), Modifier.size(68.dp), ringColor = GlassAccent)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(timer.mode, color = GlassInk, fontWeight = FontWeight.Black)
                    Text(if (timer.running) "Focus running" else if (timer.completed) "Timer complete" else "Paused", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                }
                IconButton(onClick = if (timer.running) onPause else onResume) { Icon(if (timer.running) Icons.Outlined.Pause else Icons.Outlined.PlayArrow, contentDescription = null, tint = GlassInk) }
                IconButton(onClick = onStop) { Icon(Icons.Outlined.Stop, contentDescription = null, tint = GlassDanger) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StudyEntryDetailSheet(entry: StudyEntry, state: AppUiState, viewModel: AppViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val missed = state.study.mistakes.filter { it.sessionId == entry.id }.sortedBy { it.questionNumber }
    ModalBottomSheet(onDismissRequest = viewModel::closeStudyEntryDetails, sheetState = sheetState, containerColor = Color(0xFF0B1020), contentColor = GlassInk) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 780.dp).navigationBarsPadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                SectionTitle("Submitted Detail", "Exact saved result from Supabase", action = { IconButton(onClick = viewModel::closeStudyEntryDetails) { Icon(Icons.Outlined.Close, null, tint = GlassInk) } })
            }
            item {
                GlassCard(Modifier.fillMaxWidth(), radius = 28.dp, accent = activityColor(entry.activityType).copy(alpha = 0.14f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(48.dp).clip(CircleShape).background(activityColor(entry.activityType).copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                            Icon(activityIcon(entry.activityType), contentDescription = null, tint = activityColor(entry.activityType), modifier = Modifier.size(24.dp))
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(entry.item.displayName, color = GlassInk, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
                            Text(entry.item.fullPath, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        InfoTile("Type", humanStatus(entry.activityType), Modifier.weight(1f), activityColor(entry.activityType))
                        InfoTile("Date", entry.sessionDate, Modifier.weight(1f), GlassMuted)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        InfoTile("Primary", entry.primaryMetric, Modifier.weight(1f), GlassAccent)
                        InfoTile("Secondary", entry.secondaryMetric, Modifier.weight(1f), GlassWarning)
                    }
                }
            }
            item {
                GlassCard(Modifier.fillMaxWidth(), radius = 26.dp) {
                    SectionTitle("What you submitted", "Only the fields that exist for this activity are shown.")
                    Spacer(Modifier.height(10.dp))
                    if (entry.details.isEmpty()) {
                        Text("No extra details saved for this entry.", color = GlassMuted)
                    } else {
                        entry.details.forEach { (label, value) -> DetailLine(label, value) }
                    }
                }
            }
            if (entry.activityType == "test") {
                item {
                    GlassCard(Modifier.fillMaxWidth(), radius = 26.dp, accent = GlassDanger.copy(alpha = 0.10f)) {
                        SectionTitle("Inside Submitted Test", "Missed questions linked to this exact test attempt")
                        Spacer(Modifier.height(10.dp))
                        if (missed.isEmpty()) {
                            Text("No missed questions were stored for this test.", color = GlassMuted)
                        } else {
                            missed.forEach { mistake ->
                                DetailLine("Q${mistake.questionNumber} • ${humanStatus(mistake.issueType)}", mistake.questionText.ifBlank { "No question text saved" })
                                if (mistake.optionsText.isNotBlank()) DetailLine("Options", mistake.optionsText)
                                DetailLine("Your answer", mistake.selectedOptionKey.ifBlank { "--" })
                                DetailLine("Correct answer", mistake.correctOptionKey.ifBlank { "--" })
                                if (mistake.questionNote.isNotBlank()) DetailLine("Note", mistake.questionNote)
                                Divider(color = Color.White.copy(alpha = 0.08f), modifier = Modifier.padding(vertical = 8.dp))
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(22.dp)) }
        }
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, color = GlassMuted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(0.42f))
        Text(value.ifBlank { "--" }, color = GlassInk, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(0.58f))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddActivitySheet(state: AppUiState, viewModel: AppViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val selectedType = state.selectedAddActivityType
    ModalBottomSheet(onDismissRequest = viewModel::closeAddActivitySheet, sheetState = sheetState, containerColor = Color(0xFF0B1020), contentColor = GlassInk) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 780.dp).navigationBarsPadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (selectedType == null) {
                item { SmartAddTypePicker(state, viewModel) }
            } else {
                item { SmartAddSourcePickerHeader(selectedType, viewModel) }
                val itemsForType = smartAddItemsForType(state, selectedType)
                if (itemsForType.isEmpty()) {
                    item {
                        GlassCard(Modifier.fillMaxWidth(), radius = 26.dp, accent = activityColor(selectedType).copy(alpha = 0.14f)) {
                            Text("No ${humanStatus(selectedType)} source exists yet", color = GlassInk, fontWeight = FontWeight.Black)
                            Spacer(Modifier.height(6.dp))
                            Text("Create a reusable source/category first. After that, today's progress/result will be logged against that exact source.", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                            Spacer(Modifier.height(12.dp))
                            PrimaryGlassButton("Create new ${humanStatus(selectedType)} source", Modifier.fillMaxWidth()) { viewModel.openCatalogCreator(selectedType) }
                        }
                    }
                } else {
                    item {
                        GlassCard(Modifier.fillMaxWidth(), radius = 24.dp, accent = activityColor(selectedType).copy(alpha = 0.10f)) {
                            Text("Log today's ${humanStatus(selectedType)}", color = GlassInk, fontWeight = FontWeight.Black)
                            Text("Choose the exact source first. The app will open the correct database-backed form for that source.", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    items(itemsForType.take(12), key = { it.id }) { item ->
                        SmartAddCatalogRow(item) { viewModel.openExistingCatalogItem(item) }
                    }
                    item {
                        GlassCard(Modifier.fillMaxWidth(), radius = 24.dp) {
                            Text("Missing source/category?", color = GlassInk, fontWeight = FontWeight.Black)
                            Text("Add it once, then use it daily. This writes a new study_items catalog row, not a risky new SQL table from the phone.", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                            Spacer(Modifier.height(10.dp))
                            PrimaryGlassButton("Create new ${humanStatus(selectedType)} source", Modifier.fillMaxWidth()) { viewModel.openCatalogCreator(selectedType) }
                        }
                    }
                }
            }
            item {
                GlassCard(Modifier.fillMaxWidth(), radius = 24.dp) {
                    Text("Timer Modes", color = GlassInk, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(10.dp))
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("Pomodoro 25", "Deep Work 50", "Short Review 10").forEach { mode -> ChoiceChip(mode, false) { viewModel.startTimer(mode); viewModel.closeAddActivitySheet() } }
                    }
                }
            }
            item { Spacer(Modifier.height(12.dp)) }
        }
    }
}

@Composable
private fun SmartAddTypePicker(state: AppUiState, viewModel: AppViewModel) {
    val subtitle = when (state.currentTab) {
        AppTab.Home -> "Quick launcher: choose what you want to submit or create."
        AppTab.Today -> "Only today's work: log a session, mock, video, reading, or review mistakes."
        AppTab.Study -> "Catalog-aware add: choose a type, then log existing source or create a new one."
        AppTab.Mistakes -> "Mistake flow: add a test with missed questions or review existing mistakes."
        AppTab.Progress -> "Progress is calculated from submitted entries. Add real data, not duplicate analytics."
    }
    SectionTitle("Smart Add", subtitle)
    Spacer(Modifier.height(12.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        QuickActionTile("Mock/Test", Icons.Outlined.Quiz, Modifier.weight(1f), GlassWarning) { viewModel.chooseAddActivityType("test") }
        QuickActionTile("Video", Icons.Outlined.Videocam, Modifier.weight(1f), GlassAccent2) { viewModel.chooseAddActivityType("video") }
    }
    Spacer(Modifier.height(10.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        QuickActionTile("Revision", Icons.Outlined.Psychology, Modifier.weight(1f), GlassAccent) { viewModel.chooseAddActivityType("revision") }
        QuickActionTile("Reading", Icons.Outlined.MenuBook, Modifier.weight(1f), GlassSuccess) { viewModel.chooseAddActivityType("reading") }
    }
    Spacer(Modifier.height(10.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        QuickActionTile("Review mistakes", Icons.Outlined.ErrorOutline, Modifier.weight(1f), GlassDanger) { viewModel.quickAddActivity("mistake") }
        QuickActionTile("Timer", Icons.Outlined.Timer, Modifier.weight(1f), GlassAccent) { viewModel.quickAddActivity("timer") }
    }
    Spacer(Modifier.height(12.dp))
    GlassCard(Modifier.fillMaxWidth(), radius = 24.dp, accent = GlassAccent.copy(alpha = 0.10f)) {
        Text("How this Add works", color = GlassInk, fontWeight = FontWeight.Black)
        Text("First choose the type. Then either submit today's progress for an existing source or create a reusable source/category first.", color = GlassMuted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun SmartAddSourcePickerHeader(activityType: String, viewModel: AppViewModel) {
    SectionTitle("Add ${humanStatus(activityType)}", "Log today’s entry for an existing source, or create a new reusable category/source first.")
    Spacer(Modifier.height(8.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = viewModel::backToAddTypePicker, modifier = Modifier.weight(1f)) { Text("Back") }
        PrimaryGlassButton("New ${humanStatus(activityType)}", Modifier.weight(1f)) { viewModel.openCatalogCreator(activityType) }
    }
}

@Composable
private fun SmartAddCatalogRow(item: CatalogItem, onClick: () -> Unit) {
    PressableCard(Modifier.fillMaxWidth(), radius = 24.dp, onClick = onClick) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(42.dp).clip(CircleShape).background(activityColor(item.activityType).copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                Icon(activityIcon(item.activityType), contentDescription = null, tint = activityColor(item.activityType), modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(item.displayName, color = GlassInk, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(item.fullPath, color = GlassMuted, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (item.shortDescription.isNotBlank()) Text(item.shortDescription, color = GlassMuted, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(8.dp))
            Text("Log", color = GlassAccent, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelMedium)
        }
    }
}


@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CatalogCreatorSheet(state: AppUiState, viewModel: AppViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val draft = state.catalogDraft
    val templates = state.study.templates.filter { it.activityType == draft.activityType && it.isActive }
    ModalBottomSheet(onDismissRequest = viewModel::closeCatalogCreator, sheetState = sheetState, containerColor = Color(0xFF0B1020), contentColor = GlassInk) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 780.dp).navigationBarsPadding().imePadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { SectionTitle("New ${humanStatus(draft.activityType)} Source", "Creates a reusable catalog source/category for your private Supabase model. Submissions will be stored in the correct entry tables.", action = { IconButton(onClick = viewModel::closeCatalogCreator) { Icon(Icons.Outlined.Close, null, tint = GlassInk) } }) }
            item {
                FormSectionCard("Activity type", "Choose the type first so the app asks the right fields later.") {
                    OptionChips(listOf("test", "video", "revision", "reading"), draft.activityType) { type ->
                        val template = state.study.templates.firstOrNull { it.activityType == type && it.isActive }?.templateKey.orEmpty()
                        viewModel.updateCatalogDraft { it.copy(activityType = type, templateKey = template) }
                    }
                }
            }
            item {
                FormSectionCard("Catalog identity", "This becomes the exact source/category you can select again and again.") {
                    GlassTextField(draft.platformName, { value -> viewModel.updateCatalogDraft { it.copy(platformName = value) } }, when (draft.activityType) { "video" -> "Platform / class app *"; "test" -> "Mock platform/source *"; else -> "Platform / source name *" })
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GlassTextField(draft.platformIcon, { value -> viewModel.updateCatalogDraft { it.copy(platformIcon = value) } }, "Icon", Modifier.weight(0.35f))
                        GlassTextField(draft.mainCategory, { value -> viewModel.updateCatalogDraft { it.copy(mainCategory = value) } }, when (draft.activityType) { "video" -> "Course / subject *"; "test" -> "Main test category *"; "reading" -> "Reading category *"; else -> "Main category *" }, Modifier.weight(0.65f))
                    }
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.subCategory, { value -> viewModel.updateCatalogDraft { it.copy(subCategory = value) } }, when (draft.activityType) { "video" -> "Batch / playlist / chapter"; "test" -> "Section / bundle / topic"; else -> "Sub category" })
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.itemName, { value -> viewModel.updateCatalogDraft { it.copy(itemName = value) } }, when (draft.activityType) { "video" -> "Video series / topic name *"; "test" -> "Mock / test name *"; "reading" -> "Book / article / material name *"; else -> "Revision / item name *" })
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.displayName, { value -> viewModel.updateCatalogDraft { it.copy(displayName = value) } }, "Display name shown in app")
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.teacherOrSource, { value -> viewModel.updateCatalogDraft { it.copy(teacherOrSource = value) } }, when (draft.activityType) { "video" -> "Teacher name / channel"; "test" -> "Test creator / source"; else -> "Teacher / source" })
                }
            }
            item {
                FormSectionCard("Smart defaults", "These defaults make the later daily submission form accurate and fast.") {
                    GlassTextField(draft.targetCount, { value -> viewModel.updateCatalogDraft { it.copy(targetCount = value) } }, when (draft.activityType) { "test" -> "Total questions in this test"; "video" -> "Total videos in this source"; "revision" -> "Total revision target"; else -> "Target count" })
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.dailyTarget, { value -> viewModel.updateCatalogDraft { it.copy(dailyTarget = value) } }, when (draft.activityType) { "video" -> "How many videos per day"; "test" -> "How many mocks per day"; "revision" -> "Revision target per day"; else -> "Daily target" })
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.requiredFieldsNote, { value -> viewModel.updateCatalogDraft { it.copy(requiredFieldsNote = value) } }, "Special fields/rules for this source", singleLine = false, minLines = 2)
                    Spacer(Modifier.height(8.dp))
                    GlassTextField(draft.shortDescription, { value -> viewModel.updateCatalogDraft { it.copy(shortDescription = value) } }, "Short description", singleLine = false, minLines = 2)
                }
            }
            if (templates.isNotEmpty()) {
                item {
                    FormSectionCard("Form template", "The template controls which fields the app asks when you submit.") {
                        templates.forEach { template ->
                            ChoiceChip(template.templateKey, draft.templateKey == template.templateKey) {
                                viewModel.updateCatalogDraft { it.copy(templateKey = template.templateKey) }
                            }
                        }
                    }
                }
            }
            item {
                PrimaryGlassButton(if (state.loading) "Creating..." else "Create source and log today's entry", enabled = !state.loading, modifier = Modifier.fillMaxWidth()) { viewModel.createCatalogItem() }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(state: AppUiState, viewModel: AppViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var draft by remember(state.settings) { mutableStateOf(state.settings) }
    var deletePhrase by rememberSaveable { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = viewModel::closeSettingsSheet, sheetState = sheetState, containerColor = Color(0xFF0B1020), contentColor = GlassInk) {
        Column(Modifier.fillMaxWidth().heightIn(max = 760.dp).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle("Profile & Settings", "Local settings for the Android companion")
            GlassTextField(draft.displayName, { draft = draft.copy(displayName = it) }, "Display name")
            GlassTextField(draft.examTarget, { draft = draft.copy(examTarget = it) }, "Exam target")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GlassTextField(draft.dailyGoalMinutes.toString(), { draft = draft.copy(dailyGoalMinutes = it.toIntOrNull() ?: draft.dailyGoalMinutes) }, "Daily goal min", Modifier.weight(1f))
                GlassTextField(draft.weeklyMockGoal.toString(), { draft = draft.copy(weeklyMockGoal = it.toIntOrNull() ?: draft.weeklyMockGoal) }, "Weekly mocks", Modifier.weight(1f))
            }
            PrimaryGlassButton("Save settings", Modifier.fillMaxWidth()) { viewModel.saveLocalSettings(draft) }
            GlassCard(Modifier.fillMaxWidth(), radius = 24.dp) {
                Text("Active Supabase project", color = GlassInk, fontWeight = FontWeight.Black)
                Spacer(Modifier.height(8.dp))
                ModuleChoice.values().forEach { module ->
                    PressableCard(Modifier.fillMaxWidth(), radius = 20.dp, onClick = { viewModel.selectModule(module); viewModel.closeSettingsSheet() }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(module.title, color = GlassInk, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            if (state.selectedModule == module) Text("Active", color = GlassSuccess, fontWeight = FontWeight.Bold)
                        }
                        Text(module.projectId, color = GlassMuted, style = MaterialTheme.typography.bodySmall)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
            GlassCard(Modifier.fillMaxWidth(), radius = 24.dp) {
                SectionTitle("App Stats", "Calculated from loaded data")
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    InfoTile("Study days", state.study.entries.map { it.sessionDate }.distinct().size.toString(), Modifier.weight(1f))
                    InfoTile("Tests", state.study.entries.count { it.activityType == "test" }.toString(), Modifier.weight(1f))
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    InfoTile("Mistakes", state.study.mistakes.size.toString(), Modifier.weight(1f))
                    InfoTile("Fixed", state.study.mistakes.count { it.reviewStatus == "Fixed" }.toString(), Modifier.weight(1f))
                }
            }
            GlassCard(Modifier.fillMaxWidth(), radius = 24.dp, accent = GlassDanger.copy(alpha = 0.10f)) {
                SectionTitle("Strict Danger Zone", "Deletion requires exact typed confirmation so it is never tapped by mistake.")
                Spacer(Modifier.height(10.dp))
                GlassTextField(deletePhrase, { deletePhrase = it }, if (state.selectedModule == ModuleChoice.Study) "Type DELETE STUDY DATA" else "Type CLEAR DAILY HISTORY")
                Spacer(Modifier.height(10.dp))
                if (state.selectedModule == ModuleChoice.Study) {
                    OutlinedButton(onClick = { viewModel.clearStudyHistory(deletePhrase) }, enabled = deletePhrase == "DELETE STUDY DATA", modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Outlined.DeleteOutline, null); Spacer(Modifier.width(6.dp)); Text("Delete Study History Only")
                    }
                } else {
                    OutlinedButton(onClick = viewModel::clearDailyHistory, enabled = deletePhrase == "CLEAR DAILY HISTORY", modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Outlined.DeleteOutline, null); Spacer(Modifier.width(6.dp)); Text("Clear Daily History Only")
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = viewModel::resetDefaultTasks, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Outlined.RestartAlt, null); Spacer(Modifier.width(6.dp)); Text("Reset Daily Defaults") }
            }
            OutlinedButton(onClick = viewModel::signOut, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Outlined.Logout, null); Spacer(Modifier.width(8.dp)); Text("Logout") }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StudyFormSheet(state: AppUiState, form: ActiveStudyForm, viewModel: AppViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val fields = visibleFieldsFor(form.item, state.study.fieldsByTemplateKey, "session")
    ModalBottomSheet(onDismissRequest = viewModel::closeStudyForm, sheetState = sheetState, containerColor = Color(0xFF0B1020), contentColor = GlassInk) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 780.dp).navigationBarsPadding().imePadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                SectionTitle(form.item.formTitle.ifBlank { "Log ${humanStatus(form.item.activityType)}" }, form.item.fullPath, action = { IconButton(onClick = viewModel::closeStudyForm) { Icon(Icons.Outlined.Close, null, tint = GlassInk) } })
            }
            if (form.item.activityType == "test") {
                item { TestPreviewCard(form.values, form.missedQuestions.size) }
                item { FormSectionCard("Basic Result", "Score, duration, and total questions") { fields.filterKeys("total_questions", "max_marks", "marks_obtained", "total_duration_seconds", "time_taken_seconds").forEach { DynamicField(it, form.values[it.fieldKey].orEmpty()) { v -> viewModel.updateStudyField(it.fieldKey, v) } } } }
                item { FormSectionCard("Question Breakdown", "Right, wrong, skipped, unseen") { fields.filterKeys("right_count", "wrong_count", "skipped_count", "unseen_count").forEach { DynamicField(it, form.values[it.fieldKey].orEmpty()) { v -> viewModel.updateStudyField(it.fieldKey, v) } } } }
                item { FormSectionCard("Time Breakdown", "Utilized, wasted, correct/wrong/skipped time") { fields.filterKeys("utilized_seconds", "wasted_seconds", "correct_time_seconds", "wrong_time_seconds", "skipped_time_seconds").forEach { DynamicField(it, form.values[it.fieldKey].orEmpty()) { v -> viewModel.updateStudyField(it.fieldKey, v) } } } }
                item { FormSectionCard("Rank & Range", "Rank, percentile, and question range") { fields.filterKeys("rank", "total_rank", "percentile", "range_from", "range_to", "result_notes").forEach { DynamicField(it, form.values[it.fieldKey].orEmpty()) { v -> viewModel.updateStudyField(it.fieldKey, v) } } } }
                item {
                    FormSectionCard("Missed Questions", "Add wrong, skipped, or unseen questions") {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { viewModel.addMissedQuestion("wrong") }, modifier = Modifier.weight(1f)) { Text("Wrong") }
                            OutlinedButton(onClick = { viewModel.addMissedQuestion("skipped") }, modifier = Modifier.weight(1f)) { Text("Skipped") }
                            OutlinedButton(onClick = { viewModel.addMissedQuestion("unseen") }, modifier = Modifier.weight(1f)) { Text("Unseen") }
                        }
                        form.missedQuestions.forEachIndexed { index, q -> MissedQuestionEditor(index, q, viewModel) }
                    }
                }
            } else {
                item { FormSectionCard("${humanStatus(form.item.activityType)} Details", form.item.shortDescription) { fields.forEach { DynamicField(it, form.values[it.fieldKey].orEmpty()) { v -> viewModel.updateStudyField(it.fieldKey, v) } } } }
            }
            item {
                PrimaryGlassButton(if (form.saving) "Saving..." else "Save activity", enabled = !form.saving, modifier = Modifier.fillMaxWidth()) { viewModel.saveStudyActivity() }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun TestPreviewCard(values: Map<String, String>, missedCount: Int) {
    val right = values["right_count"].asInt()
    val wrong = values["wrong_count"].asInt()
    val skipped = values["skipped_count"].asInt()
    val unseen = values["unseen_count"].asInt()
    val attempted = right + wrong + skipped
    val accuracy = if (right + wrong > 0) right.toDouble() / (right + wrong).toDouble() * 100.0 else null
    val marks = values["marks_obtained"].asDouble()
    val max = values["max_marks"].asDouble()
    val score = if (max != null && max > 0.0 && marks != null) marks / max * 100.0 else null
    GlassCard(Modifier.fillMaxWidth(), radius = 28.dp, accent = GlassWarning.copy(alpha = 0.14f)) {
        SectionTitle("Live Result Preview", "Updates as you type before saving")
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            InfoTile("Attempted", attempted.toString(), Modifier.weight(1f), GlassAccent)
            InfoTile("Accuracy", accuracy.percentText(), Modifier.weight(1f), GlassSuccess)
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            InfoTile("Score", score.percentText(), Modifier.weight(1f), GlassWarning)
            InfoTile("Unresolved", (wrong + skipped + unseen + missedCount).toString(), Modifier.weight(1f), GlassDanger)
        }
    }
}

@Composable
private fun DynamicField(field: FormField, value: String, onChange: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        val label = field.showLabel + if (field.required) " *" else ""
        if (field.inputType == "select") {
            Text(label, color = GlassInk, fontWeight = FontWeight.SemiBold)
            OptionChips(field.options(), value, onChange)
        } else {
            androidx.compose.material3.OutlinedTextField(
                value = value,
                onValueChange = onChange,
                label = { Text(label) },
                singleLine = field.inputType !in listOf("textarea", "json"),
                minLines = if (field.inputType in listOf("textarea", "json")) 3 else 1,
                keyboardOptions = KeyboardOptions(keyboardType = if (field.inputType == "number") KeyboardType.Number else KeyboardType.Text),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp)
            )
        }
        if (field.helperText.isNotBlank()) Text(field.helperText, color = GlassMuted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun MissedQuestionEditor(index: Int, question: MissedQuestionInput, viewModel: AppViewModel) {
    GlassCard(Modifier.fillMaxWidth(), radius = 22.dp, contentPadding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Question ${index + 1}", color = GlassInk, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
            IconButton(onClick = { viewModel.removeMissedQuestion(index) }) { Icon(Icons.Outlined.DeleteOutline, contentDescription = "Remove", tint = GlassDanger) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GlassTextField(question.questionNumber, { viewModel.updateMissedQuestion(index, "question_number", it) }, "No.", modifier = Modifier.weight(1f))
            GlassTextField(question.questionMarks, { viewModel.updateMissedQuestion(index, "question_marks", it) }, "Marks", modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(8.dp))
        OptionChips(listOf("wrong", "skipped", "unseen"), question.issueType) { viewModel.updateMissedQuestion(index, "issue_type", it) }
        Spacer(Modifier.height(8.dp))
        GlassTextField(question.questionText, { viewModel.updateMissedQuestion(index, "question_text", it) }, "Question text", singleLine = false, minLines = 3)
        Spacer(Modifier.height(8.dp))
        GlassTextField(question.optionsJson, { viewModel.updateMissedQuestion(index, "options_json", it) }, "Options JSON or text", singleLine = false, minLines = 2)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GlassTextField(question.selectedOptionKey, { viewModel.updateMissedQuestion(index, "selected_option_key", it) }, "Your answer", modifier = Modifier.weight(1f))
            GlassTextField(question.correctOptionKey, { viewModel.updateMissedQuestion(index, "correct_option_key", it) }, "Correct", modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GlassTextField(question.marksReceived, { viewModel.updateMissedQuestion(index, "marks_received", it) }, "Received", modifier = Modifier.weight(1f))
            GlassTextField(question.questionTime, { viewModel.updateMissedQuestion(index, "question_time_seconds", it) }, "Time", modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(8.dp))
        GlassTextField(question.questionNote, { viewModel.updateMissedQuestion(index, "question_note", it) }, "Note", singleLine = false, minLines = 2)
    }
}

private fun List<FormField>.filterKeys(vararg keys: String): List<FormField> {
    val set = keys.toSet()
    return filter { it.fieldKey in set }
}

private fun smartAddItemsForType(state: AppUiState, activityType: String): List<CatalogItem> {
    val recent = state.study.entries
        .filter { it.activityType == activityType }
        .map { it.item }
        .distinctBy { it.id }
    val favorite = state.study.catalog
        .filter { it.activityType == activityType && it.id in state.study.favoriteItemIds }
        .filterNot { catalog -> recent.any { it.id == catalog.id } }
    val remaining = state.study.catalog
        .filter { it.activityType == activityType }
        .filterNot { catalog -> recent.any { it.id == catalog.id } || favorite.any { it.id == catalog.id } }
    return recent + favorite + remaining
}

private fun filteredCatalog(study: StudyUiState): List<CatalogItem> = study.catalog.filter { item ->
    val q = study.search.trim().lowercase()
    val searchOk = q.isBlank() || listOf(item.fullPath, item.displayName, item.platformName, item.mainCategory, item.subCategory).any { it.lowercase().contains(q) }
    val activityOk = study.activityFilter == "All" || item.activityType == study.activityFilter
    val platformOk = study.platformFilter == "All" || item.platformName == study.platformFilter
    searchOk && activityOk && platformOk
}

private fun greeting(name: String): String {
    val hour = java.time.LocalTime.now().hour
    val prefix = when (hour) { in 5..11 -> "Good morning"; in 12..16 -> "Good afternoon"; in 17..21 -> "Good evening"; else -> "Deep focus" }
    return "$prefix, ${name.ifBlank { "Sam" }}"
}

private fun nextBestAction(state: AppUiState): Quad<String, String, String, AppTab> {
    val pendingMistakes = state.study.mistakes.count { it.reviewStatus != "Fixed" }
    val todayEntries = state.study.entries.count { it.sessionDate == todayIso() }
    val latestAccuracy = state.study.entries.firstOrNull { it.activityType == "test" }?.accuracyPercent
    return when {
        pendingMistakes > 0 -> Quad("Next Best Action", "Revise $pendingMistakes pending missed questions before adding another mock.", "Start Review", AppTab.Mistakes)
        todayEntries == 0 -> Quad("Start your first session", "No Supabase activity saved today. Log one small revision to protect your streak.", "Start Study", AppTab.Study)
        latestAccuracy != null && latestAccuracy < 70.0 -> Quad("Accuracy needs attention", "Latest test accuracy is ${"%.1f".format(latestAccuracy)}%. Review weak topics before another full mock.", "View Progress", AppTab.Progress)
        else -> Quad("Keep momentum", "You already have study activity today. Add one quality revision or reading session.", "Quick Add", AppTab.Study)
    }
}

data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

private fun focusScore(state: AppUiState): Int {
    val studyToday = state.study.entries.count { it.sessionDate == todayIso() }
    val daily = (state.daily.completionRate * 30f).roundToInt()
    val sessions = (studyToday * 18).coerceAtMost(36)
    val accuracy = (state.study.entries.firstOrNull { it.activityType == "test" }?.accuracyPercent ?: 0.0).roundToInt().coerceAtMost(24)
    val mistakes = if (state.study.mistakes.any { it.reviewStatus == "Fixed" }) 10 else 0
    return (daily + sessions + accuracy + mistakes).coerceIn(0, 100)
}

private fun estimatedStreak(entries: List<StudyEntry>): Int {
    if (entries.isEmpty()) return 0
    val days = entries.map { it.sessionDate }.toSet()
    var count = 0
    var day = LocalDate.now()
    while (days.contains(day.toString())) { count++; day = day.minusDays(1) }
    return count
}

private fun studyMissions(state: AppUiState): List<Triple<String, String, String>> = listOf(
    Triple("Review mistakes", "Clear at least 5 pending wrong/skipped/unseen questions.", "High"),
    Triple("Add one study session", "Log revision, reading, video, or practice from Study tab.", "Core"),
    Triple("Take or analyze a mock", "If accuracy is low, analyze instead of blindly attempting.", "Test"),
    Triple("Reading habit", "Complete The Hindu/editorial or reading practice.", "Read"),
    Triple("Evening summary", "Check progress and write one note from today.", "Review")
)

private fun activityIcon(type: String): ImageVector = when (type) {
    "test" -> Icons.Outlined.Quiz
    "video" -> Icons.Outlined.Videocam
    "reading" -> Icons.Outlined.MenuBook
    "revision" -> Icons.Outlined.Psychology
    else -> Icons.Outlined.School
}

private fun activityColor(type: String): Color = when (type) {
    "test" -> GlassWarning
    "video" -> GlassAccent2
    "reading" -> GlassSuccess
    "revision" -> GlassAccent
    else -> GlassMuted
}

private fun progressInsight(state: AppUiState): Pair<String, String> {
    val weak = state.study.mistakes.groupingBy { it.item.displayName }.eachCount().maxByOrNull { it.value }
    return if (weak != null) {
        "Weakness heatmap signal" to "${weak.key} has the highest unresolved mistake count (${weak.value}). Prioritize review before your next mock."
    } else {
        "Build your baseline" to "Add revision and test attempts to unlock trend insights, weak topics, and platform performance."
    }
}

private fun Iterable<Double>.averageOrNull(): Double? {
    val list = toList()
    return if (list.isEmpty()) null else list.average()
}

private fun Double?.percentText(): String = this?.let { "${"%.1f".format(it)}%" } ?: "--"
private fun String?.asInt(): Int = this?.trim()?.toIntOrNull() ?: 0
private fun String?.asDouble(): Double? = this?.trim()?.toDoubleOrNull()

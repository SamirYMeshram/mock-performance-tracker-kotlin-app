package com.liquidglass.study.ui

import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.liquidglass.study.ui.theme.GlassAccent
import com.liquidglass.study.ui.theme.GlassAccent2
import com.liquidglass.study.ui.theme.GlassDanger
import com.liquidglass.study.ui.theme.GlassInk
import com.liquidglass.study.ui.theme.GlassMuted
import com.liquidglass.study.ui.theme.GlassStroke
import com.liquidglass.study.ui.theme.GlassSuccess
import com.liquidglass.study.ui.theme.GlassWarning

object AppMotion {
    const val fast = 160
    const val medium = 260
    const val slow = 420
    fun <T> fastTween() = tween<T>(durationMillis = fast, easing = FastOutSlowInEasing)
    fun <T> mediumTween() = tween<T>(durationMillis = medium, easing = FastOutSlowInEasing)
    fun <T> slowTween() = tween<T>(durationMillis = slow, easing = FastOutSlowInEasing)
    fun pressSpring() = spring<Float>(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
    fun softSpring() = spring<Float>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessLow)
}

@Composable
fun LiquidBackground(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(Color(0xFF050711), Color(0xFF0A1020), Color(0xFF07151B)),
                    start = Offset.Zero,
                    end = Offset(size.width, size.height)
                )
            )
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0x55276CFF), Color.Transparent),
                    center = Offset(size.width * 0.10f, size.height * 0.06f),
                    radius = size.minDimension * 0.78f
                ),
                radius = size.minDimension * 0.78f,
                center = Offset(size.width * 0.10f, size.height * 0.06f)
            )
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0x403BFFC5), Color.Transparent),
                    center = Offset(size.width * 0.92f, size.height * 0.22f),
                    radius = size.minDimension * 0.56f
                ),
                radius = size.minDimension * 0.56f,
                center = Offset(size.width * 0.92f, size.height * 0.22f)
            )
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0x36CFA7FF), Color.Transparent),
                    center = Offset(size.width * 0.50f, size.height * 0.92f),
                    radius = size.minDimension * 0.64f
                ),
                radius = size.minDimension * 0.64f,
                center = Offset(size.width * 0.50f, size.height * 0.92f)
            )
            drawRect(Color(0x66000000))
        }
        content()
    }
}

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    radius: Dp = 28.dp,
    contentPadding: Dp = 16.dp,
    accent: Color = Color.White.copy(alpha = 0.16f),
    content: @Composable ColumnScope.() -> Unit
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier = modifier
            .shadow(22.dp, shape, ambientColor = Color.White.copy(alpha = 0.03f), spotColor = Color.Black.copy(alpha = 0.42f))
            .clip(shape)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        accent,
                        Color.White.copy(alpha = 0.075f),
                        Color.White.copy(alpha = 0.105f)
                    )
                )
            )
            .border(1.dp, GlassStroke, shape)
            .padding(contentPadding),
        content = content
    )
}

@Composable
fun PressableCard(
    modifier: Modifier = Modifier,
    radius: Dp = 28.dp,
    enabled: Boolean = true,
    onClick: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && enabled) 0.975f else 1f, animationSpec = AppMotion.pressSpring(), label = "press-card")
    GlassCard(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick),
        radius = radius,
        content = content
    )
}

@Composable
fun PrimaryGlassButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.height(52.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.White.copy(alpha = 0.90f),
            contentColor = Color(0xFF07101F),
            disabledContainerColor = Color.White.copy(alpha = 0.14f),
            disabledContentColor = GlassMuted
        ),
        shape = RoundedCornerShape(18.dp)
    ) { Text(text, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis) }
}

@Composable
fun GhostGlassButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = modifier) { Text(text, color = GlassInk, fontWeight = FontWeight.SemiBold) }
}

@Composable
fun SectionTitle(title: String, subtitle: String? = null, action: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleLarge, color = GlassInk, fontWeight = FontWeight.ExtraBold)
            if (!subtitle.isNullOrBlank()) Text(subtitle, color = GlassMuted, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (action != null) Box(Modifier.padding(start = 12.dp)) { action() }
    }
}

@Composable
fun InfoTile(label: String, value: String, modifier: Modifier = Modifier, tone: Color = GlassAccent) {
    GlassCard(modifier = modifier, radius = 22.dp, contentPadding = 14.dp, accent = tone.copy(alpha = 0.12f)) {
        Text(label, color = GlassMuted, style = MaterialTheme.typography.labelMedium, maxLines = 1)
        Spacer(Modifier.height(6.dp))
        Text(value, color = GlassInk, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun AnimatedStatCard(label: String, value: Float, suffix: String = "", icon: ImageVector? = null, modifier: Modifier = Modifier) {
    val animated by animateFloatAsState(targetValue = value, animationSpec = AppMotion.slowTween(), label = "stat-$label")
    GlassCard(modifier = modifier, radius = 24.dp, contentPadding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Box(Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                    Icon(icon, contentDescription = null, tint = GlassAccent, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(10.dp))
            }
            Column {
                Text("${animated.toInt()}$suffix", color = GlassInk, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Black)
                Text(label, color = GlassMuted, style = MaterialTheme.typography.labelMedium, maxLines = 1)
            }
        }
    }
}

@Composable
fun ProgressLine(progress: Float, modifier: Modifier = Modifier) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), animationSpec = AppMotion.slowTween(), label = "progress-line")
    Box(modifier.height(10.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.11f))) {
        Box(
            Modifier
                .fillMaxWidth(animated)
                .height(10.dp)
                .clip(RoundedCornerShape(50))
                .background(Brush.horizontalGradient(listOf(GlassAccent, GlassSuccess)))
        )
    }
}

@Composable
fun ProgressRing(progress: Float, label: String, modifier: Modifier = Modifier.size(116.dp), ringColor: Color = GlassAccent) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), animationSpec = AppMotion.slowTween(), label = "progress-ring")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = Stroke(width = 12.dp.toPx(), cap = StrokeCap.Round)
            drawArc(Color.White.copy(alpha = 0.11f), -90f, 360f, false, style = stroke)
            drawArc(
                color = ringColor,
                startAngle = -90f,
                sweepAngle = 360f * animated,
                useCenter = false,
                style = stroke
            )
        }
        Text(label, color = GlassInk, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
    }
}

@Composable
fun FloatingGlassBottomNav(current: AppTab, onSelected: (AppTab) -> Unit, modifier: Modifier = Modifier) {
    val items = listOf(
        AppTab.Home to Icons.Outlined.Home,
        AppTab.Today to Icons.Outlined.Today,
        AppTab.Study to Icons.Outlined.School,
        AppTab.Mistakes to Icons.Outlined.ErrorOutline,
        AppTab.Progress to Icons.Outlined.Analytics
    )
    GlassCard(modifier = modifier.fillMaxWidth(), radius = 34.dp, contentPadding = 8.dp, accent = Color.White.copy(alpha = 0.18f)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            items.forEach { (tab, icon) ->
                FloatingNavItem(tab = tab, icon = icon, selected = current == tab, modifier = Modifier.weight(1f)) { onSelected(tab) }
            }
        }
    }
}

@Composable
private fun FloatingNavItem(tab: AppTab, icon: ImageVector, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.94f else if (selected) 1.06f else 1f, animationSpec = AppMotion.pressSpring(), label = "nav-scale")
    val bg by animateColorAsState(if (selected) Color.White.copy(alpha = 0.18f) else Color.Transparent, animationSpec = AppMotion.mediumTween(), label = "nav-bg")
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(26.dp))
            .background(bg)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(vertical = 8.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(icon, contentDescription = tab.title, tint = if (selected) Color.White else GlassMuted, modifier = Modifier.size(22.dp))
        AnimatedVisibility(visible = selected, enter = fadeIn(AppMotion.fastTween()), exit = fadeOut(AppMotion.fastTween())) {
            Text(tab.title, color = Color.White, style = MaterialTheme.typography.labelSmall, maxLines = 1)
        }
    }
}

@Composable
fun QuickActionTile(label: String, icon: ImageVector, modifier: Modifier = Modifier, tone: Color = GlassAccent, onClick: () -> Unit) {
    PressableCard(modifier = modifier, radius = 24.dp, onClick = onClick) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(tone.copy(alpha = 0.20f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = tone, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(10.dp))
        Text(label, color = GlassInk, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, maxLines = 2)
    }
}

@Composable
fun InsightCard(title: String, body: String, cta: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    PressableCard(modifier = modifier.fillMaxWidth(), radius = 28.dp, onClick = onClick) {
        Text(title, color = GlassInk, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(6.dp))
        Text(body, color = GlassMuted, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(12.dp))
        PrimaryGlassButton(cta, modifier = Modifier.fillMaxWidth()) { onClick() }
    }
}

@Composable
fun ExpandableSection(title: String, subtitle: String? = null, expanded: Boolean, onToggle: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    GlassCard(Modifier.fillMaxWidth(), radius = 24.dp) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(title, color = GlassInk, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
                if (!subtitle.isNullOrBlank()) Text(subtitle, color = GlassMuted, style = MaterialTheme.typography.bodySmall)
            }
            Text(if (expanded) "Hide" else "Show", color = GlassAccent, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        }
        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn(AppMotion.mediumTween()) + expandVertically(AppMotion.mediumTween()),
            exit = fadeOut(AppMotion.fastTween()) + shrinkVertically(AppMotion.fastTween())
        ) {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
        }
    }
}

@Composable
fun FormSectionCard(title: String, subtitle: String? = null, content: @Composable ColumnScope.() -> Unit) {
    GlassCard(Modifier.fillMaxWidth(), radius = 24.dp, accent = Color.White.copy(alpha = 0.12f)) {
        Text(title, color = GlassInk, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
        if (!subtitle.isNullOrBlank()) Text(subtitle, color = GlassMuted, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}

@Composable
fun EmptyState(title: String, body: String, cta: String? = null, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    GlassCard(modifier = modifier.fillMaxWidth(), radius = 28.dp) {
        Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = GlassWarning, modifier = Modifier.size(34.dp))
        Spacer(Modifier.height(10.dp))
        Text(title, color = GlassInk, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(6.dp))
        Text(body, color = GlassMuted)
        if (cta != null && onClick != null) {
            Spacer(Modifier.height(14.dp))
            PrimaryGlassButton(cta, Modifier.fillMaxWidth(), onClick = onClick)
        }
    }
}

@Composable
fun SkeletonLoadingCard(modifier: Modifier = Modifier) {
    GlassCard(modifier = modifier.fillMaxWidth(), radius = 28.dp) {
        Box(Modifier.fillMaxWidth().height(18.dp).clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha = 0.14f)))
        Spacer(Modifier.height(12.dp))
        Box(Modifier.fillMaxWidth(0.72f).height(14.dp).clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha = 0.10f)))
        Spacer(Modifier.height(18.dp))
        ProgressLine(0.58f, Modifier.fillMaxWidth())
    }
}

@Composable
fun LoadingVeil(visible: Boolean) {
    if (visible) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f)), contentAlignment = Alignment.Center) {
            GlassCard(radius = 24.dp, contentPadding = 18.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Syncing...", color = GlassInk, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
fun MessageBanner(error: String?, message: String?, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val text = error ?: message ?: return
    val isError = error != null
    GlassCard(modifier = modifier.fillMaxWidth(), radius = 22.dp, contentPadding = 14.dp, accent = if (isError) GlassDanger.copy(alpha = 0.16f) else GlassSuccess.copy(alpha = 0.16f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (isError) Icons.Outlined.WarningAmber else Icons.Outlined.CheckCircle, contentDescription = null, tint = if (isError) GlassDanger else GlassSuccess, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Text(text, color = GlassInk, modifier = Modifier.weight(1f), maxLines = 3, overflow = TextOverflow.Ellipsis)
            IconButton(onClick = onDismiss, modifier = Modifier.size(34.dp)) { Icon(Icons.Outlined.Close, contentDescription = "Close", tint = GlassMuted) }
        }
    }
}

@Composable
fun GlassTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    minLines: Int = 1,
    trailing: (@Composable () -> Unit)? = null
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = singleLine,
        minLines = minLines,
        trailingIcon = trailing,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp)
    )
}

@Composable
fun ChoiceChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(selected = selected, onClick = onClick, label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) })
}

@Composable
fun OptionChips(options: List<String>, selected: String, onSelected: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            AssistChip(
                onClick = { onSelected(option) },
                label = { Text(option, maxLines = 1) },
                border = BorderStroke(1.dp, if (option == selected) Color.White else GlassStroke)
            )
        }
    }
}

@Composable
fun EmptyGlassState(title: String, body: String, modifier: Modifier = Modifier) {
    EmptyState(title = title, body = body, modifier = modifier)
}

@Composable
fun RefreshButton(onRefresh: () -> Unit) {
    IconButton(onClick = onRefresh) { Icon(Icons.Outlined.Refresh, contentDescription = "Refresh", tint = GlassInk) }
}


fun formatSeconds(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    val h = safe / 3600
    val m = (safe % 3600) / 60
    val s = safe % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}

fun shareText(context: Context, subject: String, text: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(intent, subject))
}

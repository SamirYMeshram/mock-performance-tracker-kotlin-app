package com.liquidglass.study.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

val GlassInk = Color(0xFFEFF5FF)
val GlassMuted = Color(0xFFB6C0D8)
val GlassPanel = Color(0x2EFFFFFF)
val GlassStroke = Color(0x30FFFFFF)
val GlassAccent = Color(0xFFBFD7FF)
val GlassAccent2 = Color(0xFFDCC8FF)
val GlassSuccess = Color(0xFFB8F7D4)
val GlassWarning = Color(0xFFFFE2A8)
val GlassDanger = Color(0xFFFFB8C6)
val GlassDeep = Color(0xFF070A13)
val GlassSurface = Color(0xFF101626)

object AppSpacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
}

object AppShapes {
    val card = 28.dp
    val largeCard = 34.dp
    val chip = 50.dp
}

private val darkColors = darkColorScheme(
    primary = GlassAccent,
    onPrimary = Color(0xFF07101F),
    secondary = GlassAccent2,
    onSecondary = Color(0xFF110A20),
    tertiary = GlassSuccess,
    onTertiary = Color(0xFF06170E),
    background = GlassDeep,
    onBackground = GlassInk,
    surface = GlassSurface,
    onSurface = GlassInk,
    surfaceVariant = Color(0xFF1A2133),
    onSurfaceVariant = GlassMuted,
    error = GlassDanger,
    onError = Color(0xFF23030A)
)

private val lightColors = lightColorScheme(
    primary = Color(0xFF335B92),
    onPrimary = Color.White,
    secondary = Color(0xFF725B9A),
    onSecondary = Color.White,
    tertiary = Color(0xFF18754D),
    onTertiary = Color.White,
    background = Color(0xFFF6F8FE),
    onBackground = Color(0xFF101626),
    surface = Color.White,
    onSurface = Color(0xFF101626),
    surfaceVariant = Color(0xFFE6EAF5),
    onSurfaceVariant = Color(0xFF4F5B73),
    error = Color(0xFFB3261E),
    onError = Color.White
)

@Composable
fun LiquidGlassTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && darkTheme -> dynamicDarkColorScheme(context)
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> dynamicLightColorScheme(context)
        darkTheme -> darkColors
        else -> lightColors
    }
    MaterialTheme(colorScheme = colorScheme, typography = MaterialTheme.typography, content = content)
}

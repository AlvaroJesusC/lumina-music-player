import 'package:flutter/material.dart';

import 'lumina_colors.dart';
import 'lumina_haptics.dart';
import 'lumina_motion.dart';
import 'lumina_shapes.dart';

/// Constructor de los temas visuales de Lumina Player (oscuro y claro).
///
/// Implementa las directivas de `design-system-structure`:
/// 1. `ColorScheme` autorado a mano (sin `fromSeed`).
/// 2. Todos los slots semánticos expuestos a través de `ThemeExtension`s.
/// 3. Extensiones adjuntas a ambos `ThemeData`.
/// 4. Tipografía con jerarquía limpia en Roboto.
ThemeData buildLuminaTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final colors = isDark ? LuminaColors.dark : LuminaColors.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.accentSoft,
    onPrimaryContainer: colors.accentInk,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerHighest: colors.surfaceHighest,
    outline: colors.hairline,
    error: const Color(0xFFCF6679),
    onError: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.background,
    colorScheme: colorScheme,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: colors.hairline,
      thickness: 1,
      space: 1,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: <ThemeExtension<dynamic>>[
      LuminaMotion.standardSet,
      LuminaShapes.standardSet,
      LuminaHaptics.standardSet,
      colors,
    ],
  );
}

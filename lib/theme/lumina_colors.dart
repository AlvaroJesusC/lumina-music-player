import 'package:flutter/material.dart';

import 'lumina_primitives.dart';

/// TIER 2 — Slots semánticos de color de Lumina, nombrados por rol.
///
/// Los widgets leen SIEMPRE estos slots vía [LuminaColors.of]; nunca una
/// primitiva ni un literal. Existe una instancia para cada brillo
/// ([LuminaColors.dark] y [LuminaColors.light]), ambas adjuntas a su
/// `ThemeData` correspondiente.
@immutable
class LuminaColors extends ThemeExtension<LuminaColors> {
  /// Crea un conjunto completo de slots; usar [dark] o [light].
  const LuminaColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighest,
    required this.hairline,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.accentSoft,
    required this.accentGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.trackBase,
    required this.shadow,
    required this.scrim,
    required this.backdropTop,
    required this.driftSaturation,
    required this.driftLightness,
  });

  /// Fondo base de pantallas (full-bleed, detrás de las barras del sistema).
  final Color background;

  /// Superficie de tarjetas y filas de lista.
  final Color surface;

  /// Superficie elevada (Mini-Player, hojas modales).
  final Color surfaceElevated;

  /// Superficie de mayor énfasis (campos de búsqueda, chips).
  final Color surfaceHighest;

  /// Bordes y divisores de 1 px.
  final Color hairline;

  /// Acento de relleno (botón Play, indicadores). No usar para texto pequeño.
  final Color accent;

  /// Acento apto para texto e iconos sobre [surface] (contraste AA).
  final Color accentInk;

  /// Contenido (iconos/texto) colocado SOBRE un relleno [accent].
  final Color onAccent;

  /// Fondo tenue para la fila de la canción en reproducción.
  final Color accentSoft;

  /// Resplandor del botón principal y del thumb del scrubber.
  final Color accentGlow;

  /// Texto principal (títulos).
  final Color textPrimary;

  /// Texto secundario (artista, subtítulos) — ~64 % de énfasis.
  final Color textSecondary;

  /// Texto terciario (contadores, etiquetas) — ~40 % de énfasis.
  final Color textTertiary;

  /// Pista base de barras de progreso.
  final Color trackBase;

  /// Color de sombras suaves (carátulas, Mini-Player).
  final Color shadow;

  /// Velo de legibilidad sobre fondos dinámicos del reproductor.
  final Color scrim;

  /// Color superior del degradado fijo del reproductor.
  final Color backdropTop;

  /// Saturación HSL (0–1) de los colores del fondo dinámico aleatorio.
  final double driftSaturation;

  /// Luminosidad HSL (0–1) de los colores del fondo dinámico aleatorio.
  final double driftLightness;

  /// Tema oscuro (por defecto en Lumina).
  static final LuminaColors dark = LuminaColors(
    background: LuminaPrimitives.neutral04,
    surface: LuminaPrimitives.neutral08,
    surfaceElevated: LuminaPrimitives.neutral11,
    surfaceHighest: LuminaPrimitives.neutral14,
    hairline: LuminaPrimitives.ink98.withValues(alpha: 0.08),
    accent: LuminaPrimitives.emerald70,
    accentInk: LuminaPrimitives.emerald70,
    onAccent: LuminaPrimitives.emerald06,
    accentSoft: LuminaPrimitives.emerald70.withValues(alpha: 0.12),
    accentGlow: LuminaPrimitives.emerald70.withValues(alpha: 0.35),
    textPrimary: LuminaPrimitives.ink98,
    textSecondary: LuminaPrimitives.ink98.withValues(alpha: 0.64),
    textTertiary: LuminaPrimitives.ink98.withValues(alpha: 0.40),
    trackBase: LuminaPrimitives.ink98.withValues(alpha: 0.14),
    shadow: LuminaPrimitives.black.withValues(alpha: 0.45),
    scrim: LuminaPrimitives.neutral04.withValues(alpha: 0.88),
    backdropTop: LuminaPrimitives.emeraldShadow12,
    driftSaturation: 0.55,
    driftLightness: 0.30,
  );

  /// Tema claro, autorado a mano (no es una inversión del oscuro).
  static final LuminaColors light = LuminaColors(
    background: LuminaPrimitives.neutral97,
    surface: LuminaPrimitives.neutral100,
    surfaceElevated: LuminaPrimitives.neutral100,
    surfaceHighest: LuminaPrimitives.neutral93,
    hairline: LuminaPrimitives.ink10.withValues(alpha: 0.08),
    accent: LuminaPrimitives.emerald70,
    accentInk: LuminaPrimitives.emerald50,
    onAccent: LuminaPrimitives.emerald06,
    accentSoft: LuminaPrimitives.emerald70.withValues(alpha: 0.14),
    accentGlow: LuminaPrimitives.emerald70.withValues(alpha: 0.30),
    textPrimary: LuminaPrimitives.ink10,
    textSecondary: LuminaPrimitives.ink10.withValues(alpha: 0.64),
    textTertiary: LuminaPrimitives.ink10.withValues(alpha: 0.45),
    trackBase: LuminaPrimitives.ink10.withValues(alpha: 0.12),
    shadow: LuminaPrimitives.black.withValues(alpha: 0.14),
    scrim: LuminaPrimitives.neutral97.withValues(alpha: 0.86),
    backdropTop: LuminaPrimitives.emeraldMist92,
    driftSaturation: 0.60,
    driftLightness: 0.80,
  );

  /// Devuelve los slots del tema activo. Falla en debug si el tema no se
  /// construyó con `buildLuminaTheme` — nunca devuelve un fallback.
  static LuminaColors of(BuildContext context) {
    final ext = Theme.of(context).extension<LuminaColors>();
    assert(ext != null, 'LuminaColors ausente. Usa buildLuminaTheme().');
    return ext!;
  }

  /// Color del fondo dinámico para un [hue] (0–360) con la saturación y
  /// luminosidad del tema, de modo que el texto siga siendo legible.
  Color driftColor(double hue) =>
      HSLColor.fromAHSL(1, hue % 360, driftSaturation, driftLightness)
          .toColor();

  @override
  LuminaColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHighest,
    Color? hairline,
    Color? accent,
    Color? accentInk,
    Color? onAccent,
    Color? accentSoft,
    Color? accentGlow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? trackBase,
    Color? shadow,
    Color? scrim,
    Color? backdropTop,
    double? driftSaturation,
    double? driftLightness,
  }) {
    return LuminaColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentGlow: accentGlow ?? this.accentGlow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      trackBase: trackBase ?? this.trackBase,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      backdropTop: backdropTop ?? this.backdropTop,
      driftSaturation: driftSaturation ?? this.driftSaturation,
      driftLightness: driftLightness ?? this.driftLightness,
    );
  }

  @override
  LuminaColors lerp(LuminaColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return LuminaColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfaceHighest: c(surfaceHighest, other.surfaceHighest),
      hairline: c(hairline, other.hairline),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentGlow: c(accentGlow, other.accentGlow),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      trackBase: c(trackBase, other.trackBase),
      shadow: c(shadow, other.shadow),
      scrim: c(scrim, other.scrim),
      backdropTop: c(backdropTop, other.backdropTop),
      driftSaturation: d(driftSaturation, other.driftSaturation),
      driftLightness: d(driftLightness, other.driftLightness),
    );
  }
}

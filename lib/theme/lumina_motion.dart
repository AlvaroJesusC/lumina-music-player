import 'package:flutter/material.dart';

/// Tokens de movimiento de Lumina: roles de duración y curvas.
///
/// Los widgets nunca escriben `Duration(milliseconds: …)` ni `Curves.*`;
/// piden un rol aquí y lo pasan por [LuminaMotion.resolve], que colapsa a
/// [Duration.zero] cuando el sistema pide reducir animaciones.
@immutable
class LuminaMotion extends ThemeExtension<LuminaMotion> {
  /// Crea los tokens; usar [standard].
  const LuminaMotion({
    required this.short,
    required this.medium,
    required this.long,
    required this.crossfade,
    required this.driftCycle,
    required this.standard,
    required this.emphasized,
    required this.press,
    required this.drift,
  });

  /// Reconocimiento de pulsación (escala de botón, cambio de icono).
  final Duration short;

  /// Transformación de commit (morph Play/Pause, cambio de pestaña).
  final Duration medium;

  /// Cambios de escena (escala de carátula, apertura del reproductor).
  final Duration long;

  /// Fundido del fondo ambiental al cambiar de canción.
  final Duration crossfade;

  /// Duración de un ciclo de transición del fondo dinámico aleatorio.
  final Duration driftCycle;

  /// Curva por defecto: entrada y salida naturales.
  final Curve standard;

  /// Curva enfática para elementos que entran a escena.
  final Curve emphasized;

  /// Curva corta para el estado presionado.
  final Curve press;

  /// Curva lenta y simétrica del fondo dinámico.
  final Curve drift;

  /// Valores de movimiento de Lumina.
  static const LuminaMotion standardSet = LuminaMotion(
    short: Duration(milliseconds: 120),
    medium: Duration(milliseconds: 280),
    long: Duration(milliseconds: 420),
    crossfade: Duration(milliseconds: 650),
    driftCycle: Duration(seconds: 9),
    standard: Curves.fastOutSlowIn,
    emphasized: Curves.easeOutCubic,
    press: Curves.easeOut,
    drift: Curves.easeInOutSine,
  );

  /// Devuelve los tokens del tema activo (falla en debug si faltan).
  static LuminaMotion of(BuildContext context) {
    final ext = Theme.of(context).extension<LuminaMotion>();
    assert(ext != null, 'LuminaMotion ausente. Usa buildLuminaTheme().');
    return ext!;
  }

  /// Si el usuario pidió al sistema reducir animaciones.
  static bool isReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Resuelve [full] a [Duration.zero] bajo movimiento reducido: el estado
  /// final aparece al instante, nunca "más suave".
  static Duration resolve(BuildContext context, Duration full) =>
      isReduced(context) ? Duration.zero : full;

  @override
  LuminaMotion copyWith({
    Duration? short,
    Duration? medium,
    Duration? long,
    Duration? crossfade,
    Duration? driftCycle,
    Curve? standard,
    Curve? emphasized,
    Curve? press,
    Curve? drift,
  }) {
    return LuminaMotion(
      short: short ?? this.short,
      medium: medium ?? this.medium,
      long: long ?? this.long,
      crossfade: crossfade ?? this.crossfade,
      driftCycle: driftCycle ?? this.driftCycle,
      standard: standard ?? this.standard,
      emphasized: emphasized ?? this.emphasized,
      press: press ?? this.press,
      drift: drift ?? this.drift,
    );
  }

  // Salto deliberado: duraciones y curvas no se interpolan entre temas;
  // ambos temas comparten el mismo set, así que el salto es invisible.
  @override
  LuminaMotion lerp(LuminaMotion? other, double t) =>
      t < 0.5 || other == null ? this : other;
}


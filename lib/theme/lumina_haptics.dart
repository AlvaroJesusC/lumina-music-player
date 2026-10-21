import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/appearance_settings.dart';

/// Eventos de interacción que pueden producir respuesta háptica.
enum HapticEvent {
  /// Selección ligera: favorito, aleatorio, pestañas, opciones.
  select,

  /// Commit de reproducción: Play/Pause, anterior/siguiente.
  commit,

  /// Entrada rechazada o acción no disponible.
  reject,

  /// Tarea completada (p. ej. playlist creada).
  success,
}

/// Mapa evento → intensidad háptica de Lumina.
///
/// Las llamadas nunca eligen una intensidad: nombran un [HapticEvent] y
/// llaman a [LuminaHaptics.fire]. Un slot `null` es un silencio declarado.
/// `heavyImpact` nunca se usa para errores.
@immutable
class LuminaHaptics extends ThemeExtension<LuminaHaptics> {
  /// Crea el mapa; usar [standardSet].
  const LuminaHaptics({this.select, this.commit, this.reject, this.success});

  /// Slot para [HapticEvent.select] (techo: `selectionClick`).
  final Future<void> Function()? select;

  /// Slot para [HapticEvent.commit] (techo: `lightImpact`).
  final Future<void> Function()? commit;

  /// Slot para [HapticEvent.reject] (techo: `lightImpact`).
  final Future<void> Function()? reject;

  /// Slot para [HapticEvent.success] (techo: `mediumImpact`).
  final Future<void> Function()? success;

  /// Mapa háptico de Lumina.
  static const LuminaHaptics standardSet = LuminaHaptics(
    select: HapticFeedback.selectionClick,
    commit: HapticFeedback.lightImpact,
    reject: HapticFeedback.lightImpact,
    success: HapticFeedback.mediumImpact,
  );

  /// Dispara la respuesta háptica de [event] UNA vez, en el frame del commit.
  ///
  /// Pasa por el interruptor central `AppearanceSettings.hapticsEnabled`;
  /// ninguna llamada necesita comprobarlo por su cuenta. Nunca llamar desde
  /// un listener de animación ni en un bucle por elemento.
  static void fire(BuildContext context, HapticEvent event) {
    if (!AppearanceSettings.instance.hapticsEnabled.value) return;
    final map = Theme.of(context).extension<LuminaHaptics>();
    assert(map != null, 'LuminaHaptics ausente. Usa buildLuminaTheme().');
    final slot = switch (event) {
      HapticEvent.select => map!.select,
      HapticEvent.commit => map!.commit,
      HapticEvent.reject => map!.reject,
      HapticEvent.success => map!.success,
    };
    slot?.call();
  }

  @override
  LuminaHaptics copyWith({
    Future<void> Function()? select,
    Future<void> Function()? commit,
    Future<void> Function()? reject,
    Future<void> Function()? success,
  }) {
    return LuminaHaptics(
      select: select ?? this.select,
      commit: commit ?? this.commit,
      reject: reject ?? this.reject,
      success: success ?? this.success,
    );
  }

  // Salto deliberado: las funciones no son interpolables.
  @override
  LuminaHaptics lerp(LuminaHaptics? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

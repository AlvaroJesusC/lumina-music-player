import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/playback_transition_settings.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';

/// Tarjeta de entrada en la pestaña de Ajustes para abrir el panel de
/// Crossfade y Fundidos Suaves sin inflar `music_library_page.dart`.
class CrossfadeSettingsTile extends StatelessWidget {
  const CrossfadeSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = PlaybackTransitionSettings.instance;
    final listenable = Listenable.merge([
      settings.crossfadeSeconds,
      settings.smoothPlayPauseFade,
      settings.sleepTimerFadeOut,
    ]);

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final colors = LuminaColors.of(context);
        final shapes = LuminaShapes.of(context);
        final isActive = settings.crossfadeSeconds.value > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(shapes.card),
            border: Border.all(color: colors.hairline, width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(shapes.artworkSmall),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                color: colors.accent,
                size: 22,
              ),
            ),
            title: Text(
              'Crossfade y Fundidos',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              settings.buildSummary(),
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: BoxDecoration(
                      color: colors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${settings.crossfadeSeconds.value} s',
                      style: TextStyle(
                        color: colors.accentInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
              ],
            ),
            onTap: () {
              LuminaHaptics.fire(context, HapticEvent.select);
              CrossfadeSettingsSheet.show(context);
            },
          ),
        );
      },
    );
  }
}

/// Hoja modal estilo Spotify para configurar Crossfade (slider horizontal
/// `Desactivado` → `12 s`), fundido suave en Play/Pausa y bajada progresiva
/// en el Temporizador de apagado.
class CrossfadeSettingsSheet extends StatefulWidget {
  const CrossfadeSettingsSheet({super.key});

  /// Abre la hoja modal respetando los tokens de color y forma de Lumina.
  static Future<void> show(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (_) => const CrossfadeSettingsSheet(),
    );
  }

  @override
  State<CrossfadeSettingsSheet> createState() => _CrossfadeSettingsSheetState();
}

class _CrossfadeSettingsSheetState extends State<CrossfadeSettingsSheet> {
  final PlaybackTransitionSettings _settings =
      PlaybackTransitionSettings.instance;

  late double _sliderValue;
  late int _lastHapticStep;

  @override
  void initState() {
    super.initState();
    _sliderValue = _settings.crossfadeSeconds.value.toDouble();
    _lastHapticStep = _settings.crossfadeSeconds.value;
  }

  // Seam síncrono (void) para evitar el agujero de Future descartado en callbacks.
  void _onSliderChanged(double rawValue) {
    final rounded = rawValue.round();
    if (rounded != _lastHapticStep) {
      _lastHapticStep = rounded;
      LuminaHaptics.fire(context, HapticEvent.select);
    }
    setState(() => _sliderValue = rawValue);
  }

  void _onSliderChangeEnd(double rawValue) {
    final seconds = rawValue.round();
    setState(() => _sliderValue = seconds.toDouble());
    unawaited(
      _settings.setCrossfadeSeconds(seconds).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error guardando crossfade: $e\n$s');
      }),
    );
  }

  void _onSmoothPlayPauseChanged(bool enabled) {
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _settings.setSmoothPlayPauseFade(enabled: enabled).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error guardando fade en pausa: $e\n$s');
      }),
    );
  }

  void _onSleepTimerFadeChanged(bool enabled) {
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _settings.setSleepTimerFadeOut(enabled: enabled).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error guardando fade del temporizador: $e\n$s');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final activeSeconds = _sliderValue.round();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Crossfade y Fundidos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Suaviza los cambios entre canciones, las pausas y el apagado del temporizador.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            const SizedBox(height: 18),
            _CrossfadeSliderCard(
              sliderValue: _sliderValue,
              activeSeconds: activeSeconds,
              colors: colors,
              shapes: shapes,
              onChanged: _onSliderChanged,
              onChangeEnd: _onSliderChangeEnd,
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<bool>(
              valueListenable: _settings.smoothPlayPauseFade,
              builder: (context, enabled, _) {
                return _TransitionToggleCard(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Fundido al pausar y reanudar',
                  subtitle:
                      'Atenúa suavemente el volumen al pulsar Pausa o Play en lugar de cortar de golpe.',
                  value: enabled,
                  colors: colors,
                  shapes: shapes,
                  onChanged: _onSmoothPlayPauseChanged,
                );
              },
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<bool>(
              valueListenable: _settings.sleepTimerFadeOut,
              builder: (context, enabled, _) {
                return _TransitionToggleCard(
                  icon: Icons.bedtime_outlined,
                  title: 'Bajada progresiva en Temporizador',
                  subtitle:
                      'Reduce el volumen gradualmente durante los últimos ${PlaybackTransitionSettings.sleepTimerFadeSeconds} s del Sleep Timer.',
                  value: enabled,
                  colors: colors,
                  shapes: shapes,
                  onChanged: _onSleepTimerFadeChanged,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta principal del Crossfade con visualización de curvas y slider horizontal.
class _CrossfadeSliderCard extends StatelessWidget {
  final double sliderValue;
  final int activeSeconds;
  final LuminaColors colors;
  final LuminaShapes shapes;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _CrossfadeSliderCard({
    required this.sliderValue,
    required this.activeSeconds,
    required this.colors,
    required this.shapes,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = activeSeconds > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(shapes.card),
        border: Border.all(
          color: isEnabled
              ? colors.accent.withValues(alpha: 0.35)
              : colors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows_rounded,
                color: isEnabled ? colors.accent : colors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Crossfade entre canciones',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isEnabled ? colors.accentSoft : colors.surfaceHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEnabled ? colors.accent : colors.hairline,
                  ),
                ),
                child: Text(
                  PlaybackTransitionSettings.formatCrossfadeLabel(
                    activeSeconds,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isEnabled ? colors.accentInk : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isEnabled
                ? 'Las canciones se mezclan durante $activeSeconds s al terminar la pista actual.'
                : 'Desliza hacia la derecha para activar la transición fluida estilo Spotify.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          RepaintBoundary(
            child: _CrossfadeCurvePreview(
              seconds: activeSeconds,
              colors: colors,
            ),
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.trackBase,
              thumbColor: colors.accent,
              overlayColor: colors.accentGlow.withValues(alpha: 0.25),
              trackHeight: 4,
              tickMarkShape: const RoundSliderTickMarkShape(
                tickMarkRadius: 1.5,
              ),
              activeTickMarkColor: colors.onAccent.withValues(alpha: 0.45),
              inactiveTickMarkColor: colors.textTertiary.withValues(
                alpha: 0.35,
              ),
              valueIndicatorColor: colors.accent,
              valueIndicatorTextStyle: TextStyle(
                color: colors.onAccent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            child: Semantics(
              label: 'Duración del crossfade en segundos',
              value: PlaybackTransitionSettings.formatCrossfadeLabel(
                activeSeconds,
              ),
              child: Slider(
                value: sliderValue,
                min: PlaybackTransitionSettings.minCrossfadeSeconds.toDouble(),
                max: PlaybackTransitionSettings.maxCrossfadeSeconds.toDouble(),
                divisions: PlaybackTransitionSettings.maxCrossfadeSeconds,
                label: PlaybackTransitionSettings.formatCrossfadeLabel(
                  activeSeconds,
                ),
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Desactivado',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: !isEnabled ? FontWeight.w700 : FontWeight.w500,
                    color: !isEnabled ? colors.accentInk : colors.textTertiary,
                  ),
                ),
                Text(
                  '6 s',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: activeSeconds == 6
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: activeSeconds == 6
                        ? colors.accentInk
                        : colors.textTertiary,
                  ),
                ),
                Text(
                  '${PlaybackTransitionSettings.maxCrossfadeSeconds} s',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        activeSeconds ==
                            PlaybackTransitionSettings.maxCrossfadeSeconds
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color:
                        activeSeconds ==
                            PlaybackTransitionSettings.maxCrossfadeSeconds
                        ? colors.accentInk
                        : colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visualización ligera de las dos curvas de volumen (saliente y entrante)
/// que refleja en vivo la anchura del solapamiento elegido en el slider.
class _CrossfadeCurvePreview extends StatelessWidget {
  final int seconds;
  final LuminaColors colors;

  const _CrossfadeCurvePreview({required this.seconds, required this.colors});

  @override
  Widget build(BuildContext context) {
    final overlapFraction =
        seconds / PlaybackTransitionSettings.maxCrossfadeSeconds;

    return ExcludeSemantics(
      child: Container(
        height: 58,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.hairline),
        ),
        child: CustomPaint(
          painter: _CrossfadeCurvePainter(
            overlapFraction: overlapFraction,
            outgoingColor: colors.textSecondary,
            incomingColor: colors.accent,
            overlapFillColor: colors.accentSoft,
            baselineColor: colors.hairline,
          ),
        ),
      ),
    );
  }
}

class _CrossfadeCurvePainter extends CustomPainter {
  final double overlapFraction;
  final Color outgoingColor;
  final Color incomingColor;
  final Color overlapFillColor;
  final Color baselineColor;

  final Paint _outgoingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;

  final Paint _incomingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;

  final Paint _overlapFillPaint = Paint()..style = PaintingStyle.fill;

  final Paint _baselinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  final Path _outgoingPath = Path();
  final Path _incomingPath = Path();

  _CrossfadeCurvePainter({
    required this.overlapFraction,
    required this.outgoingColor,
    required this.incomingColor,
    required this.overlapFillColor,
    required this.baselineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const top = 4.0;
    final bottom = h - 4.0;
    final amp = bottom - top;

    _baselinePaint.color = baselineColor;
    canvas.drawLine(Offset(0, bottom), Offset(w, bottom), _baselinePaint);

    // Zona de cruce centrada proporcional a los segundos elegidos (0% a 60%).
    final overlapWidth = w * (0.60 * overlapFraction);
    final mid = w * 0.5;
    final crossStart = mid - overlapWidth * 0.5;
    final crossEnd = mid + overlapWidth * 0.5;

    if (overlapWidth > 1.0) {
      _overlapFillPaint.color = overlapFillColor;
      canvas.drawRect(
        Rect.fromLTRB(crossStart, top, crossEnd, bottom),
        _overlapFillPaint,
      );
    }

    _outgoingPath.reset();
    _outgoingPath.moveTo(0, top);
    _outgoingPath.lineTo(crossStart, top);
    if (overlapWidth <= 1.0) {
      _outgoingPath.lineTo(crossStart, bottom);
    } else {
      const steps = 18;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final x = crossStart + overlapWidth * t;
        final y = bottom - amp * math.cos(t * math.pi / 2.0);
        _outgoingPath.lineTo(x, y);
      }
    }

    _incomingPath.reset();
    if (overlapWidth <= 1.0) {
      _incomingPath.moveTo(crossEnd, bottom);
      _incomingPath.lineTo(crossEnd, top);
    } else {
      _incomingPath.moveTo(crossStart, bottom);
      const steps = 18;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final x = crossStart + overlapWidth * t;
        final y = bottom - amp * math.sin(t * math.pi / 2.0);
        _incomingPath.lineTo(x, y);
      }
    }
    _incomingPath.lineTo(w, top);

    _outgoingPaint.color = outgoingColor;
    _incomingPaint.color = incomingColor;
    canvas.drawPath(_outgoingPath, _outgoingPaint);
    canvas.drawPath(_incomingPath, _incomingPaint);
  }

  @override
  bool shouldRepaint(covariant _CrossfadeCurvePainter oldDelegate) {
    return oldDelegate.overlapFraction != overlapFraction ||
        oldDelegate.outgoingColor != outgoingColor ||
        oldDelegate.incomingColor != incomingColor ||
        oldDelegate.overlapFillColor != overlapFillColor ||
        oldDelegate.baselineColor != baselineColor;
  }
}

/// Tarjeta con interruptor para opciones booleanas de fundido.
class _TransitionToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final LuminaColors colors;
  final LuminaShapes shapes;
  final ValueChanged<bool> onChanged;

  const _TransitionToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.colors,
    required this.shapes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(shapes.card),
        border: Border.all(color: colors.hairline),
      ),
      child: SwitchListTile(
        secondary: Icon(
          icon,
          color: value ? colors.accent : colors.textSecondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        value: value,
        activeThumbColor: colors.accent,
        onChanged: onChanged,
      ),
    );
  }
}

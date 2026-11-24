import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/audio_handler.dart';
import '../services/audio_service_instance.dart';
import '../services/equalizer_settings.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';

/// Tarjeta de entrada en la pestaña de Ajustes para abrir el panel del
/// Ecualizador nativo, Refuerzo de graves y Potenciador de volumen.
class EqualizerSettingsTile extends StatelessWidget {
  const EqualizerSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = EqualizerSettings.instance;
    final listenable = Listenable.merge([
      settings.enabled,
      settings.preset,
      settings.bassBoost,
      settings.loudnessBoostDb,
    ]);

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final colors = LuminaColors.of(context);
        final shapes = LuminaShapes.of(context);
        final isEnabled = settings.enabled.value;

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
                Icons.equalizer_rounded,
                color: colors.accent,
                size: 22,
              ),
            ),
            title: Text(
              'Ecualizador y Graves',
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
                if (isEnabled)
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
                      settings.preset.value.label,
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
              EqualizerSheet.show(context);
            },
          ),
        );
      },
    );
  }
}

/// Hoja modal interactiva del Ecualizador nativo de Android + Bass Boost +
/// Potenciador de volumen, accesible tanto desde Ajustes como directamente
/// desde la pantalla de reproducción mientras suena la música.
class EqualizerSheet extends StatefulWidget {
  final ValueListenable<List<double>>? centerFrequencies;

  const EqualizerSheet({super.key, this.centerFrequencies});

  /// Abre el ecualizador respetando los tokens de Lumina.
  static Future<void> show(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    ValueListenable<List<double>>? freqs;
    try {
      if (audioHandler is MyAudioHandler) {
        freqs = (audioHandler as MyAudioHandler).equalizerCenterFrequencies;
      }
    } on Error {
      // En tests sin AudioService inicializado usa frecuencias estándar.
      freqs = null;
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Evita que arrastrar hacia abajo una banda vertical del ecualizador
      // cierre accidentalmente el modal (se cierra tocando fuera o con la X).
      enableDrag: false,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (_) => EqualizerSheet(centerFrequencies: freqs),
    );
  }

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  final EqualizerSettings _settings = EqualizerSettings.instance;
  int _lastLoudnessStep = 0;
  bool _isDraggingBand = false;

  @override
  void initState() {
    super.initState();
    _lastLoudnessStep = _settings.loudnessBoostDb.value.round();
  }

  void _onBandChangeStart(double _) {
    if (!_isDraggingBand) {
      setState(() => _isDraggingBand = true);
    }
  }

  void _onToggleEnabled(bool enabled) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    unawaited(
      _settings.setEnabled(enabled: enabled).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error cambiando estado del ecualizador: $e\n$s');
      }),
    );
  }

  void _onSelectPreset(EqualizerPreset preset) {
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _settings.applyPreset(preset).catchError((Object e, StackTrace s) {
        debugPrint('Error aplicando preset de ecualizador: $e\n$s');
      }),
    );
  }

  void _onBandChanged(int index, double value) {
    unawaited(
      _settings
          .setBandLevel(index, value, persist: false)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error ajustando banda $index del ecualizador: $e\n$s');
          }),
    );
  }

  void _onBandChangeEnd(int index, double value) {
    if (_isDraggingBand) {
      setState(() => _isDraggingBand = false);
    }
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _settings
          .setBandLevel(index, value, persist: true)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error guardando banda $index del ecualizador: $e\n$s');
          }),
    );
  }

  void _onBassBoostChanged(double value) {
    unawaited(
      _settings
          .setBassBoost(value, persist: false)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error ajustando refuerzo de graves: $e\n$s');
          }),
    );
  }

  void _onBassBoostChangeEnd(double value) {
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _settings
          .setBassBoost(value, persist: true)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error guardando refuerzo de graves: $e\n$s');
          }),
    );
  }

  void _onLoudnessChanged(double value) {
    final rounded = value.round();
    if (rounded != _lastLoudnessStep) {
      _lastLoudnessStep = rounded;
      LuminaHaptics.fire(context, HapticEvent.select);
    }
    unawaited(
      _settings
          .setLoudnessBoostDb(value, persist: false)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error ajustando potenciador de volumen: $e\n$s');
          }),
    );
  }

  void _onLoudnessChangeEnd(double value) {
    unawaited(
      _settings
          .setLoudnessBoostDb(value, persist: true)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error guardando potenciador de volumen: $e\n$s');
          }),
    );
  }

  void _onReset() {
    LuminaHaptics.fire(context, HapticEvent.select);
    _lastLoudnessStep = 0;
    unawaited(
      _settings.reset().catchError((Object e, StackTrace s) {
        debugPrint('Error restableciendo ecualizador: $e\n$s');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final freqsListenable =
        widget.centerFrequencies ??
        const _StaticFreqListenable(EqualizerMath.defaultCenterFrequenciesHz);

    final settingsListenable = Listenable.merge([
      _settings.enabled,
      _settings.preset,
      _settings.bandLevels,
      _settings.bassBoost,
      _settings.loudnessBoostDb,
    ]);

    return SafeArea(
      child: AnimatedBuilder(
        animation: settingsListenable,
        builder: (context, _) {
          final isEnabled = _settings.enabled.value;
          final activePreset = _settings.preset.value;
          final rawBands = _settings.bandLevels.value;
          final effectiveBands = _settings.effectiveBandLevels();
          final bassBoost = _settings.bassBoost.value;
          final loudnessDb = _settings.loudnessBoostDb.value;

          return SingleChildScrollView(
            physics: _isDraggingBand
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.equalizer_rounded,
                      color: isEnabled ? colors.accent : colors.textSecondary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ecualizador',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            isEnabled
                                ? 'Activo en tiempo real · ${activePreset.label}'
                                : 'Activa o elige un preset para esculpir el sonido',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_settings.hasCustomModifications)
                      TextButton(
                        onPressed: _onReset,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(
                          'Plano',
                          style: TextStyle(
                            color: colors.accentInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Switch(
                      value: isEnabled,
                      activeThumbColor: colors.accent,
                      onChanged: _onToggleEnabled,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.textSecondary,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Cerrar ecualizador',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PresetSelectorStrip(
                  activePreset: activePreset,
                  isEnabled: isEnabled,
                  colors: colors,
                  shapes: shapes,
                  onSelected: _onSelectPreset,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(shapes.card),
                    border: Border.all(
                      color: isEnabled
                          ? colors.accent.withValues(alpha: 0.30)
                          : colors.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      RepaintBoundary(
                        child: _EqCurvePreview(
                          levels: effectiveBands,
                          isEnabled: isEnabled,
                          colors: colors,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<List<double>>(
                        valueListenable: freqsListenable,
                        builder: (context, freqs, _) {
                          final safeFreqs =
                              freqs.length == EqualizerSettings.bandCount
                              ? freqs
                              : EqualizerMath.defaultCenterFrequenciesHz;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              EqualizerSettings.bandCount,
                              (index) => Expanded(
                                child: _VerticalBandSlider(
                                  frequencyHz: safeFreqs[index],
                                  value: rawBands[index],
                                  effectiveValue: effectiveBands[index],
                                  isEnabled: isEnabled,
                                  colors: colors,
                                  onChangeStart: _onBandChangeStart,
                                  onChanged: (v) => _onBandChanged(index, v),
                                  onChangeEnd: (v) =>
                                      _onBandChangeEnd(index, v),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _EffectSliderCard(
                  icon: Icons.speaker_rounded,
                  title: 'Refuerzo de graves (Bass Boost)',
                  valueLabel: '+${(bassBoost * 100).round()}%',
                  value: bassBoost,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  isEnabled: isEnabled,
                  isHighlighted: isEnabled && bassBoost >= 0.05,
                  colors: colors,
                  shapes: shapes,
                  onChanged: _onBassBoostChanged,
                  onChangeEnd: _onBassBoostChangeEnd,
                ),
                const SizedBox(height: 10),
                _EffectSliderCard(
                  icon: Icons.volume_up_rounded,
                  title: 'Potenciador de volumen',
                  subtitle:
                      'Útil para canciones grabadas muy bajas (máx. +10 dB).',
                  valueLabel: loudnessDb < 0.1
                      ? '0 dB'
                      : '+${loudnessDb.round()} dB',
                  value: loudnessDb,
                  min: 0.0,
                  max: EqualizerMath.maxLoudnessBoostDb,
                  divisions: 10,
                  isEnabled: isEnabled,
                  isHighlighted: isEnabled && loudnessDb >= 0.5,
                  colors: colors,
                  shapes: shapes,
                  onChanged: _onLoudnessChanged,
                  onChangeEnd: _onLoudnessChangeEnd,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StaticFreqListenable implements ValueListenable<List<double>> {
  const _StaticFreqListenable(this.value);

  @override
  final List<double> value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Barra horizontal desplazable con chips de presets (Plano, Graves+, Pop...).
class _PresetSelectorStrip extends StatelessWidget {
  final EqualizerPreset activePreset;
  final bool isEnabled;
  final LuminaColors colors;
  final LuminaShapes shapes;
  final ValueChanged<EqualizerPreset> onSelected;

  const _PresetSelectorStrip({
    required this.activePreset,
    required this.isEnabled,
    required this.colors,
    required this.shapes,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EqualizerPreset.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = EqualizerPreset.values[index];
          final isSelected = activePreset == preset;
          final activeLook = isSelected && isEnabled;

          return GestureDetector(
            onTap: () => onSelected(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: activeLook
                    ? colors.accentSoft
                    : isSelected
                    ? colors.surfaceHighest
                    : colors.surface,
                borderRadius: BorderRadius.circular(shapes.miniPlayer),
                border: Border.all(
                  color: activeLook
                      ? colors.accent
                      : isSelected
                      ? colors.textTertiary
                      : colors.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    preset.icon,
                    size: 15,
                    color: activeLook ? colors.accentInk : colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: activeLook
                          ? colors.accentInk
                          : isSelected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Curva visual en vivo que une los 5 nodos de ganancia del ecualizador.
class _EqCurvePreview extends StatelessWidget {
  final List<double> levels;
  final bool isEnabled;
  final LuminaColors colors;

  const _EqCurvePreview({
    required this.levels,
    required this.isEnabled,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        height: 60,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.hairline),
        ),
        child: CustomPaint(
          painter: _EqCurvePainter(
            levels: levels,
            lineColor: isEnabled ? colors.accent : colors.textTertiary,
            fillColor: isEnabled
                ? colors.accentSoft
                : colors.textTertiary.withValues(alpha: 0.08),
            centerLineColor: colors.hairline,
          ),
        ),
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<double> levels;
  final Color lineColor;
  final Color fillColor;
  final Color centerLineColor;

  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _dotPaint = Paint()..style = PaintingStyle.fill;
  final Paint _centerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  final Path _curvePath = Path();
  final Path _fillPath = Path();

  _EqCurvePainter({
    required this.levels,
    required this.lineColor,
    required this.fillColor,
    required this.centerLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final midY = h * 0.5;
    final halfAmp = (h * 0.5) - 4.0;

    _centerPaint.color = centerLineColor;
    canvas.drawLine(Offset(0, midY), Offset(w, midY), _centerPaint);

    final points = <Offset>[];
    final count = levels.length;
    for (var i = 0; i < count; i++) {
      final x = count == 1 ? w * 0.5 : (i / (count - 1)) * w;
      final y = midY - (levels[i].clamp(-1.0, 1.0) * halfAmp);
      points.add(Offset(x, y));
    }

    _curvePath.reset();
    _curvePath.moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) * 0.5;
      _curvePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    _fillPath.reset();
    _fillPath.addPath(_curvePath, Offset.zero);
    _fillPath.lineTo(points.last.dx, midY);
    _fillPath.lineTo(points.first.dx, midY);
    _fillPath.close();

    _fillPaint.color = fillColor;
    _linePaint.color = lineColor;
    _dotPaint.color = lineColor;

    canvas.drawPath(_fillPath, _fillPaint);
    canvas.drawPath(_curvePath, _linePaint);
    for (final pt in points) {
      canvas.drawCircle(pt, 3.2, _dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.centerLineColor != centerLineColor ||
        oldDelegate.levels.length != levels.length) {
      return true;
    }
    for (var i = 0; i < levels.length; i++) {
      if ((oldDelegate.levels[i] - levels[i]).abs() > 0.001) return true;
    }
    return false;
  }
}

/// Barra vertical individual para una banda de frecuencia del ecualizador.
class _VerticalBandSlider extends StatelessWidget {
  final double frequencyHz;
  final double value;
  final double effectiveValue;
  final bool isEnabled;
  final LuminaColors colors;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VerticalBandSlider({
    required this.frequencyHz,
    required this.value,
    required this.effectiveValue,
    required this.isEnabled,
    required this.colors,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final freqLabel = EqualizerMath.formatFrequency(frequencyHz);
    final dbLabel = EqualizerMath.formatNormalizedDb(effectiveValue);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dbLabel,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isEnabled ? colors.accentInk : colors.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 148,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: isEnabled
                    ? colors.accent
                    : colors.textTertiary,
                inactiveTrackColor: colors.trackBase,
                thumbColor: isEnabled ? colors.accent : colors.textSecondary,
                overlayColor: colors.accentGlow.withValues(alpha: 0.20),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7.5,
                ),
              ),
              child: Semantics(
                label: 'Banda $freqLabel',
                value: dbLabel,
                child: Slider(
                  value: value.clamp(-1.0, 1.0),
                  min: -1.0,
                  max: 1.0,
                  onChangeStart: onChangeStart,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          freqLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta con slider horizontal para Bass Boost o Potenciador de volumen.
class _EffectSliderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool isEnabled;
  final bool isHighlighted;
  final LuminaColors colors;
  final LuminaShapes shapes;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _EffectSliderCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.isEnabled,
    required this.isHighlighted,
    required this.colors,
    required this.shapes,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(shapes.card),
        border: Border.all(
          color: isHighlighted
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
                icon,
                size: 20,
                color: isHighlighted ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? colors.accentSoft
                      : colors.surfaceHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isHighlighted ? colors.accent : colors.hairline,
                  ),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isHighlighted
                        ? colors.accentInk
                        : colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: colors.textTertiary),
            ),
          ],
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: isEnabled ? colors.accent : colors.textTertiary,
              inactiveTrackColor: colors.trackBase,
              thumbColor: isEnabled ? colors.accent : colors.textSecondary,
              overlayColor: colors.accentGlow.withValues(alpha: 0.20),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Semantics(
              label: title,
              value: valueLabel,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

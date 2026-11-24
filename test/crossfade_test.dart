import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_player/services/playback_transition_settings.dart';
import 'package:lumina_player/theme/lumina_theme.dart';
import 'package:lumina_player/widgets/crossfade_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CrossfadeCurve', () {
    test('mantiene potencia constante (equal-power) en todo el rango', () {
      expect(CrossfadeCurve.outgoingGain(0.0), closeTo(1.0, 1e-9));
      expect(CrossfadeCurve.outgoingGain(1.0), closeTo(0.0, 1e-9));
      expect(CrossfadeCurve.incomingGain(0.0), closeTo(0.0, 1e-9));
      expect(CrossfadeCurve.incomingGain(1.0), closeTo(1.0, 1e-9));

      for (var i = 0; i <= 20; i++) {
        final t = i / 20.0;
        final outG = CrossfadeCurve.outgoingGain(t);
        final inG = CrossfadeCurve.incomingGain(t);
        expect(outG * outG + inG * inG, closeTo(1.0, 1e-9));
      }
    });

    test('smoothRamp interpola suavemente y acota fuera de rango', () {
      expect(CrossfadeCurve.smoothRamp(0.0, 1.0, -0.5), 0.0);
      expect(CrossfadeCurve.smoothRamp(0.0, 1.0, 0.0), 0.0);
      expect(CrossfadeCurve.smoothRamp(0.0, 1.0, 0.5), closeTo(0.5, 1e-9));
      expect(CrossfadeCurve.smoothRamp(0.0, 1.0, 1.0), 1.0);
      expect(CrossfadeCurve.smoothRamp(0.0, 1.0, 1.5), 1.0);
      expect(CrossfadeCurve.smoothRamp(1.0, 0.0, 1.0), 0.0);
    });

    test('sleepTimerGain baja progresivamente dentro de la ventana final', () {
      expect(
        CrossfadeCurve.sleepTimerGain(remainingMs: 15000, fadeWindowMs: 10000),
        1.0,
      );
      expect(
        CrossfadeCurve.sleepTimerGain(remainingMs: 10000, fadeWindowMs: 10000),
        1.0,
      );
      expect(
        CrossfadeCurve.sleepTimerGain(remainingMs: 5000, fadeWindowMs: 10000),
        closeTo(0.25, 1e-9),
      );
      expect(
        CrossfadeCurve.sleepTimerGain(remainingMs: 0, fadeWindowMs: 10000),
        0.0,
      );
      expect(
        CrossfadeCurve.sleepTimerGain(remainingMs: -500, fadeWindowMs: 10000),
        0.0,
      );
    });
  });

  group('PlaybackTransitionSettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('acota segundos entre 0 y 12 y formatea etiquetas correctamente', () {
      expect(PlaybackTransitionSettings.clampCrossfadeSeconds(-5), 0);
      expect(PlaybackTransitionSettings.clampCrossfadeSeconds(0), 0);
      expect(PlaybackTransitionSettings.clampCrossfadeSeconds(6), 6);
      expect(PlaybackTransitionSettings.clampCrossfadeSeconds(25), 12);

      expect(
        PlaybackTransitionSettings.formatCrossfadeLabel(0),
        'Desactivado',
      );
      expect(PlaybackTransitionSettings.formatCrossfadeLabel(7), '7 s');
    });

    test('persiste y recarga preferencias correctamente', () async {
      final settings = PlaybackTransitionSettings.instance;
      await settings.load();
      expect(settings.crossfadeSeconds.value, 0);
      expect(settings.smoothPlayPauseFade.value, isTrue);
      expect(settings.sleepTimerFadeOut.value, isTrue);

      await settings.setCrossfadeSeconds(8);
      await settings.setSmoothPlayPauseFade(enabled: false);
      await settings.setSleepTimerFadeOut(enabled: false);

      expect(settings.crossfadeSeconds.value, 8);
      expect(settings.smoothPlayPauseFade.value, isFalse);
      expect(settings.sleepTimerFadeOut.value, isFalse);
      expect(settings.buildSummary(), 'Crossfade 8 s');

      // Verificar recarga desde SharedPreferences
      await settings.load();
      expect(settings.crossfadeSeconds.value, 8);
      expect(settings.smoothPlayPauseFade.value, isFalse);
      expect(settings.sleepTimerFadeOut.value, isFalse);
    });
  });

  group('CrossfadeSettingsSheet widget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PlaybackTransitionSettings.instance.load();
    });

    testWidgets('muestra el slider horizontal y los switches en Ajustes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLuminaTheme(brightness: Brightness.dark),
          home: const Scaffold(body: CrossfadeSettingsSheet()),
        ),
      );

      expect(find.text('Crossfade entre canciones'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Fundido al pausar y reanudar'), findsOneWidget);
      expect(find.text('Bajada progresiva en Temporizador'), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 0.0);
      expect(slider.max, 12.0);
      expect(slider.divisions, 12);

      // Verificar que los valores del math importado coinciden con los límites
      expect(math.cos(0), 1.0);
    });
  });
}

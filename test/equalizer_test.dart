import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_player/services/equalizer_settings.dart';
import 'package:lumina_player/theme/lumina_theme.dart';
import 'package:lumina_player/widgets/equalizer_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EqualizerMath', () {
    test('mapea ganancia normalizada al rango real del dispositivo Android', () {
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: -1.0,
          minDevice: -1.5,
          maxDevice: 1.5,
        ),
        closeTo(-1.5, 1e-9),
      );
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: 0.0,
          minDevice: -1.5,
          maxDevice: 1.5,
        ),
        closeTo(0.0, 1e-9),
      );
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: 1.0,
          minDevice: -1.5,
          maxDevice: 1.5,
        ),
        closeTo(1.5, 1e-9),
      );
      // Valores fuera de rango se acotan con seguridad.
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: 5.0,
          minDevice: -1.5,
          maxDevice: 1.5,
        ),
        closeTo(1.5, 1e-9),
      );
      // Rangos asimétricos se respetan en cada signo.
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: -0.5,
          minDevice: -1.2,
          maxDevice: 1.8,
        ),
        closeTo(-0.6, 1e-9),
      );
      expect(
        EqualizerMath.mapNormalizedToDeviceGain(
          normalized: 0.5,
          minDevice: -1.2,
          maxDevice: 1.8,
        ),
        closeTo(0.9, 1e-9),
      );
    });

    test('convierte dB de Loudness a unidades seguras de just_audio (0..1)', () {
      expect(EqualizerMath.loudnessDbToJustAudioTargetGain(-3.0), 0.0);
      expect(EqualizerMath.loudnessDbToJustAudioTargetGain(0.0), 0.0);
      expect(
        EqualizerMath.loudnessDbToJustAudioTargetGain(5.0),
        closeTo(0.5, 1e-9),
      );
      expect(
        EqualizerMath.loudnessDbToJustAudioTargetGain(10.0),
        closeTo(1.0, 1e-9),
      );
      expect(
        EqualizerMath.loudnessDbToJustAudioTargetGain(30.0),
        closeTo(1.0, 1e-9),
      );
    });

    test('remuestrea correctamente a distintos números de bandas hardware', () {
      const five = [1.0, 0.5, 0.0, -0.5, -1.0];
      expect(EqualizerMath.resampleNormalizedBands(five, 5), five);
      expect(EqualizerMath.resampleNormalizedBands(five, 0), isEmpty);
      expect(EqualizerMath.resampleNormalizedBands(five, 1), [0.0]);

      final nine = EqualizerMath.resampleNormalizedBands(five, 9);
      expect(nine.length, 9);
      expect(nine.first, closeTo(1.0, 1e-9));
      expect(nine[4], closeTo(0.0, 1e-9));
      expect(nine.last, closeTo(-1.0, 1e-9));
    });

    test('applyBassBoostToBand refuerza solo bandas graves y acota a 1.0', () {
      expect(
        EqualizerMath.applyBassBoostToBand(
          baseNormalized: 0.6,
          bandIndex: 0,
          bassBoost: 1.0,
        ),
        closeTo(1.0, 1e-9),
      );
      expect(
        EqualizerMath.applyBassBoostToBand(
          baseNormalized: 0.1,
          bandIndex: 1,
          bassBoost: 1.0,
        ),
        closeTo(0.45, 1e-9),
      );
      expect(
        EqualizerMath.applyBassBoostToBand(
          baseNormalized: 0.2,
          bandIndex: 3,
          bassBoost: 1.0,
        ),
        closeTo(0.2, 1e-9),
      );
    });

    test('formatea frecuencias y decibelios legibles', () {
      expect(EqualizerMath.formatFrequency(60.0), '60 Hz');
      expect(EqualizerMath.formatFrequency(230.0), '230 Hz');
      expect(EqualizerMath.formatFrequency(3600.0), '3.6 kHz');
      expect(EqualizerMath.formatFrequency(14000.0), '14 kHz');

      expect(EqualizerMath.formatNormalizedDb(0.0), '0 dB');
      expect(EqualizerMath.formatNormalizedDb(0.5), '+6 dB');
      expect(EqualizerMath.formatNormalizedDb(-0.5), '-6 dB');
    });
  });

  group('EqualizerSettings', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await EqualizerSettings.instance.load();
    });

    test('aplica presets, persiste cambios y recarga estado completo', () async {
      final settings = EqualizerSettings.instance;
      expect(settings.enabled.value, isFalse);
      expect(settings.preset.value, EqualizerPreset.flat);
      expect(settings.buildSummary(), 'Desactivado');

      await settings.applyPreset(EqualizerPreset.bassBoost);
      expect(settings.enabled.value, isTrue);
      expect(settings.preset.value, EqualizerPreset.bassBoost);
      expect(settings.bandLevels.value, EqualizerPreset.bassBoost.bands);

      await settings.setBandLevel(2, 0.4);
      expect(settings.preset.value, EqualizerPreset.custom);
      expect(settings.bandLevels.value[2], closeTo(0.4, 1e-9));

      await settings.setBassBoost(0.5);
      await settings.setLoudnessBoostDb(4.0);
      expect(
        settings.buildSummary(),
        'Personalizado · Graves +50% · Volumen +4 dB',
      );

      // Recargar desde SharedPreferences
      await settings.load();
      expect(settings.enabled.value, isTrue);
      expect(settings.preset.value, EqualizerPreset.custom);
      expect(settings.bandLevels.value[2], closeTo(0.4, 1e-9));
      expect(settings.bassBoost.value, closeTo(0.5, 1e-9));
      expect(settings.loudnessBoostDb.value, closeTo(4.0, 1e-9));

      await settings.reset();
      expect(settings.preset.value, EqualizerPreset.flat);
      expect(settings.hasCustomModifications, isFalse);
      expect(settings.bassBoost.value, 0.0);
      expect(settings.loudnessBoostDb.value, 0.0);
    });
  });

  group('EqualizerSheet widget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await EqualizerSettings.instance.load();
    });

    testWidgets('renderiza 5 bandas + Bass Boost + Loudness y aplica preset', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLuminaTheme(brightness: Brightness.dark),
          home: const Scaffold(body: EqualizerSheet()),
        ),
      );

      expect(find.text('Ecualizador'), findsOneWidget);
      expect(find.text('Refuerzo de graves (Bass Boost)'), findsOneWidget);
      expect(find.text('Potenciador de volumen'), findsOneWidget);
      // 5 sliders verticales de bandas + 1 Bass Boost + 1 Loudness = 7
      expect(find.byType(Slider), findsNWidgets(7));

      // Tocar preset "Rock" activa automáticamente el ecualizador
      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(EqualizerSettings.instance.enabled.value, isTrue);
      expect(EqualizerSettings.instance.preset.value, EqualizerPreset.rock);

      // El botón "Plano" en el header aparece y restablece todo
      await tester.tap(find.widgetWithText(TextButton, 'Plano'));
      await tester.pumpAndSettle();

      expect(EqualizerSettings.instance.preset.value, EqualizerPreset.flat);
      expect(EqualizerSettings.instance.hasCustomModifications, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EqualizerSettingsTile se renderiza en tema claro sin errores', (
      tester,
    ) async {
      await EqualizerSettings.instance.applyPreset(EqualizerPreset.pop);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLuminaTheme(brightness: Brightness.light),
          home: const Scaffold(body: EqualizerSettingsTile()),
        ),
      );

      expect(find.text('Ecualizador y Graves'), findsOneWidget);
      expect(find.text('Pop'), findsNWidgets(2)); // subtítulo + badge
      expect(tester.takeException(), isNull);
    });
  });
}

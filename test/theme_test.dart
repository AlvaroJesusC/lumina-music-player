import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_player/services/appearance_settings.dart';
import 'package:lumina_player/theme/lumina_colors.dart';
import 'package:lumina_player/theme/lumina_haptics.dart';
import 'package:lumina_player/theme/lumina_motion.dart';
import 'package:lumina_player/theme/lumina_shapes.dart';
import 'package:lumina_player/theme/lumina_theme.dart';

void main() {
  group('Lumina Theme Tests', () {
    test('buildLuminaTheme attaches all required extensions for dark mode', () {
      final theme = buildLuminaTheme(brightness: Brightness.dark);
      expect(theme.brightness, Brightness.dark);
      expect(theme.extension<LuminaColors>(), isNotNull);
      expect(theme.extension<LuminaMotion>(), isNotNull);
      expect(theme.extension<LuminaShapes>(), isNotNull);
      expect(theme.extension<LuminaHaptics>(), isNotNull);
    });

    test('buildLuminaTheme attaches all required extensions for light mode', () {
      final theme = buildLuminaTheme(brightness: Brightness.light);
      expect(theme.brightness, Brightness.light);
      expect(theme.extension<LuminaColors>(), isNotNull);
      expect(theme.extension<LuminaMotion>(), isNotNull);
      expect(theme.extension<LuminaShapes>(), isNotNull);
      expect(theme.extension<LuminaHaptics>(), isNotNull);
    });

    test('LuminaColors dark and light provide emerald accent #2FD27A', () {
      expect(LuminaColors.dark.accent, const Color(0xFF2FD27A));
      expect(LuminaColors.light.accent, const Color(0xFF2FD27A));
    });

    test('PlayerBackgroundStyle parsing defaults safely without throwing', () {
      expect(PlayerBackgroundStyle.parse('ambient'), PlayerBackgroundStyle.ambient);
      expect(PlayerBackgroundStyle.parse('gradient'), PlayerBackgroundStyle.gradient);
      expect(PlayerBackgroundStyle.parse('animated'), PlayerBackgroundStyle.animated);
      expect(PlayerBackgroundStyle.parse('unknown_corrupt_data'), PlayerBackgroundStyle.ambient);
      expect(PlayerBackgroundStyle.parse(null), PlayerBackgroundStyle.ambient);
    });
  });
}

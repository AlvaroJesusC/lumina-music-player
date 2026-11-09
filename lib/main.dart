import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'services/appearance_settings.dart';
import 'services/library_filter_settings.dart';
import 'services/audio_handler.dart';
import 'services/audio_service_instance.dart';
import 'app.dart';

Future<void> main() async {
  // 1. Inicialización mínima obligatoria
  WidgetsFlutterBinding.ensureInitialized();

  // Cargar preferencias de apariencia y filtros de biblioteca antes del primer paint
  await AppearanceSettings.instance.load();
  await LibraryFilterSettings.instance.load();

  // 2. Inicializar AudioService ANTES de runApp
  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.lumina_player.channel.audio',
      androidNotificationChannelName: 'Lumina Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const LuminaApp());
}

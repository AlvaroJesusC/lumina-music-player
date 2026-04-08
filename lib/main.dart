import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'services/audio_service_instance.dart';
import 'app.dart';

Future<void> main() async {
  // 1. Inicialización mínima obligatoria
  WidgetsFlutterBinding.ensureInitialized();

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

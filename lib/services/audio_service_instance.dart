import 'package:audio_service/audio_service.dart';

/// Instancia global del manejador de audio.
/// Se inicializa en main() antes de runApp() y se importa
/// desde cualquier archivo que necesite controlar el audio.
late AudioHandler audioHandler;

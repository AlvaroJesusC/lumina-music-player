import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_player/modelos/modelo_info_actualizacion.dart';
import 'package:lumina_player/servicios/servicio_actualizador.dart';
import 'package:lumina_player/theme/lumina_theme.dart';
import 'package:lumina_player/widgets/dialogo_actualizacion.dart';

void main() {
  group('Pruebas de ModeloInfoActualizacion', () {
    test('Calcula correctamente el tamaño en Megabytes legibles', () {
      const modeloConBytes = ModeloInfoActualizacion(
        versionRemota: '1.0.1',
        versionActual: '1.0.0',
        notasCambios: 'Novedades de prueba',
        urlDescargaApk: 'https://ejemplo.com/app.apk',
        nombreArchivo: 'app.apk',
        tamanoBytes: 31457280, // ~30 MB
        hayNuevaVersion: true,
      );

      expect(modeloConBytes.tamanoLegible, '30.0 MB');

      const modeloSinBytes = ModeloInfoActualizacion(
        versionRemota: '1.0.1',
        versionActual: '1.0.0',
        notasCambios: '',
        urlDescargaApk: '',
        nombreArchivo: '',
        tamanoBytes: null,
        hayNuevaVersion: true,
      );

      expect(modeloSinBytes.tamanoLegible, '');
    });
  });

  group('Pruebas de Comparación SemVer (esVersionMayor)', () {
    test('Detecta correctamente versiones superiores', () {
      expect(ServicioActualizador.esVersionMayor('1.0.1', '1.0.0'), isTrue);
      expect(ServicioActualizador.esVersionMayor('1.1.0', '1.0.9'), isTrue);
      expect(ServicioActualizador.esVersionMayor('2.0.0', '1.9.9'), isTrue);
      expect(ServicioActualizador.esVersionMayor('v1.0.2', '1.0.1'), isTrue);
      expect(ServicioActualizador.esVersionMayor('1.0.0', 'v0.9.5'), isTrue);
    });

    test('Detecta versiones iguales o menores como falsas', () {
      expect(ServicioActualizador.esVersionMayor('1.0.0', '1.0.0'), isFalse);
      expect(ServicioActualizador.esVersionMayor('v1.0.0', '1.0.0'), isFalse);
      expect(ServicioActualizador.esVersionMayor('0.9.9', '1.0.0'), isFalse);
      expect(ServicioActualizador.esVersionMayor('1.0.0', '1.0.1'), isFalse);
    });
  });

  group('Pruebas de UI de DialogoActualizacion', () {
    testWidgets('Renderiza correctamente el diálogo con el tema de Lumina', (tester) async {
      const info = ModeloInfoActualizacion(
        versionRemota: '1.1.0',
        versionActual: '1.0.0',
        notasCambios: 'Mejoras en el ecualizador y rendimiento.',
        urlDescargaApk: 'https://ejemplo.com/lumina.apk',
        nombreArchivo: 'lumina.apk',
        tamanoBytes: 29360128, // 28 MB
        hayNuevaVersion: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLuminaTheme(brightness: Brightness.dark),
          home: const Scaffold(
            body: DialogoActualizacion(info: info),
          ),
        ),
      );

      // Verificamos elementos clave de UI
      expect(find.text('Actualización disponible'), findsOneWidget);
      expect(find.text('v1.0.0 ➜ v1.1.0'), findsOneWidget);
      expect(find.text('Mejoras en el ecualizador y rendimiento.'), findsOneWidget);
      expect(find.text('Actualizar ahora'), findsOneWidget);
      expect(find.text('Más tarde'), findsOneWidget);
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
    });
  });
}


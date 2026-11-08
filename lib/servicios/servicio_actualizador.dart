import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../modelos/modelo_info_actualizacion.dart';

/// Servicio encargado de consultar las actualizaciones en GitHub Releases,
/// cotejar la versión semántica local contra la remota y obtener el APK
/// optimizado según la arquitectura del dispositivo (arm64-v8a, etc.).
class ServicioActualizador {
  // Configuración del repositorio oficial en GitHub
  static const String usuarioGitHub = 'AlvaroJesusC';
  static const String repositorioGitHub = 'lumina-music-player';

  static const String _prefUltimoChequeo = 'timestamp_ultimo_chequeo_update';

  /// Consulta la API pública de GitHub Releases para comprobar si hay actualizaciones.
  ///
  /// Si [forzar] es falso, respeta un enfriamiento de 4 horas para no saturar
  /// la cuota anónima de la API de GitHub en cada arranque de la app.
  static Future<ModeloInfoActualizacion?> verificarActualizacion({
    bool forzar = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!forzar) {
        final ultimoChequeo = prefs.getInt(_prefUltimoChequeo) ?? 0;
        final ahora = DateTime.now().millisecondsSinceEpoch;
        const cuatroHorasMs = 4 * 60 * 60 * 1000;

        if (ahora - ultimoChequeo < cuatroHorasMs) {
          return null; // Aún en periodo de enfriamiento
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final versionActual = packageInfo.version;

      final url = Uri.parse(
        'https://api.github.com/repos/$usuarioGitHub/$repositorioGitHub/releases/latest',
      );

      final respuesta = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'LuminaPlayer-Updater',
        },
      ).timeout(const Duration(seconds: 10));

      await prefs.setInt(_prefUltimoChequeo, DateTime.now().millisecondsSinceEpoch);

      if (respuesta.statusCode != 200) {
        debugPrint('[ServicioActualizador] GitHub API HTTP ${respuesta.statusCode}');
        return null;
      }

      final data = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final rawTag = (data['tag_name'] as String? ?? '').trim();
      final versionRemota = rawTag.replaceAll(RegExp(r'^[vV]'), '');

      if (versionRemota.isEmpty) return null;

      final notas = (data['body'] as String?)?.trim() ?? 'Mejoras y optimizaciones generales.';

      // Detección de arquitectura del procesador (arm64-v8a vs armeabi-v7a vs x86_64)
      String? abiPreferida;
      try {
        abiPreferida = await OtaUpdate().getAbi();
      } catch (_) {
        abiPreferida = null;
      }

      final assets = data['assets'] as List<dynamic>? ?? [];
      String? urlApk;
      String nombreArchivo = 'lumina-player-update.apk';
      int? tamanoBytes;

      // 1. Coincidencia por arquitectura nativa (APK liviano ~30MB)
      if (abiPreferida != null && abiPreferida.isNotEmpty) {
        final abi = abiPreferida.toLowerCase();
        for (final asset in assets) {
          final nombre = (asset['name'] as String? ?? '').toLowerCase();
          if (nombre.endsWith('.apk') && nombre.contains(abi)) {
            urlApk = asset['browser_download_url'] as String?;
            nombreArchivo = asset['name'] as String? ?? nombreArchivo;
            tamanoBytes = asset['size'] as int?;
            break;
          }
        }
      }

      // 2. Fallback general (primer APK encontrado si no coincide el nombre exacto de la ABI)
      if (urlApk == null) {
        for (final asset in assets) {
          final nombre = (asset['name'] as String? ?? '').toLowerCase();
          if (nombre.endsWith('.apk')) {
            urlApk = asset['browser_download_url'] as String?;
            nombreArchivo = asset['name'] as String? ?? nombreArchivo;
            tamanoBytes = asset['size'] as int?;
            break;
          }
        }
      }

      if (urlApk == null || urlApk.isEmpty) return null;

      final hayNueva = esVersionMayor(versionRemota, versionActual);

      // Si no es comprobación manual y no hay actualización, no interrumpir al usuario
      if (!forzar && !hayNueva) return null;

      return ModeloInfoActualizacion(
        versionRemota: versionRemota,
        versionActual: versionActual,
        notasCambios: notas,
        urlDescargaApk: urlApk,
        nombreArchivo: nombreArchivo,
        tamanoBytes: tamanoBytes,
        hayNuevaVersion: hayNueva,
      );
    } catch (e) {
      debugPrint('[ServicioActualizador] Error al comprobar actualización: $e');
      return null;
    }
  }

  /// Compara dos versiones semánticas (ej. "1.0.2" vs "1.0.1+1").
  /// Devuelve true si [versionRemota] es estrictamente mayor que [versionLocal].
  static bool esVersionMayor(String versionRemota, String versionLocal) {
    try {
      String limpiar(String v) =>
          v.replaceAll(RegExp(r'^[vV]'), '').split('+').first.split('-').first.trim();
      final partesRemota =
          limpiar(versionRemota).split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final partesLocal =
          limpiar(versionLocal).split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLong =
          partesRemota.length > partesLocal.length ? partesRemota.length : partesLocal.length;

      for (int i = 0; i < maxLong; i++) {
        final r = i < partesRemota.length ? partesRemota[i] : 0;
        final l = i < partesLocal.length ? partesLocal[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}


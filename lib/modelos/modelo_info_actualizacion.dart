/// Modelo inmutable con la información de una versión disponible en GitHub Releases.
class ModeloInfoActualizacion {
  final String versionRemota;
  final String versionActual;
  final String notasCambios;
  final String urlDescargaApk;
  final String nombreArchivo;
  final int? tamanoBytes;
  final bool hayNuevaVersion;

  const ModeloInfoActualizacion({
    required this.versionRemota,
    required this.versionActual,
    required this.notasCambios,
    required this.urlDescargaApk,
    required this.nombreArchivo,
    this.tamanoBytes,
    required this.hayNuevaVersion,
  });

  /// Devuelve el tamaño del archivo formateado en Megabytes (ej. "28.5 MB").
  String get tamanoLegible {
    if (tamanoBytes == null || tamanoBytes! <= 0) return '';
    final megas = tamanoBytes! / (1024 * 1024);
    return '${megas.toStringAsFixed(1)} MB';
  }
}


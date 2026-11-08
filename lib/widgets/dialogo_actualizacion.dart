import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../modelos/modelo_info_actualizacion.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';

/// Diálogo elegante y adaptativo para presentar nuevas actualizaciones de Lumina Player,
/// descargar el APK en segundo plano con indicador de porcentaje y disparar el instalador nativo.
class DialogoActualizacion extends StatefulWidget {
  final ModeloInfoActualizacion info;

  const DialogoActualizacion({super.key, required this.info});

  /// Muestra el diálogo modal de actualización sobre el contexto actual.
  static Future<void> mostrar(
    BuildContext context, {
    required ModeloInfoActualizacion info,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogoActualizacion(info: info),
    );
  }

  @override
  State<DialogoActualizacion> createState() => _DialogoActualizacionState();
}

class _DialogoActualizacionState extends State<DialogoActualizacion> {
  StreamSubscription<OtaEvent>? _subscripcion;
  bool _descargando = false;
  double _progreso = 0.0;
  String _estadoMensaje = '';
  String? _errorMensaje;

  @override
  void dispose() {
    _subscripcion?.cancel();
    super.dispose();
  }

  void _iniciarActualizacion() {
    LuminaHaptics.fire(context, HapticEvent.commit);

    setState(() {
      _descargando = true;
      _errorMensaje = null;
      _progreso = 0.0;
      _estadoMensaje = 'Conectando con el servidor...';
    });

    try {
      _subscripcion = OtaUpdate()
          .execute(
            widget.info.urlDescargaApk,
            destinationFilename: widget.info.nombreArchivo,
          )
          .listen(
            (OtaEvent event) {
              if (!mounted) return;
              switch (event.status) {
                case OtaStatus.DOWNLOADING:
                  final p = double.tryParse(event.value ?? '0') ?? 0.0;
                  setState(() {
                    _progreso = (p / 100.0).clamp(0.0, 1.0);
                    _estadoMensaje = 'Descargando: ${p.toInt()}%';
                  });
                  break;
                case OtaStatus.INSTALLING:
                  setState(() {
                    _progreso = 1.0;
                    _estadoMensaje = 'Abriendo instalador del sistema...';
                  });
                  LuminaHaptics.fire(context, HapticEvent.success);
                  break;
                case OtaStatus.INSTALLATION_DONE:
                  setState(() => _estadoMensaje = 'Instalación finalizada.');
                  break;
                case OtaStatus.INSTALLATION_ERROR:
                  LuminaHaptics.fire(context, HapticEvent.reject);
                  setState(() {
                    _descargando = false;
                    _errorMensaje =
                        'No se pudo iniciar el instalador. Verifica los permisos de instalación de la app.';
                  });
                  break;
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  LuminaHaptics.fire(context, HapticEvent.reject);
                  setState(() {
                    _descargando = false;
                    _errorMensaje =
                        'Permiso denegado para instalar fuentes desconocidas. Concede el permiso en Ajustes de Android.';
                  });
                  break;
                case OtaStatus.DOWNLOAD_ERROR:
                  LuminaHaptics.fire(context, HapticEvent.reject);
                  setState(() {
                    _descargando = false;
                    _errorMensaje =
                        'Error de conexión al descargar la actualización. Revisa tu red.';
                  });
                  break;
                case OtaStatus.INTERNAL_ERROR:
                  LuminaHaptics.fire(context, HapticEvent.reject);
                  setState(() {
                    _descargando = false;
                    _errorMensaje =
                        'Error interno del actualizador: ${event.value ?? ""}';
                  });
                  break;
                case OtaStatus.ALREADY_RUNNING_ERROR:
                  setState(() => _estadoMensaje = 'Descarga en curso...');
                  break;
                case OtaStatus.CHECKSUM_ERROR:
                  LuminaHaptics.fire(context, HapticEvent.reject);
                  setState(() {
                    _descargando = false;
                    _errorMensaje =
                        'Error de verificación en el archivo descargado. Intenta de nuevo.';
                  });
                  break;
                case OtaStatus.CANCELED:
                  setState(() {
                    _descargando = false;
                    _estadoMensaje = 'Descarga cancelada.';
                  });
                  break;
              }
            },
            onError: (dynamic error) {
              if (!mounted) return;
              LuminaHaptics.fire(context, HapticEvent.reject);
              setState(() {
                _descargando = false;
                _errorMensaje = 'Error en la actualización: $error';
              });
            },
          );
    } catch (e) {
      if (!mounted) return;
      LuminaHaptics.fire(context, HapticEvent.reject);
      setState(() {
        _descargando = false;
        _errorMensaje = 'Excepción al iniciar descarga: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final tamano = widget.info.tamanoLegible;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(shapes.card + 4),
          border: Border.all(color: colors.hairline, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera con icono estilizado y datos de versión
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(shapes.artworkSmall),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: colors.accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actualización disponible',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: colors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v${widget.info.versionActual} ➜ v${widget.info.versionRemota}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.accentInk,
                              ),
                            ),
                          ),
                          if (tamano.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '($tamano)',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Sección de notas de versión
            Text(
              'Novedades de esta versión:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceHighest,
                borderRadius: BorderRadius.circular(shapes.field),
                border: Border.all(color: colors.hairline, width: 0.8),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    widget.info.notasCambios,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Barra de progreso animada durante la descarga
            if (_descargando) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progreso > 0 ? _progreso : null,
                  minHeight: 6,
                  backgroundColor: colors.trackBase,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _estadoMensaje,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_progreso > 0)
                    Text(
                      '${(_progreso * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colors.accentInk,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Mensaje de error
            if (_errorMensaje != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMensaje!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Botones de acción
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_descargando)
                  TextButton(
                    onPressed: () {
                      LuminaHaptics.fire(context, HapticEvent.select);
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(shapes.field),
                      ),
                    ),
                    child: const Text(
                      'Más tarde',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _descargando ? null : _iniciarActualizacion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(shapes.field),
                    ),
                  ),
                  child: Text(
                    _descargando
                        ? 'Descargando...'
                        : (_errorMensaje != null
                            ? 'Reintentar'
                            : 'Actualizar ahora'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


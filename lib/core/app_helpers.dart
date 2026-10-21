import 'package:flutter/material.dart';

class AppHelpers {
  /// Portada predeterminada única: fondo gris elegante con una nota musical en medio.
  static Widget getDefaultCover({
    required BuildContext context,
    int? id,
    double? width,
    double? height,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double iconSize = (width != null && height != null)
        ? (width < height ? width : height) * 0.48
        : (width != null ? width * 0.48 : (height != null ? height * 0.48 : 28));

    return Container(
      width: width,
      height: height,
      color: isDark ? const Color(0xFF282828) : const Color(0xFFE2E2E2),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize.clamp(16.0, 96.0),
        color: isDark ? Colors.white54 : Colors.black45,
      ),
    );
  }

  /// Mantenido por retrocompatibilidad: retorna la portada predeterminada única.
  static Widget getRandomDefaultCover({
    required BuildContext context,
    required int id,
    double? width,
    double? height,
  }) {
    return getDefaultCover(
      context: context,
      id: id,
      width: width,
      height: height,
    );
  }
}

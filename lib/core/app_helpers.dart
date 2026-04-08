import 'package:flutter/material.dart';

/// Utilidades estáticas compartidas en toda la app.
class AppHelpers {
  static Widget getRandomDefaultCover({
    required BuildContext context,
    required int id,
    double? width,
    double? height,
  }) {
    final coverIndex = (id.hashCode).abs() % 5 + 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/covers/cover_$coverIndex.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: isDark
          ? Container(color: Colors.black.withValues(alpha: 0.3))
          : null,
    );
  }
}

import 'package:flutter/material.dart';

/// Tokens de forma: radios por rol, no por número.
@immutable
class LuminaShapes extends ThemeExtension<LuminaShapes> {
  /// Crea los tokens; usar [standardSet].
  const LuminaShapes({
    required this.artworkLarge,
    required this.artworkMedium,
    required this.artworkSmall,
    required this.card,
    required this.miniPlayer,
    required this.sheet,
    required this.field,
  });

  /// Carátula del reproductor completo.
  final double artworkLarge;

  /// Carátula en layout horizontal o portadas de playlist.
  final double artworkMedium;

  /// Miniaturas en listas y Mini-Player.
  final double artworkSmall;

  /// Tarjetas y filas de lista.
  final double card;

  /// Cápsula del Mini-Player flotante.
  final double miniPlayer;

  /// Borde superior de hojas modales y del reproductor completo.
  final double sheet;

  /// Campos de búsqueda.
  final double field;

  /// Valores de forma de Lumina.
  static const LuminaShapes standardSet = LuminaShapes(
    artworkLarge: 28,
    artworkMedium: 22,
    artworkSmall: 12,
    card: 18,
    miniPlayer: 20,
    sheet: 30,
    field: 16,
  );

  /// Devuelve los tokens del tema activo (falla en debug si faltan).
  static LuminaShapes of(BuildContext context) {
    final ext = Theme.of(context).extension<LuminaShapes>();
    assert(ext != null, 'LuminaShapes ausente. Usa buildLuminaTheme().');
    return ext!;
  }

  @override
  LuminaShapes copyWith({
    double? artworkLarge,
    double? artworkMedium,
    double? artworkSmall,
    double? card,
    double? miniPlayer,
    double? sheet,
    double? field,
  }) {
    return LuminaShapes(
      artworkLarge: artworkLarge ?? this.artworkLarge,
      artworkMedium: artworkMedium ?? this.artworkMedium,
      artworkSmall: artworkSmall ?? this.artworkSmall,
      card: card ?? this.card,
      miniPlayer: miniPlayer ?? this.miniPlayer,
      sheet: sheet ?? this.sheet,
      field: field ?? this.field,
    );
  }

  @override
  LuminaShapes lerp(LuminaShapes? other, double t) {
    if (other == null) return this;
    double d(double a, double b) => a + (b - a) * t;
    return LuminaShapes(
      artworkLarge: d(artworkLarge, other.artworkLarge),
      artworkMedium: d(artworkMedium, other.artworkMedium),
      artworkSmall: d(artworkSmall, other.artworkSmall),
      card: d(card, other.card),
      miniPlayer: d(miniPlayer, other.miniPlayer),
      sheet: d(sheet, other.sheet),
      field: d(field, other.field),
    );
  }
}

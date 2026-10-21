import 'package:flutter/painting.dart';

/// TIER 1 — Primitivas de color de Lumina.
///
/// ÚNICO archivo del proyecto autorizado a declarar literales de color.
/// Los nombres describen el valor medido (luminosidad aproximada ×100 o el
/// tono), nunca el rol: los widgets jamás leen esta clase directamente, sólo
/// los slots semánticos de `LuminaColors`.
abstract final class LuminaPrimitives {
  // Neutros fríos (oscuro → claro).
  static const Color neutral04 = Color(0xFF0B0B0F);
  static const Color neutral08 = Color(0xFF15151B);
  static const Color neutral11 = Color(0xFF1C1C24);
  static const Color neutral14 = Color(0xFF24242E);
  static const Color neutral93 = Color(0xFFECEEF2);
  static const Color neutral97 = Color(0xFFF6F7F9);
  static const Color neutral100 = Color(0xFFFFFFFF);

  // Tinta para texto.
  static const Color ink98 = Color(0xFFF7F7FA);
  static const Color ink10 = Color(0xFF101114);

  // Acento esmeralda (relleno) y variantes con contraste AA.
  static const Color emerald70 = Color(0xFF2FD27A);
  static const Color emerald50 = Color(0xFF0B8A49);
  static const Color emerald06 = Color(0xFF04140B);

  // Tintes de fondo para el degradado fijo del reproductor.
  static const Color emeraldShadow12 = Color(0xFF0F2A1C);
  static const Color emeraldMist92 = Color(0xFFDDF5E8);

  // Negro puro para sombras (la opacidad se aplica en el slot semántico).
  static const Color black = Color(0xFF000000);
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/appearance_settings.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_motion.dart';
import 'cached_artwork.dart';

/// Fondo adaptativo y de ultra alto rendimiento para el reproductor completo.
///
/// Soporta los tres modos elegibles en Ajustes:
/// 1. [PlayerBackgroundStyle.gradient]: Degradado fijo elegante con tinte esmeralda.
/// 2. [PlayerBackgroundStyle.ambient]: Tinte ambiental derivado de la carátula
///    actual mediante una miniatura ultraligera (sin BackdropFilter costoso).
/// 3. [PlayerBackgroundStyle.animated]: Degradado dinámico que cambia de color
///    suavemente a lo largo del tiempo.
///
/// Optimizado para 60/120 FPS con [RepaintBoundary], parada automática bajo
/// movimiento reducido y descarte limpio de animación.
class PlayerBackground extends StatefulWidget {
  final int songId;
  final Widget child;

  const PlayerBackground({
    super.key,
    required this.songId,
    required this.child,
  });

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _driftController;
  late final Animation<double> _driftAnimation;

  @override
  void initState() {
    super.initState();
    _driftController = AnimationController(
      vsync: this,
      duration: LuminaMotion.standardSet.driftCycle,
    );

    _driftAnimation = CurvedAnimation(
      parent: _driftController,
      curve: LuminaMotion.standardSet.drift,
    );

    if (AppearanceSettings.instance.backgroundStyle.value ==
        PlayerBackgroundStyle.animated) {
      _startDriftIfAllowed();
    }

    AppearanceSettings.instance.backgroundStyle.addListener(_onStyleChanged);
  }

  void _onStyleChanged() {
    if (!mounted) return;
    if (AppearanceSettings.instance.backgroundStyle.value ==
        PlayerBackgroundStyle.animated) {
      _startDriftIfAllowed();
    } else {
      _driftController.stop();
    }
    setState(() {});
  }

  void _startDriftIfAllowed() {
    if (!LuminaMotion.isReduced(context)) {
      _driftController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    AppearanceSettings.instance.backgroundStyle.removeListener(_onStyleChanged);
    _driftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final style = AppearanceSettings.instance.backgroundStyle.value;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Capa de Fondo (Aislada con RepaintBoundary)
        RepaintBoundary(
          child: switch (style) {
            PlayerBackgroundStyle.gradient => _buildFixedGradient(colors),
            PlayerBackgroundStyle.ambient => _buildAmbientBackground(colors),
            PlayerBackgroundStyle.animated => _buildAnimatedGradient(colors),
          },
        ),

        // 2. Contenido interactivo (pasado como child para no re-renderizarlo)
        widget.child,
      ],
    );
  }

  Widget _buildFixedGradient(LuminaColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.backdropTop,
            colors.background,
            colors.background,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildAmbientBackground(LuminaColors colors) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base oscura
        ColoredBox(color: colors.background),

        // Minilámina de carátula estirada y atenuada (0 ms de raster blur)
        Opacity(
          opacity: 0.18,
          child: CachedArtwork(
            songId: widget.songId,
            width: double.infinity,
            height: double.infinity,
            borderRadius: 0,
            size: 60, // Tamaño muy pequeño para rendimiento instantáneo
          ),
        ),

        // Velo de gradiente para contraste impecable de los controles
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.background.withValues(alpha: 0.60),
                colors.background.withValues(alpha: 0.92),
                colors.background,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedGradient(LuminaColors colors) {
    // Si el usuario tiene animaciones reducidas, se muestra estático
    if (LuminaMotion.isReduced(context)) {
      return _buildFixedGradient(colors);
    }

    return AnimatedBuilder(
      animation: _driftAnimation,
      builder: (context, _) {
        final t = _driftAnimation.value;
        // Ciclo HSL suave con derivación cromática controlada
        final hue1 = (145.0 + math.sin(t * math.pi) * 45.0) % 360.0;
        final hue2 = (210.0 + math.cos(t * math.pi) * 35.0) % 360.0;

        final color1 = colors.driftColor(hue1).withValues(alpha: 0.28);
        final color2 = colors.driftColor(hue2).withValues(alpha: 0.20);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color1,
                color2,
                colors.background,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        );
      },
    );
  }
}

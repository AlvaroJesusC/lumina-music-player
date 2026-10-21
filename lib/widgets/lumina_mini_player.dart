import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';
import 'cached_artwork.dart';

/// Mini-Player flotante de alta estética y rendimiento ultraoptimizado.
///
/// Características:
/// - Cápsula flotante elevada con borde sutil y sombra difuminada.
/// - Línea de progreso inferior aislada con [RepaintBoundary] para no
///   reconstruir la carátula ni los textos en cada tick de posición.
/// - Micro-interacciones hápticas en Play/Pause y Siguiente.
/// - Conexión íntegra a [AudioHandler].
class LuminaMiniPlayer extends StatelessWidget {
  final MediaItem item;
  final AudioHandler audioHandler;
  final VoidCallback onTap;

  const LuminaMiniPlayer({
    super.key,
    required this.item,
    required this.audioHandler,
    required this.onTap,
  });

  void _handlePlayPause(BuildContext context, bool playing) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    final action = playing ? audioHandler.pause() : audioHandler.play();
    unawaited(
      action.catchError((Object error, StackTrace stack) {
        debugPrint('Error toggling play/pause from mini player: $error\n$stack');
      }),
    );
  }

  void _handleNext(BuildContext context) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    unawaited(
      audioHandler.skipToNext().catchError((Object error, StackTrace stack) {
        debugPrint('Error skipping to next from mini player: $error\n$stack');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final songId = int.tryParse(item.id) ?? 0;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(shapes.miniPlayer),
            border: Border.all(color: colors.hairline, width: 1),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(shapes.miniPlayer),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(shapes.miniPlayer),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      child: Row(
                        children: [
                          CachedArtwork(
                            songId: songId,
                            width: 52,
                            height: 52,
                            borderRadius: shapes.artworkSmall,
                            size: 160,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    letterSpacing: -0.2,
                                    color: colors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.artist ?? "Desconocido",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.skip_next_rounded,
                              color: colors.textPrimary,
                              size: 30,
                            ),
                            tooltip: 'Siguiente',
                            onPressed: () => _handleNext(context),
                          ),
                          StreamBuilder<PlaybackState>(
                            stream: audioHandler.playbackState,
                            builder: (context, snapshot) {
                              final playing = snapshot.data?.playing ?? false;
                              return IconButton(
                                icon: Icon(
                                  playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_filled_rounded,
                                  size: 40,
                                  color: colors.accent,
                                ),
                                tooltip: playing ? 'Pausar' : 'Reproducir',
                                onPressed: () =>
                                    _handlePlayPause(context, playing),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    _MiniPlayerProgressBar(
                      totalDuration: item.duration ?? Duration.zero,
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de progreso de 2 px en la base del Mini-Player (aislada en RepaintBoundary)
class _MiniPlayerProgressBar extends StatelessWidget {
  final Duration totalDuration;
  final LuminaColors colors;

  const _MiniPlayerProgressBar({
    required this.totalDuration,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDuration.inMilliseconds <= 0) {
      return const SizedBox(height: 2);
    }

    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: AudioService.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final double fraction = (position.inMilliseconds /
                  totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);

          return Container(
            height: 2,
            width: double.infinity,
            color: colors.trackBase,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(color: colors.accent),
            ),
          );
        },
      ),
    );
  }
}

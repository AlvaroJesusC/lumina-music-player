import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_motion.dart';
import '../theme/lumina_shapes.dart';
import '../widgets/cached_artwork.dart';
import '../widgets/player_background.dart';
import '../widgets/queue_bottom_sheet.dart';

/// Reproductor a pantalla completa de alta fidelidad estética y 60/120 FPS.
///
/// Implementa las directivas de las skills:
/// - `design-system-structure`: Lee tokens semánticos de LuminaColors/Motion/Shapes.
/// - `motion-and-haptics`: Morphing suave en Play/Pause, escalado natural de
///   carátula y feedback háptico gobernado por el interruptor central.
/// - `flutter-performance`: Scrubber aislado en RepaintBoundary, fondos
///   desacoplados del árbol estático y sin BackdropFilter costoso.
/// - `async-safety`: Handlers async-safe protegidos contra excepciones.
class FullPlayerScreen extends StatefulWidget {
  final AudioHandler audioHandler;
  final Set<int> favoriteIds;
  final void Function(int) onToggleFavorite;

  const FullPlayerScreen({
    super.key,
    required this.audioHandler,
    required this.favoriteIds,
    required this.onToggleFavorite,
  });

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  void _showQueueModal(BuildContext context) {
    QueueBottomSheet.show(context, widget.audioHandler);
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        final songId = int.tryParse(item.id) ?? 0;

        return SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(shapes.sheet),
            ),
            child: PlayerBackground(
              songId: songId,
              child: SafeArea(
                child: OrientationBuilder(
                  builder: (context, orientation) {
                    final isLandscape = orientation == Orientation.landscape;

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        if (isLandscape) {
                          return _LandscapePlayerLayout(
                            item: item,
                            songId: songId,
                            audioHandler: widget.audioHandler,
                            favoriteIds: widget.favoriteIds,
                            onToggleFavorite: widget.onToggleFavorite,
                            colors: colors,
                            constraints: constraints,
                            onShowQueue: () => _showQueueModal(context),
                          );
                        }

                        return _PortraitPlayerLayout(
                          item: item,
                          songId: songId,
                          audioHandler: widget.audioHandler,
                          favoriteIds: widget.favoriteIds,
                          onToggleFavorite: widget.onToggleFavorite,
                          colors: colors,
                          constraints: constraints,
                          onShowQueue: () => _showQueueModal(context),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Barra superior refinada con controles de minimizado y cola de reproducción
class _PlayerHeader extends StatelessWidget {
  final String? album;
  final LuminaColors colors;
  final VoidCallback onClose;
  final VoidCallback onShowQueue;

  const _PlayerHeader({
    required this.album,
    required this.colors,
    required this.onClose,
    required this.onShowQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 32,
            color: colors.textPrimary,
          ),
          tooltip: 'Minimizar',
          onPressed: onClose,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "REPRODUCIENDO",
                style: TextStyle(
                  letterSpacing: 2.2,
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (album != null && album!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  album!,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.queue_music_rounded,
            size: 24,
            color: colors.textPrimary,
          ),
          tooltip: 'Cola de reproducción',
          onPressed: onShowQueue,
        ),
      ],
    );
  }
}

/// Carátula animada con escala orgánica entre reproducción y pausa
class _PlayerArtwork extends StatelessWidget {
  final int songId;
  final double size;
  final LuminaColors colors;
  final AudioHandler audioHandler;

  const _PlayerArtwork({
    required this.songId,
    required this.size,
    required this.colors,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    final shapes = LuminaShapes.of(context);
    final motion = LuminaMotion.of(context);

    return RepaintBoundary(
      child: StreamBuilder<PlaybackState>(
        stream: audioHandler.playbackState,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data?.playing ?? false;
          final scale = isPlaying ? 1.0 : 0.93;

          return AnimatedScale(
            scale: LuminaMotion.isReduced(context) ? 1.0 : scale,
            duration: LuminaMotion.resolve(context, motion.long),
            curve: motion.standard,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(shapes.artworkLarge),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: colors.accentGlow.withValues(alpha: 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CachedArtwork(
                songId: songId,
                width: size,
                height: size,
                borderRadius: shapes.artworkLarge,
                size: 500,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Información de la canción (título y artista) con jerarquía tipográfica limpia
class _SongInfo extends StatelessWidget {
  final String title;
  final String? artist;
  final LuminaColors colors;

  const _SongInfo({
    required this.title,
    required this.artist,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: colors.textPrimary,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          artist ?? "Desconocido",
          style: TextStyle(
            fontSize: 16,
            color: colors.accentInk,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Scrubber aislado de la barra de progreso (flutter-performance).
class _IsolatedProgressBar extends StatelessWidget {
  final AudioHandler audioHandler;
  final Duration totalDuration;
  final LuminaColors colors;

  const _IsolatedProgressBar({
    required this.audioHandler,
    required this.totalDuration,
    required this.colors,
  });

  void _handleSeek(Duration position) {
    unawaited(
      audioHandler.seek(position).catchError((Object error, StackTrace stack) {
        debugPrint('Error seeking in audio: $error\n$stack');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: AudioService.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          return ProgressBar(
            progress: position,
            total: totalDuration,
            progressBarColor: colors.accent,
            baseBarColor: colors.trackBase,
            bufferedBarColor: colors.textTertiary.withValues(alpha: 0.25),
            thumbColor: colors.accent,
            thumbGlowColor: colors.accentGlow,
            barHeight: 4,
            thumbRadius: 7,
            timeLabelTextStyle: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            onSeek: _handleSeek,
          );
        },
      ),
    );
  }
}

/// Botón de favorito aislado con micro-interacción de escala y respuesta háptica
class _FavoriteButton extends StatefulWidget {
  final int songId;
  final bool initialIsFavorite;
  final void Function(int) onToggleFavorite;
  final LuminaColors colors;

  const _FavoriteButton({
    super.key,
    required this.songId,
    required this.initialIsFavorite,
    required this.onToggleFavorite,
    required this.colors,
  });

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initialIsFavorite;
  }

  @override
  void didUpdateWidget(covariant _FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        oldWidget.initialIsFavorite != widget.initialIsFavorite) {
      _isFavorite = widget.initialIsFavorite;
    }
  }

  void _handleToggle() {
    LuminaHaptics.fire(context, HapticEvent.select);
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onToggleFavorite(widget.songId);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: LuminaMotion.resolve(
          context,
          LuminaMotion.of(context).short,
        ),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: child,
        ),
        child: Icon(
          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(_isFavorite),
          color: _isFavorite ? widget.colors.accent : widget.colors.textSecondary,
          size: 26,
        ),
      ),
      tooltip: _isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
      onPressed: _handleToggle,
    );
  }
}

/// Botón Play/Pause con Morphing animado y retroalimentación háptica
class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final LuminaColors colors;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    required this.colors,
  });

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: LuminaMotion.standardSet.medium,
    );
    if (widget.isPlaying) {
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.colors.accent,
        boxShadow: [
          BoxShadow(
            color: widget.colors.accentGlow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        icon: AnimatedIcon(
          icon: AnimatedIcons.play_pause,
          progress: _animController,
          size: 38,
          color: widget.colors.onAccent,
        ),
        tooltip: widget.isPlaying ? 'Pausar' : 'Reproducir',
        onPressed: widget.onPressed,
      ),
    );
  }
}

/// Controles de reproducción aislados con RepaintBoundary y respuesta háptica
class _PlaybackControls extends StatelessWidget {
  final AudioHandler audioHandler;
  final int songId;
  final bool isFavorite;
  final void Function(int) onToggleFavorite;
  final LuminaColors colors;

  const _PlaybackControls({
    required this.audioHandler,
    required this.songId,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.colors,
  });

  void _handleShuffle(BuildContext context, bool isShuffle) {
    LuminaHaptics.fire(context, HapticEvent.select);
    final nextMode = isShuffle
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    unawaited(
      audioHandler.setShuffleMode(nextMode).catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('Error toggling shuffle: $error\n$stack');
      }),
    );
  }

  void _handlePrevious(BuildContext context) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    unawaited(
      audioHandler.skipToPrevious().catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('Error skipping to previous: $error\n$stack');
      }),
    );
  }

  void _handlePlayPause(BuildContext context, bool playing) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    final action = playing ? audioHandler.pause() : audioHandler.play();
    unawaited(
      action.catchError((Object error, StackTrace stack) {
        debugPrint('Error toggling play/pause: $error\n$stack');
      }),
    );
  }

  void _handleNext(BuildContext context) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    unawaited(
      audioHandler.skipToNext().catchError((Object error, StackTrace stack) {
        debugPrint('Error skipping to next: $error\n$stack');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<PlaybackState>(
        stream: audioHandler.playbackState,
        builder: (context, snapshot) {
          final playback = snapshot.data;
          final isShuffle =
              (playback?.shuffleMode ?? AudioServiceShuffleMode.none) !=
              AudioServiceShuffleMode.none;
          final playing = playback?.playing ?? false;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: isShuffle ? colors.accent : colors.textTertiary,
                  size: 24,
                ),
                tooltip: 'Aleatorio',
                onPressed: () => _handleShuffle(context, isShuffle),
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 38,
                  color: colors.textPrimary,
                ),
                tooltip: 'Anterior',
                onPressed: () => _handlePrevious(context),
              ),
              _PlayPauseButton(
                isPlaying: playing,
                onPressed: () => _handlePlayPause(context, playing),
                colors: colors,
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 38,
                  color: colors.textPrimary,
                ),
                tooltip: 'Siguiente',
                onPressed: () => _handleNext(context),
              ),
              _FavoriteButton(
                key: ValueKey(songId),
                songId: songId,
                initialIsFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
                colors: colors,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Layout vertical (Portrait)
class _PortraitPlayerLayout extends StatelessWidget {
  final MediaItem item;
  final int songId;
  final AudioHandler audioHandler;
  final Set<int> favoriteIds;
  final void Function(int) onToggleFavorite;
  final LuminaColors colors;
  final BoxConstraints constraints;
  final VoidCallback onShowQueue;

  const _PortraitPlayerLayout({
    required this.item,
    required this.songId,
    required this.audioHandler,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.colors,
    required this.constraints,
    required this.onShowQueue,
  });

  @override
  Widget build(BuildContext context) {
    final double artworkSize = (constraints.maxHeight * 0.40).clamp(
      180.0,
      360.0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PlayerHeader(
            album: item.album,
            colors: colors,
            onClose: () => Navigator.pop(context),
            onShowQueue: onShowQueue,
          ),
          Center(
            child: _PlayerArtwork(
              songId: songId,
              size: artworkSize,
              colors: colors,
              audioHandler: audioHandler,
            ),
          ),
          _SongInfo(
            title: item.title,
            artist: item.artist,
            colors: colors,
          ),
          _IsolatedProgressBar(
            audioHandler: audioHandler,
            totalDuration: item.duration ?? Duration.zero,
            colors: colors,
          ),
          _PlaybackControls(
            audioHandler: audioHandler,
            songId: songId,
            isFavorite: favoriteIds.contains(songId),
            onToggleFavorite: onToggleFavorite,
            colors: colors,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Layout horizontal (Landscape adaptativo en dos columnas)
class _LandscapePlayerLayout extends StatelessWidget {
  final MediaItem item;
  final int songId;
  final AudioHandler audioHandler;
  final Set<int> favoriteIds;
  final void Function(int) onToggleFavorite;
  final LuminaColors colors;
  final BoxConstraints constraints;
  final VoidCallback onShowQueue;

  const _LandscapePlayerLayout({
    required this.item,
    required this.songId,
    required this.audioHandler,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.colors,
    required this.constraints,
    required this.onShowQueue,
  });

  @override
  Widget build(BuildContext context) {
    final double artworkSize = (constraints.maxHeight * 0.72).clamp(
      130.0,
      280.0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: _PlayerArtwork(
                songId: songId,
                size: artworkSize,
                colors: colors,
                audioHandler: audioHandler,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PlayerHeader(
                  album: item.album,
                  colors: colors,
                  onClose: () => Navigator.pop(context),
                  onShowQueue: onShowQueue,
                ),
                _SongInfo(
                  title: item.title,
                  artist: item.artist,
                  colors: colors,
                ),
                _IsolatedProgressBar(
                  audioHandler: audioHandler,
                  totalDuration: item.duration ?? Duration.zero,
                  colors: colors,
                ),
                _PlaybackControls(
                  audioHandler: audioHandler,
                  songId: songId,
                  isFavorite: favoriteIds.contains(songId),
                  onToggleFavorite: onToggleFavorite,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

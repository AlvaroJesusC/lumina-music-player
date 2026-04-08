import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../core/app_helpers.dart';

/// Reproductor a pantalla completa que se muestra como bottom sheet modal.
class FullPlayerScreen extends StatefulWidget {
  final AudioHandler audioHandler;
  final Set<int> favoriteIds;
  final Function(int) onToggleFavorite;

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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black87;

    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        return Container(
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 35,
                          color: onSurface,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        "REPRODUCIENDO",
                        style: TextStyle(
                          letterSpacing: 2,
                          color: onSurface.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: QueryArtworkWidget(
                        id: int.parse(item.id),
                        type: ArtworkType.AUDIO,
                        artworkWidth: MediaQuery.of(context).size.width * 0.85,
                        artworkHeight: MediaQuery.of(context).size.width * 0.85,
                        size: 2000,
                        format: ArtworkFormat.PNG,
                        artworkFit: BoxFit.cover,
                        nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                          context: context,
                          id: int.parse(item.id),
                          width: MediaQuery.of(context).size.width * 0.85,
                          height: MediaQuery.of(context).size.width * 0.85,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.artist ?? "Desconocido",
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ],
                  ),
                  StreamBuilder<Duration>(
                    stream: AudioService.position,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      return ProgressBar(
                        progress: position,
                        total: item.duration ?? Duration.zero,
                        progressBarColor: const Color(0xFF4CAF50),
                        baseBarColor: onSurface.withValues(alpha: 0.1),
                        thumbColor: onSurface,
                        barHeight: 4,
                        thumbRadius: 6,
                        onSeek: (d) => widget.audioHandler.seek(d),
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StreamBuilder<PlaybackState>(
                        stream: widget.audioHandler.playbackState,
                        builder: (context, snapshot) {
                          final shuffleMode =
                              snapshot.data?.shuffleMode ??
                              AudioServiceShuffleMode.none;
                          final isShuffle =
                              shuffleMode != AudioServiceShuffleMode.none;
                          return IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: isShuffle
                                  ? const Color(0xFF4CAF50)
                                  : onSurface.withValues(alpha: 0.5),
                            ),
                            onPressed: () => widget.audioHandler.setShuffleMode(
                              isShuffle
                                  ? AudioServiceShuffleMode.none
                                  : AudioServiceShuffleMode.all,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          size: 45,
                          color: onSurface,
                        ),
                        onPressed: () => widget.audioHandler.skipToPrevious(),
                      ),
                      StreamBuilder<PlaybackState>(
                        stream: widget.audioHandler.playbackState,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1DB954),
                            ),
                            child: IconButton(
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 45,
                                color: Colors.white,
                              ),
                              onPressed: () => playing
                                  ? widget.audioHandler.pause()
                                  : widget.audioHandler.play(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next_rounded,
                          size: 45,
                          color: onSurface,
                        ),
                        onPressed: () => widget.audioHandler.skipToNext(),
                      ),
                      IconButton(
                        icon: Icon(
                          widget.favoriteIds.contains(int.parse(item.id))
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: widget.favoriteIds.contains(int.parse(item.id))
                              ? const Color(0xFF4CAF50)
                              : onSurface,
                        ),
                        onPressed: () {
                          widget.onToggleFavorite(int.parse(item.id));
                          setState(() {}); // Forzar actualización de UI
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

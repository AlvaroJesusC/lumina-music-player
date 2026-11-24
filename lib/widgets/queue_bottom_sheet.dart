import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';
import '../services/sleep_timer_service.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';
import 'cached_artwork.dart';

/// Modal estilo Spotify para visualizar y gestionar la "Fila de reproducción" (Cola).
class QueueBottomSheet extends StatefulWidget {
  final AudioHandler audioHandler;

  const QueueBottomSheet({super.key, required this.audioHandler});

  static void show(BuildContext context, AudioHandler audioHandler) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QueueBottomSheet(audioHandler: audioHandler),
    );
  }

  @override
  State<QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends State<QueueBottomSheet> {
  MyAudioHandler get _handler => widget.audioHandler as MyAudioHandler;

  void _handlePlayPause(bool isPlaying) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    final future = isPlaying
        ? widget.audioHandler.pause()
        : widget.audioHandler.play();
    unawaited(
      future.catchError((Object e, StackTrace s) {
        debugPrint('Error toggling play/pause in queue sheet: $e\n$s');
      }),
    );
  }

  void _handleToggleShuffle(bool isShuffle) {
    LuminaHaptics.fire(context, HapticEvent.select);
    final nextMode = isShuffle
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    unawaited(
      widget.audioHandler.setShuffleMode(nextMode).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error toggling shuffle in queue sheet: $e\n$s');
      }),
    );
  }

  void _handleReorder(
    List<int> upcomingIndices,
    int oldIdx,
    int newIdx,
  ) {
    var targetIdx = newIdx;
    if (targetIdx > oldIdx) targetIdx -= 1;
    if (oldIdx == targetIdx) return;
    if (oldIdx < 0 || oldIdx >= upcomingIndices.length) return;
    if (targetIdx < 0 || targetIdx >= upcomingIndices.length) return;

    final fromEffective = upcomingIndices[oldIdx];
    final toEffective = upcomingIndices[targetIdx];

    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _handler
          .reorderEffectiveQueueItem(fromEffective, toEffective)
          .catchError((Object e, StackTrace s) {
            debugPrint('Error reordering queue item: $e\n$s');
          }),
    );
  }

  void _handleRemove(int effectiveIdx) {
    LuminaHaptics.fire(context, HapticEvent.select);
    unawaited(
      _handler.removeEffectiveQueueItemAt(effectiveIdx).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error removing queue item: $e\n$s');
      }),
    );
  }

  void _handleSkipToItem(int actualIdx) {
    LuminaHaptics.fire(context, HapticEvent.commit);
    unawaited(
      widget.audioHandler.skipToQueueItem(actualIdx).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint('Error skipping to queue item: $e\n$s');
      }),
    );
  }

  void _showSleepTimerModal(BuildContext context) {
    final timerService = SleepTimerService.instance;
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(shapes.sheet),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Temporizador de apagado',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _timerOption(ctx, '15 minutos', const Duration(minutes: 15)),
                _timerOption(ctx, '30 minutos', const Duration(minutes: 30)),
                _timerOption(ctx, '45 minutos', const Duration(minutes: 45)),
                _timerOption(ctx, '1 hora', const Duration(hours: 1)),
                ListTile(
                  leading: Icon(
                    Icons.music_off_rounded,
                    color: colors.accent,
                  ),
                  title: Text(
                    'Al final de esta canción',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  onTap: () {
                    timerService.startEndOfSongTimer(widget.audioHandler);
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
                if (timerService.isActive)
                  ListTile(
                    leading: const Icon(
                      Icons.close_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Desactivar temporizador',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      timerService.cancelTimer();
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timerOption(BuildContext ctx, String title, Duration duration) {
    final colors = LuminaColors.of(ctx);
    return ListTile(
      leading: Icon(Icons.timer_outlined, color: colors.accent),
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      onTap: () {
        SleepTimerService.instance.startTimer(duration, widget.audioHandler);
        Navigator.pop(ctx);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = colors.surfaceElevated;
    final cardBg = colors.surface;
    final onSurface = colors.textPrimary;
    final accentGreen = colors.accent;

    return ValueListenableBuilder<int>(
      valueListenable: _handler.queueRevision,
      builder: (context, _, _) {
        return StreamBuilder<MediaItem?>(
          stream: widget.audioHandler.mediaItem,
          builder: (context, mediaSnapshot) {
            final currentMediaItem = mediaSnapshot.data;

            final effectiveItems = _handler.effectiveQueueItems;
            final currentEffectiveIdx = _handler.currentEffectiveQueueIndex;

            // Canciones que van a continuación en la fila (después de la actual)
            final upcomingIndices = <int>[];
            if (currentEffectiveIdx != -1 &&
                currentEffectiveIdx < effectiveItems.length - 1) {
              for (
                var i = currentEffectiveIdx + 1;
                i < effectiveItems.length;
                i++
              ) {
                upcomingIndices.add(i);
              }
            }

            return Container(
              height: MediaQuery.sizeOf(context).height * 0.78,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(shapes.sheet),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Manija de arrastre
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12, bottom: 14),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Título y subtítulo estilo Spotify
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fila de reproducción',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: onSurface.withValues(alpha: 0.6),
                              ),
                              children: [
                                const TextSpan(text: 'Reproduciendo '),
                                TextSpan(
                                  text:
                                      currentMediaItem?.title ?? 'Lumina Music',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: onSurface,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Tarjeta de la canción en reproducción actual
                    if (currentMediaItem != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.3 : 0.05,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CachedArtwork(
                              songId: int.tryParse(currentMediaItem.id) ?? 0,
                              width: 48,
                              height: 48,
                              borderRadius: 8,
                              size: 150,
                              nullArtworkWidget: Container(
                                width: 48,
                                height: 48,
                                color: accentGreen.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.music_note,
                                  color: accentGreen,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentMediaItem.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: colors.accentInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentMediaItem.artist ?? 'Desconocido',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Botón Play/Pause aislado: solo este botón escucha playbackState
                            StreamBuilder<PlaybackState>(
                              stream: widget.audioHandler.playbackState,
                              builder: (context, playbackSnapshot) {
                                final isPlaying =
                                    playbackSnapshot.data?.playing ?? false;
                                return GestureDetector(
                                  onTap: () => _handlePlayPause(isPlaying),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // Encabezado de la fila siguiente (escucha solo shuffleMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      child: StreamBuilder<PlaybackState>(
                        stream: widget.audioHandler.playbackState,
                        builder: (context, playbackSnapshot) {
                          final isShuffle =
                              (playbackSnapshot.data?.shuffleMode ??
                                  AudioServiceShuffleMode.none) !=
                              AudioServiceShuffleMode.none;
                          return Row(
                            children: [
                              Icon(
                                isShuffle
                                    ? Icons.shuffle
                                    : Icons.format_list_bulleted_rounded,
                                size: 16,
                                color: isShuffle
                                    ? accentGreen
                                    : onSurface.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isShuffle
                                    ? 'Reproduciendo en modo aleatorio'
                                    : 'A continuación en la fila',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isShuffle
                                      ? accentGreen
                                      : onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${upcomingIndices.length} restantes',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const Divider(height: 14, thickness: 0.5),

                    // Lista interactiva y reordenable (aislada de playbackState)
                    Expanded(
                      child: upcomingIndices.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.queue_music_rounded,
                                    size: 48,
                                    color: onSurface.withValues(alpha: 0.25),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No hay más canciones en la fila',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Theme(
                              data: Theme.of(context).copyWith(
                                canvasColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                              ),
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                itemCount: upcomingIndices.length,
                                onReorder: (oldIdx, newIdx) => _handleReorder(
                                  upcomingIndices,
                                  oldIdx,
                                  newIdx,
                                ),
                                itemBuilder: (context, index) {
                                  final effectiveIdx = upcomingIndices[index];
                                  final item = effectiveItems[effectiveIdx];
                                  final actualIdx = _handler.getActualIndex(
                                    effectiveIdx,
                                  );
                                  final isQueued = _handler.isUserQueued(item);

                                  return Container(
                                    key: ValueKey<String>(
                                      _handler.queueEntryKey(
                                        item,
                                        effectiveIdx,
                                      ),
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                      leading: CachedArtwork(
                                        songId: int.tryParse(item.id) ?? 0,
                                        width: 44,
                                        height: 44,
                                        borderRadius: 6,
                                        size: 120,
                                        nullArtworkWidget: Container(
                                          width: 44,
                                          height: 44,
                                          color: onSurface.withValues(
                                            alpha: 0.08,
                                          ),
                                          child: Icon(
                                            Icons.music_note,
                                            size: 20,
                                            color: onSurface.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: onSurface,
                                              ),
                                            ),
                                          ),
                                          if (isQueued) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: accentGreen.withValues(
                                                  alpha: 0.16,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'En cola',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: colors.accentInk,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text(
                                        item.artist ?? 'Desconocido',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: onSurface.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: onSurface.withValues(
                                                alpha: 0.35,
                                              ),
                                            ),
                                            tooltip: 'Quitar de la fila',
                                            onPressed: () =>
                                                _handleRemove(effectiveIdx),
                                          ),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              child: Icon(
                                                Icons.drag_handle_rounded,
                                                color: onSurface.withValues(
                                                  alpha: 0.35,
                                                ),
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _handleSkipToItem(actualIdx),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),

                    // Barra inferior de botones cápsula (Modo aleatorio y Temporizador)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border(
                          top: BorderSide(
                            color: onSurface.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Botón: Modo aleatorio (aislado en su propio StreamBuilder)
                          Expanded(
                            child: StreamBuilder<PlaybackState>(
                              stream: widget.audioHandler.playbackState,
                              builder: (context, playbackSnapshot) {
                                final isShuffle =
                                    (playbackSnapshot.data?.shuffleMode ??
                                        AudioServiceShuffleMode.none) !=
                                    AudioServiceShuffleMode.none;
                                return InkWell(
                                  onTap: () => _handleToggleShuffle(isShuffle),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isShuffle
                                          ? Border.all(
                                              color: accentGreen,
                                              width: 1.5,
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shuffle,
                                          color: isShuffle
                                              ? accentGreen
                                              : onSurface.withValues(
                                                  alpha: 0.6,
                                                ),
                                          size: 20,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Modo aleatorio',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isShuffle
                                                ? accentGreen
                                                : onSurface.withValues(
                                                    alpha: 0.7,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Botón: Temporizador
                          ValueListenableBuilder<int?>(
                            valueListenable: SleepTimerService
                                .instance
                                .remainingMinutesNotifier,
                            builder: (context, remainingMinutes, _) {
                              final isTimerActive =
                                  SleepTimerService.instance.isActive;
                              final timerLabel =
                                  SleepTimerService.instance.label;

                              return Expanded(
                                child: InkWell(
                                  onTap: () => _showSleepTimerModal(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isTimerActive
                                          ? Border.all(
                                              color: accentGreen,
                                              width: 1.5,
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_outlined,
                                          color: isTimerActive
                                              ? accentGreen
                                              : onSurface.withValues(
                                                  alpha: 0.6,
                                                ),
                                          size: 20,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          timerLabel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isTimerActive
                                                ? accentGreen
                                                : onSurface.withValues(
                                                    alpha: 0.7,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

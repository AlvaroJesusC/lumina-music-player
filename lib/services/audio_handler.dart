import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

/// Orden de aleatoriedad personalizado que prioriza las canciones
/// añadidas por el usuario a la cola de reproducción.
class QueueAwareShuffleOrder extends ShuffleOrder {
  final Random _random;
  @override
  final indices = <int>[];

  final int? Function() getCurrentIndex;
  final int Function() getUserQueueCount;
  final bool Function() isQueueInsertion;

  QueueAwareShuffleOrder({
    required this.getCurrentIndex,
    required this.getUserQueueCount,
    required this.isQueueInsertion,
    Random? random,
  }) : _random = random ?? Random();

  @override
  void shuffle({int? initialIndex}) {
    assert(initialIndex == null || indices.contains(initialIndex));
    if (indices.length <= 1) return;
    indices.shuffle(_random);
    if (initialIndex == null) return;

    const initialPos = 0;
    final swapPos = indices.indexOf(initialIndex);
    if (swapPos != -1 && swapPos != initialPos) {
      final swapIndex = indices[initialPos];
      indices[initialPos] = initialIndex;
      indices[swapPos] = swapIndex;
    }
  }

  @override
  void insert(int index, int count) {
    // 1. Desplazar índices existentes que estén después del punto de inserción
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) {
        indices[i] += count;
      }
    }

    final newIndices = List.generate(count, (i) => index + i);

    // 2. Si es una inserción de usuario a la cola, colocarla inmediatamente después de la canción actual
    if (isQueueInsertion()) {
      final currentIdx = getCurrentIndex();
      int targetPos = -1;
      if (currentIdx != null) {
        final currentPosInShuffle = indices.indexOf(currentIdx);
        if (currentPosInShuffle != -1) {
          targetPos = (currentPosInShuffle + 1 + getUserQueueCount()).clamp(0, indices.length);
        }
      }

      for (var i = 0; i < newIndices.length; i++) {
        final newIndex = newIndices[i];
        if (targetPos >= 0 && targetPos <= indices.length) {
          indices.insert(targetPos + i, newIndex);
        } else {
          indices.add(newIndex);
        }
      }
    } else {
      // Inserción regular (carga masiva de canciones)
      for (var newIndex in newIndices) {
        final insertionIndex = _random.nextInt(indices.length + 1);
        indices.insert(insertionIndex, newIndex);
      }
    }
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    final oldIndices = List.generate(count, (i) => start + i).toSet();
    indices.removeWhere(oldIndices.contains);
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) {
        indices[i] -= count;
      }
    }
  }

  @override
  void clear() {
    indices.clear();
  }
}

/// Manejador principal de audio para Lumina Player.
/// Extiende [BaseAudioHandler] de audio_service para integrarse
/// con la notificación persistente y los controles de media del sistema.
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  late final ConcatenatingAudioSource _playlist;
  late final QueueAwareShuffleOrder _shuffleOrder;

  // Estado y control de la cola añadida por el usuario
  int _userQueueCount = 0;
  bool _isQueueInsertion = false;
  int? _lastIndex;
  List<String> _currentPlaylistIds = [];

  // Overrides de metadatos: songId -> {title, artist}
  final Map<String, Map<String, String>> _metadataOverrides = {};

  MediaItem _applyOverride(MediaItem item) {
    final ov = _metadataOverrides[item.id];
    if (ov == null) return item;
    return item.copyWith(
      title: ov['title'] ?? item.title,
      artist: ov['artist'] ?? item.artist,
    );
  }

  MyAudioHandler() {
    _shuffleOrder = QueueAwareShuffleOrder(
      getCurrentIndex: () => _player.currentIndex,
      getUserQueueCount: () => _userQueueCount,
      isQueueInsertion: () => _isQueueInsertion,
    );
    _playlist = ConcatenatingAudioSource(
      children: [],
      shuffleOrder: _shuffleOrder,
    );
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      await _player.setLoopMode(LoopMode.all);
      _notifyAudioHandlerAboutPlaybackEvents();
      _listenForSequenceStateChanges();

      // Seguimiento de avance de canciones para decrementar la cola del usuario
      _player.currentIndexStream.listen((index) {
        if (index != null && _lastIndex != null && index != _lastIndex) {
          if (_userQueueCount > 0) {
            _userQueueCount--;
          }
        }
        _lastIndex = index;
      });
    } catch (e) {
      debugPrint("Error inicializando player: $e");
    }
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((_) {
      _broadcastState();
    });
    _player.shuffleModeEnabledStream.listen((_) {
      _broadcastState();
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    final queueIndex = _player.currentIndex;

    final processingState =
        (_player.processingState == ProcessingState.ready &&
            _playlist.length == 0)
        ? AudioProcessingState.idle
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex,
        shuffleMode: (_player.shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.sequence;
      if (sequence == null || sequence.isEmpty) return;

      // Actualizar mediaItem actual aplicando override si existe
      final currentItem = sequenceState?.currentSource?.tag as MediaItem?;
      if (currentItem != null) {
        mediaItem.add(_applyOverride(currentItem));
      }

      // Optimización Binder IPC: Para evitar sobrecargar el canal del sistema
      // (límite de 1MB en Android Binder), enviamos una ventana segura a queue
      final currentIdx = sequenceState?.currentIndex ?? 0;
      final start = (currentIdx - 5).clamp(0, sequence.length);
      final end = (currentIdx + 45).clamp(0, sequence.length);

      final windowSources = sequence.sublist(start, end);
      final items = windowSources
          .map((source) => _applyOverride(source.tag as MediaItem))
          .toList();
      queue.add(items);
    });
  }

  /// Resuelve rutas de audio locales y URLs de forma segura para evitar
  /// errores de codificación en caracteres especiales (#, %, etc.)
  Uri _resolveUri(String urlString) {
    if (urlString.isEmpty) return Uri();
    if (urlString.startsWith('content://') ||
        urlString.startsWith('http://') ||
        urlString.startsWith('https://')) {
      return Uri.tryParse(urlString) ?? Uri.file(urlString);
    }
    return Uri.file(urlString);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Guarda un override de título/artista y re-emite los streams
  /// para actualizar el reproductor en tiempo real.
  void updateSongTag(String songId, String newTitle, String newArtist) {
    _metadataOverrides[songId] = {'title': newTitle, 'artist': newArtist};
    _reEmitWithOverrides(songId);
  }

  /// Elimina el override de una canción (restablecer al original).
  void clearSongTagOverride(String songId) {
    _metadataOverrides.remove(songId);
    _reEmitWithOverrides(songId);
  }

  void _reEmitWithOverrides(String songId) {
    final sequence = _player.sequence;
    if (sequence != null) {
      final currentIdx = _player.currentIndex ?? 0;
      final start = (currentIdx - 5).clamp(0, sequence.length);
      final end = (currentIdx + 45).clamp(0, sequence.length);
      final updatedItems = sequence
          .sublist(start, end)
          .map((source) => _applyOverride(source.tag as MediaItem))
          .toList();
      queue.add(updatedItems);
    }
    final currentTag =
        _player.sequenceState?.currentSource?.tag as MediaItem?;
    if (currentTag != null && currentTag.id == songId) {
      mediaItem.add(_applyOverride(currentTag));
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    final newIds = mediaItems.map((e) => e.id).toList();

    // Optimización: si ya es la misma lista cargada, no recreamos nada desde cero
    if (_listEquals(_currentPlaylistIds, newIds) && _playlist.length == mediaItems.length) {
      _userQueueCount = 0;
      return;
    }

    _userQueueCount = 0;
    _currentPlaylistIds = newIds;

    final audioSources = mediaItems.map(
      (item) => AudioSource.uri(
        _resolveUri(item.extras?['url']?.toString() ?? ''),
        tag: item,
      ),
    );

    await _playlist.clear();
    await _playlist.addAll(audioSources.toList());

    if (_player.shuffleModeEnabled) {
      await _player.shuffle();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    try {
      final url = mediaItem.extras?['url']?.toString() ?? '';
      final audioSource = AudioSource.uri(
        _resolveUri(url),
        tag: mediaItem,
      );

      // Si el reproductor está vacío o no se ha iniciado:
      if (_playlist.length == 0 || _player.currentIndex == null) {
        _isQueueInsertion = false;
        _userQueueCount = 0;
        _currentPlaylistIds = [mediaItem.id];
        await _playlist.add(audioSource);
        await _player.seek(Duration.zero, index: 0);
        super.mediaItem.add(mediaItem);
        await _player.play();
        return;
      }

      // Si ya hay canciones en reproducción:
      // Insertar después de la actual respetando canciones encoladas previamente (FIFO)
      final currentIdx = _player.currentIndex ?? 0;
      final insertIndex = (currentIdx + 1 + _userQueueCount).clamp(0, _playlist.length);

      _isQueueInsertion = true;
      await _playlist.insert(insertIndex, audioSource);
      _userQueueCount++;
      if (insertIndex <= _currentPlaylistIds.length) {
        _currentPlaylistIds.insert(insertIndex, mediaItem.id);
      }
    } catch (e) {
      debugPrint("Error al añadir a la cola: $e");
    } finally {
      _isQueueInsertion = false;
    }
  }

  /// Remueve una canción de la cola en el índice especificado
  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (_userQueueCount > 0 && index > (_player.currentIndex ?? 0)) {
      _userQueueCount--;
    }
    if (index < _currentPlaylistIds.length) {
      _currentPlaylistIds.removeAt(index);
    }
    await _playlist.removeAt(index);
  }

  /// Mueve una canción de una posición a otra dentro de la cola
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {
    if (fromIndex < 0 || fromIndex >= _playlist.length) return;
    if (toIndex < 0 || toIndex >= _playlist.length) return;
    if (fromIndex == toIndex) return;

    if (fromIndex < _currentPlaylistIds.length && toIndex < _currentPlaylistIds.length) {
      final id = _currentPlaylistIds.removeAt(fromIndex);
      _currentPlaylistIds.insert(toIndex, id);
    }
    await _playlist.move(fromIndex, toIndex);
  }



  /// Devuelve los elementos en el orden efectivo de reproducción (respetando shuffle si está activo)
  List<MediaItem> get effectiveQueueItems {
    final sequence = _player.sequence;
    if (sequence == null || sequence.isEmpty) return [];

    final indices = _player.effectiveIndices ?? List.generate(sequence.length, (i) => i);
    final items = <MediaItem>[];
    for (final idx in indices) {
      if (idx >= 0 && idx < sequence.length) {
        items.add(_applyOverride(sequence[idx].tag as MediaItem));
      }
    }
    return items;
  }

  /// Mapea el índice efectivo (de la cola visual) al índice real en la secuencia
  int getActualIndex(int effectiveIndex) {
    final indices = _player.effectiveIndices;
    if (indices == null || effectiveIndex < 0 || effectiveIndex >= indices.length) {
      return effectiveIndex;
    }
    return indices[effectiveIndex];
  }

  /// Devuelve el índice en effectiveQueueItems que coincide con la canción actual
  int get currentEffectiveQueueIndex {
    final currentIdx = _player.currentIndex;
    if (currentIdx == null) return -1;
    final indices = _player.effectiveIndices;
    if (indices == null) return currentIdx;
    return indices.indexOf(currentIdx);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      if (_player.shuffleModeEnabled) {
        await _player.shuffle();
      }
      int nextIndex = _player.effectiveIndices?.first ?? 0;
      await _player.seek(Duration.zero, index: nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      int lastIndex = _player.effectiveIndices?.last ?? (_playlist.length - 1);
      await _player.seek(Duration.zero, index: lastIndex);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) {
      await stop();
    }
  }
}

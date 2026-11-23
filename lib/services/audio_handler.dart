import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

/// Orden de aleatoriedad personalizado que respeta las canciones añadidas por
/// el usuario a la cola de reproducción y permite reordenar la fila en modo
/// aleatorio sin perder ni dispersar canciones.
class QueueAwareShuffleOrder extends ShuffleOrder {
  final Random _random;

  @override
  final indices = <int>[];

  /// Si es `true`, la siguiente invocación a [shuffle] deja [indices] intacto
  /// para sincronizar un reordenamiento manual con `just_audio` y ExoPlayer.
  bool suppressNextShuffle = false;

  /// Posición exacta en [indices] donde debe colocarse la siguiente inserción
  /// manual a la cola. Si es `null`, se inserta aleatoriamente (carga masiva).
  int? pendingInsertShufflePos;

  /// Si no es `null`, fuerza qué índice real queda en la posición `0` durante
  /// la siguiente invocación a [shuffle].
  int? forcedInitialIndex;

  /// Devuelve los índices reales de las canciones encoladas manualmente por el
  /// usuario que deben permanecer inmediatamente después de la canción actual
  /// cuando se activa o recalcula el modo aleatorio.
  final List<int> Function()? getPreservedUpcomingIndices;

  QueueAwareShuffleOrder({
    this.getPreservedUpcomingIndices,
    Random? random,
  }) : _random = random ?? Random();

  /// Mueve el elemento ubicado en [fromPos] hacia [toPos] dentro de [indices]
  /// (orden efectivo en modo aleatorio), conservando todos los demás elementos.
  bool moveEffectiveIndex(int fromPos, int toPos) {
    if (fromPos < 0 || fromPos >= indices.length) return false;
    if (toPos < 0 || toPos >= indices.length) return false;
    if (fromPos == toPos) return false;
    final moved = indices.removeAt(fromPos);
    indices.insert(toPos, moved);
    return true;
  }

  @override
  void shuffle({int? initialIndex}) {
    if (suppressNextShuffle) return;
    final effectiveInitial = forcedInitialIndex ?? initialIndex;
    assert(effectiveInitial == null || indices.contains(effectiveInitial));
    if (indices.length <= 1) return;

    final preserved = getPreservedUpcomingIndices?.call() ?? const <int>[];
    final validPreserved = <int>[];
    final pinnedSet = <int>{};

    if (effectiveInitial != null && indices.contains(effectiveInitial)) {
      pinnedSet.add(effectiveInitial);
    }
    for (final idx in preserved) {
      if (indices.contains(idx) && pinnedSet.add(idx)) {
        validPreserved.add(idx);
      }
    }

    final remaining = <int>[
      for (final idx in indices)
        if (!pinnedSet.contains(idx)) idx,
    ];
    remaining.shuffle(_random);

    indices
      ..clear()
      ..addAll([
        if (effectiveInitial != null && pinnedSet.contains(effectiveInitial))
          effectiveInitial,
        ...validPreserved,
        ...remaining,
      ]);
  }

  @override
  void insert(int index, int count) {
    // 1. Desplazar índices existentes que estén en o después del punto de inserción.
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) {
        indices[i] += count;
      }
    }

    final newIndices = List.generate(count, (i) => index + i);
    final explicitTargetPos = pendingInsertShufflePos;

    // 2. Si es una inserción controlada a la cola, colocarla en la posición exacta.
    if (explicitTargetPos != null) {
      final clampedTarget = explicitTargetPos.clamp(0, indices.length);
      for (var i = 0; i < newIndices.length; i++) {
        indices.insert(clampedTarget + i, newIndices[i]);
      }
      return;
    }

    // 3. Inserción regular (carga masiva de canciones).
    for (final newIndex in newIndices) {
      final insertionIndex = _random.nextInt(indices.length + 1);
      indices.insert(insertionIndex, newIndex);
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
  static const String _queueUidExtraKey = 'queueUid';

  final _player = AudioPlayer();
  late final ConcatenatingAudioSource _playlist;
  late final QueueAwareShuffleOrder _shuffleOrder;

  // Identidad única de cada entrada en la cola (incluso si se repite una canción)
  int _nextQueueUid = 1;
  final Set<String> _userQueuedUids = <String>{};
  String? _currentPlayingUid;
  List<String> _currentPlaylistIds = [];

  // Serializa operaciones sobre la cola para evitar carreras con ExoPlayer
  Future<void> _opChain = Future<void>.value();

  // Notificador reactivo para que QueueBottomSheet se actualice en cada cambio
  final ValueNotifier<int> _queueRevision = ValueNotifier<int>(0);
  ValueListenable<int> get queueRevision => _queueRevision;

  // Suscripciones del reproductor
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<bool>? _shuffleModeSub;
  StreamSubscription<SequenceState?>? _sequenceStateSub;

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

  MediaItem _tagWithQueueUid(MediaItem item) {
    final uid = 'q_${_nextQueueUid++}';
    final mergedExtras = <String, dynamic>{
      ...?item.extras,
      _queueUidExtraKey: uid,
    };
    return item.copyWith(extras: mergedExtras);
  }

  String? _queueUidOfItem(MediaItem? item) {
    return item?.extras?[_queueUidExtraKey]?.toString();
  }

  String? _queueUidOfSource(AudioSource source) {
    if (source is IndexedAudioSource) {
      return _queueUidOfItem(source.tag as MediaItem?);
    }
    return null;
  }

  /// Devuelve una clave estable y única para identificar una fila en
  /// [ReorderableListView], incluso si la misma canción se encoló varias veces.
  String queueEntryKey(MediaItem item, int fallbackIndex) {
    return _queueUidOfItem(item) ?? '${item.id}_$fallbackIndex';
  }

  /// Indica si la canción representada por [item] fue añadida manualmente por
  /// el usuario a la cola de reproducción.
  bool isUserQueued(MediaItem item) {
    final uid = _queueUidOfItem(item);
    return uid != null && _userQueuedUids.contains(uid);
  }

  MyAudioHandler() {
    _shuffleOrder = QueueAwareShuffleOrder(
      getPreservedUpcomingIndices: _getContiguousUserQueuedActualIndices,
    );
    _playlist = ConcatenatingAudioSource(
      children: [],
      shuffleOrder: _shuffleOrder,
    );
    unawaited(
      _initPlayer().catchError((Object e, StackTrace s) {
        debugPrint('Error inicializando MyAudioHandler: $e\n$s');
      }),
    );
  }

  /// Ejecuta [action] en estricto orden secuencial para evitar carreras entre
  /// inserciones, reordenamientos, eliminaciones y cambios de modo aleatorio.
  Future<T> _enqueueOp<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _opChain = _opChain.then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, s) {
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
      }
    });
    return completer.future;
  }

  void _bumpQueueRevision() {
    _queueRevision.value = _queueRevision.value + 1;
  }

  /// Resuelve de forma segura el índice real de la canción en reproducción
  /// dentro de `_playlist.children`, incluso si ExoPlayer aún no ha emitido el
  /// nuevo `currentIndex` tras una eliminación previa.
  int? _resolveCurrentActualIndex() {
    final children = _playlist.children;
    if (children.isEmpty) return null;

    final playerIdx = _player.currentIndex;
    if (playerIdx != null && playerIdx >= 0 && playerIdx < children.length) {
      if (_currentPlayingUid == null ||
          _queueUidOfSource(children[playerIdx]) == _currentPlayingUid) {
        return playerIdx;
      }
    }

    if (_currentPlayingUid != null) {
      for (var i = 0; i < children.length; i++) {
        if (_queueUidOfSource(children[i]) == _currentPlayingUid) {
          return i;
        }
      }
    }

    if (playerIdx != null && playerIdx >= 0 && playerIdx < children.length) {
      return playerIdx;
    }
    return null;
  }

  List<int> _currentEffectiveOrder() {
    final length = _playlist.length;
    if (length == 0) return const [];
    if (_player.shuffleModeEnabled) {
      if (_shuffleOrder.indices.length == length) {
        return _shuffleOrder.indices;
      }
      final fallback = _player.effectiveIndices;
      if (fallback != null && fallback.length == length) {
        return fallback;
      }
    }
    return List<int>.generate(length, (i) => i);
  }

  int _contiguousUserQueueCountInOrder({
    required List<int> order,
    required int currentPos,
  }) {
    final children = _playlist.children;
    var count = 0;
    for (var pos = currentPos + 1; pos < order.length; pos++) {
      final actualIdx = order[pos];
      if (actualIdx < 0 || actualIdx >= children.length) break;
      final uid = _queueUidOfSource(children[actualIdx]);
      if (uid != null && _userQueuedUids.contains(uid)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  List<int> _getContiguousUserQueuedActualIndices() {
    final currentActual = _resolveCurrentActualIndex();
    if (currentActual == null) return const [];

    final order = _currentEffectiveOrder();
    final currentPos = order.indexOf(currentActual);
    if (currentPos == -1) return const [];

    final count = _contiguousUserQueueCountInOrder(
      order: order,
      currentPos: currentPos,
    );
    if (count == 0) return const [];

    return order.sublist(currentPos + 1, currentPos + 1 + count);
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      await _player.setLoopMode(LoopMode.all);
      _notifyAudioHandlerAboutPlaybackEvents();
      _listenForSequenceStateChanges();

      // Seguimiento de la canción en reproducción para consumir canciones de la
      // cola manual cuando efectivamente comienzan a reproducirse.
      _currentIndexSub = _player.currentIndexStream.listen((index) {
        if (index != null && index >= 0 && index < _playlist.length) {
          final uid = _queueUidOfSource(_playlist.children[index]);
          if (uid != null) {
            _currentPlayingUid = uid;
            if (_userQueuedUids.remove(uid)) {
              _bumpQueueRevision();
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error inicializando player: $e');
    }
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _playbackEventSub = _player.playbackEventStream.listen((_) {
      _broadcastState();
    });
    _shuffleModeSub = _player.shuffleModeEnabledStream.listen((_) {
      _broadcastState();
      _bumpQueueRevision();
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    final queueIndex = _resolveCurrentActualIndex() ?? _player.currentIndex;

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
    _sequenceStateSub = _player.sequenceStateStream.listen((
      SequenceState? sequenceState,
    ) {
      final sequence = sequenceState?.sequence;
      if (sequence == null || sequence.isEmpty) {
        _bumpQueueRevision();
        return;
      }

      // Actualizar mediaItem actual aplicando override si existe
      final currentItem = sequenceState?.currentSource?.tag as MediaItem?;
      if (currentItem != null) {
        final uid = _queueUidOfItem(currentItem);
        if (uid != null) {
          _currentPlayingUid = uid;
          _userQueuedUids.remove(uid);
        }
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
      _bumpQueueRevision();
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
    for (var i = 0; i < a.length; i++) {
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
      final currentIdx = _resolveCurrentActualIndex() ?? 0;
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
    _bumpQueueRevision();
  }

  Future<void> _loadQueueItemsInternal(List<MediaItem> mediaItems) async {
    final newIds = mediaItems.map((e) => e.id).toList();

    // Optimización: si ya es la misma lista cargada y sin canciones manuales
    // pendientes, no recreamos las fuentes desde cero.
    if (_listEquals(_currentPlaylistIds, newIds) &&
        _playlist.length == mediaItems.length &&
        _userQueuedUids.isEmpty) {
      return;
    }

    _userQueuedUids.clear();
    _currentPlayingUid = null;
    _currentPlaylistIds = newIds;

    final audioSources = mediaItems.map((item) {
      final tagged = _tagWithQueueUid(item);
      return AudioSource.uri(
        _resolveUri(tagged.extras?['url']?.toString() ?? ''),
        tag: tagged,
      );
    }).toList();

    _shuffleOrder.pendingInsertShufflePos = null;
    await _playlist.clear();
    if (audioSources.isNotEmpty) {
      await _playlist.addAll(audioSources);
    }
  }

  /// Carga una lista y reproduce desde [initialIndex]. Si el modo aleatorio
  /// está activo (o [shuffleEnabled] es `true`), fija [initialIndex] en la
  /// posición 0 del orden aleatorio para que toda la lista restante aparezca
  /// como próxima en la fila.
  Future<void> playFromList(
    List<MediaItem> mediaItems, {
    required int initialIndex,
    bool? shuffleEnabled,
  }) {
    return _enqueueOp(() async {
      if (mediaItems.isEmpty) return;

      final safeIndex = initialIndex.clamp(0, mediaItems.length - 1);
      await _loadQueueItemsInternal(mediaItems);

      if (shuffleEnabled != null &&
          _player.shuffleModeEnabled != shuffleEnabled) {
        await _player.setShuffleModeEnabled(shuffleEnabled);
      }

      if (safeIndex < _playlist.length) {
        _currentPlayingUid = _queueUidOfSource(_playlist.children[safeIndex]);
      }

      await _player.seek(Duration.zero, index: safeIndex);

      if (_player.shuffleModeEnabled && _playlist.length > 1) {
        _shuffleOrder.forcedInitialIndex = safeIndex;
        try {
          await _player.shuffle();
        } finally {
          _shuffleOrder.forcedInitialIndex = null;
        }
      }

      _bumpQueueRevision();
      await _player.play();
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) {
    return _enqueueOp(() async {
      await _loadQueueItemsInternal(mediaItems);
      if (_player.shuffleModeEnabled && _playlist.length > 1) {
        await _player.shuffle();
      }
      _bumpQueueRevision();
    });
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) {
    return _enqueueOp(() async {
      try {
        final taggedItem = _tagWithQueueUid(mediaItem);
        final queueUid = _queueUidOfItem(taggedItem)!;
        final url = taggedItem.extras?['url']?.toString() ?? '';
        final audioSource = AudioSource.uri(_resolveUri(url), tag: taggedItem);

        final currentActual = _resolveCurrentActualIndex();

        // Si el reproductor está vacío o no se ha iniciado:
        if (_playlist.length == 0 || currentActual == null) {
          _shuffleOrder.pendingInsertShufflePos = null;
          _userQueuedUids.clear();
          _currentPlaylistIds = [taggedItem.id];
          _currentPlayingUid = queueUid;
          await _playlist.add(audioSource);
          await _player.seek(Duration.zero, index: 0);
          super.mediaItem.add(_applyOverride(taggedItem));
          _bumpQueueRevision();
          await _player.play();
          return;
        }

        // 1. Calcular inserción en orden lineal (siempre estrictamente después
        // de currentActual para nunca desplazar la pista en reproducción).
        final rawOrder = List<int>.generate(_playlist.length, (i) => i);
        final rawUserQueueCount = _contiguousUserQueueCountInOrder(
          order: rawOrder,
          currentPos: currentActual,
        );
        final insertIndex = (currentActual + 1 + rawUserQueueCount).clamp(
          currentActual + 1,
          _playlist.length,
        );

        // 2. Calcular inserción exacta en el orden aleatorio (FIFO después de
        // la canción actual y cualquier canción encolada manualmente antes).
        final currentPosInShuffle = _shuffleOrder.indices.indexOf(
          currentActual,
        );
        int? targetShufflePos;
        if (currentPosInShuffle != -1) {
          final shuffleUserQueueCount = _contiguousUserQueueCountInOrder(
            order: _shuffleOrder.indices,
            currentPos: currentPosInShuffle,
          );
          targetShufflePos =
              (currentPosInShuffle + 1 + shuffleUserQueueCount).clamp(
                currentPosInShuffle + 1,
                _shuffleOrder.indices.length,
              );
        }

        _userQueuedUids.add(queueUid);
        _shuffleOrder.pendingInsertShufflePos = targetShufflePos;
        try {
          await _playlist.insert(insertIndex, audioSource);
        } finally {
          _shuffleOrder.pendingInsertShufflePos = null;
        }

        if (insertIndex <= _currentPlaylistIds.length) {
          _currentPlaylistIds.insert(insertIndex, taggedItem.id);
        }

        // Re-sincronizar explícitamente el orden aleatorio en ExoPlayer si el
        // modo aleatorio está activo, evitando desfaces temporales tras insert.
        if (_player.shuffleModeEnabled) {
          await _syncShuffleOrderWithoutReshuffling();
        }

        _bumpQueueRevision();
      } catch (e, s) {
        debugPrint('Error al añadir a la cola: $e\n$s');
        rethrow;
      }
    });
  }

  Future<void> _syncShuffleOrderWithoutReshuffling() async {
    _shuffleOrder.suppressNextShuffle = true;
    try {
      await _player.shuffle();
    } finally {
      _shuffleOrder.suppressNextShuffle = false;
    }
  }

  /// Remueve una canción de la cola usando su índice efectivo (visual).
  Future<void> removeEffectiveQueueItemAt(int effectiveIndex) {
    return _enqueueOp(() async {
      final order = _currentEffectiveOrder();
      if (effectiveIndex < 0 || effectiveIndex >= order.length) return;
      final actualIdx = order[effectiveIndex];
      await _removeActualIndexInternal(actualIdx);
    });
  }

  /// Remueve una canción de la cola en el índice real especificado.
  @override
  Future<void> removeQueueItemAt(int index) {
    return _enqueueOp(() => _removeActualIndexInternal(index));
  }

  Future<void> _removeActualIndexInternal(int index) async {
    if (index < 0 || index >= _playlist.length) return;

    final removedUid = _queueUidOfSource(_playlist.children[index]);
    if (removedUid != null) {
      _userQueuedUids.remove(removedUid);
    }

    if (index < _currentPlaylistIds.length) {
      _currentPlaylistIds.removeAt(index);
    }

    await _playlist.removeAt(index);
    _bumpQueueRevision();
  }

  /// Reordena una canción en la fila visual (índice efectivo [fromEffectiveIndex]
  /// hacia [toEffectiveIndex]).
  ///
  /// - En modo aleatorio: reordena únicamente [_shuffleOrder.indices] y lo
  ///   sincroniza con `just_audio`/ExoPlayer sin tocar `_playlist.children`,
  ///   evitando que la canción desaparezca o desplace la pista actual.
  /// - En modo normal: mueve la pista en `_playlist` de forma segura.
  Future<void> reorderEffectiveQueueItem(
    int fromEffectiveIndex,
    int toEffectiveIndex,
  ) {
    return _enqueueOp(() async {
      final order = _currentEffectiveOrder();
      if (order.isEmpty) return;

      final currentEffective = currentEffectiveQueueIndex;
      if (fromEffectiveIndex <= currentEffective ||
          toEffectiveIndex <= currentEffective) {
        return;
      }
      if (fromEffectiveIndex < 0 || fromEffectiveIndex >= order.length) return;
      if (toEffectiveIndex < 0 || toEffectiveIndex >= order.length) return;
      if (fromEffectiveIndex == toEffectiveIndex) return;

      final userQueueCountBefore = _contiguousUserQueueCountInOrder(
        order: order,
        currentPos: currentEffective,
      );
      final movedActualIdx = order[fromEffectiveIndex];
      final movedUid = _queueUidOfSource(_playlist.children[movedActualIdx]);

      if (_player.shuffleModeEnabled) {
        final didMove = _shuffleOrder.moveEffectiveIndex(
          fromEffectiveIndex,
          toEffectiveIndex,
        );
        if (!didMove) return;

        _updateUserQueueMembershipAfterReorder(
          movedUid: movedUid,
          fromEffectiveIndex: fromEffectiveIndex,
          toEffectiveIndex: toEffectiveIndex,
          currentEffectiveIndex: currentEffective,
          userQueueCountBefore: userQueueCountBefore,
        );

        _bumpQueueRevision();
        await _syncShuffleOrderWithoutReshuffling();
      } else {
        if (fromEffectiveIndex < _currentPlaylistIds.length &&
            toEffectiveIndex < _currentPlaylistIds.length) {
          final id = _currentPlaylistIds.removeAt(fromEffectiveIndex);
          _currentPlaylistIds.insert(toEffectiveIndex, id);
        }

        _updateUserQueueMembershipAfterReorder(
          movedUid: movedUid,
          fromEffectiveIndex: fromEffectiveIndex,
          toEffectiveIndex: toEffectiveIndex,
          currentEffectiveIndex: currentEffective,
          userQueueCountBefore: userQueueCountBefore,
        );

        await _playlist.move(fromEffectiveIndex, toEffectiveIndex);
      }

      _bumpQueueRevision();
    });
  }

  /// Mantiene coherente el prefijo contiguo de canciones encoladas manualmente
  /// tras arrastrar una canción hacia arriba o hacia abajo en la fila.
  void _updateUserQueueMembershipAfterReorder({
    required String? movedUid,
    required int fromEffectiveIndex,
    required int toEffectiveIndex,
    required int currentEffectiveIndex,
    required int userQueueCountBefore,
  }) {
    if (movedUid == null || userQueueCountBefore <= 0) return;

    final userQueueEndBefore = currentEffectiveIndex + userQueueCountBefore;
    final wasInUserQueue = fromEffectiveIndex <= userQueueEndBefore;

    if (!wasInUserQueue && toEffectiveIndex <= userQueueEndBefore) {
      // El usuario promovió una pista dentro de la sección de cola manual.
      _userQueuedUids.add(movedUid);
    } else if (wasInUserQueue && toEffectiveIndex > userQueueEndBefore) {
      // El usuario movió una pista de la cola manual después de pistas normales.
      _userQueuedUids.remove(movedUid);
    }
  }

  /// Mueve una canción por índice real (compatibilidad para modo lineal).
  Future<void> moveQueueItem(int fromIndex, int toIndex) {
    return _enqueueOp(() async {
      if (fromIndex < 0 || fromIndex >= _playlist.length) return;
      if (toIndex < 0 || toIndex >= _playlist.length) return;
      if (fromIndex == toIndex) return;

      if (_player.shuffleModeEnabled) {
        final fromEff = _shuffleOrder.indices.indexOf(fromIndex);
        final toEff = _shuffleOrder.indices.indexOf(toIndex);
        if (fromEff != -1 && toEff != -1) {
          _shuffleOrder.moveEffectiveIndex(fromEff, toEff);
          await _syncShuffleOrderWithoutReshuffling();
          _bumpQueueRevision();
        }
        return;
      }

      if (fromIndex < _currentPlaylistIds.length &&
          toIndex < _currentPlaylistIds.length) {
        final id = _currentPlaylistIds.removeAt(fromIndex);
        _currentPlaylistIds.insert(toIndex, id);
      }
      await _playlist.move(fromIndex, toIndex);
      _bumpQueueRevision();
    });
  }

  /// Devuelve los elementos en el orden efectivo de reproducción (respetando
  /// el modo aleatorio si está activo).
  List<MediaItem> get effectiveQueueItems {
    final children = _playlist.children;
    if (children.isEmpty) return [];

    final indices = _currentEffectiveOrder();
    final items = <MediaItem>[];
    for (final idx in indices) {
      if (idx >= 0 && idx < children.length) {
        final source = children[idx];
        if (source is IndexedAudioSource && source.tag is MediaItem) {
          items.add(_applyOverride(source.tag as MediaItem));
        }
      }
    }
    return items;
  }

  /// Mapea el índice efectivo (de la cola visual) al índice real en la secuencia.
  int getActualIndex(int effectiveIndex) {
    final indices = _currentEffectiveOrder();
    if (effectiveIndex < 0 || effectiveIndex >= indices.length) {
      return effectiveIndex;
    }
    return indices[effectiveIndex];
  }

  /// Devuelve el índice en [effectiveQueueItems] que coincide con la canción actual.
  int get currentEffectiveQueueIndex {
    final currentIdx = _resolveCurrentActualIndex();
    if (currentIdx == null) return -1;
    final indices = _currentEffectiveOrder();
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
    if (_playlist.length == 0) return;
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      if (_player.shuffleModeEnabled) {
        await _player.shuffle();
      }
      final nextIndex = _player.effectiveIndices?.first ?? 0;
      await _player.seek(Duration.zero, index: nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.length == 0) return;
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      final lastIndex = _player.effectiveIndices?.last ?? (_playlist.length - 1);
      await _player.seek(Duration.zero, index: lastIndex);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    return _enqueueOp(() async {
      final enabled = shuffleMode != AudioServiceShuffleMode.none;
      if (enabled && _playlist.length > 1) {
        final currentActual = _resolveCurrentActualIndex();
        _shuffleOrder.forcedInitialIndex = currentActual;
        try {
          await _player.shuffle();
        } finally {
          _shuffleOrder.forcedInitialIndex = null;
        }
      }
      await _player.setShuffleModeEnabled(enabled);
      _bumpQueueRevision();
    });
  }

  @override
  Future<void> skipToQueueItem(int index) {
    return _enqueueOp(() async {
      if (index < 0 || index >= _playlist.length) return;
      final targetUid = _queueUidOfSource(_playlist.children[index]);
      if (targetUid != null) {
        _currentPlayingUid = targetUid;
        _userQueuedUids.remove(targetUid);
      }
      await _player.seek(Duration.zero, index: index);
      _bumpQueueRevision();
    });
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

  Future<void> dispose() async {
    await _currentIndexSub?.cancel();
    await _playbackEventSub?.cancel();
    await _shuffleModeSub?.cancel();
    await _sequenceStateSub?.cancel();
    _queueRevision.dispose();
    await _player.dispose();
  }
}

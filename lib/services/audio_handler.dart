import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'crossfade_engine.dart';
import 'equalizer_engine.dart';
import 'sleep_timer_service.dart';

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
///
/// Gestiona la cola inteligente (`QueueAwareShuffleOrder`) en memoria sobre un
/// motor real de doble deck (`CrossfadeEngine` Deck A ↔ Deck B) con ecualizador
/// sincronizado en ambos decks (`EqualizerEngine`), logrando crossfade estilo
/// Spotify sin cortes ni pausas en la canción saliente.
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const String _queueUidExtraKey = 'queueUid';

  late final EqualizerEngine _equalizerEngine;
  late final QueueAwareShuffleOrder _shuffleOrder;
  late final CrossfadeEngine _crossfadeEngine;

  /// Frecuencias centrales de las bandas del ecualizador del dispositivo.
  ValueListenable<List<double>> get equalizerCenterFrequencies =>
      _equalizerEngine.centerFrequenciesHz;

  // Lista maestra en memoria + estado lógico de reproducción y modo aleatorio.
  final List<MediaItem> _items = [];
  bool _shuffleEnabled = false;
  int? _currentActualIndex;

  // Identidad única de cada entrada en la cola (incluso si se repite una canción)
  int _nextQueueUid = 1;
  final Set<String> _userQueuedUids = <String>{};
  String? _currentPlayingUid;
  List<String> _currentPlaylistIds = [];

  // Serializa operaciones sobre la cola para evitar carreras de estado.
  Future<void> _opChain = Future<void>.value();

  // Notificador reactivo para que QueueBottomSheet se actualice en cada cambio
  final ValueNotifier<int> _queueRevision = ValueNotifier<int>(0);
  ValueListenable<int> get queueRevision => _queueRevision;

  // Suscripción de eventos del deck actualmente activo.
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  // Overrides de metadatos: songId -> {title, artist}
  final Map<String, Map<String, String>> _metadataOverrides = {};

  AudioPlayer get _activePlayer => _crossfadeEngine.activePlayer;

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
    _equalizerEngine = EqualizerEngine();
    _shuffleOrder = QueueAwareShuffleOrder(
      getPreservedUpcomingIndices: _getContiguousUserQueuedActualIndices,
    );
    _crossfadeEngine = CrossfadeEngine(
      equalizerEngine: _equalizerEngine,
      resolveCurrentTrackKey: _resolveCurrentTrackKey,
      resolveNextTrack: _resolveNextTrackCandidate,
      onCrossfadeStarted: _handleCrossfadeStarted,
      onActiveTrackCompleted: _handleActiveTrackCompleted,
      onActiveDeckChanged: _bindPlaybackStreamToDeck,
      isCrossfadeSuppressed: () => SleepTimerService.instance.isStopAtEndOfSong,
    );
    _bindPlaybackStreamToDeck(_activePlayer);
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

  void _bindPlaybackStreamToDeck(AudioPlayer deck) {
    unawaited(_playbackEventSub?.cancel());
    _playbackEventSub = deck.playbackEventStream.listen((_) {
      if (deck == _activePlayer) {
        _broadcastState();
      }
    });
    _broadcastState();
  }

  /// Resuelve de forma segura el índice real de la canción en reproducción
  /// dentro de [_items].
  int? _resolveCurrentActualIndex() {
    if (_items.isEmpty) return null;

    final idx = _currentActualIndex;
    if (idx != null && idx >= 0 && idx < _items.length) {
      if (_currentPlayingUid == null ||
          _queueUidOfItem(_items[idx]) == _currentPlayingUid) {
        return idx;
      }
    }

    if (_currentPlayingUid != null) {
      for (var i = 0; i < _items.length; i++) {
        if (_queueUidOfItem(_items[i]) == _currentPlayingUid) {
          _currentActualIndex = i;
          return i;
        }
      }
    }

    if (idx != null && idx >= 0 && idx < _items.length) {
      return idx;
    }
    return null;
  }

  List<int> _currentEffectiveOrder() {
    final length = _items.length;
    if (length == 0) return const [];
    if (_shuffleEnabled) {
      if (_shuffleOrder.indices.length == length) {
        return _shuffleOrder.indices;
      }
    }
    return List<int>.generate(length, (i) => i);
  }

  int _contiguousUserQueueCountInOrder({
    required List<int> order,
    required int currentPos,
  }) {
    var count = 0;
    for (var pos = currentPos + 1; pos < order.length; pos++) {
      final actualIdx = order[pos];
      if (actualIdx < 0 || actualIdx >= _items.length) break;
      final uid = _queueUidOfItem(_items[actualIdx]);
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

  void _broadcastState() {
    final player = _activePlayer;
    final playing = player.playing;
    final queueIndex = _resolveCurrentActualIndex();

    final processingState =
        (player.processingState == ProcessingState.ready && _items.isEmpty)
        ? AudioProcessingState.idle
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[player.processingState]!;

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
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: queueIndex,
        shuffleMode: _shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  /// Publica el elemento actual y una ventana acotada de la cola hacia Android
  /// MediaSession (evitando el límite de 1 MB de Binder IPC).
  void _publishCurrentAndQueueWindow() {
    if (_items.isEmpty) {
      queue.add(const []);
      _bumpQueueRevision();
      return;
    }

    final currentIdx = _resolveCurrentActualIndex() ?? 0;
    final currentItem = _items[currentIdx];
    final uid = _queueUidOfItem(currentItem);
    if (uid != null) {
      _currentPlayingUid = uid;
      _userQueuedUids.remove(uid);
    }
    mediaItem.add(_applyOverride(currentItem));

    final start = (currentIdx - 5).clamp(0, _items.length);
    final end = (currentIdx + 45).clamp(0, _items.length);
    final windowItems = _items.sublist(start, end).map(_applyOverride).toList();
    queue.add(windowItems);
    _bumpQueueRevision();
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

  Uri _uriOfItem(MediaItem item) =>
      _resolveUri(item.extras?['url']?.toString() ?? '');

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String? _resolveCurrentTrackKey() {
    if (_currentPlayingUid != null) return _currentPlayingUid;
    final idx = _resolveCurrentActualIndex();
    if (idx == null || idx < 0 || idx >= _items.length) return null;
    return _queueUidOfItem(_items[idx]) ?? _items[idx].id;
  }

  /// Devuelve el siguiente candidato en orden efectivo (respetando aleatorio,
  /// cola manual FIFO y repetición circular de la lista).
  NextTrackCandidate? _resolveNextTrackCandidate() {
    if (_items.length <= 1) return null;
    final currentActual = _resolveCurrentActualIndex();
    if (currentActual == null) return null;

    final order = _currentEffectiveOrder();
    if (order.length <= 1) return null;

    final currentPos = order.indexOf(currentActual);
    final nextPos = currentPos == -1 ? 0 : (currentPos + 1) % order.length;
    final nextActual = order[nextPos];
    if (nextActual < 0 || nextActual >= _items.length) return null;

    final nextItem = _items[nextActual];
    final uri = _uriOfItem(nextItem);
    if (uri.toString().isEmpty) return null;

    return NextTrackCandidate(
      actualIndex: nextActual,
      trackKey: _queueUidOfItem(nextItem) ?? '${nextItem.id}_$nextActual',
      uri: uri,
      mediaItem: _applyOverride(nextItem),
    );
  }

  /// Invocado por [CrossfadeEngine] justo al iniciar la mezcla en el segundo
  /// deck: actualiza el índice actual, consume la entrada de cola manual y
  /// refresca UI + notificación inmediatamente (estilo Spotify).
  void _handleCrossfadeStarted(
    NextTrackCandidate next,
    AudioPlayer newActiveDeck,
  ) {
    if (next.actualIndex < 0 || next.actualIndex >= _items.length) return;
    _currentActualIndex = next.actualIndex;
    _currentPlayingUid = _queueUidOfItem(_items[next.actualIndex]);
    if (_currentPlayingUid != null) {
      _userQueuedUids.remove(_currentPlayingUid);
    }
    _publishCurrentAndQueueWindow();
    _broadcastState();
  }

  /// Invocado cuando el deck activo llega al final natural de una pista
  /// (cuando crossfade está en `0 s`, la pista era muy corta o está activo
  /// el temporizador "Al final de esta canción").
  Future<void> _handleActiveTrackCompleted() {
    return _enqueueOp(() async {
      if (_items.isEmpty) return;

      final stopAtEndOfSong = SleepTimerService.instance.isStopAtEndOfSong;

      if (_items.length == 1) {
        final onlyItem = _items.first;
        if (stopAtEndOfSong) {
          await _crossfadeEngine.loadAndPlayOnActiveDeck(
            _uriOfItem(onlyItem),
            autoPlay: false,
          );
          SleepTimerService.instance.cancelTimer();
        } else {
          await _crossfadeEngine.loadAndPlayOnActiveDeck(
            _uriOfItem(onlyItem),
            autoPlay: true,
          );
        }
        _broadcastState();
        return;
      }

      final next = _resolveNextTrackCandidate();
      if (next == null) return;

      _currentActualIndex = next.actualIndex;
      _currentPlayingUid = _queueUidOfItem(_items[next.actualIndex]);
      if (_currentPlayingUid != null) {
        _userQueuedUids.remove(_currentPlayingUid);
      }

      if (stopAtEndOfSong) {
        await _crossfadeEngine.loadAndPlayOnActiveDeck(
          next.uri,
          autoPlay: false,
        );
        _publishCurrentAndQueueWindow();
        _broadcastState();
        return;
      }

      final switched = await _crossfadeEngine.switchToPreloadedStandby(
        expected: next,
        autoPlay: true,
      );
      if (!switched) {
        await _crossfadeEngine.loadAndPlayOnActiveDeck(
          next.uri,
          autoPlay: true,
        );
      }
      _publishCurrentAndQueueWindow();
      _broadcastState();
    });
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
    if (_items.isEmpty) return;
    final currentIdx = _resolveCurrentActualIndex() ?? 0;
    final start = (currentIdx - 5).clamp(0, _items.length);
    final end = (currentIdx + 45).clamp(0, _items.length);
    queue.add(_items.sublist(start, end).map(_applyOverride).toList());

    final currentTag = _items[currentIdx];
    if (currentTag.id == songId) {
      mediaItem.add(_applyOverride(currentTag));
    }
    _bumpQueueRevision();
  }

  void _loadQueueItemsInternal(List<MediaItem> mediaItems) {
    final newIds = mediaItems.map((e) => e.id).toList();

    // Optimización: si ya es la misma lista cargada y sin canciones manuales
    // pendientes, conservamos las entradas actuales.
    if (_listEquals(_currentPlaylistIds, newIds) &&
        _items.length == mediaItems.length &&
        _userQueuedUids.isEmpty) {
      return;
    }

    _userQueuedUids.clear();
    _currentPlayingUid = null;
    _currentActualIndex = null;
    _currentPlaylistIds = newIds;

    _items
      ..clear()
      ..addAll(mediaItems.map(_tagWithQueueUid));

    _shuffleOrder.pendingInsertShufflePos = null;
    _shuffleOrder.clear();
    if (_items.isNotEmpty) {
      _shuffleOrder.insert(0, _items.length);
    }
    _crossfadeEngine.invalidatePreload();
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
      _loadQueueItemsInternal(mediaItems);

      if (shuffleEnabled != null) {
        _shuffleEnabled = shuffleEnabled;
      }

      _currentActualIndex = safeIndex;
      final selectedItem = _items[safeIndex];
      _currentPlayingUid = _queueUidOfItem(selectedItem);

      if (_shuffleEnabled && _items.length > 1) {
        _shuffleOrder.forcedInitialIndex = safeIndex;
        try {
          _shuffleOrder.shuffle(initialIndex: safeIndex);
        } finally {
          _shuffleOrder.forcedInitialIndex = null;
        }
      }

      _publishCurrentAndQueueWindow();
      await _crossfadeEngine.loadAndPlayOnActiveDeck(
        _uriOfItem(selectedItem),
        autoPlay: true,
      );
      _broadcastState();
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) {
    return _enqueueOp(() async {
      _loadQueueItemsInternal(mediaItems);
      if (_shuffleEnabled && _items.length > 1) {
        _shuffleOrder.shuffle(initialIndex: _currentActualIndex);
      }
      _publishCurrentAndQueueWindow();
    });
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) {
    return _enqueueOp(() async {
      try {
        final taggedItem = _tagWithQueueUid(mediaItem);
        final queueUid = _queueUidOfItem(taggedItem)!;
        final currentActual = _resolveCurrentActualIndex();

        // Si el reproductor está vacío o no se ha iniciado:
        if (_items.isEmpty || currentActual == null) {
          _shuffleOrder.pendingInsertShufflePos = null;
          _userQueuedUids.clear();
          _currentPlaylistIds = [taggedItem.id];
          _items
            ..clear()
            ..add(taggedItem);
          _shuffleOrder.clear();
          _shuffleOrder.insert(0, 1);
          _currentActualIndex = 0;
          _currentPlayingUid = queueUid;
          _publishCurrentAndQueueWindow();
          await _crossfadeEngine.loadAndPlayOnActiveDeck(
            _uriOfItem(taggedItem),
            autoPlay: true,
          );
          _broadcastState();
          return;
        }

        // 1. Inserción en orden lineal (siempre estrictamente después de
        //    currentActual y de las canciones encoladas manualmente antes).
        final rawOrder = List<int>.generate(_items.length, (i) => i);
        final rawUserQueueCount = _contiguousUserQueueCountInOrder(
          order: rawOrder,
          currentPos: currentActual,
        );
        final insertIndex = (currentActual + 1 + rawUserQueueCount).clamp(
          currentActual + 1,
          _items.length,
        );

        // 2. Inserción exacta en orden aleatorio (FIFO después de actual + cola).
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
        _items.insert(insertIndex, taggedItem);
        if (insertIndex <= _currentPlaylistIds.length) {
          _currentPlaylistIds.insert(insertIndex, taggedItem.id);
        }

        _shuffleOrder.pendingInsertShufflePos = targetShufflePos;
        try {
          _shuffleOrder.insert(insertIndex, 1);
        } finally {
          _shuffleOrder.pendingInsertShufflePos = null;
        }

        _crossfadeEngine.invalidatePreload();
        _publishCurrentAndQueueWindow();
      } catch (e, s) {
        debugPrint('Error al añadir a la cola: $e\n$s');
        rethrow;
      }
    });
  }

  /// Remueve una canción de la cola usando su índice efectivo (visual).
  Future<void> removeEffectiveQueueItemAt(int effectiveIndex) {
    return _enqueueOp(() async {
      final order = _currentEffectiveOrder();
      if (effectiveIndex < 0 || effectiveIndex >= order.length) return;
      final actualIdx = order[effectiveIndex];
      _removeActualIndexInternal(actualIdx);
    });
  }

  /// Remueve una canción de la cola en el índice real especificado.
  @override
  Future<void> removeQueueItemAt(int index) {
    return _enqueueOp(() async => _removeActualIndexInternal(index));
  }

  void _removeActualIndexInternal(int index) {
    if (index < 0 || index >= _items.length) return;

    final removedUid = _queueUidOfItem(_items[index]);
    if (removedUid != null) {
      _userQueuedUids.remove(removedUid);
    }

    _items.removeAt(index);
    if (index < _currentPlaylistIds.length) {
      _currentPlaylistIds.removeAt(index);
    }
    _shuffleOrder.removeRange(index, index + 1);

    if (_currentActualIndex != null) {
      if (_items.isEmpty) {
        _currentActualIndex = null;
        _currentPlayingUid = null;
      } else if (index < _currentActualIndex!) {
        _currentActualIndex = _currentActualIndex! - 1;
      } else if (index == _currentActualIndex!) {
        _currentActualIndex = _currentActualIndex!.clamp(0, _items.length - 1);
      }
    }

    _crossfadeEngine.invalidatePreload();
    _publishCurrentAndQueueWindow();
  }

  /// Reordena una canción en la fila visual (índice efectivo [fromEffectiveIndex]
  /// hacia [toEffectiveIndex]).
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
      final movedUid = _queueUidOfItem(_items[movedActualIdx]);

      if (_shuffleEnabled) {
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
      } else {
        final movedItem = _items.removeAt(fromEffectiveIndex);
        _items.insert(toEffectiveIndex, movedItem);

        if (fromEffectiveIndex < _currentPlaylistIds.length &&
            toEffectiveIndex < _currentPlaylistIds.length) {
          final id = _currentPlaylistIds.removeAt(fromEffectiveIndex);
          _currentPlaylistIds.insert(toEffectiveIndex, id);
        }

        // Mantener _shuffleOrder alineado con el nuevo tamaño/índices.
        _shuffleOrder.clear();
        _shuffleOrder.insert(0, _items.length);

        _updateUserQueueMembershipAfterReorder(
          movedUid: movedUid,
          fromEffectiveIndex: fromEffectiveIndex,
          toEffectiveIndex: toEffectiveIndex,
          currentEffectiveIndex: currentEffective,
          userQueueCountBefore: userQueueCountBefore,
        );
      }

      _crossfadeEngine.invalidatePreload();
      _publishCurrentAndQueueWindow();
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
      _userQueuedUids.add(movedUid);
    } else if (wasInUserQueue && toEffectiveIndex > userQueueEndBefore) {
      _userQueuedUids.remove(movedUid);
    }
  }

  /// Mueve una canción por índice real (compatibilidad para modo lineal).
  Future<void> moveQueueItem(int fromIndex, int toIndex) {
    return _enqueueOp(() async {
      if (fromIndex < 0 || fromIndex >= _items.length) return;
      if (toIndex < 0 || toIndex >= _items.length) return;
      if (fromIndex == toIndex) return;

      if (_shuffleEnabled) {
        final fromEff = _shuffleOrder.indices.indexOf(fromIndex);
        final toEff = _shuffleOrder.indices.indexOf(toIndex);
        if (fromEff != -1 && toEff != -1) {
          _shuffleOrder.moveEffectiveIndex(fromEff, toEff);
          _crossfadeEngine.invalidatePreload();
          _bumpQueueRevision();
        }
        return;
      }

      final moved = _items.removeAt(fromIndex);
      _items.insert(toIndex, moved);
      if (fromIndex < _currentPlaylistIds.length &&
          toIndex < _currentPlaylistIds.length) {
        final id = _currentPlaylistIds.removeAt(fromIndex);
        _currentPlaylistIds.insert(toIndex, id);
      }
      _currentActualIndex = _resolveCurrentActualIndex();
      _crossfadeEngine.invalidatePreload();
      _publishCurrentAndQueueWindow();
    });
  }

  /// Devuelve los elementos en el orden efectivo de reproducción (respetando
  /// el modo aleatorio si está activo).
  List<MediaItem> get effectiveQueueItems {
    if (_items.isEmpty) return [];

    final indices = _currentEffectiveOrder();
    final items = <MediaItem>[];
    for (final idx in indices) {
      if (idx >= 0 && idx < _items.length) {
        items.add(_applyOverride(_items[idx]));
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

  /// Aplica el factor de atenuación `[0.0, 1.0]` del temporizador de apagado.
  Future<void> setSleepTimerVolumeFactor(double factor) =>
      _crossfadeEngine.setSleepTimerVolumeFactor(factor);

  /// Pausa la reproducción al finalizar la bajada progresiva del temporizador.
  Future<void> pauseFromSleepTimer() => _crossfadeEngine.pauseFromSleepTimer();

  /// Restaura suavemente el volumen si el usuario cancela el temporizador.
  Future<void> restoreSleepTimerVolume() =>
      _crossfadeEngine.restoreSleepTimerVolume();

  @override
  Future<void> play() => _crossfadeEngine.playWithFade();

  @override
  Future<void> pause() => _crossfadeEngine.pauseWithFade();

  @override
  Future<void> seek(Duration position) async {
    await _crossfadeEngine.cancelActiveTransition();
    await _activePlayer.seek(position);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() {
    return _enqueueOp(() async {
      if (_items.isEmpty) return;

      final order = _currentEffectiveOrder();
      final currentActual = _resolveCurrentActualIndex();
      final currentPos = currentActual == null
          ? -1
          : order.indexOf(currentActual);

      int nextActual;
      if (order.length <= 1) {
        nextActual = 0;
      } else if (currentPos >= 0 && currentPos + 1 < order.length) {
        nextActual = order[currentPos + 1];
      } else {
        if (_shuffleEnabled) {
          _shuffleOrder.shuffle();
        }
        nextActual = _currentEffectiveOrder().first;
      }

      await _playActualIndex(nextActual);
    });
  }

  @override
  Future<void> skipToPrevious() {
    return _enqueueOp(() async {
      if (_items.isEmpty) return;

      final order = _currentEffectiveOrder();
      final currentActual = _resolveCurrentActualIndex();
      final currentPos = currentActual == null
          ? -1
          : order.indexOf(currentActual);

      int prevActual;
      if (order.length <= 1) {
        prevActual = 0;
      } else if (currentPos > 0) {
        prevActual = order[currentPos - 1];
      } else {
        prevActual = order.last;
      }

      await _playActualIndex(prevActual);
    });
  }

  Future<void> _playActualIndex(int actualIndex) async {
    if (actualIndex < 0 || actualIndex >= _items.length) return;
    final targetItem = _items[actualIndex];
    _currentActualIndex = actualIndex;
    _currentPlayingUid = _queueUidOfItem(targetItem);
    if (_currentPlayingUid != null) {
      _userQueuedUids.remove(_currentPlayingUid);
    }

    _publishCurrentAndQueueWindow();
    await _crossfadeEngine.loadAndPlayOnActiveDeck(
      _uriOfItem(targetItem),
      autoPlay: true,
    );
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    return _enqueueOp(() async {
      final enabled = shuffleMode != AudioServiceShuffleMode.none;
      _shuffleEnabled = enabled;
      if (enabled && _items.length > 1) {
        final currentActual = _resolveCurrentActualIndex();
        _shuffleOrder.forcedInitialIndex = currentActual;
        try {
          _shuffleOrder.shuffle(initialIndex: currentActual);
        } finally {
          _shuffleOrder.forcedInitialIndex = null;
        }
      }
      _crossfadeEngine.invalidatePreload();
      _broadcastState();
      _bumpQueueRevision();
    });
  }

  @override
  Future<void> skipToQueueItem(int index) {
    return _enqueueOp(() async {
      if (index < 0 || index >= _items.length) return;
      await _playActualIndex(index);
    });
  }

  @override
  Future<void> stop() async {
    await _crossfadeEngine.stopBothDecks();
    _broadcastState();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_activePlayer.playing) {
      await stop();
    }
  }

  Future<void> dispose() async {
    await _playbackEventSub?.cancel();
    _playbackEventSub = null;
    await _crossfadeEngine.dispose();
    _equalizerEngine.dispose();
    _queueRevision.dispose();
  }
}

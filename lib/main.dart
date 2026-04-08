import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

late AudioHandler _audioHandler;

Future<void> main() async {
  // 1. Inicialización mínima obligatoria
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inicializar AudioService ANTES de runApp
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.lumina_player.channel.audio',
      androidNotificationChannelName: 'Lumina Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const LuminaApp());
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

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
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      await _player.setLoopMode(LoopMode.all);
      _notifyAudioHandlerAboutPlaybackEvents();
      _listenForSequenceStateChanges();
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

      // Actualizar queue aplicando overrides de metadatos
      final items = sequence
          .map((source) => _applyOverride(source.tag as MediaItem))
          .toList();
      queue.add(items);

      // Actualizar mediaItem actual aplicando override si existe
      final currentItem = sequenceState?.currentSource?.tag as MediaItem?;
      if (currentItem != null) {
        mediaItem.add(_applyOverride(currentItem));
      }
    });
  }

  /// Guarda un override de titulo/artista y re-emite los streams
  /// para actualizar el reproductor en tiempo real.
  void updateSongTag(String songId, String newTitle, String newArtist) {
    _metadataOverrides[songId] = {'title': newTitle, 'artist': newArtist};
    _reEmitWithOverrides(songId);
  }

  /// Elimina el override de una cancion (restablecer al original).
  void clearSongTagOverride(String songId) {
    _metadataOverrides.remove(songId);
    _reEmitWithOverrides(songId);
  }

  void _reEmitWithOverrides(String songId) {
    final sequence = _player.sequence;
    if (sequence != null) {
      final updatedItems = sequence
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
    final audioSources = mediaItems.map(
      (item) => AudioSource.uri(Uri.parse(item.extras!['url']), tag: item),
    );
    await _playlist.clear();
    await _playlist.addAll(audioSources.toList());

    // Si el modo aleatorio está encendido, baraja de nuevo los elementos recién añadidos - canciones
    if (_player.shuffleModeEnabled) {
      await _player.shuffle();
    }

    queue.add(mediaItems);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final audioSource = AudioSource.uri(
      Uri.parse(mediaItem.extras!['url']),
      tag: mediaItem,
    );

    // Insertar justo después de la canción actual (Reproducir a continuación)
    int insertIndex = _playlist.length;
    if (_player.currentIndex != null) {
      insertIndex = _player.currentIndex! + 1;
    }

    await _playlist.insert(insertIndex, audioSource);

    // just_audio emitirá el nuevo "sequenceStateStream" y nuestra función
    // _listenForSequenceStateChanges actualizará la queue de la interfaz automáticamente,
    // así que no necesitamos modificar 'queue.value' manualmente aquí.
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
      // Wrap around explicitly when there's no next item
      if (_player.shuffleModeEnabled) {
        await _player.shuffle(); // Reshuffle for a truly infinite random feel
      }
      // Seek to the beginning of the sequence (either original or shuffled)
      int nextIndex = _player.effectiveIndices?.first ?? 0;
      await _player.seek(Duration.zero, index: nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      // Loop back to the end of the playlist
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
    if (index < 0 || index >= queue.value.length) return;
    _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Si el usuario cierra la app deslizando de recientes, y está en pausa,
    // matamos el servicio para que desaparezca la notificación fantasma.
    if (!_player.playing) {
      await stop();
    }
  }
}

class AppHelpers {
  static Widget getRandomDefaultCover({
    required BuildContext context,
    required int id,
    double? width,
    double? height,
  }) {
    final coverIndex = (id.hashCode).abs() % 5 + 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/covers/cover_$coverIndex.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: isDark
          ? Container(color: Colors.black.withValues(alpha: 0.3))
          : null,
    );
  }
}

class PlaylistModelCustom {
  final String id;
  String name;
  List<SongModel> songs;
  String? coverPath;

  PlaylistModelCustom({
    required this.id,
    required this.name,
    required this.songs,
    this.coverPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverPath': coverPath,
      'songs': songs.map((s) {
        return {
          '_id': s.id,
          'title': s.title,
          'artist': s.artist,
          'album': s.album,
          'duration': s.duration,
          '_data': s.data,
          '_uri': s.uri,
          '_display_name': s.displayName,
          '_display_name_wo_ext': s.displayNameWOExt,
          '_size': s.size,
          'album_id': s.albumId,
          'artist_id': s.artistId,
        };
      }).toList(),
    };
  }

  factory PlaylistModelCustom.fromJson(Map<String, dynamic> json) {
    return PlaylistModelCustom(
      id: json['id'],
      name: json['name'],
      coverPath: json['coverPath'] as String?,
      songs: (json['songs'] as List).map((s) {
        return SongModel(s);
      }).toList(),
    );
  }
}

class LuminaApp extends StatefulWidget {
  const LuminaApp({super.key});
  @override
  State<LuminaApp> createState() => _LuminaAppState();
}

class _LuminaAppState extends State<LuminaApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  void _toggleTheme(bool isDark) =>
      setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.light,
          primary: const Color(0xFF4CAF50),
          secondary: const Color(0xFF4CAF50),
          surface: const Color(0xFFF5F5F5),
          onSurface: Colors.black87,
        ),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1A1A1A),
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: SplashScreen(themeMode: _themeMode, onThemeChanged: _toggleTheme),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;
  const SplashScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _chunks = [
    "Lumina,",
    "ilumina tu vida",
    "con música", // Últimas dos palabras juntas
  ];

  @override
  void initState() {
    super.initState();
    // 5 chunks, 1 segundo por chunk => 5 segundos en total
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _controller.forward();

    // Damos 1 segundo extra para que se vea el resultado final y recien cambiamos
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MusicLibraryPage(
              themeMode: widget.themeMode,
              onThemeChanged: widget.onThemeChanged,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black87;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/iconoApp.png', width: 150, height: 150),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6.0,
              runSpacing: 4.0,
              children: List.generate(_chunks.length, (index) {
                // Cada chunk comienza exactamente a su fraccion de tiempo
                // index 0 -> 0.0, index 1 -> 0.2, index 2 -> 0.4... (cada 1 segundo)
                final double start = index / _chunks.length;
                // Cada animación de aparición dura 0.2 (1 segundo de 5)
                final double end = (start + 0.2).clamp(0.0, 1.0);

                final Animation<double> slideAnimation =
                    Tween<double>(begin: 20.0, end: 0.0).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Interval(start, end, curve: Curves.easeOutCubic),
                      ),
                    );

                final Animation<double> opacityAnimation =
                    Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Interval(start, end, curve: Curves.easeIn),
                      ),
                    );

                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, slideAnimation.value),
                      child: Opacity(
                        opacity: opacityAnimation.value,
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    _chunks[index],
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.8),
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class MusicLibraryPage extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;
  const MusicLibraryPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  int _selectedIndex = 0;
  final List<SongModel> _songs = [];
  final Set<int> _favoriteIds = {};
  final List<PlaylistModelCustom> _playlists = [];
  PlaylistModelCustom? _selectedPlaylist;
  bool _isLoading = true;
  String _searchQuery = "";
  String _playlistSearchQuery = "";
  final Map<int, Map<String, String>> _customMetadata = {};

  @override
  void initState() {
    super.initState();
    // EJECUCIÓN SEGURA: Esperamos a que la Activity esté vinculada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      _loadFavorites();
      _loadPlaylists();
      _loadCustomMetadata();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      // 1. Pedir permisos de audio y almacenamiento
      final status = await [Permission.audio, Permission.storage].request();

      // 2. Pedir notificaciones
      await Permission.notification.request();

      if (status[Permission.audio]!.isGranted ||
          status[Permission.storage]!.isGranted) {
        _loadSongs();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error en permisos: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (mounted) {
        setState(() {
          _songs.clear();
          _songs.addAll(songs.where((song) => song.isMusic == true).toList());
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshLibrary() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Buscando nuevas canciones...',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors
                .black, // Color oscuro para contrastar con el fondo blanco
          ),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),
    );
    await _loadSongs();
  }

  List<SongModel> get _filteredSongs {
    if (_searchQuery.isEmpty) return _songs;
    return _songs.where((song) {
      final title = song.title.toLowerCase();
      final artist = (song.artist ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  List<SongModel> get _favoriteSongs {
    final favorites = _songs.where((s) => _favoriteIds.contains(s.id)).toList();
    if (_searchQuery.isEmpty) return favorites;
    return favorites.where((song) {
      final title = song.title.toLowerCase();
      final artist = (song.artist ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  List<PlaylistModelCustom> get _filteredPlaylists {
    if (_playlistSearchQuery.isEmpty) return _playlists;
    return _playlists
        .where(
          (p) =>
              p.name.toLowerCase().contains(_playlistSearchQuery.toLowerCase()),
        )
        .toList();
  }

  void _toggleFavorite(int songId) {
    setState(() {
      if (_favoriteIds.contains(songId)) {
        _favoriteIds.remove(songId);
      } else {
        _favoriteIds.add(songId);
      }
    });
    _saveFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];
      setState(() {
        _favoriteIds.clear();
        _favoriteIds.addAll(favorites.map((e) => int.parse(e)));
      });
    } catch (e) {
      debugPrint("Error cargando favoritos: $e");
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'favorites',
        _favoriteIds.map((e) => e.toString()).toList(),
      );
    } catch (e) {
      debugPrint("Error guardando favoritos: $e");
    }
  }

  Future<void> _loadCustomMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? encodedData = prefs.getString('custom_metadata');
      if (encodedData != null) {
        final Map<String, dynamic> decodedData = jsonDecode(encodedData);
        setState(() {
          _customMetadata.clear();
          decodedData.forEach((key, value) {
            _customMetadata[int.parse(key)] = Map<String, String>.from(value);
          });
        });
      }
    } catch (e) {
      debugPrint("Error cargando custom metadata: $e");
    }
  }

  Future<void> _saveCustomMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encodedData = jsonEncode(
        _customMetadata.map((key, value) => MapEntry(key.toString(), value)),
      );
      await prefs.setString('custom_metadata', encodedData);
    } catch (e) {
      debugPrint("Error guardando custom metadata: $e");
    }
  }

  String _getSongTitle(SongModel song) {
    return _customMetadata[song.id]?['title'] ?? song.title;
  }

  String _getSongArtist(SongModel song) {
    return _customMetadata[song.id]?['artist'] ?? song.artist ?? "Desconocido";
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encodedData = jsonEncode(
        _playlists.map((p) => p.toJson()).toList(),
      );
      await prefs.setString('playlists', encodedData);
    } catch (e) {
      debugPrint("Error guardando playlists: $e");
    }
  }

  Future<void> _loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? encodedData = prefs.getString('playlists');
      if (encodedData != null) {
        final List<dynamic> decodedData = jsonDecode(encodedData);
        setState(() {
          _playlists.clear();
          _playlists.addAll(
            decodedData.map((json) => PlaylistModelCustom.fromJson(json)),
          );
        });
      }
    } catch (e) {
      debugPrint("Error cargando playlists: $e");
    }
  }

  Future<void> _playSong(SongModel song, {List<SongModel>? fromList}) async {
    final listToPlay = fromList ?? _songs;
    final mediaItems = listToPlay
        .map(
          (s) => MediaItem(
            id: '${s.id}',
            album: s.album ?? "Desconocido",
            title: _getSongTitle(s),
            artist: _getSongArtist(s),
            artUri: Uri.parse(
              'content://media/external/audio/media/${s.id}/albumart',
            ),
            duration: Duration(milliseconds: s.duration ?? 0),
            extras: {'url': s.data},
          ),
        )
        .toList();

    final index = listToPlay.indexWhere((s) => s.id == song.id);

    await _audioHandler.addQueueItems(mediaItems);
    await _audioHandler.skipToQueueItem(index != -1 ? index : 0);
    _audioHandler.play();
  }

  void _playPlaylist(
    List<SongModel> playlistSongs, {
    bool shuffle = false,
  }) async {
    if (playlistSongs.isEmpty) return;
    if (shuffle) {
      await _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    } else {
      await _audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
    }
    _playSong(playlistSongs[0], fromList: playlistSongs);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex != 2 || _selectedPlaylist == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex == 2 && _selectedPlaylist != null) {
          setState(() => _selectedPlaylist = null);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildMainContent(),
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildMiniPlayer(snapshot.data!),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_selectedIndex == 3) return _buildSettingsContent();
    if (_selectedIndex == 2) {
      return _selectedPlaylist != null
          ? _buildPlaylistDetailView(_selectedPlaylist!)
          : _buildPlaylistsContent();
    }
    if (_selectedIndex == 1) return _buildFavoritesContent();

    final displaySongs = _filteredSongs;
    return Container(
      decoration: _buildBackgroundDecoration(),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(onRefresh: _refreshLibrary),
            _buildSectionTitle('Tu Biblioteca', displaySongs.length),
            _buildSearchBar(),
            const SizedBox(height: 20),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshLibrary,
                color: const Color(0xFF4CAF50),
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : displaySongs.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.2,
                          ),
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 60,
                                  color: Colors.grey[800],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _searchQuery.isEmpty
                                      ? "No se encontró música"
                                      : "Sin resultados",
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: displaySongs.length,
                        itemBuilder: (context, index) =>
                            _buildMusicCard(displaySongs[index]),
                      ),
              ),
            ),
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData) return const SizedBox(height: 85);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _buildBackgroundDecoration() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF0A0A0A),
                const Color(0xFF1A1A1A),
                const Color(0xFF0A0A0A),
              ]
            : [Colors.white, Colors.grey[100]!, Colors.white],
      ),
    );
  }

  Widget _buildFavoritesContent() {
    final favorites = _favoriteSongs;
    return Container(
      decoration: _buildBackgroundDecoration(),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSectionTitle('Favoritos', favorites.length),
            _buildSearchBar(),
            const SizedBox(height: 20),
            Expanded(
              child: favorites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 60,
                            color: Colors.grey[800],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _searchQuery.isEmpty
                                ? "Aún no tienes favoritos"
                                : "Sin resultados en favoritos",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: favorites.length,
                      itemBuilder: (context, index) =>
                          _buildMusicCard(favorites[index]),
                    ),
            ),
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData) return const SizedBox(height: 85);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredPlaylists = _filteredPlaylists;

    return Container(
      decoration: _buildBackgroundDecoration(),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildPlaylistsHeader(isDark),
            _buildPlaylistSearchBar(),
            Expanded(
              child: _playlists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            size: 60,
                            color: Colors.grey[800],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Crea tu primera lista",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 25,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: filteredPlaylists.length,
                      itemBuilder: (context, index) =>
                          _buildPlaylistGridCard(filteredPlaylists[index]),
                    ),
            ),
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData) return const SizedBox(height: 85);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          onChanged: (value) => setState(() => _playlistSearchQuery = value),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Buscar en mis listas...',
            hintStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            border: InputBorder.none,
            icon: Icon(
              Icons.search,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistGridCard(PlaylistModelCustom playlist) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => setState(() => _selectedPlaylist = playlist),
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Editar'),
                  onTap: () {
                    Navigator.pop(context);
                    _openEditPlaylist(playlist);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.red),
                  title: const Text(
                    'Eliminar',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deletePlaylist(playlist);
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _buildLargePlaylistCover(playlist),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            '${playlist.songs.length} canciones',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargePlaylistCover(PlaylistModelCustom playlist) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(30);

    // Si hay portada personalizada, mostrarla primero
    if (playlist.coverPath != null && File(playlist.coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(playlist.coverPath!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    if (playlist.songs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[200],
          borderRadius: borderRadius,
        ),
        child: Icon(
          Icons.music_note_rounded,
          size: 50,
          color: colorScheme.primary.withValues(alpha: 0.5),
        ),
      );
    }

    if (playlist.songs.length == 1 ||
        playlist.name.toLowerCase().contains("favoritos")) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: QueryArtworkWidget(
          id: playlist.songs[0].id,
          type: ArtworkType.AUDIO,
          size: 500,
          artworkFit: BoxFit.cover,
          nullArtworkWidget: AppHelpers.getRandomDefaultCover(
            context: context,
            id: playlist.songs[0].id,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[200],
        borderRadius: borderRadius,
      ),
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: 4,
          itemBuilder: (context, i) {
            if (i < playlist.songs.length) {
              if (i == 3 && playlist.songs.length > 4) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A34),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '+${playlist.songs.length - 3}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF252A34),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: QueryArtworkWidget(
                    id: playlist.songs[i].id,
                    type: ArtworkType.AUDIO,
                    format: ArtworkFormat.JPEG,
                    size: 2000,
                    artworkBorder: BorderRadius.zero,
                    artworkFit: BoxFit.cover,
                    nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                      context: context,
                      id: playlist.songs[i].id,
                    ),
                  ),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF252A34).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getPlaylistDuration(List<SongModel> songs) {
    int totalMs = songs.fold(0, (sum, song) => sum + (song.duration ?? 0));
    Duration duration = Duration(milliseconds: totalMs);
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    return '$minutes min $seconds s';
  }

  Widget _buildHeaderCollage(PlaylistModelCustom playlist) {
    // Si hay portada personalizada, mostrarla en lugar del collage
    if (playlist.coverPath != null && File(playlist.coverPath!).existsSync()) {
      return Image.file(
        File(playlist.coverPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (playlist.songs.isEmpty) return Container(color: Colors.grey[900]);

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      ),
      itemCount: min(playlist.songs.length, 4),
      itemBuilder: (context, i) => QueryArtworkWidget(
        id: playlist.songs[i].id,
        type: ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 2000,
        artworkBorder: BorderRadius.zero,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: AppHelpers.getRandomDefaultCover(
          context: context,
          id: playlist.songs[i].id,
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 50,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary
              ? const Color(0xFF4CAF50)
              : Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }

  Widget _buildSongListItem(SongModel song, List<SongModel> list) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFavorite = _favoriteIds.contains(song.id);

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final isSelected = snapshot.data?.id == '${song.id}';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    artworkWidth: 55,
                    artworkHeight: 55,
                    artworkFit: BoxFit.cover,
                    nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                      context: context,
                      id: song.id,
                      width: 55,
                      height: 55,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: InkWell(
                    onTap: () => _playSong(song, fromList: list),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getSongTitle(song),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isSelected
                                ? const Color(0xFF4CAF50)
                                : colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _getSongArtist(song),
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite
                            ? const Color(0xFF4CAF50)
                            : colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      onPressed: () => _toggleFavorite(song.id),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      onPressed: () => _showSongOptions(context, song),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistDetailView(PlaylistModelCustom playlist) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final durationText = _getPlaylistDuration(playlist.songs);

    return Container(
      color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 400,
            child: Opacity(opacity: 0.7, child: _buildHeaderCollage(playlist)),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    isDark
                        ? const Color(0xFF0A0A0A).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.4),
                    isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  ],
                  stops: const [0.0, 0.5, 0.85],
                ),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => setState(() => _selectedPlaylist = null),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 15,
                      top: 8,
                      bottom: 8,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4CAF50),
                          width: 2,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.image_rounded),
                                    title: const Text('Cambiar portada'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _changePlaylistCover(playlist);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.edit_rounded),
                                    title: const Text('Renombrar lista'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _renamePlaylist(playlist);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.delete_rounded,
                                      color: Colors.red,
                                    ),
                                    title: const Text(
                                      'Eliminar lista',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _deletePlaylist(playlist);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 100),
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 10,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${playlist.songs.length} canciones • $durationText',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildCircleButton(
                            icon: Icons.edit_rounded,
                            onTap: () => _showEditPlaylistDialog(playlist),
                            size: 45,
                          ),
                          const SizedBox(width: 12),
                          _buildCircleButton(
                            icon: Icons.add_rounded,
                            onTap: () => _openAddSongsToPlaylist(playlist),
                            size: 45,
                          ),
                          const SizedBox(width: 15),
                          _buildCircleButton(
                            icon: Icons.shuffle_rounded,
                            onTap: () =>
                                _playPlaylist(playlist.songs, shuffle: true),
                            size: 55,
                          ),
                          const SizedBox(width: 15),
                          _buildCircleButton(
                            icon: Icons.play_arrow_rounded,
                            onTap: () =>
                                _playPlaylist(playlist.songs, shuffle: false),
                            size: 75,
                            isPrimary: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = playlist.songs[index];
                  return _buildSongListItem(song, playlist.songs);
                }, childCount: playlist.songs.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ],
      ),
    );
  }

  void _renamePlaylist(PlaylistModelCustom playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar lista'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nuevo nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  playlist.name = controller.text;
                });
                _savePlaylists();
                Navigator.pop(context);
              }
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  void _changePlaylistCover(PlaylistModelCustom playlist) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          final index = _playlists.indexWhere((p) => p.id == playlist.id);
          if (index != -1) {
            _playlists[index] = PlaylistModelCustom(
              id: playlist.id,
              name: playlist.name,
              songs: playlist.songs,
              coverPath: picked.path,
            );
            if (_selectedPlaylist?.id == playlist.id) {
              _selectedPlaylist = _playlists[index];
            }
          }
        });
        _savePlaylists();
      }
    } catch (e) {
      debugPrint('Error al cambiar portada: $e');
    }
  }
  /// Construye una miniatura 2×2 con dimensiones explícitas para funcionar
  /// correctamente dentro de un AlertDialog (que no provee restricciones
  /// de tamaño a GridView).
  Widget _buildDialogCollage(PlaylistModelCustom playlist, bool isDark) {
    // Tamaño de cada celda: 110px total - 4px padding*2 - 3px gap = 99px / 2 ≈ 49px
    const double cellSize = 49.0;
    const double gap = 3.0;

    Widget cell(int i) {
      if (i < playlist.songs.length) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: cellSize,
            height: cellSize,
            child: QueryArtworkWidget(
              id: playlist.songs[i].id,
              type: ArtworkType.AUDIO,
              format: ArtworkFormat.JPEG,
              size: 200,
              artworkWidth: cellSize,
              artworkHeight: cellSize,
              artworkBorder: BorderRadius.zero,
              artworkFit: BoxFit.cover,
              nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                context: context,
                id: playlist.songs[i].id,
                width: cellSize,
                height: cellSize,
              ),
            ),
          ),
        );
      }
      return Container(
        width: cellSize,
        height: cellSize,
        decoration: BoxDecoration(
          color: const Color(0xFF252A34).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [cell(0), const SizedBox(width: gap), cell(1)],
          ),
          const SizedBox(height: gap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [cell(2), const SizedBox(width: gap), cell(3)],
          ),
        ],
      ),
    );
  }

  void _showEditPlaylistDialog(PlaylistModelCustom playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? localCoverPath = playlist.coverPath;
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(Icons.edit_rounded, color: Color(0xFF4CAF50), size: 22),
                SizedBox(width: 8),
                Text(
                  'Editar lista',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Selector de portada ---
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                    final XFile? picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (picked != null) {
                      setDialogState(() => localCoverPath = picked.path);
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1A1A1A)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: localCoverPath != null &&
                                  File(localCoverPath!).existsSync()
                              ? Image.file(
                                  File(localCoverPath!),
                                  fit: BoxFit.cover,
                                  width: 110,
                                  height: 110,
                                )
                              : playlist.songs.isEmpty
                              ? Icon(
                                  Icons.music_note_rounded,
                                  size: 44,
                                  color: const Color(
                                    0xFF4CAF50,
                                  ).withValues(alpha: 0.6),
                                )
                              : _buildDialogCollage(playlist, isDark),
                        ),
                      ),
                      // Badge de cámara
                      Positioned(
                        bottom: -6,
                        right: -6,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Añadir portada',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
                // --- Campo de nombre ---
                TextField(
                  controller: nameController,
                  autofocus: false,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Nombre de la lista',
                    labelStyle: const TextStyle(color: Color(0xFF4CAF50)),
                    prefixIcon: const Icon(
                      Icons.playlist_play_rounded,
                      color: Color(0xFF4CAF50),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR'),
              ),
              TextButton(
                onPressed: () {
                  final newName = nameController.text.trim();
                  Navigator.pop(context);
                  setState(() {
                    final index =
                        _playlists.indexWhere((p) => p.id == playlist.id);
                    if (index != -1) {
                      _playlists[index] = PlaylistModelCustom(
                        id: playlist.id,
                        name: newName.isEmpty ? playlist.name : newName,
                        songs: playlist.songs,
                        coverPath: localCoverPath,
                      );
                      if (_selectedPlaylist?.id == playlist.id) {
                        _selectedPlaylist = _playlists[index];
                      }
                    }
                  });
                  _savePlaylists();
                },
                child: const Text(
                  'GUARDAR',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openAddSongsToPlaylist(PlaylistModelCustom playlist) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddSongsScreen(
          allSongs: _songs,
          currentPlaylistSongs: playlist.songs,
        ),
      ),
    );

    if (result != null && result is List<SongModel>) {
      setState(() {
        playlist.songs.addAll(result);
      });
      _savePlaylists();
    }
  }

  void _openCreatePlaylist() async {
    final defaultName = "Lista ${_playlists.length + 1}";
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePlaylistScreen(
          availableSongs: _songs,
          defaultName: defaultName,
        ),
      ),
    );

    if (result != null && result is PlaylistModelCustom) {
      setState(() {
        _playlists.add(result);
      });
      _savePlaylists();
    }
  }

  void _openEditPlaylist(PlaylistModelCustom playlist) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePlaylistScreen(
          availableSongs: _songs,
          initialPlaylist: playlist,
        ),
      ),
    );

    if (result != null && result is PlaylistModelCustom) {
      setState(() {
        final index = _playlists.indexWhere((p) => p.id == playlist.id);
        if (index != -1) {
          _playlists[index] = result;
          if (_selectedPlaylist?.id == playlist.id) {
            _selectedPlaylist = result;
          }
        }
      });
      _savePlaylists();
    }
  }

  void _deletePlaylist(PlaylistModelCustom playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text('¿Seguro que quieres eliminar "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _playlists.removeWhere((p) => p.id == playlist.id);
                if (_selectedPlaylist?.id == playlist.id) {
                  _selectedPlaylist = null;
                }
              });
              _savePlaylists();
              Navigator.pop(context);
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    return Container(
      decoration: _buildBackgroundDecoration(),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Ajustes',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildSettingTile(
                    icon: Icons.dark_mode_rounded,
                    title: 'Modo Oscuro',
                    trailing: Switch(
                      value: Theme.of(context).brightness == Brightness.dark,
                      onChanged: (value) => widget.onThemeChanged(value),
                      activeThumbColor: const Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Aplicación Creada por ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const TextSpan(
                      text: 'Alvaro Jesus',
                      style: TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData) return const SizedBox(height: 85);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF4CAF50)),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  void _showSongOptions(BuildContext context, SongModel song) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      artworkWidth: 40,
                      artworkHeight: 40,
                      nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                        context: context,
                        id: song.id,
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ),
                  title: Text(
                    _getSongTitle(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _getSongArtist(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Editar canción'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditSongDialog(song);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Agregar a lista de reproducción'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddToPlaylistDialog(song);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: const Text('Añadir a la cola de reproducción'),
                  onTap: () {
                    Navigator.pop(context);
                    _addToQueue(song);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.visibility_off_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Ocultar canción (Eliminar de la vista)',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteSong(song);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateAudioHandlerMetadata(SongModel song) {
    (_audioHandler as MyAudioHandler).updateSongTag(
      '${song.id}',
      _getSongTitle(song),
      _getSongArtist(song),
    );
  }

  void _clearAudioHandlerMetadata(SongModel song) {
    (_audioHandler as MyAudioHandler).clearSongTagOverride('${song.id}');
  }

  void _showEditSongDialog(SongModel song) {
    final titleController = TextEditingController(text: _getSongTitle(song));
    final artistController = TextEditingController(text: _getSongArtist(song));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_rounded, color: Color(0xFF4CAF50), size: 22),
            const SizedBox(width: 8),
            const Text(
              'Editar canción',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                labelText: 'Título',
                labelStyle: const TextStyle(color: Color(0xFF4CAF50)),
                prefixIcon: const Icon(Icons.music_note_rounded, color: Color(0xFF4CAF50)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: artistController,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                labelText: 'Artista',
                labelStyle: const TextStyle(color: Color(0xFF4CAF50)),
                prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF4CAF50)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar primero para garantizar que se cierra
              setState(() {
                _customMetadata.remove(song.id);
              });
              _saveCustomMetadata();
              _clearAudioHandlerMetadata(song);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Canción restablecida al original'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );
            },
            child: const Text(
              'RESTABLECER',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = titleController.text.trim();
              final newArtist = artistController.text.trim();
              if (newTitle.isEmpty) return;
              Navigator.pop(context); // Cerrar primero para garantizar que se cierra
              setState(() {
                _customMetadata[song.id] = {
                  'title': newTitle,
                  'artist': newArtist,
                };
              });
              _saveCustomMetadata();
              _updateAudioHandlerMetadata(song);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Canción actualizada'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );
            },
            child: const Text(
              'GUARDAR',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(SongModel song) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agregar a...'),
          content: SizedBox(
            width: double.maxFinite,
            child: _playlists.isEmpty
                ? const Text('No tienes listas creadas aún.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _playlists.length + 1, // +1 for "Create new"
                    itemBuilder: (context, index) {
                      if (index == _playlists.length) {
                        return ListTile(
                          leading: const Icon(Icons.add),
                          title: const Text('Crear nueva lista'),
                          onTap: () {
                            Navigator.pop(context);
                            _openCreatePlaylistWithSong(song);
                          },
                        );
                      }
                      final playlist = _playlists[index];
                      final alreadyAdded = playlist.songs.any(
                        (s) => s.id == song.id,
                      );
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(playlist.name),
                        trailing: alreadyAdded
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (!alreadyAdded) {
                            setState(() {
                              playlist.songs.add(song);
                            });
                            _savePlaylists();
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Agregada a "${playlist.name}"'),
                                backgroundColor: const Color(0xFF6C63FF),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
          ],
        );
      },
    );
  }

  void _openCreatePlaylistWithSong(SongModel song) async {
    final defaultName = "Lista ${_playlists.length + 1}";
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePlaylistScreen(
          availableSongs: _songs,
          defaultName: defaultName,
        ),
      ),
    );

    if (result != null && result is PlaylistModelCustom) {
      if (!result.songs.any((s) => s.id == song.id)) {
        result.songs.add(song);
      }
      setState(() {
        _playlists.add(result);
      });
      _savePlaylists();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lista creada y canción agregada'),
          backgroundColor: Color.fromARGB(255, 255, 255, 255),
        ),
      );
    }
  }

  void _addToQueue(SongModel song) {
    final mediaItem = MediaItem(
      id: '${song.id}',
      album: song.album ?? "Desconocido",
      title: _getSongTitle(song),
      artist: _getSongArtist(song),
      artUri: Uri.parse(
        'content://media/external/audio/media/${song.id}/albumart',
      ),
      duration: Duration(milliseconds: song.duration ?? 0),
      extras: {'url': song.data},
    );
    _audioHandler.addQueueItem(mediaItem);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Añadida a la cola de reproducción',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Color.fromARGB(255, 255, 255, 255),
      ),
    );
  }

  void _deleteSong(SongModel song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ocultar canción'),
        content: Text(
          'Debido a restricciones de Android, la canción no se borrará de tu teléfono centralmente, pero se ocultará de Lumina Player.\n\n¿Deseas ocultar "${song.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _songs.removeWhere((s) => s.id == song.id);
                // Also remove from favorites if it was there
                if (_favoriteIds.contains(song.id)) {
                  _favoriteIds.remove(song.id);
                  _saveFavorites();
                }
              });
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Canción ocultada exitosamente'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text('OCULTAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicCard(SongModel song) {
    bool isSelected = false;
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        isSelected = snapshot.data?.id == '${song.id}';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4CAF50).withOpacity(0.15)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 5,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 50,
                height: 50,
                child: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  format: ArtworkFormat.JPEG,
                  size: 2000,
                  artworkWidth: 50,
                  artworkHeight: 50,
                  artworkBorder: BorderRadius.zero,
                  artworkFit: BoxFit.cover,
                  nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                    context: context,
                    id: song.id,
                    width: 50,
                    height: 50,
                  ),
                ),
              ),
            ),
            title: Text(
              _getSongTitle(song),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF4CAF50)
                    : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              _getSongArtist(song),
              maxLines: 1,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _favoriteIds.contains(song.id)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _favoriteIds.contains(song.id)
                        ? const Color(0xFF4CAF50)
                        : colorScheme.onSurface.withOpacity(0.5),
                    size: 20,
                  ),
                  onPressed: () => _toggleFavorite(song.id),
                ),
                IconButton(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: colorScheme.onSurface.withOpacity(0.5),
                    size: 20,
                  ),
                  onPressed: () => _showSongOptions(context, song),
                ),
              ],
            ),
            onTap: () => _playSong(song),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(MediaItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showFullPlayer(),
      child: Container(
        height: 75,
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: QueryArtworkWidget(
                id: int.parse(item.id),
                type: ArtworkType.AUDIO,
                artworkWidth: 55,
                artworkHeight: 55,
                size: 300,
                artworkFit: BoxFit.cover,
                nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                  context: context,
                  id: int.parse(item.id),
                  width: 55,
                  height: 55,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.artist ?? "Desconocido",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.skip_next_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => _audioHandler.skipToNext(),
            ),
            StreamBuilder<PlaybackState>(
              stream: _audioHandler.playbackState,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return IconButton(
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    size: 40,
                    color: const Color(0xFF4CAF50),
                  ),
                  onPressed: () =>
                      playing ? _audioHandler.pause() : _audioHandler.play(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFullPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FullPlayerScreen(
        audioHandler: _audioHandler,
        favoriteIds: _favoriteIds,
        onToggleFavorite: _toggleFavorite,
      ),
    );
  }

  Widget _buildHeader({VoidCallback? onRefresh}) => Padding(
    padding: const EdgeInsets.all(20.0),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            color: Colors.black,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Lumina',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        if (onRefresh != null)
          IconButton(
            onPressed: onRefresh,
            icon: Icon(
              Icons.refresh_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            tooltip: 'Actualizar biblioteca',
          ),
      ],
    ),
  );

  Widget _buildSectionTitle(String title, int count) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          '$count canciones',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _buildPlaylistsHeader(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Mis Listas',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        GestureDetector(
          onTap: () => _openCreatePlaylist(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add,
              color: Color(0xFF4CAF50),
              size: 24,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Buscar...',
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
          icon: Icon(
            Icons.search,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    ),
  );

  Widget _buildBottomNavBar() => BottomNavigationBar(
    currentIndex: _selectedIndex,
    onTap: (i) => setState(() {
      _selectedIndex = i;
      if (i != 2) _selectedPlaylist = null;
    }),
    type: BottomNavigationBarType.fixed,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0A0A0A)
        : Colors.white,
    selectedItemColor: const Color(0xFF4CAF50),
    unselectedItemColor: Colors.grey,
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Librería'),
      BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favoritos'),
      BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Listas'),
      BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
    ],
  );
}

class CreatePlaylistScreen extends StatefulWidget {
  final List<SongModel> availableSongs;
  final PlaylistModelCustom? initialPlaylist;
  final String? defaultName;

  const CreatePlaylistScreen({
    super.key,
    required this.availableSongs,
    this.initialPlaylist,
    this.defaultName,
  });

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}


class _CreatePlaylistScreenState extends State<CreatePlaylistScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<SongModel> _selectedSongs = [];
  String _searchQuery = '';
  String? _selectedCoverPath;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialPlaylist != null) {
      _nameController.text = widget.initialPlaylist!.name;
      _selectedSongs.addAll(widget.initialPlaylist!.songs);
      _selectedCoverPath = widget.initialPlaylist!.coverPath;
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _selectedCoverPath = picked.path);
      }
    } catch (e) {
      debugPrint('Error al seleccionar imagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.initialPlaylist == null ? 'Nueva Lista' : 'Editar Lista',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              final nameToUse = _nameController.text.trim().isEmpty
                  ? (widget.defaultName ?? "Mi Lista")
                  : _nameController.text.trim();

              Navigator.pop(
                context,
                PlaylistModelCustom(
                  id:
                      widget.initialPlaylist?.id ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameToUse,
                  songs: List.from(_selectedSongs),
                  coverPath: _selectedCoverPath,
                ),
              );
            },
            child: const Text(
              'GUARDAR',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                  onTap: _pickCoverImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: _selectedCoverPath != null &&
                                  File(_selectedCoverPath!).existsSync()
                              ? Image.file(
                                  File(_selectedCoverPath!),
                                  fit: BoxFit.cover,
                                  width: 100,
                                  height: 100,
                                )
                              : _selectedSongs.isEmpty
                              ? const Icon(
                                  Icons.image_search_rounded,
                                  size: 40,
                                  color: Colors.grey,
                                )
                              : GridView.builder(
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                      ),
                                  itemCount: min(_selectedSongs.length, 4),
                                  itemBuilder: (context, i) =>
                                      QueryArtworkWidget(
                                        id: _selectedSongs[i].id,
                                        type: ArtworkType.AUDIO,
                                        format: ArtworkFormat.JPEG,
                                        artworkBorder: BorderRadius.zero,
                                        artworkFit: BoxFit.cover,
                                        nullArtworkWidget:
                                            AppHelpers.getRandomDefaultCover(
                                              context: context,
                                              id: _selectedSongs[i].id,
                                            ),
                                      ),
                                ),
                        ),
                      ),
                      // Botón de cámara superpuesto
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Añadir portada',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: widget.initialPlaylist == null,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Nombre de la lista (Opcional)',
                      hintStyle: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar canción...',
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  icon: Icon(
                    Icons.search,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Seleccionar canciones',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_selectedSongs.length} seleccionadas',
                  style: const TextStyle(color: Color(0xFF4CAF50)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: widget.availableSongs
                  .where(
                    (s) =>
                        s.title.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ) ||
                        (s.artist ?? "").toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ),
                  )
                  .length,
              itemBuilder: (context, index) {
                final filteredSongs = widget.availableSongs
                    .where(
                      (s) =>
                          s.title.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ) ||
                          (s.artist ?? "").toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ),
                    )
                    .toList();
                final song = filteredSongs[index];
                final isSelected = _selectedSongs.any((s) => s.id == song.id);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: const Color(0xFF4CAF50),
                  checkboxShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    song.artist ?? "Desconocido",
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: QueryArtworkWidget(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        format: ArtworkFormat.JPEG,
                        size: 2000,
                        artworkWidth: 50,
                        artworkHeight: 50,
                        artworkBorder: BorderRadius.zero,
                        artworkFit: BoxFit.cover,
                        nullArtworkWidget: AppHelpers.getRandomDefaultCover(
                          context: context,
                          id: song.id,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedSongs.add(song);
                      } else {
                        _selectedSongs.removeWhere((s) => s.id == song.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AddSongsScreen extends StatefulWidget {
  final List<SongModel> allSongs;
  final List<SongModel> currentPlaylistSongs;

  const AddSongsScreen({
    super.key,
    required this.allSongs,
    required this.currentPlaylistSongs,
  });

  @override
  State<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<AddSongsScreen> {
  final List<SongModel> _selectedToAdd = [];
  late List<SongModel> _notAddedSongs;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final currentIds = widget.currentPlaylistSongs.map((s) => s.id).toSet();
    _notAddedSongs = widget.allSongs
        .where((s) => !currentIds.contains(s.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Añadir canciones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selectedToAdd),
            child: const Text(
              'LISTO',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar canción...',
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  icon: Icon(
                    Icons.search,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _notAddedSongs.isEmpty
                ? const Center(child: Text("No hay más canciones para añadir"))
                : ListView.builder(
                    itemCount: _notAddedSongs
                        .where(
                          (s) =>
                              s.title.toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              ) ||
                              (s.artist ?? "").toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              ),
                        )
                        .length,
                    itemBuilder: (context, index) {
                      final filteredSongs = _notAddedSongs
                          .where(
                            (s) =>
                                s.title.toLowerCase().contains(
                                  _searchQuery.toLowerCase(),
                                ) ||
                                (s.artist ?? "").toLowerCase().contains(
                                  _searchQuery.toLowerCase(),
                                ),
                          )
                          .toList();
                      final song = filteredSongs[index];
                      final isSelected = _selectedToAdd.contains(song);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: const Color(0xFF4CAF50),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedToAdd.add(song);
                            } else {
                              _selectedToAdd.remove(song);
                            }
                          });
                        },
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(song.artist ?? "Desconocido"),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: QueryArtworkWidget(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              format: ArtworkFormat.JPEG,
                              size: 2000,
                              artworkWidth: 50,
                              artworkHeight: 50,
                              artworkBorder: BorderRadius.zero,
                              artworkFit: BoxFit.cover,
                              nullArtworkWidget:
                                  AppHelpers.getRandomDefaultCover(
                                    context: context,
                                    id: song.id,
                                    width: 50,
                                    height: 50,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FullPlayerScreen extends StatefulWidget {
  final AudioHandler audioHandler;
  final Set<int> favoriteIds;
  final Function(int) onToggleFavorite;

  const _FullPlayerScreen({
    required this.audioHandler,
    required this.favoriteIds,
    required this.onToggleFavorite,
  });

  @override
  State<_FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<_FullPlayerScreen> {
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

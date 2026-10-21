import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/playlist_model.dart';
import '../services/appearance_settings.dart';
import '../services/audio_handler.dart';
import '../services/audio_service_instance.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';
import 'create_playlist_screen.dart';
import 'add_songs_screen.dart';
import 'full_player_screen.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/cached_artwork.dart';
import '../widgets/lumina_mini_player.dart';


/// Widget que mantiene el estado de cada pestaña mientras proporciona
/// una transición de desvanecimiento suave y fluida al cambiar de pestaña.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}

/// Página principal de la app. Contiene la biblioteca, favoritos,
/// listas de reproducción y ajustes.
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
            color: Colors.black,
          ),
        ),
        duration: Duration(seconds: 3),
        backgroundColor: Color.fromARGB(255, 255, 255, 255),
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

    await audioHandler.addQueueItems(mediaItems);
    await audioHandler.skipToQueueItem(index != -1 ? index : 0);
    audioHandler.play();
  }

  void _playPlaylist(
    List<SongModel> playlistSongs, {
    bool shuffle = false,
  }) async {
    if (playlistSongs.isEmpty) return;
    if (shuffle) {
      await audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    } else {
      await audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
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
              stream: audioHandler.mediaItem,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LuminaMiniPlayer(
                      item: snapshot.data!,
                      audioHandler: audioHandler,
                      onTap: _showFullPlayer,
                    ),
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
    return FadeIndexedStack(
      index: _selectedIndex,
      children: [
        _buildLibraryContent(),
        _buildFavoritesContent(),
        _buildPlaylistsTabContent(),
        _buildSettingsContent(),
      ],
    );
  }

  Widget _buildPlaylistsTabContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.08, 0.0),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _selectedPlaylist != null
          ? KeyedSubtree(
              key: ValueKey('playlist_${_selectedPlaylist!.id}'),
              child: _buildPlaylistDetailView(_selectedPlaylist!),
            )
          : KeyedSubtree(
              key: const ValueKey('playlists_list'),
              child: _buildPlaylistsContent(),
            ),
    );
  }

  Widget _buildLibraryContent() {
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
                        key: const PageStorageKey('library_empty'),
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
                    : StreamBuilder<MediaItem?>(
                        stream: audioHandler.mediaItem,
                        builder: (context, mediaSnapshot) {
                          final playingId = mediaSnapshot.data?.id;
                          return ListView.builder(
                            key: const PageStorageKey('library_list'),
                            itemExtent: 82.0,
                            cacheExtent: 250,
                            padding: const EdgeInsets.only(
                              left: 20,
                              right: 20,
                              bottom: 95,
                            ),
                            itemCount: displaySongs.length,
                            itemBuilder: (context, index) {
                              final song = displaySongs[index];
                              return _buildMusicCard(
                                song,
                                isSelected: playingId == '${song.id}',
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _buildBackgroundDecoration() {
    return BoxDecoration(
      color: LuminaColors.of(context).background,
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
                  : StreamBuilder<MediaItem?>(
                      stream: audioHandler.mediaItem,
                      builder: (context, mediaSnapshot) {
                        final playingId = mediaSnapshot.data?.id;
                        return ListView.builder(
                          key: const PageStorageKey('favorites_list'),
                          itemExtent: 82.0,
                          cacheExtent: 250,
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 95,
                          ),
                          itemCount: favorites.length,
                          itemBuilder: (context, index) {
                            final song = favorites[index];
                            return _buildMusicCard(
                              song,
                              isSelected: playingId == '${song.id}',
                            );
                          },
                        );
                      },
                    ),
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
                      key: const PageStorageKey('playlists_grid'),
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 95,
                      ),
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
      return CachedArtwork(
        songId: playlist.songs[0].id,
        borderRadius: 24,
        size: 250,
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
              return CachedArtwork(
                songId: playlist.songs[i].id,
                borderRadius: 10,
                size: 150,
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
      itemBuilder: (context, i) => CachedArtwork(
        songId: playlist.songs[i].id,
        borderRadius: 0,
        size: 150,
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

  Widget _buildSongListItem(
    SongModel song,
    List<SongModel> list, {
    bool isSelected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFavorite = _favoriteIds.contains(song.id);

    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            CachedArtwork(
              songId: song.id,
              width: 55,
              height: 55,
              borderRadius: 12,
              size: 150,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: InkWell(
                onTap: () => _playSong(song, fromList: list),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(height: 2),
                    Text(
                      _getSongArtist(song),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 400,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isDark
                        ? const Color(0xFF0A0A0A).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.6),
                    isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  ],
                  stops: const [0.0, 0.9],
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
              StreamBuilder<MediaItem?>(
                stream: audioHandler.mediaItem,
                builder: (context, mediaSnapshot) {
                  final playingId = mediaSnapshot.data?.id;
                  return SliverFixedExtentList(
                    itemExtent: 80.0,
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final song = playlist.songs[index];
                      return _buildSongListItem(
                        song,
                        playlist.songs,
                        isSelected: playingId == '${song.id}',
                      );
                    }, childCount: playlist.songs.length),
                  );
                },
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
        return CachedArtwork(
          songId: playlist.songs[i].id,
          width: cellSize,
          height: cellSize,
          borderRadius: 4,
          size: 100,
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
            title: const Row(
              children: [
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
                      onChanged: (value) {
                        LuminaHaptics.fire(context, HapticEvent.select);
                        widget.onThemeChanged(value);
                      },
                      activeThumbColor: LuminaColors.of(context).accent,
                    ),
                  ),
                  ValueListenableBuilder<PlayerBackgroundStyle>(
                    valueListenable: AppearanceSettings.instance.backgroundStyle,
                    builder: (context, style, _) {
                      return _buildSettingTile(
                        icon: Icons.palette_outlined,
                        title: 'Fondo del Reproductor',
                        subtitle: '${style.label} — ${style.description}',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: LuminaColors.of(context).textTertiary,
                        ),
                        onTap: () => _showBackgroundStylePicker(context),
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppearanceSettings.instance.hapticsEnabled,
                    builder: (context, enabled, _) {
                      return _buildSettingTile(
                        icon: Icons.vibration_rounded,
                        title: 'Respuesta Háptica',
                        subtitle: 'Vibración táctil en botones y controles',
                        trailing: Switch(
                          value: enabled,
                          onChanged: (val) async {
                            await AppearanceSettings.instance
                                .setHapticsEnabled(enabled: val);
                            if (val && context.mounted) {
                              LuminaHaptics.fire(context, HapticEvent.select);
                            }
                          },
                          activeThumbColor: LuminaColors.of(context).accent,
                        ),
                      );
                    },
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
              stream: audioHandler.mediaItem,
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

  void _showBackgroundStylePicker(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Fondo del Reproductor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                ...PlayerBackgroundStyle.values.map((style) {
                  final isSelected =
                      AppearanceSettings.instance.backgroundStyle.value == style;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? colors.accentSoft : colors.surface,
                      borderRadius: BorderRadius.circular(shapes.card),
                      border: Border.all(
                        color: isSelected ? colors.accent : colors.hairline,
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        style.label,
                        style: TextStyle(
                          color: isSelected ? colors.accentInk : colors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        style.description,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: colors.accent)
                          : null,
                      onTap: () async {
                        LuminaHaptics.fire(context, HapticEvent.select);
                        await AppearanceSettings.instance
                            .setBackgroundStyle(style);
                        if (context.mounted) {
                          Navigator.pop(context);
                          setState(() {});
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(shapes.card),
        border: Border.all(color: colors.hairline, width: 1),
      ),
      child: ListTile(
        leading: Icon(icon, color: colors.accent),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: colors.textPrimary,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              )
            : null,
        trailing: trailing,
        onTap: onTap != null
            ? () {
                LuminaHaptics.fire(context, HapticEvent.select);
                onTap();
              }
            : null,
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
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: CachedArtwork(
                    songId: song.id,
                    width: 40,
                    height: 40,
                    borderRadius: 8,
                    size: 150,
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
                  leading: const Icon(Icons.format_list_bulleted_rounded),
                  title: const Text('Ver fila de reproducción'),
                  onTap: () {
                    Navigator.pop(context);
                    QueueBottomSheet.show(context, audioHandler);
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
    (audioHandler as MyAudioHandler).updateSongTag(
      '${song.id}',
      _getSongTitle(song),
      _getSongArtist(song),
    );
  }

  void _clearAudioHandlerMetadata(SongModel song) {
    (audioHandler as MyAudioHandler).clearSongTagOverride('${song.id}');
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
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Color(0xFF4CAF50), size: 22),
            SizedBox(width: 8),
            Text(
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
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.4)),
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
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.4)),
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
              Navigator.pop(context);
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
              Navigator.pop(context);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lista creada y canción agregada'),
          backgroundColor: Color.fromARGB(255, 255, 255, 255),
        ),
      );
    }
  }

  Future<void> _addToQueue(SongModel song) async {
    try {
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
      await audioHandler.addQueueItem(mediaItem);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF222222)
              : const Color(0xFF333333),
          content: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: Color(0xFF4CAF50)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_getSongTitle(song)} añadida a la cola',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No se pudo añadir a la cola: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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

  Widget _buildMusicCard(SongModel song, {bool isSelected = false}) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final isFav = _favoriteIds.contains(song.id);

    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? colors.accentSoft : colors.surface,
        borderRadius: BorderRadius.circular(shapes.card),
        border: Border.all(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.35)
              : colors.hairline,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        leading: CachedArtwork(
          songId: song.id,
          width: 50,
          height: 50,
          borderRadius: shapes.artworkSmall,
          size: 150,
        ),
        title: Row(
          children: [
            if (isSelected) ...[
              Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: colors.accentInk,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                _getSongTitle(song),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? colors.accentInk : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          _getSongArtist(song),
          maxLines: 1,
          style: TextStyle(
            color: isSelected
                ? colors.accentInk.withValues(alpha: 0.8)
                : colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? colors.accent : colors.textTertiary,
                size: 20,
              ),
              onPressed: () {
                LuminaHaptics.fire(context, HapticEvent.select);
                _toggleFavorite(song.id);
              },
            ),
            IconButton(
              icon: Icon(
                Icons.more_vert_rounded,
                color: colors.textTertiary,
                size: 20,
              ),
              onPressed: () => _showSongOptions(context, song),
            ),
          ],
        ),
        onTap: () {
          LuminaHaptics.fire(context, HapticEvent.select);
          _playSong(song);
        },
      ),
    );
  }

  void _showFullPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FullPlayerScreen(
        audioHandler: audioHandler,
        favoriteIds: _favoriteIds,
        onToggleFavorite: _toggleFavorite,
      ),
    );
  }

  Widget _buildHeader({VoidCallback? onRefresh}) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(shapes.artworkSmall),
              boxShadow: [
                BoxShadow(
                  color: colors.accentGlow,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: colors.onAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Lumina',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            IconButton(
              onPressed: () {
                LuminaHaptics.fire(context, HapticEvent.select);
                onRefresh();
              },
              icon: Icon(
                Icons.refresh_rounded,
                color: colors.textSecondary,
              ),
              tooltip: 'Actualizar biblioteca',
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    final colors = LuminaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: colors.textPrimary,
            ),
          ),
          Text(
            '$count canciones',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsHeader(bool isDark) {
    final colors = LuminaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Mis Listas',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: colors.textPrimary,
            ),
          ),
          GestureDetector(
            onTap: () {
              LuminaHaptics.fire(context, HapticEvent.select);
              _openCreatePlaylist();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceHighest,
                shape: BoxShape.circle,
                border: Border.all(color: colors.hairline, width: 1),
              ),
              child: Icon(
                Icons.add_rounded,
                color: colors.accent,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceHighest,
          borderRadius: BorderRadius.circular(shapes.field),
          border: Border.all(color: colors.hairline, width: 1),
        ),
        child: TextField(
          onChanged: (value) => setState(() => _searchQuery = value),
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Buscar...',
            hintStyle: TextStyle(color: colors.textTertiary),
            border: InputBorder.none,
            icon: Icon(
              Icons.search_rounded,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final colors = LuminaColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(top: BorderSide(color: colors.hairline, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          LuminaHaptics.fire(context, HapticEvent.select);
          setState(() {
            _selectedIndex = i;
            if (i != 2) _selectedPlaylist = null;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: colors.surfaceElevated,
        selectedItemColor: colors.accentInk,
        unselectedItemColor: colors.textTertiary,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note_rounded),
            activeIcon: Icon(Icons.music_note_rounded),
            label: 'Librería',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border_rounded),
            activeIcon: Icon(Icons.favorite_rounded),
            label: 'Favoritos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play_rounded),
            activeIcon: Icon(Icons.playlist_play_rounded),
            label: 'Listas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

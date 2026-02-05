import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'dart:math';
import 'dart:ui';

void main() {
  runApp(const LuminaApp());
}

class PlaylistModelCustom {
  final String id;
  String name;
  List<SongModel> songs;

  PlaylistModelCustom({required this.id, required this.name, required this.songs});
}

class LuminaApp extends StatefulWidget {
  const LuminaApp({super.key});

  @override
  State<LuminaApp> createState() => _LuminaAppState();
}

class _LuminaAppState extends State<LuminaApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
          primary: const Color(0xFF6C63FF),
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
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1A1A1A),
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: MusicLibraryPage(
        themeMode: _themeMode,
        onThemeChanged: _toggleTheme,
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  int _selectedIndex = 0;
  final List<SongModel> _songs = [];
  final Set<int> _favoriteIds = {};
  final List<PlaylistModelCustom> _playlists = [];
  PlaylistModelCustom? _selectedPlaylist;
  List<SongModel> _currentPlaylistSongs = [];
  bool _isLoading = true;
  String _searchQuery = "";
  String _playlistSearchQuery = "";
  
  SongModel? _currentSong;
  bool _isPlaying = false;
  bool _isShuffle = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
        if (state.processingState == ProcessingState.completed) {
          _playNext();
        }
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.audio,
    ].request();

    if (statuses[Permission.audio]!.isGranted || statuses[Permission.storage]!.isGranted) {
      _loadSongs();
    } else {
      setState(() => _isLoading = false);
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
        content: Text('Buscando nuevas canciones...'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF6C63FF),
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
    return _playlists.where((p) => p.name.toLowerCase().contains(_playlistSearchQuery.toLowerCase())).toList();
  }

  void _toggleFavorite(int songId) {
    setState(() {
      if (_favoriteIds.contains(songId)) {
        _favoriteIds.remove(songId);
      } else {
        _favoriteIds.add(songId);
      }
    });
  }

  Future<void> _playSong(SongModel song, {List<SongModel>? fromList}) async {
    setState(() {
      _currentSong = song;
      if (fromList != null) {
        _currentPlaylistSongs = fromList;
      } else {
        _currentPlaylistSongs = [];
      }
    });
    
    try {
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.data)));
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Error al reproducir: $e");
    }
  }

  void _playPlaylist(List<SongModel> playlistSongs, {bool shuffle = false}) async {
    if (playlistSongs.isEmpty) return;
    
    List<SongModel> playList = List.from(playlistSongs);
    if (shuffle) {
      playList.shuffle();
    }
    
    setState(() {
      _isShuffle = shuffle;
      _currentPlaylistSongs = playlistSongs;
    });
    
    _playSong(playList[0], fromList: playlistSongs);
  }

  void _playNext() {
    final list = _currentPlaylistSongs.isNotEmpty 
        ? _currentPlaylistSongs 
        : (_filteredSongs.isNotEmpty ? _filteredSongs : _songs);
    if (list.isEmpty) return;
    int nextIndex;
    if (_isShuffle) {
      nextIndex = Random().nextInt(list.length);
    } else {
      int currentIndex = list.indexWhere((s) => s.id == _currentSong?.id);
      nextIndex = (currentIndex + 1) % list.length;
    }
    _playSong(list[nextIndex], fromList: _currentPlaylistSongs.isNotEmpty ? _currentPlaylistSongs : null);
  }

  void _playPrevious() {
    final list = _currentPlaylistSongs.isNotEmpty 
        ? _currentPlaylistSongs 
        : (_filteredSongs.isNotEmpty ? _filteredSongs : _songs);
    if (list.isEmpty) return;
    int currentIndex = list.indexWhere((s) => s.id == _currentSong?.id);
    int prevIndex = (currentIndex - 1 < 0) ? list.length - 1 : currentIndex - 1;
    _playSong(list[prevIndex], fromList: _currentPlaylistSongs.isNotEmpty ? _currentPlaylistSongs : null);
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
            if (_currentSong != null)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildMiniPlayer()),
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
                color: const Color(0xFF6C63FF),
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : displaySongs.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.search_off_rounded, size: 60, color: Colors.grey[800]),
                                    const SizedBox(height: 10),
                                    Text(_searchQuery.isEmpty ? "No se encontró música" : "Sin resultados", style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: displaySongs.length,
                            itemBuilder: (context, index) => _buildMusicCard(displaySongs[index]),
                          ),
              ),
            ),
            if (_currentSong != null) const SizedBox(height: 85),
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
            ? [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A), const Color(0xFF0A0A0A)]
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
                          Icon(Icons.favorite_border_rounded, size: 60, color: Colors.grey[800]),
                          const SizedBox(height: 10),
                          Text(
                            _searchQuery.isEmpty ? "Aún no tienes favoritos" : "Sin resultados en favoritos", 
                            style: TextStyle(color: Colors.grey[600])
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: favorites.length,
                      itemBuilder: (context, index) => _buildMusicCard(favorites[index]),
                    ),
            ),
            if (_currentSong != null) const SizedBox(height: 85),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredPlaylists = _filteredPlaylists;

    return Container(
      decoration: _buildBackgroundDecoration(),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildPlaylistSearchBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Mis Listas', 
                    style: TextStyle(
                      fontSize: 22, 
                      fontWeight: FontWeight.bold, 
                      color: colorScheme.onSurface
                    )
                  ),
                  GestureDetector(
                    onTap: () => _openCreatePlaylist(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Color(0xFF6C63FF), size: 24),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _playlists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 60, color: Colors.grey[800]),
                          const SizedBox(height: 10),
                          Text("Crea tu primera lista", style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 25,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: filteredPlaylists.length,
                      itemBuilder: (context, index) => _buildPlaylistGridCard(filteredPlaylists[index]),
                    ),
            ),
            if (_currentSong != null) const SizedBox(height: 85),
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
          borderRadius: BorderRadius.circular(25)
        ),
        child: TextField(
          onChanged: (value) => setState(() => _playlistSearchQuery = value),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Buscar en mis listas...', 
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
            border: InputBorder.none, 
            icon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3))
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
                  title: const Text('Eliminar', style: TextStyle(color: Colors.red)),
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

    if (playlist.songs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[200],
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.music_note_rounded, size: 50, color: colorScheme.primary.withValues(alpha: 0.5)),
      );
    }

    if (playlist.songs.length == 1 || playlist.name.toLowerCase().contains("favoritos")) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: QueryArtworkWidget(
          id: playlist.songs[0].id,
          type: ArtworkType.AUDIO,
          size: 500,
          artworkFit: BoxFit.cover,
          nullArtworkWidget: Container(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[200],
            child: Icon(Icons.music_note_rounded, size: 50, color: colorScheme.primary.withValues(alpha: 0.5)),
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
                    artworkFit: BoxFit.cover,
                    nullArtworkWidget: Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white24)),
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
    if (playlist.songs.isEmpty) return Container(color: Colors.grey[900]);
    
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
      itemCount: min(playlist.songs.length, 4),
      itemBuilder: (context, i) => QueryArtworkWidget(
        id: playlist.songs[i].id,
        type: ArtworkType.AUDIO,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: Container(color: Colors.grey[900]),
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap, double size = 50, bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary ? const Color(0xFF6C63FF) : Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }

  Widget _buildSongListItem(SongModel song, List<SongModel> list) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFavorite = _favoriteIds.contains(song.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              nullArtworkWidget: Container(
                width: 55, height: 55, color: Colors.white12,
                child: const Icon(Icons.music_note, color: Colors.white30),
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
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(song.artist ?? "Desconocido", style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? const Color(0xFF4CAF50) : colorScheme.onSurface.withValues(alpha: 0.5)),
            onPressed: () => _toggleFavorite(song.id),
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface.withValues(alpha: 0.5)),
            onPressed: () {
            },
          ),
        ],
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
            child: Opacity(
              opacity: 0.7, 
              child: _buildHeaderCollage(playlist),
            ),
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
                    isDark ? const Color(0xFF0A0A0A).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4),
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
                    padding: const EdgeInsets.only(right: 15, top: 8, bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.edit_rounded),
                                    title: const Text('Renombrar lista'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _renamePlaylist(playlist);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.delete_rounded, color: Colors.red),
                                    title: const Text('Eliminar lista', style: TextStyle(color: Colors.red)),
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
                            onTap: () => _openAddSongsToPlaylist(playlist),
                            size: 45,
                          ),
                          const SizedBox(width: 15),
                          _buildCircleButton(
                            icon: Icons.shuffle_rounded,
                            onTap: () => _playPlaylist(playlist.songs, shuffle: true),
                            size: 55,
                          ),
                          const SizedBox(width: 15),
                          _buildCircleButton(
                            icon: Icons.play_arrow_rounded,
                            onTap: () => _playPlaylist(playlist.songs, shuffle: false),
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = playlist.songs[index];
                    return _buildSongListItem(song, playlist.songs);
                  },
                  childCount: playlist.songs.length,
                ),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  playlist.name = controller.text;
                });
                Navigator.pop(context);
              }
            },
            child: const Text('GUARDAR'),
          ),
        ],
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
    }
  }

  void _openCreatePlaylist() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreatePlaylistScreen(availableSongs: _songs)),
    );

    if (result != null && result is PlaylistModelCustom) {
      setState(() {
        _playlists.add(result);
      });
    }
  }

  void _openEditPlaylist(PlaylistModelCustom playlist) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreatePlaylistScreen(availableSongs: _songs, initialPlaylist: playlist)),
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
    }
  }

  void _deletePlaylist(PlaylistModelCustom playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text('¿Seguro que quieres eliminar "${playlist.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () {
              setState(() {
                _playlists.removeWhere((p) => p.id == playlist.id);
                if (_selectedPlaylist?.id == playlist.id) {
                  _selectedPlaylist = null;
                }
              });
              Navigator.pop(context); 
            }, 
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red))
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
                  Text('Ajustes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
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
                      value: widget.themeMode == ThemeMode.dark,
                      onChanged: (value) => widget.onThemeChanged(value),
                      activeThumbColor: const Color(0xFF4CAF50),
                    ),
                  ),
                  _buildSettingTile(
                    icon: Icons.notifications_rounded,
                    title: 'Notificaciones',
                    trailing: Switch(value: true, onChanged: (v) {}, activeThumbColor: const Color(0xFF4CAF50)),
                  ),
                  _buildSettingTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Acerca de Lumina',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Lumina Player',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Icon(Icons.music_note_rounded, color: Color(0xFF6C63FF)),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Aplicación Creada por ',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    TextSpan(
                      text: 'Alvaro Jesus',
                      style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            if (_currentSong != null) const SizedBox(height: 85),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({required IconData icon, required String title, Widget? trailing, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6C63FF)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  Widget _buildMusicCard(SongModel song) {
    bool isSelected = _currentSong?.id == song.id;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF6C63FF).withValues(alpha: 0.1) : colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: SizedBox(
          width: 50,
          height: 50,
          child: ClipOval(
            child: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkWidth: 50,
              artworkHeight: 50,
              artworkFit: BoxFit.cover,
              nullArtworkWidget: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.music_note, color: Color(0xFF6C63FF), size: 28),
              ),
            ),
          ),
        ),
        title: Text(
          song.title, 
          maxLines: 1, 
          overflow: TextOverflow.ellipsis, 
          style: TextStyle(
            color: isSelected ? const Color(0xFF6C63FF) : colorScheme.onSurface, 
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
          )
        ),
        subtitle: Text(
          song.artist ?? "Desconocido", 
          maxLines: 1, 
          style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)
        ),
        trailing: _favoriteIds.contains(song.id) 
            ? const Icon(Icons.favorite, color: Color(0xFF4CAF50), size: 20)
            : null,
        onTap: () => _playSong(song),
      ),
    );
  }

  Widget _buildMiniPlayer() {
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
              offset: const Offset(0, 5)
            )
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: QueryArtworkWidget(
                id: _currentSong!.id, 
                type: ArtworkType.AUDIO, 
                size: 300, 
                artworkFit: BoxFit.cover,
                nullArtworkWidget: const Icon(Icons.music_note)
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_currentSong!.title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_currentSong!.artist ?? "Desconocido", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
            IconButton(icon: Icon(Icons.skip_next_rounded, color: Theme.of(context).colorScheme.onSurface), onPressed: _playNext),
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 40, color: const Color(0xFF4CAF50)),
              onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return _FullPlayerScreen(
            song: _currentSong!,
            player: _audioPlayer,
            isShuffle: _isShuffle,
            isFavorite: _favoriteIds.contains(_currentSong!.id),
            onNext: () { _playNext(); setModalState(() {}); },
            onPrevious: () { _playPrevious(); setModalState(() {}); },
            onShuffle: () { setState(() => _isShuffle = !_isShuffle); setModalState(() {}); },
            onToggleFavorite: () { _toggleFavorite(_currentSong!.id); setModalState(() {}); },
          );
        }
      ),
    );
  }

  Widget _buildHeader({VoidCallback? onRefresh}) => Padding(
    padding: const EdgeInsets.all(20.0),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 24),
      ),
      const SizedBox(width: 12),
      Text('Lumina', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
      const Spacer(),
      if (onRefresh != null)
        IconButton(
          onPressed: onRefresh,
          icon: Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          tooltip: 'Actualizar biblioteca',
        ),
    ]),
  );

  Widget _buildSectionTitle(String title, int count) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        Text('$count canciones', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
      ],
    ),
  );

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, 
        borderRadius: BorderRadius.circular(20)
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Buscar...', 
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          border: InputBorder.none, 
          icon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))
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
    backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0A0A0A) : Colors.white,
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

  const CreatePlaylistScreen({super.key, required this.availableSongs, this.initialPlaylist});

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}

class _CreatePlaylistScreenState extends State<CreatePlaylistScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<SongModel> _selectedSongs = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPlaylist != null) {
      _nameController.text = widget.initialPlaylist!.name;
      _selectedSongs.addAll(widget.initialPlaylist!.songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.initialPlaylist == null ? 'Nueva Lista' : 'Editar Lista', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              if (_nameController.text.isNotEmpty) {
                Navigator.pop(context, PlaylistModelCustom(
                  id: widget.initialPlaylist?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _nameController.text,
                  songs: List.from(_selectedSongs),
                ));
              }
            },
            child: const Text('GUARDAR', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]
                  ),
                  child: _selectedSongs.isEmpty
                      ? const Icon(Icons.image_search_rounded, size: 40, color: Colors.grey)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
                            itemCount: min(_selectedSongs.length, 4),
                            itemBuilder: (context, i) => QueryArtworkWidget(
                              id: _selectedSongs[i].id,
                              type: ArtworkType.AUDIO,
                              artworkFit: BoxFit.cover,
                              nullArtworkWidget: Container(color: Colors.grey[900]),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: widget.initialPlaylist == null,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Nombre de la lista',
                      hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.3)),
                      border: UnderlineInputBorder(borderSide: BorderSide(color: colorScheme.primary)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text('Seleccionar canciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                const Spacer(),
                Text('${_selectedSongs.length} seleccionadas', style: const TextStyle(color: Color(0xFF4CAF50))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: widget.availableSongs.length,
              itemBuilder: (context, index) {
                final song = widget.availableSongs[index];
                final isSelected = _selectedSongs.any((s) => s.id == song.id);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: const Color(0xFF4CAF50),
                  checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colorScheme.onSurface)),
                  subtitle: Text(song.artist ?? "Desconocido", style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.5))),
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: QueryArtworkWidget(id: song.id, type: ArtworkType.AUDIO, artworkFit: BoxFit.cover, nullArtworkWidget: const Icon(Icons.music_note)),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) { _selectedSongs.add(song); } else { _selectedSongs.removeWhere((s) => s.id == song.id); }
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

  const AddSongsScreen({super.key, required this.allSongs, required this.currentPlaylistSongs});

  @override
  State<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<AddSongsScreen> {
  final List<SongModel> _selectedToAdd = [];
  late List<SongModel> _notAddedSongs;

  @override
  void initState() {
    super.initState();
    final currentIds = widget.currentPlaylistSongs.map((s) => s.id).toSet();
    _notAddedSongs = widget.allSongs.where((s) => !currentIds.contains(s.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Añadir canciones', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selectedToAdd),
            child: const Text('LISTO', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: _notAddedSongs.isEmpty
          ? const Center(child: Text("No hay más canciones para añadir"))
          : ListView.builder(
              itemCount: _notAddedSongs.length,
              itemBuilder: (context, index) {
                final song = _notAddedSongs[index];
                final isSelected = _selectedToAdd.contains(song);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: const Color(0xFF4CAF50),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) { _selectedToAdd.add(song); } else { _selectedToAdd.remove(song); }
                    });
                  },
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist ?? "Desconocido"),
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QueryArtworkWidget(id: song.id, type: ArtworkType.AUDIO, artworkFit: BoxFit.cover, nullArtworkWidget: const Icon(Icons.music_note)),
                  ),
                );
              },
            ),
    );
  }
}

class _FullPlayerScreen extends StatelessWidget {
  final SongModel song;
  final AudioPlayer player;
  final bool isShuffle;
  final bool isFavorite;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onShuffle;
  final VoidCallback onToggleFavorite;

  const _FullPlayerScreen({
    required this.song,
    required this.player,
    required this.isShuffle,
    required this.isFavorite,
    required this.onNext,
    required this.onPrevious,
    required this.onShuffle,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black87;

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
                  IconButton(icon: Icon(Icons.keyboard_arrow_down, size: 35, color: onSurface), onPressed: () => Navigator.pop(context)),
                  Text("REPRODUCIENDO", style: TextStyle(letterSpacing: 2, color: onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: QueryArtworkWidget(
                    id: song.id, type: ArtworkType.AUDIO, artworkWidth: MediaQuery.of(context).size.width * 0.85, artworkHeight: MediaQuery.of(context).size.width * 0.85, size: 2000, format: ArtworkFormat.PNG,
                    artworkFit: BoxFit.cover,
                    nullArtworkWidget: Container(height: MediaQuery.of(context).size.width * 0.85, width: MediaQuery.of(context).size.width * 0.85, color: onSurface.withValues(alpha: 0.1), child: const Icon(Icons.music_note, size: 100, color: Color(0xFF6C63FF))),
                  ),
                ),
              ),
              Column(
                children: [
                  Text(song.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: onSurface), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(song.artist ?? "Desconocido", style: const TextStyle(fontSize: 18, color: Color(0xFF4CAF50))),
                ],
              ),
              StreamBuilder<Duration?>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  return ProgressBar(
                    progress: snapshot.data ?? Duration.zero, total: player.duration ?? Duration.zero, progressBarColor: const Color(0xFF4CAF50), baseBarColor: onSurface.withValues(alpha: 0.1), thumbColor: onSurface, barHeight: 4, thumbRadius: 6, onSeek: (d) => player.seek(d),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: Icon(Icons.shuffle, color: isShuffle ? const Color(0xFF4CAF50) : onSurface.withValues(alpha: 0.5)), onPressed: onShuffle),
                  IconButton(icon: Icon(Icons.skip_previous_rounded, size: 45, color: onSurface), onPressed: onPrevious),
                  StreamBuilder<bool>(
                    stream: player.playingStream,
                    builder: (context, snapshot) {
                      bool playing = snapshot.data ?? false;
                      return Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1DB954)), child: IconButton(icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 45, color: Colors.white), onPressed: () => playing ? player.pause() : player.play()));
                    },
                  ),
                  IconButton(icon: Icon(Icons.skip_next_rounded, size: 45, color: onSurface), onPressed: onNext),
                  IconButton(icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? const Color(0xFF4CAF50) : onSurface), onPressed: onToggleFavorite),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'dart:math';

void main() {
  runApp(const LuminaApp());
}

class LuminaApp extends StatelessWidget {
  const LuminaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
      home: const MusicLibraryPage(),
    );
  }
}

class MusicLibraryPage extends StatefulWidget {
  const MusicLibraryPage({super.key});

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  int _selectedIndex = 0;
  List<SongModel> _songs = [];
  bool _isLoading = true;
  
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
      setState(() {
        _songs = songs.where((song) => song.isMusic == true).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playSong(SongModel song) async {
    // Sincronización inmediata: Cambiamos la info antes de cargar el audio
    setState(() {
      _currentSong = song;
    });
    
    try {
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.data)));
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Error al reproducir: $e");
    }
  }

  void _playNext() {
    if (_songs.isEmpty) return;
    int nextIndex;
    if (_isShuffle) {
      nextIndex = Random().nextInt(_songs.length);
    } else {
      int currentIndex = _songs.indexWhere((s) => s.id == _currentSong?.id);
      nextIndex = (currentIndex + 1) % _songs.length;
    }
    _playSong(_songs[nextIndex]);
  }

  void _playPrevious() {
    if (_songs.isEmpty) return;
    int currentIndex = _songs.indexWhere((s) => s.id == _currentSong?.id);
    int prevIndex = (currentIndex - 1 < 0) ? _songs.length - 1 : currentIndex - 1;
    _playSong(_songs[prevIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMainContent(),
          if (_currentSong != null)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildMiniPlayer()),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildMainContent() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSectionTitle(),
            _buildSearchBar(),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _songs.isEmpty
                      ? const Center(child: Text("No se encontró música"))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _songs.length,
                          itemBuilder: (context, index) => _buildMusicCard(_songs[index]),
                        ),
            ),
            if (_currentSong != null) const SizedBox(height: 85),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicCard(SongModel song) {
    bool isSelected = _currentSong?.id == song.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.1) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: QueryArtworkWidget(
          id: song.id, type: ArtworkType.AUDIO,
          nullArtworkWidget: const Icon(Icons.music_note, color: Color(0xFF6C63FF)),
        ),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isSelected ? const Color(0xFF6C63FF) : Colors.white)),
        subtitle: Text(song.artist ?? "Desconocido", maxLines: 1),
        onTap: () => _playSong(song),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return GestureDetector(
      onTap: () => _showFullPlayer(),
      child: Container(
        height: 75,
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: QueryArtworkWidget(
                id: _currentSong!.id, 
                type: ArtworkType.AUDIO, 
                size: 300, // Calidad mejorada también en el mini player
                nullArtworkWidget: const Icon(Icons.music_note)
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_currentSong!.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_currentSong!.artist ?? "Desconocido", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: _playNext),
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
            onNext: () {
              _playNext();
              setModalState(() {});
            },
            onPrevious: () {
              _playPrevious();
              setModalState(() {});
            },
            onShuffle: () {
              setState(() => _isShuffle = !_isShuffle);
              setModalState(() {});
            },
          );
        }
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.all(20.0),
    child: Row(children: [
      const Icon(Icons.music_note_rounded, color: Color(0xFF6C63FF), size: 30),
      const SizedBox(width: 10),
      const Text('Lumina', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildSectionTitle() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 20),
    child: Text('Tu Biblioteca', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
  );

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
      child: const TextField(decoration: InputDecoration(hintText: 'Buscar...', border: InputBorder.none, icon: Icon(Icons.search, color: Colors.grey))),
    ),
  );

  Widget _buildBottomNavBar() => BottomNavigationBar(
    currentIndex: _selectedIndex,
    onTap: (i) => setState(() => _selectedIndex = i),
    type: BottomNavigationBarType.fixed,
    backgroundColor: const Color(0xFF0A0A0A),
    selectedItemColor: const Color(0xFF4CAF50),
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Librería'),
      BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favoritos'),
      BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Listas'),
      BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
    ],
  );
}

class _FullPlayerScreen extends StatelessWidget {
  final SongModel song;
  final AudioPlayer player;
  final bool isShuffle;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onShuffle;

  const _FullPlayerScreen({
    required this.song,
    required this.player,
    required this.isShuffle,
    required this.onNext,
    required this.onPrevious,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 35), onPressed: () => Navigator.pop(context)),
                  const Text("REPRODUCIENDO", style: TextStyle(letterSpacing: 2, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              
              // Portada en MÁXIMA CALIDAD (size: 2000)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    artworkWidth: MediaQuery.of(context).size.width * 0.85,
                    artworkHeight: MediaQuery.of(context).size.width * 0.85,
                    size: 2000, // <--- Subida máxima de calidad del buffer
                    format: ArtworkFormat.PNG,
                    nullArtworkWidget: Container(
                      height: MediaQuery.of(context).size.width * 0.85,
                      width: MediaQuery.of(context).size.width * 0.85,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note, size: 100, color: Color(0xFF6C63FF)),
                    ),
                  ),
                ),
              ),
              
              Column(
                children: [
                  Text(song.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(song.artist ?? "Desconocido", style: const TextStyle(fontSize: 18, color: Color(0xFF4CAF50))),
                ],
              ),
              
              StreamBuilder<Duration?>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  return ProgressBar(
                    progress: snapshot.data ?? Duration.zero,
                    total: player.duration ?? Duration.zero,
                    progressBarColor: const Color(0xFF4CAF50),
                    baseBarColor: Colors.white10,
                    thumbColor: Colors.white,
                    barHeight: 4,
                    thumbRadius: 6,
                    onSeek: (d) => player.seek(d),
                  );
                },
              ),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: Icon(Icons.shuffle, color: isShuffle ? const Color(0xFF4CAF50) : Colors.grey), onPressed: onShuffle),
                  IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 45), onPressed: onPrevious),
                  StreamBuilder<bool>(
                    stream: player.playingStream,
                    builder: (context, snapshot) {
                      bool playing = snapshot.data ?? false;
                      return Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1DB954)),
                        child: IconButton(
                          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 45, color: Colors.white),
                          onPressed: () => playing ? player.pause() : player.play(),
                        ),
                      );
                    },
                  ),
                  IconButton(icon: const Icon(Icons.skip_next_rounded, size: 45), onPressed: onNext),
                  IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
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

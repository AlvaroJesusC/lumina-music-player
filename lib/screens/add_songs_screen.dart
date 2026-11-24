import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_shapes.dart';
import '../widgets/cached_artwork.dart';

/// Pantalla para añadir canciones a una lista de reproducción existente.
class AddSongsScreen extends StatefulWidget {
  final List<SongModel> allSongs;
  final List<SongModel> currentPlaylistSongs;
  final Map<int, Map<String, String>> customMetadata;

  const AddSongsScreen({
    super.key,
    required this.allSongs,
    required this.currentPlaylistSongs,
    this.customMetadata = const {},
  });

  @override
  State<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<AddSongsScreen> {
  final List<SongModel> _selectedToAdd = [];
  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _titleOf(SongModel song) =>
      widget.customMetadata[song.id]?['title'] ?? song.title;

  String _artistOf(SongModel song) =>
      widget.customMetadata[song.id]?['artist'] ?? song.artist ?? 'Desconocido';

  void _toggleSong(SongModel song, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedIds.add(song.id)) {
          _selectedToAdd.add(song);
        }
      } else {
        _selectedIds.remove(song.id);
        _selectedToAdd.removeWhere((s) => s.id == song.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    return Scaffold(
      backgroundColor: colors.background,
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
            child: Text(
              _selectedToAdd.isEmpty
                  ? 'LISTO'
                  : 'LISTO (${_selectedToAdd.length})',
              style: TextStyle(
                color: colors.accentInk,
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
                color: colors.surfaceHighest,
                borderRadius: BorderRadius.circular(shapes.field),
                border: Border.all(color: colors.hairline),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar canción...',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  border: InputBorder.none,
                  icon: Icon(Icons.search_rounded, color: colors.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: _notAddedSongs.isEmpty
                ? Center(
                    child: Text(
                      'No hay más canciones para añadir',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final q = _searchQuery.trim().toLowerCase();
                      final filteredSongs = q.isEmpty
                          ? _notAddedSongs
                          : _notAddedSongs.where((s) {
                              return _titleOf(s).toLowerCase().contains(q) ||
                                  _artistOf(s).toLowerCase().contains(q);
                            }).toList();

                      if (filteredSongs.isEmpty) {
                        return Center(
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemExtent: 72.0,
                        cacheExtent: 250,
                        itemCount: filteredSongs.length,
                        itemBuilder: (context, index) {
                          final song = filteredSongs[index];
                          final isSelected = _selectedIds.contains(song.id);
                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: colors.accent,
                            onChanged: (val) =>
                                _toggleSong(song, val ?? false),
                            title: Text(
                              _titleOf(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            subtitle: Text(
                              _artistOf(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.textSecondary),
                            ),
                            secondary: CachedArtwork(
                              songId: song.id,
                              width: 50,
                              height: 50,
                              borderRadius: 8,
                              size: 150,
                            ),
                          );
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

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../widgets/cached_artwork.dart';

/// Pantalla para añadir canciones a una lista de reproducción existente.
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
                : Builder(
                    builder: (context) {
                      final filteredSongs = _searchQuery.isEmpty
                          ? _notAddedSongs
                          : _notAddedSongs.where((s) {
                              final q = _searchQuery.toLowerCase();
                              return s.title.toLowerCase().contains(q) ||
                                  (s.artist ?? "").toLowerCase().contains(q);
                            }).toList();

                      if (filteredSongs.isEmpty) {
                        return const Center(child: Text("Sin resultados"));
                      }

                      return ListView.builder(
                        itemExtent: 72.0,
                        cacheExtent: 250,
                        itemCount: filteredSongs.length,
                        itemBuilder: (context, index) {
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

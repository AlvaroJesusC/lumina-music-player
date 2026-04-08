import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../core/app_helpers.dart';

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

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image_picker/image_picker.dart';
import '../models/playlist_model.dart';
import '../widgets/cached_artwork.dart';

/// Pantalla para crear o editar una lista de reproducción.
class CreatePlaylistScreen extends StatefulWidget {
  final List<SongModel> availableSongs;
  final PlaylistModelCustom? initialPlaylist;
  final String? defaultName;
  final Map<int, Map<String, String>> customMetadata;

  const CreatePlaylistScreen({
    super.key,
    required this.availableSongs,
    this.initialPlaylist,
    this.defaultName,
    this.customMetadata = const {},
  });

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}

class _CreatePlaylistScreenState extends State<CreatePlaylistScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<SongModel> _selectedSongs = [];
  final Set<int> _selectedIds = {};
  String _searchQuery = '';
  String? _selectedCoverPath;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialPlaylist != null) {
      _nameController.text = widget.initialPlaylist!.name;
      _selectedSongs.addAll(widget.initialPlaylist!.songs);
      _selectedIds.addAll(widget.initialPlaylist!.songs.map((s) => s.id));
      _selectedCoverPath = widget.initialPlaylist!.coverPath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _titleOf(SongModel song) =>
      widget.customMetadata[song.id]?['title'] ?? song.title;

  String _artistOf(SongModel song) =>
      widget.customMetadata[song.id]?['artist'] ?? song.artist ?? 'Desconocido';

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
                              child:
                                  _selectedCoverPath != null &&
                                      _selectedCoverPath!.isNotEmpty
                                  ? Image.file(
                                      File(_selectedCoverPath!),
                                      fit: BoxFit.cover,
                                      width: 100,
                                      height: 100,
                                      cacheWidth: 260,
                                      cacheHeight: 260,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.image_search_rounded,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
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
                                          CachedArtwork(
                                            songId: _selectedSongs[i].id,
                                            borderRadius: 0,
                                            size: 150,
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
                controller: _searchController,
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
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
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
            child: Builder(
              builder: (context) {
                final q = _searchQuery.trim().toLowerCase();
                final filteredSongs = q.isEmpty
                    ? widget.availableSongs
                    : widget.availableSongs.where((s) {
                        return _titleOf(s).toLowerCase().contains(q) ||
                            _artistOf(s).toLowerCase().contains(q);
                      }).toList();

                if (filteredSongs.isEmpty) {
                  return const Center(child: Text("Sin resultados"));
                }

                return ListView.builder(
                  itemExtent: 72.0,
                  cacheExtent: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = filteredSongs[index];
                    final isSelected = _selectedIds.contains(song.id);
                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: const Color(0xFF4CAF50),
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      title: Text(
                        _titleOf(song),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        _artistOf(song),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      secondary: CachedArtwork(
                        songId: song.id,
                        width: 50,
                        height: 50,
                        borderRadius: 10,
                        size: 150,
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            if (_selectedIds.add(song.id)) {
                              _selectedSongs.add(song);
                            }
                          } else {
                            _selectedIds.remove(song.id);
                            _selectedSongs.removeWhere((s) => s.id == song.id);
                          }
                        });
                      },
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

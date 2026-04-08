import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image_picker/image_picker.dart';
import '../models/playlist_model.dart';
import '../core/app_helpers.dart';

/// Pantalla para crear o editar una lista de reproducción.
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

import 'package:on_audio_query/on_audio_query.dart';

/// Modelo de lista de reproducción personalizada.
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

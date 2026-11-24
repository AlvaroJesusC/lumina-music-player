import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../core/app_helpers.dart';

/// Widget de carátula ultra optimizado con caché LRU en memoria RAM
/// diferenciado por resolución `(songId, size)` y deduplicación de consultas
/// concurrentes para que múltiples instancias del mismo ID siempre reciban
/// la imagen al completarse.
class CachedArtwork extends StatefulWidget {
  final int songId;
  final double width;
  final double height;
  final double borderRadius;
  final int size;
  final int quality;
  final Widget? nullArtworkWidget;

  const CachedArtwork({
    super.key,
    required this.songId,
    this.width = 50,
    this.height = 50,
    this.borderRadius = 8,
    this.size = 150,
    this.quality = 85,
    this.nullArtworkWidget,
  });

  // Caché estático acotado tipo LRU indexado por (songId, size) para que una
  // miniatura de 60 px (fondo ambiental) nunca degrade la carátula de 500 px.
  static const int _maxCacheEntries = 180;
  static final Map<(int, int), Uint8List?> _cache = {};
  static final Map<(int, int), Future<Uint8List?>> _inFlight = {};
  static final OnAudioQuery _query = OnAudioQuery();

  /// Limpia la memoria si es necesario.
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  static void _putCache((int, int) key, Uint8List? bytes) {
    if (_cache.length >= _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    _cache[key] = bytes;
  }

  /// Obtiene o comparte una consulta en curso para `(id, size)`.
  static Future<Uint8List?> _fetchArtwork(int id, int size, int quality) {
    final key = (id, size);
    return _inFlight.putIfAbsent(key, () {
      return _query
          .queryArtwork(
            id,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: size,
            quality: quality,
          )
          .then<Uint8List?>((bytes) {
            _putCache(key, bytes);
            _inFlight.remove(key);
            return bytes;
          })
          .catchError((Object _) {
            _putCache(key, null);
            _inFlight.remove(key);
            return null;
          });
    });
  }

  @override
  State<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<CachedArtwork> {
  Uint8List? _artBytes;

  @override
  void initState() {
    super.initState();
    _loadArt();
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId || oldWidget.size != widget.size) {
      _loadArt();
    }
  }

  void _loadArt() {
    final id = widget.songId;
    final size = widget.size;
    final key = (id, size);

    // Retorno sincrónico instantáneo (0 ms) si ya está en caché con esa resolución.
    if (CachedArtwork._cache.containsKey(key)) {
      final cached = CachedArtwork._cache.remove(key);
      CachedArtwork._cache[key] = cached;
      _artBytes = cached;
      return;
    }

    _artBytes = null;

    // Todos los widgets que pidan (id, size) simultáneamente se suscriben al
    // mismo Future en curso, evitando carátulas atascadas en el ícono genérico.
    CachedArtwork._fetchArtwork(id, size, widget.quality).then((bytes) {
      if (mounted && widget.songId == id && widget.size == size) {
        setState(() {
          _artBytes = bytes;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.nullArtworkWidget ??
        AppHelpers.getDefaultCover(
          context: context,
          id: widget.songId,
          width: widget.width,
          height: widget.height,
        );

    Widget content;
    if (_artBytes != null && _artBytes!.isNotEmpty) {
      // Aspect getter estrecho para evitar rebuilds globales de MediaQuery.
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final targetWidth = (widget.width * dpr).round().clamp(30, 800);
      final targetHeight = (widget.height * dpr).round().clamp(30, 800);

      content = Image.memory(
        _artBytes!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: targetWidth,
        cacheHeight: targetHeight,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      content = fallback;
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: content,
        ),
      ),
    );
  }
}

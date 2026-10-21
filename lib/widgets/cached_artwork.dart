import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../core/app_helpers.dart';

/// Widget de carátula ultra optimizado con caché en memoria RAM.
/// Elimina los tirones y lag al desplazarse en listas de reproducción grandes.
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

  // Caché estático acotado tipo LRU en memoria (ID -> bytes)
  static const int _maxCacheEntries = 120;
  static final Map<int, Uint8List?> _cache = {};
  static final Set<int> _pending = {};
  static final OnAudioQuery _query = OnAudioQuery();

  /// Limpia la memoria si es necesario
  static void clearCache() {
    _cache.clear();
    _pending.clear();
  }

  static void _putCache(int id, Uint8List? bytes) {
    if (_cache.length >= _maxCacheEntries) {
      // Desalojo de la entrada más antigua (LRU)
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    _cache[id] = bytes;
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
    if (oldWidget.songId != widget.songId) {
      _loadArt();
    }
  }

  void _loadArt() {
    final id = widget.songId;

    // Si ya está en memoria, retorno sincrónico instantáneo (0ms) y refresco LRU
    if (CachedArtwork._cache.containsKey(id)) {
      final cached = CachedArtwork._cache.remove(id);
      CachedArtwork._cache[id] = cached;
      _artBytes = cached;
      return;
    }

    _artBytes = null;

    if (!CachedArtwork._pending.contains(id)) {
      CachedArtwork._pending.add(id);

      CachedArtwork._query
          .queryArtwork(
            id,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: widget.size,
            quality: widget.quality,
          )
          .then((bytes) {
            CachedArtwork._putCache(id, bytes);
            CachedArtwork._pending.remove(id);
            if (mounted && widget.songId == id) {
              setState(() {
                _artBytes = bytes;
              });
            }
          })
          .catchError((_) {
            CachedArtwork._putCache(id, null);
            CachedArtwork._pending.remove(id);
          });
    }
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
      // Aspect getter estrecho para evitar rebuilds globales de MediaQuery
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

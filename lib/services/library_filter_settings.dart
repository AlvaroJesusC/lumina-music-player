import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Filtro de duración mínima para excluir notas de voz, tonos y clips cortos.
enum MinDurationFilter {
  /// Sin filtro de duración.
  off(0, 'Desactivado', 'Mostrar todos los audios sin importar su duración'),

  /// Oculta audios de menos de 15 segundos.
  sec15(15, '15 segundos', 'Ocultar efectos de sonido y clips muy cortos'),

  /// Oculta audios de menos de 30 segundos (recomendado).
  sec30(30, '30 segundos', 'Recomendado — filtra notas de voz y tonos'),

  /// Oculta audios de menos de 60 segundos.
  sec60(60, '60 segundos', 'Solo canciones completas (1 minuto o más)');

  const MinDurationFilter(this.seconds, this.label, this.description);

  /// Duración mínima en segundos.
  final int seconds;

  /// Etiqueta visible en Ajustes.
  final String label;

  /// Descripción explicativa para el selector.
  final String description;

  /// Duración mínima en milisegundos para comparar con `SongModel.duration`.
  int get milliseconds => seconds * 1000;

  /// Convierte el nombre persistido; cae en [sec30] por defecto.
  static MinDurationFilter parse(String? raw) =>
      MinDurationFilter.values.firstWhere(
        (f) => f.name == raw,
        orElse: () => MinDurationFilter.sec30,
      );
}

/// Criterio de ordenamiento de las canciones en la biblioteca.
enum SongSortOption {
  /// Orden alfabético A → Z por título.
  titleAsc(
    'Nombre (A - Z)',
    'Orden alfabético ascendente',
    Icons.sort_by_alpha_rounded,
  ),

  /// Orden alfabético Z → A por título.
  titleDesc(
    'Nombre (Z - A)',
    'Orden alfabético descendente',
    Icons.sort_by_alpha_rounded,
  ),

  /// Orden alfabético A → Z por artista.
  artistAsc(
    'Artista (A - Z)',
    'Agrupado alfabéticamente por artista',
    Icons.person_outline_rounded,
  ),

  /// Canciones añadidas o descargadas más recientemente primero.
  dateAddedDesc(
    'Fecha de añadido (Recientes)',
    'Las últimas canciones descargadas primero',
    Icons.new_releases_outlined,
  ),

  /// Canciones más antiguas primero.
  dateAddedAsc(
    'Fecha de añadido (Antiguas)',
    'Las primeras canciones del dispositivo primero',
    Icons.history_rounded,
  );

  const SongSortOption(this.label, this.description, this.icon);

  /// Nombre visible en el menú de ordenamiento.
  final String label;

  /// Subtítulo descriptivo en el selector.
  final String description;

  /// Icono representativo de la opción.
  final IconData icon;

  /// Etiqueta corta para el botón de la barra de herramientas.
  String get shortLabel => switch (this) {
        SongSortOption.titleAsc => 'A - Z',
        SongSortOption.titleDesc => 'Z - A',
        SongSortOption.artistAsc => 'Artista',
        SongSortOption.dateAddedDesc => 'Recientes',
        SongSortOption.dateAddedAsc => 'Antiguas',
      };

  /// Convierte el valor guardado; cae en [titleAsc] por defecto.
  static SongSortOption parse(String? raw) =>
      SongSortOption.values.firstWhere(
        (o) => o.name == raw,
        orElse: () => SongSortOption.titleAsc,
      );
}

/// Filtro rápido de canciones añadidas recientemente.
enum RecentAddedFilter {
  /// Todas las canciones de la biblioteca.
  all(null, 'Todas'),

  /// Canciones añadidas en los últimos 7 días.
  last7Days(7, 'Últimos 7 días'),

  /// Canciones añadidas en los últimos 30 días.
  last30Days(30, 'Últimos 30 días');

  const RecentAddedFilter(this.days, this.label);

  /// Ventana de días hacia atrás, o `null` para mostrar todas.
  final int? days;

  /// Etiqueta del chip de filtro.
  final String label;
}

/// Servicio singleton que persiste y evalúa los filtros de biblioteca
/// (duración mínima, lista negra de carpetas y ordenamiento).
final class LibraryFilterSettings {
  LibraryFilterSettings._();

  /// Instancia única de la app.
  static final LibraryFilterSettings instance = LibraryFilterSettings._();

  static const String _kMinDuration = 'library_min_duration_filter';
  static const String _kSortOption = 'library_sort_option';
  static const String _kBlacklistedFolders = 'library_blacklisted_folders';

  /// Patrones de carpetas excluidas por defecto (WhatsApp, tonos, grabaciones).
  static const List<String> defaultBlacklistedPatterns = [
    '/whatsapp/media/whatsapp audio',
    '/whatsapp/media/whatsapp voice notes',
    '/android/media/com.whatsapp/whatsapp/media',
    '/telegram/telegram audio',
    '/ringtones',
    '/notifications',
    '/alarms',
    '/recordings',
    '/soundrecorder',
  ];

  /// Filtro activo de duración mínima.
  final ValueNotifier<MinDurationFilter> minDuration =
      ValueNotifier(MinDurationFilter.sec30);

  /// Ordenamiento activo de la biblioteca.
  final ValueNotifier<SongSortOption> sortOption =
      ValueNotifier(SongSortOption.titleAsc);

  /// Conjunto de rutas o patrones de carpetas en lista negra (en minúsculas).
  final ValueNotifier<Set<String>> blacklistedFolders =
      ValueNotifier(Set<String>.from(defaultBlacklistedPatterns));

  /// Carga las preferencias guardadas desde `SharedPreferences`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      minDuration.value =
          MinDurationFilter.parse(prefs.getString(_kMinDuration));
      sortOption.value = SongSortOption.parse(prefs.getString(_kSortOption));

      final savedFolders = prefs.getStringList(_kBlacklistedFolders);
      if (savedFolders != null) {
        blacklistedFolders.value =
            savedFolders.map(normalizePath).where((e) => e.isNotEmpty).toSet();
      } else {
        blacklistedFolders.value =
            Set<String>.from(defaultBlacklistedPatterns);
      }
    } on Exception catch (e, st) {
      debugPrint('LibraryFilterSettings.load falló: $e\n$st');
    }
  }

  /// Actualiza y persiste el filtro de duración mínima.
  Future<void> setMinDuration(MinDurationFilter filter) async {
    minDuration.value = filter;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMinDuration, filter.name);
    } on Exception catch (e, st) {
      debugPrint('LibraryFilterSettings.setMinDuration falló: $e\n$st');
    }
  }

  /// Actualiza y persiste el criterio de ordenamiento.
  Future<void> setSortOption(SongSortOption option) async {
    sortOption.value = option;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSortOption, option.name);
    } on Exception catch (e, st) {
      debugPrint('LibraryFilterSettings.setSortOption falló: $e\n$st');
    }
  }

  /// Añade una ruta o patrón de carpeta a la lista negra.
  Future<void> addBlacklistedFolder(String rawPath) async {
    final norm = normalizePath(rawPath);
    if (norm.isEmpty) return;
    final updated = Set<String>.from(blacklistedFolders.value)..add(norm);
    blacklistedFolders.value = updated;
    await _persistBlacklistedFolders(updated);
  }

  /// Elimina una regla específica de la lista negra.
  Future<void> removeBlacklistedRule(String rule) async {
    final updated = Set<String>.from(blacklistedFolders.value)..remove(rule);
    blacklistedFolders.value = updated;
    await _persistBlacklistedFolders(updated);
  }

  /// Alterna el bloqueo de una carpeta detectada en el dispositivo.
  Future<void> toggleFolder(String folderPath) async {
    final norm = normalizePath(folderPath);
    if (norm.isEmpty) return;
    final updated = Set<String>.from(blacklistedFolders.value);
    final matching =
        updated.where((rule) => _pathMatchesRule(norm, rule)).toList();

    if (matching.isNotEmpty) {
      updated.removeAll(matching);
    } else {
      updated.add(norm);
    }
    blacklistedFolders.value = updated;
    await _persistBlacklistedFolders(updated);
  }

  /// Restaura la lista negra de carpetas a los valores recomendados por defecto.
  Future<void> resetBlacklistedFolders() async {
    final defaults = Set<String>.from(defaultBlacklistedPatterns);
    blacklistedFolders.value = defaults;
    await _persistBlacklistedFolders(defaults);
  }

  Future<void> _persistBlacklistedFolders(Set<String> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kBlacklistedFolders, folders.toList());
    } on Exception catch (e, st) {
      debugPrint('LibraryFilterSettings._persistBlacklistedFolders: $e\n$st');
    }
  }

  /// Normaliza una ruta de sistema de archivos para comparación insensible a mayúsculas.
  static String normalizePath(String path) {
    var clean = path.trim().replaceAll('\\', '/').toLowerCase();
    while (clean.endsWith('/') && clean.length > 1) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  /// Extrae el directorio padre de la ruta completa de un archivo de audio.
  static String extractFolderPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return normalized.substring(0, lastSlash);
  }

  /// Nombre corto de la carpeta para mostrar en listas.
  static String folderDisplayName(String folderPath) {
    final clean = folderPath.replaceAll('\\', '/');
    final parts = clean.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return folderPath;
    if (parts.length == 1) return parts.first;
    return '${parts[parts.length - 1]} (${parts[parts.length - 2]})';
  }

  static bool _pathMatchesRule(String normalizedFolderPath, String rule) {
    if (rule.isEmpty) return false;
    return normalizedFolderPath == rule ||
        normalizedFolderPath.endsWith(rule) ||
        normalizedFolderPath.contains('$rule/');
  }

  /// Indica si [folderPath] coincide con alguna regla activa de la lista negra.
  bool isFolderBlacklisted(String folderPath) {
    final norm = normalizePath(folderPath);
    for (final rule in blacklistedFolders.value) {
      if (_pathMatchesRule(norm, rule)) return true;
    }
    return false;
  }

  /// Evalúa si una canción debe mostrarse en la biblioteca principal.
  bool shouldIncludeSong(SongModel song, Set<int> hiddenSongIds) {
    if (song.isMusic != true) return false;
    if (song.isRingtone == true ||
        song.isAlarm == true ||
        song.isNotification == true) {
      return false;
    }
    if (hiddenSongIds.contains(song.id)) return false;

    final minMs = minDuration.value.milliseconds;
    if (minMs > 0 && (song.duration ?? 0) < minMs) {
      return false;
    }

    final folder = extractFolderPath(song.data);
    if (isFolderBlacklisted(folder)) {
      return false;
    }

    return true;
  }

  /// Obtiene la fecha de adición o modificación de [song] en UTC/local.
  static DateTime? resolveSongDate(SongModel song) {
    final raw = song.dateAdded ?? song.dateModified;
    if (raw == null || raw <= 0) return null;
    // Android MediaStore guarda DATE_ADDED en segundos; si > 10^11 ya son ms.
    final ms = raw > 100000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Evalúa si [song] cumple con el filtro de añadidas recientemente.
  static bool matchesRecentFilter(
    SongModel song,
    RecentAddedFilter filter,
    DateTime now,
  ) {
    final days = filter.days;
    if (days == null) return true;
    final songDate = resolveSongDate(song);
    if (songDate == null) return false;
    final cutoff = now.subtract(Duration(days: days));
    return songDate.isAfter(cutoff);
  }
}


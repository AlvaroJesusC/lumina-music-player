import 'package:flutter/material.dart';
import '../services/library_filter_settings.dart';
import '../theme/lumina_colors.dart';
import '../theme/lumina_haptics.dart';
import '../theme/lumina_shapes.dart';

/// Barra horizontal con chips de "Añadidas recientemente" y botón de "Ordenar".
class LibraryFilterBar extends StatelessWidget {
  final RecentAddedFilter activeRecentFilter;
  final SongSortOption activeSortOption;
  final ValueChanged<RecentAddedFilter> onRecentFilterChanged;
  final VoidCallback onOpenSortSheet;

  const LibraryFilterBar({
    super.key,
    required this.activeRecentFilter,
    required this.activeSortOption,
    required this.onRecentFilterChanged,
    required this.onOpenSortSheet,
  });

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: RecentAddedFilter.values.map((filter) {
                  final isSelected = activeRecentFilter == filter;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: GestureDetector(
                      onTap: () {
                        LuminaHaptics.fire(context, HapticEvent.select);
                        onRecentFilterChanged(filter);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? colors.accentSoft : colors.surface,
                          borderRadius:
                              BorderRadius.circular(shapes.miniPlayer),
                          border: Border.all(
                            color:
                                isSelected ? colors.accent : colors.hairline,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (filter != RecentAddedFilter.all) ...[
                              Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: isSelected
                                    ? colors.accentInk
                                    : colors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              filter.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? colors.accentInk
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              LuminaHaptics.fire(context, HapticEvent.select);
              onOpenSortSheet();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceHighest,
                borderRadius: BorderRadius.circular(shapes.miniPlayer),
                border: Border.all(color: colors.hairline, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 16,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    activeSortOption.shortLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja modal para elegir el ordenamiento de la biblioteca.
class SortBottomSheet extends StatelessWidget {
  final VoidCallback onChanged;

  const SortBottomSheet({
    super.key,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onChanged,
  }) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (_) => SortBottomSheet(onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final current = LibraryFilterSettings.instance.sortOption.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Ordenar canciones por',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            ...SongSortOption.values.map((option) {
              final isSelected = current == option;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentSoft : colors.surface,
                  borderRadius: BorderRadius.circular(shapes.card),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.hairline,
                    width: 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    option.icon,
                    color: isSelected ? colors.accent : colors.textSecondary,
                  ),
                  title: Text(
                    option.label,
                    style: TextStyle(
                      color:
                          isSelected ? colors.accentInk : colors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    option.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: colors.accent)
                      : null,
                  onTap: () async {
                    LuminaHaptics.fire(context, HapticEvent.select);
                    final navigator = Navigator.of(context);
                    await LibraryFilterSettings.instance.setSortOption(option);
                    onChanged();
                    navigator.pop();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Hoja modal para elegir el filtro de duración mínima de audios.
class MinDurationFilterSheet extends StatelessWidget {
  final VoidCallback onChanged;

  const MinDurationFilterSheet({
    super.key,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onChanged,
  }) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (_) => MinDurationFilterSheet(onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final current = LibraryFilterSettings.instance.minDuration.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Ocultar audios cortos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Evita que notas de voz de WhatsApp, tonos y sonidos cortos aparezcan en tu biblioteca.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            ...MinDurationFilter.values.map((filter) {
              final isSelected = current == filter;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentSoft : colors.surface,
                  borderRadius: BorderRadius.circular(shapes.card),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.hairline,
                    width: 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    filter == MinDurationFilter.off
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    color: isSelected ? colors.accent : colors.textSecondary,
                  ),
                  title: Text(
                    filter.label,
                    style: TextStyle(
                      color:
                          isSelected ? colors.accentInk : colors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    filter.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: colors.accent)
                      : null,
                  onTap: () async {
                    LuminaHaptics.fire(context, HapticEvent.select);
                    final navigator = Navigator.of(context);
                    await LibraryFilterSettings.instance.setMinDuration(filter);
                    onChanged();
                    navigator.pop();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Hoja modal para gestionar la Lista Negra de Carpetas (ej. `/WhatsApp/Media/`).
class BlacklistFoldersSheet extends StatefulWidget {
  final Map<String, int> detectedFolders;
  final VoidCallback onChanged;

  const BlacklistFoldersSheet({
    super.key,
    required this.detectedFolders,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, int> detectedFolders,
    required VoidCallback onChanged,
  }) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet)),
      ),
      builder: (_) => BlacklistFoldersSheet(
        detectedFolders: detectedFolders,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<BlacklistFoldersSheet> createState() => _BlacklistFoldersSheetState();
}

class _BlacklistFoldersSheetState extends State<BlacklistFoldersSheet> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _addCustomPath() {
    final raw = _pathController.text.trim();
    if (raw.isEmpty) return;
    LuminaHaptics.fire(context, HapticEvent.commit);
    _pathController.clear();
    LibraryFilterSettings.instance.addBlacklistedFolder(raw).then((_) {
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = LuminaColors.of(context);
    final shapes = LuminaShapes.of(context);
    final settings = LibraryFilterSettings.instance;
    final rules = settings.blacklistedFolders.value.toList()..sort();
    final folderEntries = widget.detectedFolders.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Lista negra de carpetas',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    LuminaHaptics.fire(context, HapticEvent.select);
                    await settings.resetBlacklistedFolders();
                    if (!mounted) return;
                    setState(() {});
                    widget.onChanged();
                  },
                  icon: Icon(
                    Icons.restore_rounded,
                    size: 18,
                    color: colors.accent,
                  ),
                  label: Text(
                    'Por defecto',
                    style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Los audios dentro de carpetas bloqueadas (ej. /WhatsApp/Media/) se ignoran automáticamente.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: colors.surfaceHighest,
                      borderRadius: BorderRadius.circular(shapes.field),
                      border: Border.all(color: colors.hairline, width: 1),
                    ),
                    child: TextField(
                      controller: _pathController,
                      onSubmitted: (_) => _addCustomPath(),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ej: /WhatsApp/Media/ o /Grabaciones',
                        hintStyle: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                  ),
                  onPressed: _addCustomPath,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Bloquear ruta',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (folderEntries.isNotEmpty) ...[
                    Text(
                      'CARPETAS DETECTADAS EN TU DISPOSITIVO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...folderEntries.map((entry) {
                      final folderPath = entry.key;
                      final count = entry.value;
                      final isBlocked =
                          settings.isFolderBlacklisted(folderPath);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(shapes.card),
                          border: Border.all(
                            color: isBlocked
                                ? Colors.redAccent.withValues(alpha: 0.45)
                                : colors.hairline,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isBlocked
                                ? Icons.folder_off_rounded
                                : Icons.folder_open_rounded,
                            color: isBlocked
                                ? Colors.redAccent
                                : colors.accent,
                          ),
                          title: Text(
                            LibraryFilterSettings.folderDisplayName(folderPath),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '$folderPath • $count audio(s)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                          trailing: Switch(
                            value: isBlocked,
                            activeThumbColor: Colors.redAccent,
                            onChanged: (_) async {
                              LuminaHaptics.fire(context, HapticEvent.select);
                              await settings.toggleFolder(folderPath);
                              if (!mounted) return;
                              setState(() {});
                              widget.onChanged();
                            },
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    'REGLAS DE EXCLUSIÓN ACTIVAS (${rules.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No hay carpetas bloqueadas actualmente.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: rules.map((rule) {
                        return Chip(
                          backgroundColor: colors.surface,
                          side: BorderSide(color: colors.hairline),
                          label: Text(
                            rule,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textPrimary,
                            ),
                          ),
                          deleteIcon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                          onDeleted: () async {
                            LuminaHaptics.fire(context, HapticEvent.select);
                            await settings.removeBlacklistedRule(rule);
                            if (!mounted) return;
                            setState(() {});
                            widget.onChanged();
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


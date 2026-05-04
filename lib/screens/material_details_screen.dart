import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/course_material.dart';
import '../services/api.dart';
import '../services/parser.dart';
import '../services/language.dart';
import '../services/mock_data.dart';
import '../main.dart';

class MaterialDetailsScreen extends StatefulWidget {
  final CourseSubject subject;
  const MaterialDetailsScreen({super.key, required this.subject});

  @override
  State<MaterialDetailsScreen> createState() => _MaterialDetailsScreenState();
}

class _MaterialDetailsScreenState extends State<MaterialDetailsScreen> {
  String             _courseTitle = '';
  List<LectureGroup> _groups      = [];
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      // ── ADMIN SANDBOX ────────────────────────────────────────
      if (MockDataService.isActive) {
        final parsed = MockDataService.buildMockMaterialDetails(
            widget.subject.payloadForDetails);
        if (mounted) {
          setState(() {
            _courseTitle = parsed.courseTitle;
            _groups      = parsed.groups;
            _loading     = false;
          });
        }
        return;
      }
      // ────────────────────────────────────────────────────────
      final html = await ApiService.fetchMaterialDetails(
          widget.subject.payloadForDetails);
      if (html == null || html.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = true; });
        return;
      }
      final parsed = await Parser.parseMaterialDetails(html);
      if (mounted) {
        setState(() {
          _courseTitle = parsed.courseTitle;
          _groups      = parsed.groups;
          _loading     = false;
        });
      }
    } catch (e) {
      debugPrint('MaterialDetailsScreen._loadDetails error: $e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.tr('update_open_error'))),
        );
      }
    }
  }

  List<Widget> _buildSkeleton(ThemeData theme, Color primary, bool isDark) {
    final base  = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _DetSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Имитирует одну LectureGroup-карточку (заголовок + N файлов)
    Widget groupCard({int files = 3, double nameWidth = double.infinity}) {
      final fileTiles = List.generate(files, (i) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: [
                box(36, 36, r: 9),            // иконка файла
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(nameWidth, 13, r: 4),
                    const SizedBox(height: 4),
                    box(28, 10, r: 3),         // ext badge (PDF / PPTX)
                  ],
                )),
                const SizedBox(width: 8),
                box(56, 28, r: 10),            // кнопка «Open»
              ],
            ),
          ),
          if (i < files - 1)
            Divider(height: 1, indent: 64,
                color: theme.dividerColor.withOpacity(0.4)),
        ],
      ));

      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(
                  isDark ? 0.18 : 0.25)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            // Хедер группы
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  box(32, 32, r: 9),            // иконка папки
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(nameWidth, 15, r: 5),
                      const SizedBox(height: 5),
                      box(80, 11, r: 4),
                    ],
                  )),
                  const SizedBox(width: 8),
                  box(28, 22, r: 6),             // счётчик файлов
                  const SizedBox(width: 6),
                  box(20, 20, r: 5),             // стрелка
                ],
              ),
            ),
            // Файлы
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(children: fileTiles),
            ),
          ],
        ),
      );
    }

    return [
      groupCard(files: 3, nameWidth: 200),
      groupCard(files: 2, nameWidth: 230),
      groupCard(files: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: themeNotifier,
          builder: (context, _, __) {
            final theme   = Theme.of(context);
            final isDark  = theme.brightness == Brightness.dark;
            final primary = theme.colorScheme.primary;
            final bottomPad = MediaQuery.of(context).padding.bottom + 24;

            return Scaffold(
              body: CustomScrollView(
                slivers: [

                  // ── AppBar with gradient header ─────────────────
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 130,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
                      title: Text(
                        widget.subject.code,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end:   Alignment.bottomRight,
                            colors: [primary, primary.withOpacity(0.65)],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(72, 16, 20, 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  LanguageService.subjectDisplayName(widget.subject.code, widget.subject.name),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.92),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline_rounded,
                                        size: 13,
                                        color: Colors.white.withOpacity(0.7)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        LanguageService.translateName(widget.subject.teacher),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Body ────────────────────────────────────────
                  if (_loading)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          _buildSkeleton(theme, primary, isDark)),
                      ),
                    )
                  else if (_error)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_rounded,
                                size: 52,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text(LanguageService.tr('no_data'),
                                style: TextStyle(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _loadDetails,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(LanguageService.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_groups.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open_rounded,
                                size: 52,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text(LanguageService.tr('no_data'),
                                style: TextStyle(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding:
                          EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _LectureGroupCard(
                            group:   _groups[i],
                            isDark:  isDark,
                            primary: primary,
                            onOpen:  _openUrl,
                          ),
                          childCount: _groups.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Lecture Group Card ───────────────────────────────────────────────────────

class _LectureGroupCard extends StatefulWidget {
  final LectureGroup group;
  final bool         isDark;
  final Color        primary;
  final void Function(String) onOpen;

  const _LectureGroupCard({
    required this.group,
    required this.isDark,
    required this.primary,
    required this.onOpen,
  });

  @override
  State<_LectureGroupCard> createState() => _LectureGroupCardState();
}

class _LectureGroupCardState extends State<_LectureGroupCard> {
  // Lectures with files are expanded by default; empty ones are collapsed.
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.group.hasFiles;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(widget.isDark ? 0.15 : 0.055),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            InkWell(
              onTap: group.hasFiles
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: _expanded && group.hasFiles
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    // Lecture number badge
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: group.hasFiles
                            ? widget.primary.withOpacity(0.12)
                            : theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        group.hasFiles
                            ? Icons.menu_book_rounded
                            : Icons.hourglass_empty_rounded,
                        size: 18,
                        color: group.hasFiles
                            ? widget.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LanguageService.translateLectureTitle(group.title),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: group.hasFiles
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant
                                      .withOpacity(0.6),
                            ),
                          ),
                          if (group.date.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              group.date,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (group.hasFiles) ...[
                      // File count chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${group.files.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: widget.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── File list ──────────────────────────────────────────
            if (_expanded && group.hasFiles) ...[
              Divider(
                  height: 1,
                  color: theme.dividerColor.withOpacity(0.5)),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  children: [
                    ...group.files.asMap().entries.map((e) {
                      final isLast = e.key == group.files.length - 1;
                      return _FileTile(
                        file:    e.value,
                        isLast:  isLast,
                        primary: widget.primary,
                        isDark:  widget.isDark,
                        onOpen:  () => widget.onOpen(e.value.url),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── File Tile ────────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final MaterialFile file;
  final bool         isLast;
  final Color        primary;
  final bool         isDark;
  final VoidCallback onOpen;

  const _FileTile({
    required this.file,
    required this.isLast,
    required this.primary,
    required this.isDark,
    required this.onOpen,
  });

  static IconData _iconFor(String ext) {
    switch (ext) {
      case 'pdf':    return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':   return Icons.description_rounded;
      case 'ppt':
      case 'pptx':   return Icons.slideshow_rounded;
      case 'xls':
      case 'xlsx':   return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':    return Icons.folder_zip_rounded;
      case 'gdrive': return Icons.add_to_drive_rounded;
      default:       return Icons.insert_drive_file_rounded;
    }
  }

  static Color _colorFor(String ext) {
    switch (ext) {
      case 'pdf':            return const Color(0xFFE53935);
      case 'doc': case 'docx': return const Color(0xFF1565C0);
      case 'ppt': case 'pptx': return const Color(0xFFE64A19);
      case 'xls': case 'xlsx': return const Color(0xFF2E7D32);
      case 'gdrive':           return const Color(0xFF1E88E5);
      default:                 return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext   = file.extension;
    final icon  = _iconFor(ext);
    final color = _colorFor(ext);

    // Clean up the filename shown in the UI — strip the long hash suffix.
    // Raw name: "OS_lec01_pres - 2026-02-17_11-50-46_3N6pP1bT...pdf"
    // We want:  "OS_lec01_pres"
    String displayName = file.name;
    final dashIdx = displayName.indexOf(' - ');
    if (dashIdx != -1) displayName = displayName.substring(0, dashIdx).trim();

    return Column(
      children: [
        InkWell(
          onTap: onOpen,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(16))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ext.isNotEmpty && ext != 'gdrive')
                        Text(
                          ext.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        LanguageService.tr('open'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 64,
              color: Theme.of(context).dividerColor.withOpacity(0.4)),
      ],
    );
  }
}

// ─── Shimmer-прямоугольник для скелетона деталей материала ───────
class _DetSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _DetSkeletonBox({
    required this.width, required this.height,
    required this.radius, required this.base, required this.shine,
  });
  @override
  State<_DetSkeletonBox> createState() => _DetSkeletonBoxState();
}
class _DetSkeletonBoxState extends State<_DetSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(widget.base, widget.shine, _anim.value),
      ),
    ),
  );
}
// lib/screens/materials_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../models/semester.dart';
import '../models/course_material.dart';
import '../models/syllabus_subject.dart';
import '../services/api.dart';
import '../services/parser.dart';
import '../services/language.dart';
import '../services/mock_data.dart';
import '../main.dart';
import 'main_screen.dart';
import 'material_details_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Wrapper — Materials | Syllabus tab switcher
// ═══════════════════════════════════════════════════════════════════

class MaterialsScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const MaterialsScreen({super.key, this.onMenuTap});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _syllabusActivated = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_onTabSettled);
  }

  void _onTabSettled() {
    if (_tabCtrl.indexIsChanging) return;
    if (_tabCtrl.index == 1 && !_syllabusActivated) {
      setState(() => _syllabusActivated = true);
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabSettled);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) => Scaffold(
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegmentedTabBar(
                        controller: _tabCtrl,
                        tabs: [
                          LanguageService.tr('materials'),
                          LanguageService.tr('syllabus'),
                        ],
                        isDark: isDark,
                        primary: primary,
                      ),
                    ),
                    const NotificationBell(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MaterialsTabBody(primary: primary, isDark: isDark),
                  _syllabusActivated
                      ? _SyllabusTabBody(primary: primary, isDark: isDark)
                      : const Center(child: SizedBox.shrink()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Segmented pill-style tab bar ─────────────────────────────────

class _SegmentedTabBar extends StatefulWidget {
  final TabController controller;
  final List<String>  tabs;
  final bool          isDark;
  final Color         primary;

  const _SegmentedTabBar({
    required this.controller,
    required this.tabs,
    required this.isDark,
    required this.primary,
  });

  @override
  State<_SegmentedTabBar> createState() => _SegmentedTabBarState();
}

class _SegmentedTabBarState extends State<_SegmentedTabBar> {
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (widget.controller.indexIsChanging) return;
    if (mounted && _current != widget.controller.index) {
      setState(() => _current = widget.controller.index);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.06);

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(widget.tabs.length, (i) {
          final active = _current == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticService.medium();
                widget.controller.animateTo(i);
                if (mounted) setState(() => _current = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: active
                      ? (widget.isDark ? const Color(0xFF1A3A6E) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: active
                      ? [BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: Text(
                    widget.tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? widget.primary
                          : (widget.isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Materials tab body
// ═══════════════════════════════════════════════════════════════════

class _MaterialsTabBody extends StatefulWidget {
  final Color primary;
  final bool  isDark;
  const _MaterialsTabBody({required this.primary, required this.isDark});

  @override
  State<_MaterialsTabBody> createState() => _MaterialsTabBodyState();
}

class _MaterialsTabBodyState extends State<_MaterialsTabBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Semester>      _semesters = [];
  List<CourseSubject> _subjects  = [];
  Semester?           _selectedSem;
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({Semester? sem}) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      // ── ADMIN SANDBOX ────────────────────────────────────────
      if (MockDataService.isActive) {
        final parsed = MockDataService.buildMockMaterialsList();
        if (mounted) {
          setState(() {
            if (parsed.semesters.isNotEmpty) {
              _semesters   = parsed.semesters;
              _selectedSem = sem ?? parsed.semesters.last;
            }
            _subjects = parsed.subjects;
            _loading  = false;
          });
        }
        return;
      }
      // ────────────────────────────────────────────────────────
      final html = sem != null
          ? await ApiService.fetchMaterialsList(
              semesterId:   sem.id.toString(),
              semesterName: sem.name,
            )
          : await ApiService.fetchMaterialsList();

      if (html == null || html.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = true; });
        return;
      }

      final parsed = await Parser.parseMaterialsList(html);
      if (mounted) {
        setState(() {
          if (parsed.semesters.isNotEmpty) {
            _semesters   = parsed.semesters;
            _selectedSem = sem ?? parsed.semesters.last;
          }
          _subjects = parsed.subjects;
          _loading  = false;
        });
      }
    } catch (e) {
      debugPrint('MaterialsTabBody error: $e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme     = Theme.of(context);
    final bottomPad = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight;

    return RefreshIndicator(
      onRefresh: () => _loadData(sem: _selectedSem),
      child: CustomScrollView(
        slivers: [
          if (_semesters.isNotEmpty)
            SliverToBoxAdapter(
              child: _SemesterPicker(
                semesters: _semesters,
                selected:  _selectedSem,
                primary:   widget.primary,
                isDark:    widget.isDark,
                onChanged: (sem) {
                  setState(() => _selectedSem = sem);
                  _loadData(sem: sem);
                },
              ),
            ),
          if (_loading)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomPad),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildSkeletonCards(theme, widget.primary, widget.isDark)),
              ),
            )
          else if (_error)
            SliverFillRemaining(
              child: _ErrorView(onRetry: () => _loadData(sem: _selectedSem)),
            )
          else if (_subjects.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_off_rounded, size: 52,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(LanguageService.tr('no_data'),
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomPad),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubjectCard(
                      subject: _subjects[i],
                      isDark:  widget.isDark,
                      primary: widget.primary,
                      index:   i,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MaterialDetailsScreen(subject: _subjects[i]),
                        ),
                      ),
                    ),
                  ),
                  childCount: _subjects.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Syllabus tab body
// ═══════════════════════════════════════════════════════════════════

class _SyllabusTabBody extends StatefulWidget {
  final Color primary;
  final bool  isDark;
  const _SyllabusTabBody({required this.primary, required this.isDark});

  @override
  State<_SyllabusTabBody> createState() => _SyllabusTabBodyState();
}

class _SyllabusTabBodyState extends State<_SyllabusTabBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Semester>        _semesters = [];
  List<SyllabusSubject> _subjects  = [];
  Semester?             _selectedSem;
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({Semester? sem}) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final html = sem != null
          ? await ApiService.fetchSyllabusList(
              semesterId:   sem.id.toString(),
              semesterName: sem.name,
            )
          : await ApiService.fetchSyllabusList();

      if (html == null || html.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = true; });
        return;
      }

      final parsed = await Parser.parseSyllabusList(html);
      if (mounted) {
        setState(() {
          if (parsed.semesters.isNotEmpty) {
            _semesters   = parsed.semesters;
            _selectedSem = sem ?? parsed.semesters.last;
          }
          _subjects = parsed.subjects;
          _loading  = false;
        });
      }
    } catch (e) {
      debugPrint('SyllabusTabBody error: $e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme     = Theme.of(context);
    final bottomPad = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight;

    return RefreshIndicator(
      onRefresh: () => _loadData(sem: _selectedSem),
      child: CustomScrollView(
        slivers: [
          if (_semesters.isNotEmpty)
            SliverToBoxAdapter(
              child: _SemesterPicker(
                semesters: _semesters,
                selected:  _selectedSem,
                primary:   widget.primary,
                isDark:    widget.isDark,
                onChanged: (sem) {
                  setState(() => _selectedSem = sem);
                  _loadData(sem: sem);
                },
              ),
            ),
          if (_loading)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomPad),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildSkeletonCards(theme, widget.primary, widget.isDark)),
              ),
            )
          else if (_error)
            SliverFillRemaining(
              child: _ErrorView(onRetry: () => _loadData(sem: _selectedSem)),
            )
          else if (_subjects.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_rounded, size: 52,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(LanguageService.tr('no_data'),
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomPad),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SyllabusCard(
                      subject: _subjects[i],
                      isDark:  widget.isDark,
                      primary: widget.primary,
                      index:   i,
                    ),
                  ),
                  childCount: _subjects.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared skeleton builder (Materials & Syllabus) ──────────────
List<Widget> _buildSkeletonCards(ThemeData theme, Color primary, bool isDark) {
  final base  = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
  final shine = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

  Widget box(double w, double h, {double r = 8}) =>
      _MatSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

  Widget card({double nameWidth = double.infinity}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
            blurRadius: 14, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          // Квадратная иконка предмета
          box(52, 52, r: 13),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(56, 11, r: 4),   // код предмета
                const SizedBox(height: 5),
                box(nameWidth, 15, r: 6),
                const SizedBox(height: 5),
                box(nameWidth == double.infinity ? 160 : nameWidth * 0.65, 14, r: 5),
                const SizedBox(height: 6),
                Row(children: [
                  box(13, 13, r: 3),
                  const SizedBox(width: 5),
                  box(130, 11, r: 4), // преподаватель
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          box(20, 20, r: 5),          // стрелка / кнопка
        ],
      ),
    ),
  );

  return [
    card(nameWidth: 220),
    card(),
    card(nameWidth: 200),
    card(nameWidth: 250),
    card(),
    card(nameWidth: 230),
  ];
}

// ═══════════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════════

// Translates Georgian semester names into the current UI language.
String _formatSemName(String rawName) {
  const geoToTrKey = <String, String>{
    'გაზაფხულის': 'sem_spring',
    'ზაფხულის':   'sem_summer',
    'შემოდგომის': 'sem_autumn',
    'ზამთრის':    'sem_winter',
    'სემესტრი':   'sem_semester',
  };
  final lang = LanguageService.currentLang.value;
  String name = rawName.trim();
  if (lang != 'ქართული') {
    geoToTrKey.forEach((geo, key) {
      if (name.contains(geo)) name = name.replaceAll(geo, LanguageService.tr(key));
    });
  }
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.length <= 28) return name;
  final parts = name.split(' ');
  if (parts.length >= 2) return '${parts[0]} ${parts[1]}';
  return '${name.substring(0, 24)}…';
}

class _SemesterPicker extends StatelessWidget {
  final List<Semester>          semesters;
  final Semester?               selected;
  final Color                   primary;
  final bool                    isDark;
  final void Function(Semester) onChanged;

  const _SemesterPicker({
    required this.semesters,
    required this.selected,
    required this.primary,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<Semester>(
            isExpanded: true,
            value: selected,
            borderRadius: BorderRadius.circular(14),
            icon: Icon(Icons.expand_more_rounded, color: primary, size: 20),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            items: semesters.map((s) => DropdownMenuItem(
              value: s,
              child: Text(_formatSemName(s.name), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (s) { if (s != null) onChanged(s); },
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(LanguageService.tr('no_data'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(LanguageService.tr('retry')),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final CourseSubject subject;
  final bool          isDark;
  final Color         primary;
  final int           index;
  final VoidCallback  onTap;

  const _SubjectCard({
    required this.subject,
    required this.isDark,
    required this.primary,
    required this.index,
    required this.onTap,
  });

  static const _tints = [0.10, 0.08, 0.12, 0.07, 0.09, 0.11];

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final opacity = _tints[index % _tints.length];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticService.medium(); onTap(); },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
                blurRadius: 14, offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: primary.withOpacity(opacity + 0.05),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    subject.code.split(' ').first,
                    style: TextStyle(color: primary, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.code,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: primary, letterSpacing: 0.3)),
                    const SizedBox(height: 3),
                    Text(
                      LanguageService.subjectDisplayName(subject.code, subject.name),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.person_outline_rounded, size: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(child: Text(
                        LanguageService.translateName(subject.teacher),
                        style: TextStyle(fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Syllabus Card ────────────────────────────────────────────────

enum _BtnState { idle, downloading, opening, error }

class _SyllabusCard extends StatefulWidget {
  final SyllabusSubject subject;
  final bool            isDark;
  final Color           primary;
  final int             index;

  const _SyllabusCard({
    required this.subject,
    required this.isDark,
    required this.primary,
    required this.index,
  });

  @override
  State<_SyllabusCard> createState() => _SyllabusCardState();
}

class _SyllabusCardState extends State<_SyllabusCard> {
  _BtnState _state  = _BtnState.idle;
  String?   _errMsg;

  static const _tints = [0.10, 0.08, 0.12, 0.07, 0.09, 0.11];

  Future<void> _openSyllabus() async {
    if (_state == _BtnState.downloading || _state == _BtnState.opening) return;
    setState(() { _state = _BtnState.downloading; _errMsg = null; });

    final bytes = await ApiService.downloadSyllabusPdf(
      studentId: widget.subject.studentId,
      cxrId:     widget.subject.cxrId,
    );

    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      setState(() { _state = _BtnState.error;
          _errMsg = LanguageService.tr('syllabus_error'); });
      return;
    }

    setState(() => _state = _BtnState.opening);

    try {
      final dir  = await getTemporaryDirectory();
      final safe = widget.subject.code.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final path = '${dir.path}/syllabus_$safe.pdf';
      await File(path).writeAsBytes(bytes);

      final result = await OpenFile.open(path, type: 'application/pdf');
      if (!mounted) return;

      if (result.type != ResultType.done) {
        setState(() { _state = _BtnState.error;
            _errMsg = result.message.contains('No APP')
                ? LanguageService.tr('syllabus_no_viewer')
                : LanguageService.tr('syllabus_error'); });
      } else {
        setState(() => _state = _BtnState.idle);
      }
    } catch (e) {
      if (mounted) setState(() { _state = _BtnState.error;
          _errMsg = LanguageService.tr('syllabus_error'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final opacity = _tints[widget.index % _tints.length];
    final primary = widget.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(widget.isDark ? 0.18 : 0.06),
              blurRadius: 14, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: primary.withOpacity(opacity + 0.05),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text(
                widget.subject.code.split(' ').first,
                style: TextStyle(color: primary, fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 0.2),
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.subject.code,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: primary, letterSpacing: 0.3)),
                const SizedBox(height: 3),
                Text(
                  LanguageService.subjectDisplayName(
                      widget.subject.code, widget.subject.name),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.person_outline_rounded, size: 13,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    LanguageService.translateName(widget.subject.teacher),
                    style: TextStyle(fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
                if (_state == _BtnState.error && _errMsg != null) ...[
                  const SizedBox(height: 6),
                  Text(_errMsg!,
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _OpenButton(state: _state, primary: primary,
              isDark: widget.isDark, onTap: _openSyllabus),
        ],
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  final _BtnState    state;
  final Color        primary;
  final bool         isDark;
  final VoidCallback onTap;

  const _OpenButton({
    required this.state,
    required this.primary,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state == _BtnState.downloading || state == _BtnState.opening;
    String label; IconData icon; Color color;

    switch (state) {
      case _BtnState.downloading:
        label = LanguageService.tr('syllabus_downloading');
        icon  = Icons.downloading_rounded; color = primary; break;
      case _BtnState.opening:
        label = LanguageService.tr('syllabus_opening');
        icon  = Icons.open_in_new_rounded; color = primary; break;
      case _BtnState.error:
        label = LanguageService.tr('retry');
        icon  = Icons.refresh_rounded;
        color = Theme.of(context).colorScheme.error; break;
      case _BtnState.idle: default:
        label = LanguageService.tr('syllabus_open');
        icon  = Icons.picture_as_pdf_rounded; color = primary;
    }

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: busy ? color.withOpacity(0.08)
              : color.withOpacity(isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(busy ? 0.2 : 0.35), width: 1),
        ),
        child: busy
            ? SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 3),
                  Text(label,
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w600, color: color),
                      textAlign: TextAlign.center, maxLines: 2),
                ],
              ),
      ),
    );
  }
}

// ─── Shimmer-прямоугольник для скелетона материалов ──────────────
class _MatSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _MatSkeletonBox({
    required this.width, required this.height,
    required this.radius, required this.base, required this.shine,
  });
  @override
  State<_MatSkeletonBox> createState() => _MatSkeletonBoxState();
}
class _MatSkeletonBoxState extends State<_MatSkeletonBox>
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
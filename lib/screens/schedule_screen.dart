// lib/screens/schedule_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import 'package:flutter/cupertino.dart';
import '../models/lesson.dart';
import '../models/lesson_override.dart';
import '../models/semester.dart';
import '../services/parser.dart';
import '../services/api.dart';
import '../services/data_service.dart';
import '../services/language.dart';
import '../services/lesson_override_service.dart';
import '../services/notification_service.dart';
import '../models/notification_item.dart';
import '../utils/schedule_utils.dart';
import '../main.dart';

// ─── Nav-bar content height (matches _AppNavBar SizedBox in main_screen.dart) ──
// Used to calculate the correct bottom clearance when extendBody = true.
const double _kNavBarContentHeight = 62.0;

class LessonPhase {
  final String nameKey;
  final int    durationMins;
  final bool   isBreak;
  final int?   partNumber;
  const LessonPhase({
    required this.nameKey,
    required this.durationMins,
    required this.isBreak,
    this.partNumber,
  });
}

class ScheduleScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const ScheduleScreen({super.key, this.onMenuTap});

  static void clearCache() {
    _ScheduleScreenState._cachedSchedule  = null;
    _ScheduleScreenState._cachedSemesters = null;
  }

  // Kept for backward compat with notification_history_screen.
  // CalendarScreen listens to this when open.
  static final ValueNotifier<DateTime?> highlightRequest = ValueNotifier(null);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static List<Lesson>?   _cachedSchedule;
  static List<Semester>? _cachedSemesters;

  Map<String, List<Lesson>> _groupedLessons = {};
  List<Semester>            _semesters      = [];
  Semester?                 _selectedSem;
  bool _loading       = true;
  bool _semLoading    = false;
  bool _isVacationDay = false;

  Set<String>   _attendanceDates = {};
  List<String>  _activeDays      = [];   // кеш — пересчитывается только в _applyData
  Timer?        _statusTimer;            // обновляет статус активной лекции

  @override
  void initState() {
    super.initState();
    _loadData();
    LessonOverrideService.version.addListener(_onOverridesChanged);
    // Раз в минуту перерисовываем статус лекций (прогресс-бар, бейджи).
    // Без этого таймера прогресс-бар замирал до следующего внешнего setState.
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onOverridesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    LessonOverrideService.version.removeListener(_onOverridesChanged);
    super.dispose();
  }

  // ─── ЗАГРУЗКА ───────────────────────────────────────────────────

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    if (forceRefresh) DataService.instance.invalidateAll();

    try {
      final lessons = await DataService.instance.fetchSchedule(forceRefresh: forceRefresh);

      List<Semester> sems = [];
      if (!forceRefresh && _cachedSemesters != null) {
        sems = _cachedSemesters!;
      } else {
        final html = await ApiService.getHtml(ApiService.scheduleUrl);
        if (html != null) sems = await Parser.parseSemestersAsync(html);
      }

      if (lessons.isNotEmpty) {
        _cachedSchedule  = lessons;
        _cachedSemesters = sems;
        LanguageService.seedCodeMap({
          for (final l in lessons)
            if (l.code.isNotEmpty && l.name.isNotEmpty) l.code: l.name,
        });
      }

      await DataService.instance.fetchAttendance();
      final dates = DataService.instance.attendanceDates;

      if (lessons.isNotEmpty) {
        _applyData(lessons, sems, dates);
      } else if (_cachedSchedule != null && _cachedSchedule!.isNotEmpty) {
        _applyData(_cachedSchedule!, _cachedSemesters ?? [], _attendanceDates);
      } else {
        _applyData([], [], {});
      }
    } catch (e) {
      debugPrint('ScheduleScreen._loadData ERROR: $e');
      if (_cachedSchedule != null && _cachedSchedule!.isNotEmpty) {
        _applyData(_cachedSchedule!, _cachedSemesters ?? [], _attendanceDates);
      } else {
        _applyData([], [], {});
      }
    }
  }

  Future<void> _switchSemester(Semester sem) async {
    if (_selectedSem == sem || !mounted) return;
    setState(() { _semLoading = true; _selectedSem = sem; });
    try {
      final lessons = await Parser.parseScheduleForSemester(sem);
      _applyData(lessons, _semesters, _attendanceDates, preserveSemesters: true);
    } catch (e) {
      debugPrint('switchSemester ERROR: $e');
    }
    if (mounted) setState(() => _semLoading = false);
  }

  void _applyData(List<Lesson> lessons, List<Semester> sems, Set<String> dates,
      {bool preserveSemesters = false}) {
    final grouped = <String, List<Lesson>>{};
    for (final l in lessons) {
      if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
    }
    grouped.forEach((_, list) => list.sort((a, b) => a.time.compareTo(b.time)));

    final now   = DateTime.now();
    final today = kWeekDays[now.weekday - 1];

    bool isVacation = lessons.isNotEmpty && !grouped.containsKey(today);

    if (!isVacation && dates.isNotEmpty) {
      final todayStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      if (!dates.contains(todayStr)) {
        final cutoff = now.subtract(const Duration(days: 21));
        final active = dates.any((d) {
          final p = d.split('/');
          if (p.length != 3) return false;
          try {
            final dt = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
            return dt.isAfter(cutoff) && dt.isBefore(now);
          } catch (_) { return false; }
        });
        if (active) isVacation = true;
      }
    }

    final newSems = preserveSemesters ? _semesters : sems;
    final newSel  = preserveSemesters
        ? _selectedSem
        : (newSems.isNotEmpty ? newSems.last : null);

    // ── Кешируем activeDays: пересчёт только здесь, не в каждом build() ──
    final scheduleDays = kWeekDays.where((d) => grouped.containsKey(d)).toSet();
    final extraDays    = <String>{};
    for (int i = 0; i < 14; i++) {
      final d    = now.add(Duration(days: i));
      final dKey = kWeekDays[d.weekday - 1];
      if (!scheduleDays.contains(dKey)) {
        final date = DateTime(d.year, d.month, d.day);
        if (LessonOverrideService.getAddedForDate(date).isNotEmpty) {
          extraDays.add(dKey);
        }
      }
    }
    final newActiveDays = kWeekDays
        .where((d) => scheduleDays.contains(d) || extraDays.contains(d))
        .toList();

    if (mounted) {
      setState(() {
        _loading         = false;
        _groupedLessons  = grouped;
        _semesters       = newSems;
        _selectedSem     = newSel;
        _isVacationDay   = isVacation;
        _attendanceDates = dates;
        _activeDays      = newActiveDays;
      });
    }
  }

  // ─── ДАТА СЛЕДУЮЩЕГО ВХОЖДЕНИЯ ДНЯ НЕДЕЛИ ───────────────────────

  DateTime _nextDateForDay(String dayName) {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final dayIdx = kWeekDays.indexOf(dayName) + 1;
    int diff     = dayIdx - now.weekday;
    if (diff < 0) diff += 7;
    return today.add(Duration(days: diff));
  }

  String _formatDateShort(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  // ─── СТАТУС ЛЕКЦИИ ──────────────────────────────────────────────

  DateTime? _parseTime(String timeStr, DateTime base, {bool isEnd = false}) {
    try {
      final parts = timeStr.replaceAll(RegExp(r'[^\d:-]'), '').split('-');
      if (parts.isEmpty) return null;
      final idx = isEnd && parts.length > 1 ? 1 : 0;
      final tp  = parts[idx].trim().split(':');
      if (tp.length < 2) return null;
      return DateTime(base.year, base.month, base.day,
          int.parse(tp[0]), int.parse(tp[1]));
    } catch (_) { return null; }
  }

  int _getLessonStatus(String day, String timeStr) {
    if (_isVacationDay) return 0;
    final now        = DateTime.now();
    final currentDay = kWeekDays[now.weekday - 1];
    if (day != currentDay) return 0;
    final start = _parseTime(timeStr, now);
    var   end   = _parseTime(timeStr, now, isEnd: true);
    if (start == null) return 0;
    end ??= start.add(const Duration(hours: 1, minutes: 55));
    if (now.isAfter(start) && now.isBefore(end)) return 1;
    if (now.isAfter(end)) return -1;
    final diff = start.difference(now).inMinutes;
    if (diff > 0 && diff <= 30) return 2;
    return 0;
  }

  List<LessonPhase> _generatePhases(int totalMins) {
    final phases = <LessonPhase>[];
    int rem = totalMins, part = 1;
    while (rem > 0) {
      final dur = rem > 55 ? 55 : rem;
      phases.add(LessonPhase(nameKey: 'part', durationMins: dur, isBreak: false, partNumber: part));
      rem -= dur;
      if (rem > 0) {
        final bDur = rem > 10 ? 10 : rem;
        phases.add(LessonPhase(nameKey: 'break', durationMins: bDur, isBreak: true));
        rem -= bDur; part++;
      }
    }
    return phases;
  }

  Map<String, dynamic> _checkTimelineStatus(String timeStr) {
    final now   = DateTime.now();
    final start = _parseTime(timeStr, now);
    var   end   = _parseTime(timeStr, now, isEnd: true);
    const empty = <LessonPhase>[];
    if (start == null) {
      return {'isBreak': false, 'nameKey': 'part', 'partNumber': null,
              'timeLeft': 0, 'elapsed': 0, 'totalMinutes': 0, 'phases': empty};
    }
    end ??= start.add(const Duration(hours: 1, minutes: 55));
    final total   = end.difference(start).inMinutes;
    final elapsed = now.difference(start).inMinutes;
    final phases  = _generatePhases(total);
    int acc = 0;
    for (final ph in phases) {
      if (elapsed >= acc && elapsed < acc + ph.durationMins) {
        return {
          'isBreak': ph.isBreak, 'nameKey': ph.nameKey,
          'partNumber': ph.partNumber,
          'timeLeft': (acc + ph.durationMins) - elapsed,
          'elapsed': elapsed, 'totalMinutes': total, 'phases': phases,
        };
      }
      acc += ph.durationMins;
    }
    return {'isBreak': false, 'nameKey': 'ending', 'partNumber': null,
            'timeLeft': 0, 'elapsed': elapsed, 'totalMinutes': total,
            'phases': phases};
  }

  // ─── BUILD ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) => ValueListenableBuilder<bool>(
        valueListenable: LanguageService.showBothTimes,
        builder: (_, showBoth, __) => _buildScaffold(showBoth),
      ),
    );
  }

  Widget _buildScaffold(bool showBoth) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    if (_loading) {
      return Scaffold(body: _buildSkeleton(theme, primary));
    }

    // Days with regular lessons
    final scheduleDays =
        kWeekDays.where((d) => _groupedLessons.containsKey(d)).toSet();

    // ── Используем кешированный список — без итерации 14 дней в каждом build() ──
    final activeDays = _activeDays.isNotEmpty
        ? _activeDays
        : scheduleDays.toList();

    // ── Bottom clearance: app nav bar content + system nav bar inset ──────────
    // The parent Scaffold uses extendBody = true, so the body draws behind the
    // nav bar.  viewPadding.bottom gives the system inset (gesture handle or
    // 3-button bar); _kNavBarContentHeight adds the 62 dp app nav bar on top.
    final systemBottom   = MediaQuery.of(context).viewPadding.bottom;
    final bottomClearance = _kNavBarContentHeight + systemBottom;

    return Scaffold(
      body: RefreshIndicator(
        color: primary,
        onRefresh: () => _loadData(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_semesters.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildSemesterChips(),
                    ),
                  if (_semLoading)
                    LinearProgressIndicator(
                        color: primary, backgroundColor: Colors.transparent, minHeight: 2)
                  else if (_semesters.length > 1)
                    const SizedBox(height: 2),
                ],
              ),
            ),

            if (_groupedLessons.isEmpty)
              // ── No data at all: centre text with proper bottom clearance ──
              SliverFillRemaining(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomClearance + 16),
                  child: Center(child: Text(LanguageService.tr('no_data'))),
                ),
              )
            else
              SliverPadding(
                // Bottom padding = comfortable scroll margin + nav bar clearance.
                // Vacation banner needs less top margin (just enough to clear the
                // nav bar); the regular list uses a larger value so the last card
                // scrolls fully above the nav bar with room to spare.
                padding: EdgeInsets.fromLTRB(
                  16, 8, 16,
                  (_isVacationDay ? 16 : 80) + bottomClearance,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      if (_isVacationDay && i == activeDays.length) {
                        return _buildVacationBanner(primary);
                      }
                      final d = activeDays[i];
                      return _buildDaySection(
                          d,
                          _groupedLessons[d] ?? [],
                          showBoth, isDark);
                    },
                    childCount: activeDays.length + (_isVacationDay ? 1 : 0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── СЕМЕСТРЫ ────────────────────────────────────────────────────


  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  Widget _buildSkeleton(ThemeData theme, Color primary) {
    final isDark = theme.brightness == Brightness.dark;
    final base   = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine  = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _SkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Карточка лекции — точно повторяет layout _buildLessonCard
    Widget lessonCard({double nameWidth = double.infinity}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.15 : 0.20)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: primary.withOpacity(0.18)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        box(52, 11, r: 4),
                        const SizedBox(width: 8),
                        box(48, 11, r: 4),
                      ]),
                      const SizedBox(height: 9),
                      box(nameWidth, 14, r: 6),
                      const SizedBox(height: 5),
                      box(nameWidth == double.infinity ? 200 : nameWidth * 0.7, 12, r: 5),
                      const SizedBox(height: 6),
                      box(140, 10, r: 4),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: box(36, 36, r: 10),
              ),
            ],
          ),
        ),
      ),
    );

    Widget dayHeader({bool withTodayBadge = false}) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 2),
      child: Row(
        children: [
          if (withTodayBadge) ...[
            box(8, 8, r: 99),
            const SizedBox(width: 8),
          ],
          box(withTodayBadge ? 90 : 110, 18, r: 6),
          if (withTodayBadge) ...[
            const SizedBox(width: 8),
            box(44, 18, r: 20),
          ],
          const Spacer(),
          box(80, 26, r: 12),
        ],
      ),
    );

    final systemBottom    = MediaQuery.of(context).viewPadding.bottom;
    final bottomClearance = _kNavBarContentHeight + systemBottom;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 80 + bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(170, 40, r: 20),
          const SizedBox(height: 2),
          dayHeader(withTodayBadge: true),
          lessonCard(),
          lessonCard(nameWidth: 220),
          dayHeader(),
          lessonCard(nameWidth: 240),
          lessonCard(),
          lessonCard(nameWidth: 200),
          dayHeader(),
          lessonCard(nameWidth: 260),
          lessonCard(),
        ],
      ),
    );
  }

  Widget _buildSemesterChips() {
    if (_semesters.isEmpty || _selectedSem == null) return const SizedBox.shrink();
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark  = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
      child: GestureDetector(
        onTap: () { HapticService.medium(); _showSemesterSheet(); },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.6)
                : primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primary.withOpacity(0.25), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_rounded, size: 16, color: primary),
              const SizedBox(width: 8),
              Text(_formatSemName(_selectedSem!.name),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary)),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: primary.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSemesterSheet() {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.45, minChildSize: 0.25, maxChildSize: 0.75,
        expand: false,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(alignment: Alignment.centerLeft,
                    child: Text(LanguageService.tr('schedule'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  children: _semesters.map((sem) {
                    final sel = _selectedSem == sem;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      onTap: () { HapticService.medium(); Navigator.pop(context); _switchSemester(sem); },
                      leading: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? primary : primary.withOpacity(0.08),
                        ),
                        child: Icon(sel ? Icons.check_rounded : Icons.layers_rounded,
                            size: 18, color: sel ? Colors.white : primary),
                      ),
                      title: Text(_formatSemName(sem.name),
                          style: TextStyle(
                            fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                            color: sel ? primary : theme.colorScheme.onSurface,
                            fontSize: 15,
                          )),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  static const _geoToTrKey = <String, String>{
    'გაზაფხულის': 'sem_spring',
    'ზაფხულის':   'sem_summer',
    'შემოდგომის': 'sem_autumn',
    'ზამთრის':    'sem_winter',
    'სემესტრი':   'sem_semester',
  };

  String _formatSemName(String rawName) {
    final lang = LanguageService.currentLang.value;
    String name = rawName.trim();
    if (lang != 'ქართული') {
      _geoToTrKey.forEach((geo, key) {
        if (name.contains(geo)) name = name.replaceAll(geo, LanguageService.tr(key));
      });
    }
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.length <= 24) return name;
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0]} ${parts[1]}';
    return '${name.substring(0, 20)}…';
  }

  // ─── БАННЕР КАНИКУЛ ─────────────────────────────────────────────

  Widget _buildVacationBanner(Color primary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Text('🏖️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(LanguageService.tr('vacation_today'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        ],
      ),
    );
  }

  // ─── СЕКЦИЯ ДНЯ ─────────────────────────────────────────────────

  Widget _buildDaySection(
      String day, List<Lesson> lessons, bool showBoth, bool isDark) {
    final theme   = Theme.of(context);
    final now     = DateTime.now();
    final today   = kWeekDays[now.weekday - 1];
    final isToday = day == today && !_isVacationDay;
    final date    = _nextDateForDay(day);
    final added   = LessonOverrideService.getAddedForDate(date);
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8, left: 2),
          child: Row(
            children: [
              if (isToday) ...[
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: primary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              Text(
                LanguageService.translateDay(day),
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isToday ? primary : theme.colorScheme.onSurface,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(LanguageService.tr('today'),
                      style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () { HapticService.medium(); _showAddLectureSheet(date); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: primary),
                      const SizedBox(width: 3),
                      Text(LanguageService.tr('add_lecture'),
                          style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ...lessons.map((l) => RepaintBoundary(
              child: _buildLessonCard(l, showBoth, isDark, date: date))),
        ...added.map((ov) => RepaintBoundary(
              child: _buildOverrideCard(ov, isDark))),
      ],
    );
  }

  // ─── КАРТОЧКА ДОБАВЛЕННОЙ ЛЕКЦИИ ─────────────────────────────────

  Widget _buildOverrideCard(LessonOverride ov, bool isDark) {
    final theme   = Theme.of(context);
    const accent  = Color(0xFF2563EB);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.30), width: 1.0),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              LanguageService.tr('added_lecture').toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700,
                                  color: accent, letterSpacing: 0.3),
                            ),
                          ),
                          if (ov.lessonTime.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(ov.lessonTime,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(LanguageService.translateName(ov.lessonName),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (ov.lessonTeacher.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            LanguageService.translateName(ov.lessonTeacher),
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.80)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Delete button
                  SizedBox(
                    width: 36, height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.40),
                      onPressed: () async {
                        await LessonOverrideService.remove(ov.id);
                        await NotificationService.notify(
                          title: LanguageService.tr('notif_lesson_removed_title'),
                          body:  ov.lessonName,
                          type:  NotificationType.lessonCancelled,
                          date:  ov.date,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── КАРТОЧКА ЛЕКЦИИ ────────────────────────────────────────────

  Widget _buildLessonCard(Lesson lesson, bool showBoth, bool isDark,
      {DateTime? date}) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final status  = _getLessonStatus(lesson.day, lesson.time);

    final targetDate = date ?? _nextDateForDay(lesson.day);
    final cancelled  = LessonOverrideService.isCancelled(
        lesson.name, lesson.teacher, targetDate);

    Color   accentColor = cancelled
        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.35)
        : primary;
    Widget? badge;

    // Вычисляем один раз и передаём в прогресс-бар, чтобы не вызывать повторно
    Map<String, dynamic>? timelineStatus;

    if (!cancelled) {
      if (status == 1) {
        timelineStatus  = _checkTimelineStatus(lesson.time);
        final isBrk    = timelineStatus['isBreak'] as bool? ?? false;
        final isHacker = themeNotifier.value == 'hacker';
        accentColor    = isBrk ? Colors.blue : (isHacker ? Colors.amber : Colors.green);
        String ph      = LanguageService.tr(timelineStatus['nameKey'] as String? ?? 'part');
        final pNum     = timelineStatus['partNumber'];
        if (pNum != null) ph = '$ph $pNum';
        badge = _StatusBadge(label: ph, color: accentColor);
      } else if (status == 2) {
        accentColor = Colors.orange;
        badge = _StatusBadge(label: LanguageService.tr('soon'), color: accentColor);
      } else if (status == -1) {
        accentColor = const Color(0xFF16A34A);
        badge = _StatusBadge(
            label: LanguageService.tr('done'), color: const Color(0xFF16A34A),
            icon: Icons.check_rounded);
      }
    } else {
      badge = _StatusBadge(
          label: LanguageService.tr('lesson_cancelled'),
          color: theme.colorScheme.onSurfaceVariant,
          icon: Icons.block_rounded);
    }

    String displayTime = lesson.time;
    if (displayTime.contains('-')) {
      displayTime = showBoth
          ? '${displayTime.split('-')[0].trim()} – ${displayTime.split('-')[1].trim()}'
          : displayTime.split('-')[0].trim();
    }

    final stripeColor = cancelled
        ? theme.colorScheme.outlineVariant.withOpacity(0.5)
        : accentColor;

    return Opacity(
      opacity: cancelled ? 0.50 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: status == 1 && !cancelled
                ? accentColor.withOpacity(0.40)
                : theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.22 : 0.28),
            width: status == 1 && !cancelled ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: (status == 1 && !cancelled ? accentColor : Colors.black)
                  .withOpacity(isDark ? 0.13 : 0.07),
              blurRadius: status == 1 && !cancelled ? 12 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 4, color: stripeColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule_rounded, size: 16, color: accentColor),
                        const SizedBox(width: 5),
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15,
                            color: accentColor, letterSpacing: 0.1,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 7),
                          badge,
                        ],
                        const Spacer(),
                        SizedBox(
                          width: 34, height: 34,
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: PopupMenuButton<String>(
                              padding:  EdgeInsets.zero,
                              iconSize: 18,
                              icon: Icon(Icons.more_vert_rounded,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.45)),
                              itemBuilder: (_) => [
                                if (!cancelled)
                                  PopupMenuItem(
                                    value: 'cancel',
                                    child: Row(children: [
                                      const Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                                      const SizedBox(width: 8),
                                      Text(LanguageService.tr('cancel_lecture'),
                                          style: const TextStyle(color: Color(0xFFDC2626))),
                                    ]),
                                  ),
                                if (cancelled)
                                  PopupMenuItem(
                                    value: 'restore',
                                    child: Row(children: [
                                      const Icon(Icons.restore_rounded, size: 16, color: Color(0xFF2563EB)),
                                      const SizedBox(width: 8),
                                      Text(LanguageService.tr('restore_lecture'),
                                          style: const TextStyle(color: Color(0xFF2563EB))),
                                    ]),
                                  ),
                              ],
                              onSelected: (val) async {
                                if (val == 'cancel') {
                                  await _cancelLesson(lesson, targetDate);
                                } else if (val == 'restore') {
                                  await _restoreLesson(lesson, targetDate);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(
                      LanguageService.translateName(lesson.name),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18, height: 1.25,
                        color: theme.colorScheme.onSurface, letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (lesson.teacher.isNotEmpty || lesson.room.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (lesson.teacher.isNotEmpty) ...[
                            Icon(Icons.person_outline_rounded, size: 15,
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.60)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                LanguageService.translateName(lesson.teacher),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.80),
                                  height: 1.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (lesson.room.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(isDark ? 0.15 : 0.09),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                    color: accentColor.withOpacity(0.28), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.meeting_room_outlined, size: 13,
                                      color: accentColor.withOpacity(0.80)),
                                  const SizedBox(width: 4),
                                  Text(lesson.room,
                                      style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w600,
                                        color: accentColor.withOpacity(0.85),
                                        letterSpacing: 0.2,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    if (status == 1 && !cancelled)
                      _buildProgressBar(lesson.time, accentColor, isDark,
                          precomputedStatus: timelineStatus),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ОТМЕНА / ВОССТАНОВЛЕНИЕ ЛЕКЦИИ ─────────────────────────────

  Future<void> _cancelLesson(Lesson lesson, DateTime date) async {
    final override = LessonOverride(
      id:            '${lesson.name}_${date.millisecondsSinceEpoch}_cancel',
      date:          date,
      lessonName:    lesson.name,
      lessonTeacher: lesson.teacher,
      lessonTime:    lesson.time,
      lessonRoom:    lesson.room,
      lessonCode:    lesson.code,
      isCancelled:   true,
    );
    await LessonOverrideService.add(override);
    await NotificationService.notify(
      title: LanguageService.tr('notif_lesson_cancelled_title'),
      body:  '${LanguageService.translateName(lesson.name)} · ${_formatDateShort(date)}',
      type:  NotificationType.lessonCancelled,
      date:  date,
    );
    if (mounted) setState(() {});
  }

  Future<void> _restoreLesson(Lesson lesson, DateTime date) async {
    final all = LessonOverrideService.getAll();
    for (final ov in all) {
      if (ov.isCancelled &&
          ov.lessonName == lesson.name &&
          _dateOnly(ov.date) == _dateOnly(date)) {
        await LessonOverrideService.remove(ov.id);
      }
    }
    await NotificationService.notify(
      title: LanguageService.tr('notif_lesson_restored_title'),
      body:  '${LanguageService.translateName(lesson.name)} · ${_formatDateShort(date)}',
      type:  NotificationType.lessonRestored,
      date:  date,
    );
    if (mounted) setState(() {});
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ─── BOTTOM SHEET ДОБАВЛЕНИЯ ЛЕКЦИИ ──────────────────────────────

  void _showAddLectureSheet(DateTime date) {
    final seen      = <String>{};
    final allLessons = <Lesson>[];
    for (final list in _groupedLessons.values) {
      for (final l in list) {
        final key = l.name.trim().toLowerCase();
        if (key.isNotEmpty && seen.add(key)) allLessons.add(l);
      }
    }
    allLessons.sort((a, b) => a.name.compareTo(b.name));

    final cancelled = LessonOverrideService.getCancelled()
        .where((ov) => _dateOnly(ov.date) == _dateOnly(date))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddLectureSheet(
        date:       date,
        allLessons: allLessons,
        cancelled:  cancelled,
        onDone:     () { if (mounted) setState(() {}); },
      ),
    );
  }

  // ─── ПРОГРЕСС-БАР ───────────────────────────────────────────────

  Widget _buildProgressBar(String timeStr, Color color, bool isDark,
      {Map<String, dynamic>? precomputedStatus}) {
    final theme   = Theme.of(context);
    final status  = precomputedStatus ?? _checkTimelineStatus(timeStr);
    final elapsed = (status['elapsed'] as int?) ?? 0;
    final phases  = (status['phases'] as List?)?.cast<LessonPhase>() ?? [];

    if (phases.isEmpty) return const SizedBox.shrink();

    final nameKey  = status['nameKey'] as String? ?? 'part';
    final pNum     = status['partNumber'];
    String pLabel  = LanguageService.tr(nameKey);
    if (pNum != null) pLabel = '$pLabel $pNum';
    final timeLeft  = (status['timeLeft']     as int?)  ?? 0;
    final isBrk     = (status['isBreak']      as bool?) ?? false;
    final totalMins = (status['totalMinutes'] as int?)  ?? 1;
    final globalProg = (elapsed / totalMins).clamp(0.0, 1.0);

    final activeColor = isBrk ? const Color(0xFF3B82F6) : color;
    final bgColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isBrk)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.coffee_rounded, size: 11, color: activeColor),
                ),
              Text(pLabel,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: activeColor, letterSpacing: 0.2,
                  )),
              const SizedBox(width: 4),
              Text(
                '· $timeLeft ${LanguageService.tr('min')} ${LanguageService.tr('left')}',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.70),
                ),
              ),
              const Spacer(),
              Text('${(globalProg * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: activeColor.withOpacity(0.80),
                  )),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 4,
            child: Row(
              children: List.generate(phases.length * 2 - 1, (idx) {
                if (idx.isOdd) {
                  return Container(width: 2, color: theme.scaffoldBackgroundColor);
                }
                final phIdx = idx ~/ 2;
                final ph    = phases[phIdx];

                int acc = 0;
                for (int k = 0; k < phIdx; k++) acc += phases[k].durationMins;
                final prog = elapsed > acc
                    ? ((elapsed - acc) / ph.durationMins).clamp(0.0, 1.0)
                    : 0.0;

                final segColor = ph.isBreak ? const Color(0xFF3B82F6) : color;
                final isFirst  = phIdx == 0;
                final isLast   = phIdx == phases.length - 1;

                return Expanded(
                  flex: ph.durationMins,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft:     isFirst ? const Radius.circular(2) : Radius.zero,
                      bottomLeft:  isFirst ? const Radius.circular(2) : Radius.zero,
                      topRight:    isLast  ? const Radius.circular(2) : Radius.zero,
                      bottomRight: isLast  ? const Radius.circular(2) : Radius.zero,
                    ),
                    child: LinearProgressIndicator(
                      value: prog,
                      backgroundColor: bgColor,
                      valueColor: AlwaysStoppedAnimation<Color>(segColor),
                      minHeight: 4,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BottomSheet добавления / восстановления лекции ───────────────

class _AddLectureSheet extends StatefulWidget {
  final DateTime             date;
  final List<Lesson>         allLessons;
  final List<LessonOverride> cancelled;
  final VoidCallback         onDone;

  const _AddLectureSheet({
    required this.date,
    required this.allLessons,
    required this.cancelled,
    required this.onDone,
  });

  @override
  State<_AddLectureSheet> createState() => _AddLectureSheetState();
}

class _AddLectureSheetState extends State<_AddLectureSheet> {
  Lesson? _pickedLesson;
  String? _pickedTimeOverride;

  final _nameCtrl    = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _roomCtrl    = TextEditingController();
  String _manualTime = '';

  bool _showManual     = false;
  bool _showLessonList = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<String?> _pickLessonTime(String initial) async {
    final part  = initial.split('-').first.trim();
    final parts = part.split(':');
    int initH = 8, initM = 0;
    if (parts.length == 2) {
      initH = int.tryParse(parts[0]) ?? 8;
      initM = int.tryParse(parts[1]) ?? 0;
    }
    int selH = initH, selM = initM;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          height: 280,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(99),
                  )),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(LanguageService.tr('time'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: () {
                        final h = selH.toString().padLeft(2, '0');
                        final m = selM.toString().padLeft(2, '0');
                        Navigator.pop(ctx, '$h:$m');
                      },
                      child: Text(LanguageService.tr('save_lecture'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (ctx2, setSt) => Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: initH),
                          itemExtent: 44,
                          onSelectedItemChanged: (v) => selH = v,
                          children: List.generate(24, (h) => Center(
                            child: Text(h.toString().padLeft(2, '0'),
                                style: TextStyle(fontSize: 22,
                                    color: theme.colorScheme.onSurface)),
                          )),
                        ),
                      ),
                      Text(':', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface)),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: initM),
                          itemExtent: 44,
                          onSelectedItemChanged: (v) => selM = v,
                          children: List.generate(60, (m) => Center(
                            child: Text(m.toString().padLeft(2, '0'),
                                style: TextStyle(fontSize: 22,
                                    color: theme.colorScheme.onSurface)),
                          )),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final String name;
    final String teacher;
    final String time;
    final String room;
    final String code;

    if (_showManual || _pickedLesson == null) {
      name    = _nameCtrl.text.trim();
      teacher = _teacherCtrl.text.trim();
      time    = _manualTime;
      room    = _roomCtrl.text.trim();
      code    = '';
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.tr('bug_fill_required'))));
        return;
      }
    } else {
      name    = _pickedLesson!.name;
      teacher = _pickedLesson!.teacher;
      time    = _pickedTimeOverride ?? _pickedLesson!.time;
      room    = _pickedLesson!.room;
      code    = _pickedLesson!.code;
    }

    final id = '${name}_${widget.date.millisecondsSinceEpoch}_added';

    final override = LessonOverride(
      id:            id,
      date:          widget.date,
      lessonName:    name,
      lessonTeacher: teacher,
      lessonTime:    time,
      lessonRoom:    room,
      lessonCode:    code,
      isAdded:       true,
    );

    await LessonOverrideService.add(override);

    await NotificationService.notify(
      title: LanguageService.tr('notif_lesson_added_title'),
      body:  '$name · ${_fmtDate(widget.date)}',
      type:  NotificationType.lessonAdded,
      date:  widget.date,
    );

    if (mounted) Navigator.pop(context);
    widget.onDone();
  }

  Future<void> _restore(LessonOverride ov) async {
    await LessonOverrideService.remove(ov.id);

    final id = '${ov.lessonName}_${widget.date.millisecondsSinceEpoch}_restored';

    final override = LessonOverride(
      id:            id,
      date:          widget.date,
      lessonName:    ov.lessonName,
      lessonTeacher: ov.lessonTeacher,
      lessonTime:    ov.lessonTime,
      lessonRoom:    ov.lessonRoom,
      lessonCode:    ov.lessonCode,
      isAdded:       true,
    );
    await LessonOverrideService.add(override);

    await NotificationService.notify(
      title: LanguageService.tr('notif_lesson_restored_title'),
      body:  '${ov.lessonName} · ${_fmtDate(widget.date)}',
      type:  NotificationType.lessonRestored,
      date:  widget.date,
    );

    if (mounted) Navigator.pop(context);
    widget.onDone();
  }

  static String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dateStr = _fmtDate(widget.date);

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize:     0.40,
      maxChildSize:     0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(99),
                )),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LanguageService.tr('add_lecture'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(dateStr,
                        style: TextStyle(fontSize: 13, color: primary,
                            fontWeight: FontWeight.w600)),
                  ],
                )),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 32 + MediaQuery.of(context).viewInsets.bottom),
                children: [

                  // ── Restore cancelled section ──────────────────────
                  if (widget.cancelled.isNotEmpty) ...[
                    _SectionLabel(LanguageService.tr('restore_cancelled')),
                    const SizedBox(height: 8),
                    ...widget.cancelled.map((ov) => _CancelledTile(
                      lessonData: ov,
                      onRestore:  () => _restore(ov),
                    )),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (!_showLessonList && !_showManual)
                      TextButton.icon(
                        onPressed: () => setState(() => _showLessonList = true),
                        icon:  const Icon(Icons.add_rounded, size: 16),
                        label: Text(LanguageService.tr('add_new_lecture')),
                      ),
                    const SizedBox(height: 8),
                  ],

                  // ── Pick subject ───────────────────────────────────
                  if (!_showManual && (widget.cancelled.isEmpty || _showLessonList)) ...[
                    _SectionLabel(LanguageService.tr('pick_subject')),
                    const SizedBox(height: 8),
                    ...widget.allLessons.map((l) {
                      final sel = l == _pickedLesson;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => setState(() {
                          _pickedLesson       = l;
                          _pickedTimeOverride = null;
                        }),
                        leading: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel ? primary : primary.withOpacity(0.08),
                          ),
                          child: Icon(
                            sel ? Icons.check_rounded : Icons.book_outlined,
                            size: 18,
                            color: sel ? Colors.white : primary,
                          ),
                        ),
                        title: Text(
                          LanguageService.translateName(l.name),
                          style: TextStyle(
                            fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                            color: sel ? primary : null,
                          ),
                        ),
                        subtitle: l.teacher.isNotEmpty
                            ? Text(LanguageService.translateName(l.teacher),
                                style: TextStyle(fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant))
                            : null,
                        trailing: l.time.isNotEmpty
                            ? Text(l.time.split('-').first.trim(),
                                style: TextStyle(fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant))
                            : null,
                      );
                    }),
                    if (_pickedLesson != null) ...[
                      const SizedBox(height: 8),
                      _TimePickerRow(
                        label:   LanguageService.tr('time'),
                        value:   _pickedTimeOverride ?? _pickedLesson!.time,
                        primary: primary,
                        theme:   theme,
                        onTap: () async {
                          final t = await _pickLessonTime(
                              _pickedTimeOverride ?? _pickedLesson!.time);
                          if (t != null) setState(() => _pickedTimeOverride = t);
                        },
                        onClear: _pickedTimeOverride != null
                            ? () => setState(() => _pickedTimeOverride = null)
                            : null,
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _showManual   = true;
                        _pickedLesson = null;
                      }),
                      icon:  const Icon(Icons.edit_rounded, size: 16),
                      label: Text(LanguageService.tr('enter_manually')),
                    ),
                  ] else ...[
                    // ── Manual entry ─────────────────────────────────
                    _SectionLabel(LanguageService.tr('enter_manually')),
                    const SizedBox(height: 8),
                    _TextField(ctrl: _nameCtrl,    label: LanguageService.tr('lesson_name'), icon: Icons.book_outlined),
                    const SizedBox(height: 10),
                    _TextField(ctrl: _teacherCtrl, label: LanguageService.tr('teacher'),     icon: Icons.person_outline_rounded),
                    const SizedBox(height: 10),
                    _TimePickerRow(
                      label:   LanguageService.tr('time'),
                      value:   _manualTime,
                      primary: primary,
                      theme:   theme,
                      onTap: () async {
                        final t = await _pickLessonTime(_manualTime);
                        if (t != null) setState(() => _manualTime = t);
                      },
                      onClear: _manualTime.isNotEmpty
                          ? () => setState(() => _manualTime = '')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _TextField(ctrl: _roomCtrl, label: LanguageService.tr('room'), icon: Icons.meeting_room_outlined),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _showManual = false),
                      icon:  const Icon(Icons.list_rounded, size: 16),
                      label: Text(LanguageService.tr('pick_subject')),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Save button ────────────────────────────────────
                  FilledButton.icon(
                    onPressed: _save,
                    icon:  const Icon(Icons.check_rounded),
                    label: Text(LanguageService.tr('save_lecture')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
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

// ─── Shared helper widgets ────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ));
}

class _TextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String   label;
  final IconData icon;
  const _TextField({required this.ctrl, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    decoration: InputDecoration(
      labelText:    label,
      prefixIcon:   Icon(icon, size: 18),
      border:       OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense:      true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class _TimePickerRow extends StatelessWidget {
  final String      label;
  final String      value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final Color       primary;
  final ThemeData   theme;

  // ignore: prefer_const_constructors_in_immutables
  _TimePickerRow({
    required this.label, required this.value,
    required this.onTap, required this.primary, required this.theme,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = value.isEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(
            color: isEmpty
                ? theme.colorScheme.outline.withOpacity(0.5)
                : primary.withOpacity(0.6),
            width: isEmpty ? 1 : 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isEmpty ? Colors.transparent : primary.withOpacity(0.06),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18,
                color: isEmpty ? theme.colorScheme.onSurfaceVariant : primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isEmpty ? label : value,
                style: TextStyle(
                  fontSize: 14,
                  color: isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (!isEmpty && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 16,
                    color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Icon(Icons.expand_more_rounded, size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CancelledTile extends StatelessWidget {
  final LessonOverride lessonData;
  final VoidCallback   onRestore;
  // ignore: prefer_const_constructors_in_immutables
  _CancelledTile({required this.lessonData, required this.onRestore});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.2)),
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(LanguageService.translateName(lessonData.lessonName),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            if (lessonData.lessonTeacher.isNotEmpty)
              Text(lessonData.lessonTeacher,
                  style: TextStyle(fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant)),
          ],
        )),
        TextButton(
          onPressed: onRestore,
          child: Text(LanguageService.tr('restore')),
        ),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String    label;
  final Color     color;
  final IconData? icon;
  const _StatusBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(icon != null ? 0.12 : 1.0),
          borderRadius: BorderRadius.circular(8),
          border: icon != null ? Border.all(color: color.withOpacity(0.35)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: icon != null ? color : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

// ─── Shimmer-прямоугольник для скелетона ─────────────────────────
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width:  widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(widget.base, widget.shine, _anim.value),
      ),
    ),
  );
}
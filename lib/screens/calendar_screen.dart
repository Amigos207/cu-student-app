// lib/screens/calendar_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../models/lesson.dart';
import '../models/lesson_override.dart';
import '../models/exam_entry.dart';
import '../services/parser.dart';
import '../services/language.dart';
import '../services/lesson_override_service.dart';
import '../services/notification_service.dart';
import '../models/notification_item.dart';
import 'schedule_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Map<String, List<Lesson>>  _groupedLessons = {};
  Map<DateTime, Set<String>> _teachersByDate = {};
  List<ExamEntry>            _examEntries    = [];
  bool                       _loading        = true;

  bool      _yearView      = false;
  DateTime  _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _calendarSelected;
  DateTime? _blinkDate;
  bool      _blinkVisible  = true;

  static const _weekDays = [
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday',
  ];

  static String _normTeacher(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static bool _teacherMatch(String a, String b) {
    final na = _normTeacher(a), nb = _normTeacher(b);
    return na.isNotEmpty && nb.isNotEmpty && (na.contains(nb) || nb.contains(na));
  }

  static DateTime? _parseDateStr(String s) {
    final parts = s.split('/');
    if (parts.length != 3) return null;
    try {
      return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) { return null; }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    ScheduleScreen.highlightRequest.addListener(_handleHighlight);
    LessonOverrideService.version.addListener(_onOverridesChanged);
    final pending = ScheduleScreen.highlightRequest.value;
    if (pending != null) {
      ScheduleScreen.highlightRequest.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyHighlight(pending));
    }
  }

  void _onOverridesChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    ScheduleScreen.highlightRequest.removeListener(_handleHighlight);
    LessonOverrideService.version.removeListener(_onOverridesChanged);
    super.dispose();
  }

  void _handleHighlight() {
    final date = ScheduleScreen.highlightRequest.value;
    if (date == null || !mounted) return;
    ScheduleScreen.highlightRequest.value = null;
    _applyHighlight(date);
  }

  void _applyHighlight(DateTime date) {
    setState(() {
      _yearView         = false;
      _calendarMonth    = DateTime(date.year, date.month);
      _calendarSelected = date;
      _blinkDate        = date;
      _blinkVisible     = true;
    });
    _startBlink(date);
  }

  void _startBlink(DateTime date) async {
    for (int i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 280));
      if (!mounted || _blinkDate != date) return;
      setState(() => _blinkVisible = !_blinkVisible);
    }
    if (mounted) setState(() { _blinkDate = null; _blinkVisible = true; });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final lessons        = await Parser.parseSchedule();
      final attendanceList = await Parser.parseAttendance(lessons);

      final teachersByDate = <DateTime, Set<String>>{};
      for (final a in attendanceList) {
        final id = a.teacher.isNotEmpty ? a.teacher : a.subject;
        for (final r in a.records) {
          if (r.isDateReal && r.date.isNotEmpty) {
            final d = _parseDateStr(r.date);
            if (d != null && id.isNotEmpty) {
              teachersByDate.putIfAbsent(d, () => <String>{}).add(id);
            }
          }
        }
      }

      final grouped = <String, List<Lesson>>{};
      for (final l in lessons) {
        if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
      }
      grouped.forEach((_, list) => list.sort((a, b) => a.time.compareTo(b.time)));

      final (_, exams) = await Parser.fetchExams();

      if (mounted) {
        setState(() {
          _groupedLessons = grouped;
          _teachersByDate = teachersByDate;
          _examEntries    = exams;
          _loading        = false;
        });
      }
    } catch (e) {
      debugPrint('CalendarScreen._loadData ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Set<DateTime> get _lectureDates => _teachersByDate.keys.toSet();

  List<ExamEntry> _examsOnDate(DateTime date) => _examEntries.where((e) {
    final d = e.date;
    return d.year == date.year && d.month == date.month && d.day == date.day;
  }).toList();

  List<Lesson> _lessonsOnDate(DateTime date) {
    final identifiers = _teachersByDate[date];
    if (identifiers == null || identifiers.isEmpty) return const [];
    final dayName = _weekDays[date.weekday - 1];
    final allDay  = _groupedLessons[dayName] ?? [];
    return allDay.where((l) {
      if (l.teacher.isEmpty && l.name.isEmpty) return true;
      return identifiers.any((id) =>
          _teacherMatch(l.teacher, id) || _teacherMatch(l.name, id));
    }).toList();
  }

  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  Widget _buildSkeleton(Color primary, bool isDark, ThemeData theme) {
    final base  = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _CalSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Реальные данные для сетки (не ждут загрузки)
    final now         = DateTime.now();
    final firstDay    = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_calendarMonth.year, _calendarMonth.month);
    final startOffset = (firstDay.weekday - 1) % 7;
    const dayLabels   = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final today       = DateTime(now.year, now.month, now.day);

    // Имитирует карточку урока (без данных)
    Widget lessonCard({double nameWidth = double.infinity}) => Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.18 : 0.25)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4,
                  color: primary.withOpacity(isDark ? 0.35 : 0.25)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(52, 11, r: 4),
                      const SizedBox(height: 7),
                      box(nameWidth, 14, r: 5),
                      const SizedBox(height: 5),
                      box(nameWidth == double.infinity ? 180 : nameWidth * 0.7, 12, r: 4),
                      const SizedBox(height: 6),
                      box(120, 10, r: 4),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                child: box(32, 32, r: 9),
              ),
            ],
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          children: [
            // Шапка месяца — реальные данные, не шиммер
            Row(children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () { HapticService.medium(); setState(() {
                  _calendarMonth = DateTime(
                      _calendarMonth.year, _calendarMonth.month - 1);
                }); },
              ),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    '${_monthName(_calendarMonth.month)} ${_calendarMonth.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 20,
                      color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () { HapticService.medium(); setState(() {
                  _calendarMonth = DateTime(
                      _calendarMonth.year, _calendarMonth.month + 1);
                }); },
              ),
            ]),

            // День-лейблы
            Row(
              children: dayLabels.map((d) => Expanded(
                child: Center(child: Text(d, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold,
                  color: (d == 'Sa' || d == 'Su')
                      ? theme.colorScheme.onSurfaceVariant.withOpacity(0.5)
                      : theme.colorScheme.onSurfaceVariant,
                ))),
              )).toList(),
            ),
            const SizedBox(height: 4),

            // Сетка дней — числа реальные, точки событий шиммер-кружком
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 1),
              itemCount: startOffset + daysInMonth,
              itemBuilder: (_, idx) {
                if (idx < startOffset) return const SizedBox.shrink();
                final day  = idx - startOffset + 1;
                final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
                final isToday = date == today;
                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday ? primary.withOpacity(0.15) : null,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Text('$day', style: TextStyle(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday ? primary : theme.colorScheme.onSurface,
                    )),
                    // Шиммер-точка вместо реальных событий
                    Positioned(
                      bottom: 4,
                      child: _CalSkeletonBox(
                        width: 5, height: 5, radius: 99,
                        base: base, shine: shine,
                      ),
                    ),
                  ]),
                );
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark  = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.tr('calendar'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      body: _loading
          ? _buildSkeleton(primary, isDark, theme)
          : RefreshIndicator(
              color: primary,
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _yearView
                        ? _buildYearView(primary, isDark, theme)
                        : _buildMonthView(primary, isDark, theme),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 24 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildYearView(Color primary, bool isDark, ThemeData theme) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const examRed = Color(0xFFC62828);
    final year  = _calendarMonth.year;

    Widget miniMonth(int month) {
      final firstDay    = DateTime(year, month, 1);
      final daysInMonth = DateUtils.getDaysInMonth(year, month);
      final startOffset = (firstDay.weekday - 1) % 7;
      final isCurrentMonth = month == now.month && year == now.year;

      return GestureDetector(
        onTap: () => setState(() {
          _calendarMonth = DateTime(year, month);
          _yearView = false;
        }),
        child: Container(
          decoration: BoxDecoration(
            color: isCurrentMonth
                ? primary.withOpacity(isDark ? 0.15 : 0.07)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: isCurrentMonth
                ? Border.all(color: primary.withOpacity(0.35), width: 1.5)
                : Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.18 : 0.10)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.10 : 0.04),
                  blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Text(_monthName(month),
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  color: isCurrentMonth ? primary : theme.colorScheme.onSurface,
                )),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 1),
              itemCount: startOffset + daysInMonth,
              itemBuilder: (_, idx) {
                if (idx < startOffset) return const SizedBox.shrink();
                final day  = idx - startOffset + 1;
                final date = DateTime(year, month, day);
                final isToday    = date == today;
                final hasLecture = _lectureDates.contains(date);
                final hasExam    = _examsOnDate(date).isNotEmpty;
                Color? bg;
                Color  fg = theme.colorScheme.onSurface;
                if (isToday) { bg = primary.withOpacity(0.85); fg = Colors.white; }
                return Container(
                  margin: const EdgeInsets.all(0.5),
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Stack(alignment: Alignment.center, children: [
                    Text('$day', style: TextStyle(
                        fontSize: 7,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: fg)),
                    if (!isToday && (hasLecture || hasExam))
                      Positioned(bottom: 1,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (hasLecture)
                            Container(width: 3, height: 3,
                                decoration: BoxDecoration(color: primary, shape: BoxShape.circle)),
                          if (hasLecture && hasExam) const SizedBox(width: 1),
                          if (hasExam)
                            Container(width: 3, height: 3,
                                decoration: const BoxDecoration(color: examRed, shape: BoxShape.circle)),
                        ]),
                      ),
                  ]),
                );
              },
            ),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() =>
                _calendarMonth = DateTime(year - 1, _calendarMonth.month)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _yearView = false),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$year',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_up_rounded, size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(() =>
                _calendarMonth = DateTime(year + 1, _calendarMonth.month)),
          ),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10, mainAxisSpacing: 10,
          childAspectRatio: 0.9,
          children: List.generate(12, (i) => miniMonth(i + 1)),
        ),
      ]),
    );
  }

  Widget _buildMonthView(Color primary, bool isDark, ThemeData theme) {
    const examRed     = Color(0xFFC62828);
    final now         = DateTime.now();
    final today       = DateTime(now.year, now.month, now.day);
    final firstDay    = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_calendarMonth.year, _calendarMonth.month);
    final startOffset = (firstDay.weekday - 1) % 7;
    const dayLabels   = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    Widget? dayDetail;
    if (_calendarSelected != null) {
      final sel     = _calendarSelected!;
      final lessons = _lessonsOnDate(sel);
      final exams   = _examsOnDate(sel);
      final added   = LessonOverrideService.getAddedForDate(sel);

      final addBtn = Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: OutlinedButton.icon(
          onPressed: () => _showAddLectureSheet(sel),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(LanguageService.tr('add_lecture')),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: primary.withOpacity(0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

      if (lessons.isEmpty && exams.isEmpty && added.isEmpty) {
        dayDetail = Column(children: [
          addBtn,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(LanguageService.tr('no_data'),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ),
          ),
        ]);
      } else {
        dayDetail = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('${sel.day} ${_monthName(sel.month)} ${sel.year}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primary)),
          ),
          addBtn,
          for (final exam in exams)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildExamCard(exam, isDark, theme, examRed)),
          for (final l in lessons)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildLessonCard(l, isDark, date: sel, theme: theme, primary: primary)),
          for (final ov in added)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildOverrideCard(ov, isDark, theme)),
          const SizedBox(height: 8),
        ]);
      }
    }

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if (d.primaryVelocity == null) return;
        if (d.primaryVelocity! < -300) {
          setState(() {
            _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
            _calendarSelected = null;
          });
        } else if (d.primaryVelocity! > 300) {
          setState(() {
            _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1);
            _calendarSelected = null;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() {
                _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1);
                _calendarSelected = null;
              }),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _yearView = true),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${_monthName(_calendarMonth.month)} ${_calendarMonth.year}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 20,
                      color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => setState(() {
                _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                _calendarSelected = null;
              }),
            ),
          ]),

          if (_examEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Dot(color: primary), const SizedBox(width: 4),
                Text(LanguageService.tr('lecture'),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                const _Dot(color: Color(0xFFC62828)), const SizedBox(width: 4),
                Text(LanguageService.tr('exams'),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),

          Row(
            children: dayLabels.map((d) => Expanded(
              child: Center(child: Text(d, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold,
                color: (d == 'Sa' || d == 'Su')
                    ? theme.colorScheme.onSurfaceVariant.withOpacity(0.5)
                    : theme.colorScheme.onSurfaceVariant,
              ))),
            )).toList(),
          ),
          const SizedBox(height: 4),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, childAspectRatio: 1),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < startOffset) return const SizedBox.shrink();
              final day        = idx - startOffset + 1;
              final date       = DateTime(_calendarMonth.year, _calendarMonth.month, day);
              final isToday    = date == today;
              final isSelected = date == _calendarSelected;
              final hasLecture = _lectureDates.contains(date);
              final hasExam    = _examsOnDate(date).isNotEmpty;
              final hasAdded   = LessonOverrideService.getAddedForDate(date).isNotEmpty;
              final isBlink    = _blinkDate != null &&
                  _blinkDate!.year == date.year &&
                  _blinkDate!.month == date.month &&
                  _blinkDate!.day == date.day;

              Color? bgColor;
              Color textColor = theme.colorScheme.onSurface;
              if (isSelected) {
                bgColor = hasExam ? examRed : primary; textColor = Colors.white;
              } else if (isBlink && _blinkVisible) {
                bgColor = primary.withOpacity(0.55); textColor = Colors.white;
              } else if (isToday) {
                bgColor = (hasExam ? examRed : primary).withOpacity(0.15);
                textColor = hasExam ? examRed : primary;
              }

              return GestureDetector(
                onTap: () { HapticService.medium(); setState(() {
                  _calendarSelected = isSelected ? null : date;
                }); },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Stack(alignment: Alignment.center, children: [
                    Text('$day', style: TextStyle(
                      fontSize: 14,
                      fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                      color: textColor,
                    )),
                    if (!isSelected && (hasLecture || hasExam || hasAdded))
                      Positioned(bottom: 4,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (hasLecture || hasAdded)
                            Container(
                              width: 5, height: 5,
                              margin: hasExam ? const EdgeInsets.only(right: 2) : EdgeInsets.zero,
                              decoration: BoxDecoration(
                                  color: isToday ? primary : primary.withOpacity(0.7),
                                  shape: BoxShape.circle),
                            ),
                          if (hasExam)
                            Container(width: 5, height: 5,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFC62828), shape: BoxShape.circle)),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 12),
          if (dayDetail != null) dayDetail,
        ]),
      ),
    );
  }

  Widget _buildExamCard(ExamEntry exam, bool isDark, ThemeData theme, Color red) {
    final lang      = LanguageService.currentLang.value;
    final name      = lang == 'ქართული' ? exam.nameKa : (exam.nameEn.isNotEmpty ? exam.nameEn : exam.nameKa);
    final isPast    = !exam.isUpcoming;
    const green     = Color(0xFF16A34A);
    final cardColor = isPast ? green : red;

    return Opacity(
      opacity: isPast ? 0.70 : 1.0,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withOpacity(isPast ? 0.35 : 0.45), width: isPast ? 1.0 : 1.5),
          boxShadow: [BoxShadow(
              color: cardColor.withOpacity(isDark ? 0.10 : 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: red),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(isPast ? Icons.check_circle_rounded : Icons.quiz_rounded,
                    size: 14, color: isPast ? green : red),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      isPast ? LanguageService.tr('exam_past').toUpperCase()
                             : LanguageService.tr('exams').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: isPast ? green : const Color(0xFFC62828))),
                ),
                if (exam.time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(exam.time, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC62828))),
                ],
              ]),
              const SizedBox(height: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.2)),
              if (exam.teacher.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text(exam.teacher,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _buildLessonCard(Lesson lesson, bool isDark,
      {required DateTime date, required ThemeData theme, required Color primary}) {
    final cancelled   = LessonOverrideService.isCancelled(lesson.name, lesson.teacher, date);
    final accentColor = cancelled
        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.35)
        : primary;

    return Opacity(
      opacity: cancelled ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.06),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.18 : 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(Icons.schedule_rounded, size: 13, color: accentColor),
              const SizedBox(width: 4),
              Text(lesson.time.contains('-')
                  ? lesson.time.split('-').first.trim() : lesson.time,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: accentColor)),
              if (lesson.room.isNotEmpty) ...[
                const SizedBox(width: 10),
                Icon(Icons.meeting_room_outlined, size: 13,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(lesson.room,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ],
              const Spacer(),
              SizedBox(
                width: 32, height: 32,
                child: Theme(
                  data: Theme.of(context).copyWith(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(Icons.more_vert_rounded,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.45)),
                    itemBuilder: (_) => [
                      if (!cancelled)
                        PopupMenuItem(value: 'cancel',
                          child: Row(children: [
                            const Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Text(LanguageService.tr('cancel_lecture'),
                                style: const TextStyle(color: Color(0xFFDC2626))),
                          ])),
                      if (cancelled)
                        PopupMenuItem(value: 'restore',
                          child: Row(children: [
                            const Icon(Icons.restore_rounded, size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                            Text(LanguageService.tr('restore_lecture'),
                                style: const TextStyle(color: Color(0xFF2563EB))),
                          ])),
                    ],
                    onSelected: (val) async {
                      if (val == 'cancel') await _cancelLesson(lesson, date);
                      if (val == 'restore') await _restoreLesson(lesson, date);
                    },
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(LanguageService.translateName(lesson.name),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                    color: theme.colorScheme.onSurface),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (lesson.teacher.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.person_outline_rounded, size: 13,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
                const SizedBox(width: 4),
                Expanded(child: Text(LanguageService.translateName(lesson.teacher),
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildOverrideCard(LessonOverride ov, bool isDark, ThemeData theme) {
    const accent = Color(0xFF2563EB);
    return Container(
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
        child: Stack(children: [
          Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Column(
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
                      child: Text(LanguageService.tr('added_lecture').toUpperCase(),
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w700,
                              color: accent, letterSpacing: 0.3)),
                    ),
                    if (ov.lessonTime.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.schedule_rounded, size: 11, color: accent),
                      const SizedBox(width: 3),
                      Text(ov.lessonTime,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                    ],
                    if (ov.lessonRoom.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.meeting_room_outlined, size: 11, color: accent.withOpacity(0.7)),
                      const SizedBox(width: 3),
                      Text(ov.lessonRoom,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                              color: accent.withOpacity(0.85))),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(LanguageService.translateName(ov.lessonName),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (ov.lessonTeacher.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.person_outline_rounded, size: 12,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.65)),
                      const SizedBox(width: 3),
                      Expanded(child: Text(LanguageService.translateName(ov.lessonTeacher),
                          style: TextStyle(fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.80)),
                          overflow: TextOverflow.ellipsis, maxLines: 1)),
                    ]),
                  ],
                ],
              )),
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
            ]),
          ),
        ]),
      ),
    );
  }

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
      body:  LanguageService.translateName(lesson.name),
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
      body:  LanguageService.translateName(lesson.name),
      type:  NotificationType.lessonRestored,
      date:  date,
    );
    if (mounted) setState(() {});
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _showAddLectureSheet(DateTime date) {
    final seen       = <String>{};
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
      builder: (_) => _CalendarAddSheet(
        date:       date,
        allLessons: allLessons,
        cancelled:  cancelled,
        onDone:     () { if (mounted) setState(() {}); },
      ),
    );
  }

  static const _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];
  String _monthName(int m) => (m >= 1 && m <= 12) ? _monthNames[m - 1] : '';
}

// ── Small dot legend widget ───────────────────────────────────────
class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}


// ─────────────────────────────────────────────────────────────────────────────
// _CalendarAddSheet — 2-step bottom sheet
//
//  Step 0: pick subject from list OR enter manually
//  Step 1: set lesson time + select room via dual wheel picker (A/B/C × 1–30)
//          Reminders removed — will be re-added in a future stable release.
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarAddSheet extends StatefulWidget {
  final DateTime             date;
  final List<Lesson>         allLessons;
  final List<LessonOverride> cancelled;
  final VoidCallback         onDone;
  const _CalendarAddSheet({
    required this.date, required this.allLessons,
    required this.cancelled, required this.onDone,
  });
  @override
  State<_CalendarAddSheet> createState() => _CalendarAddSheetState();
}

class _CalendarAddSheetState extends State<_CalendarAddSheet> {
  // ── step 0 ────────────────────────────────────────────────────────
  int     _step       = 0;
  Lesson? _picked;
  bool    _showManual = false;
  final   _nameCtrl    = TextEditingController();
  final   _teacherCtrl = TextEditingController();

  // ── step 1 — lesson time ──────────────────────────────────────────
  int _lessonHour   = 10;
  int _lessonMinute = 0;
  late final FixedExtentScrollController _lHourCtrl;
  late final FixedExtentScrollController _lMinCtrl;

  // ── step 1 — room selector (A/B/C × 1–30) ────────────────────────
  static const _roomLetters = ['A', 'B', 'C'];
  int _roomLetterIndex = 0;
  int _roomNumber      = 1; // 1–30
  late final FixedExtentScrollController _roomLetterCtrl;
  late final FixedExtentScrollController _roomNumberCtrl;

  String get _selectedRoom => '${_roomLetters[_roomLetterIndex]}$_roomNumber';

  @override
  void initState() {
    super.initState();
    _lHourCtrl      = FixedExtentScrollController(initialItem: _lessonHour);
    _lMinCtrl       = FixedExtentScrollController(initialItem: _lessonMinute);
    _roomLetterCtrl = FixedExtentScrollController(initialItem: _roomLetterIndex);
    _roomNumberCtrl = FixedExtentScrollController(initialItem: _roomNumber - 1);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _teacherCtrl.dispose();
    _lHourCtrl.dispose(); _lMinCtrl.dispose();
    _roomLetterCtrl.dispose(); _roomNumberCtrl.dispose();
    super.dispose();
  }

  static String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  bool get _step0Valid =>
      _showManual ? _nameCtrl.text.trim().isNotEmpty : _picked != null;

  Future<void> _save() async {
    final name    = _showManual ? _nameCtrl.text.trim()    : (_picked?.name    ?? '');
    final teacher = _showManual ? _teacherCtrl.text.trim() : (_picked?.teacher ?? '');
    final code    = _showManual ? ''                        : (_picked?.code   ?? '');
    if (name.isEmpty) return;

    final hh      = _lessonHour.toString().padLeft(2, '0');
    final mm      = _lessonMinute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';
    final id      = '${name}_${widget.date.millisecondsSinceEpoch}_added';

    final ov = LessonOverride(
      id: id, date: widget.date,
      lessonName: name, lessonTeacher: teacher,
      lessonTime: timeStr, lessonRoom: _selectedRoom, lessonCode: code,
      isAdded: true,
    );
    await LessonOverrideService.add(ov);

    await NotificationService.notify(
      title: LanguageService.tr('notif_lesson_added_title'),
      body:  '$name · ${_fmtDate(widget.date)}',
      type:  NotificationType.lessonAdded,
      date:  widget.date,
    );
    if (mounted) Navigator.pop(context);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: _step == 0 ? 0.70 : 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withOpacity(0.7),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              if (_step == 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => setState(() => _step = 0),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                )
              else
                const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _step == 0
                      ? LanguageService.tr('step_pick_subject')
                      : LanguageService.tr('step_set_time'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(_fmtDate(widget.date),
                    style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600)),
              ])),
              Row(children: [
                _StepDot(active: _step == 0, primary: primary),
                const SizedBox(width: 5),
                _StepDot(active: _step == 1, primary: primary),
                const SizedBox(width: 8),
              ]),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          Expanded(
            child: _step == 0
                ? _buildStep0(ctrl, theme, primary)
                : _buildStep1(ctrl, theme, primary),
          ),
        ]),
      ),
    );
  }

  Widget _buildStep0(ScrollController ctrl, ThemeData theme, Color primary) {
    return Column(children: [
      Expanded(
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          children: [
            if (!_showManual) ...[
              ...widget.allLessons.map((l) => _LessonTile(
                lesson: l, selected: l == _picked,
                primary: primary, theme: theme,
                onTap: () => setState(() { _picked = l; _showManual = false; }),
              )),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => setState(() { _showManual = true; _picked = null; }),
                icon:  const Icon(Icons.edit_outlined, size: 16),
                label: Text(LanguageService.tr('enter_manually')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ] else ...[
              _OutlineField(
                controller: _nameCtrl,
                label: LanguageService.tr('lesson_name'),
                icon:  Icons.book_outlined,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _OutlineField(
                controller: _teacherCtrl,
                label: LanguageService.tr('teacher'),
                icon:  Icons.person_outline_rounded,
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => setState(() => _showManual = false),
                icon:  const Icon(Icons.list_rounded, size: 16),
                label: Text(LanguageService.tr('pick_subject')),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20,
            16 + MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom),
        child: FilledButton.icon(
          onPressed: _step0Valid ? () => setState(() => _step = 1) : null,
          icon:  const Icon(Icons.arrow_forward_rounded),
          label: Text(LanguageService.tr('btn_next')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildStep1(ScrollController ctrl, ThemeData theme, Color primary) {
    final labelStyle = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );

    return Column(children: [
      Expanded(
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          children: [

            // ── Lesson time ──────────────────────────────────────────
            _SectionCard(theme: theme,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 16, color: primary),
                  const SizedBox(width: 6),
                  Text(LanguageService.tr('lecture_start_time'), style: labelStyle),
                ]),
                const SizedBox(height: 12),
                _TimePickerRow(
                  hourCtrl: _lHourCtrl, minuteCtrl: _lMinCtrl,
                  onHourChanged:   (h) => _lessonHour   = h,
                  onMinuteChanged: (m) => _lessonMinute = m,
                  primary: primary, theme: theme,
                ),
              ]),
            ),

            const SizedBox(height: 14),

            // ── Room selector ────────────────────────────────────────
            _SectionCard(theme: theme,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.meeting_room_outlined, size: 16, color: primary),
                  const SizedBox(width: 6),
                  Text(LanguageService.tr('room'), style: labelStyle),
                  const Spacer(),
                  // Live preview badge
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primary.withOpacity(0.25), width: 1.2),
                    ),
                    child: Text(_selectedRoom,
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: primary, letterSpacing: 0.5,
                        )),
                  ),
                ]),
                const SizedBox(height: 16),
                _RoomPickerRow(
                  letterCtrl: _roomLetterCtrl, numberCtrl: _roomNumberCtrl,
                  onLetterChanged: (i) => setState(() => _roomLetterIndex = i),
                  onNumberChanged: (i) => setState(() => _roomNumber = i + 1),
                  primary: primary, theme: theme,
                ),
              ]),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),

      Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20,
            16 + MediaQuery.of(context).viewPadding.bottom),
        child: FilledButton.icon(
          onPressed: _save,
          icon:  const Icon(Icons.check_rounded),
          label: Text(LanguageService.tr('save_lecture')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]);
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final bool  active;
  final Color primary;
  const _StepDot({required this.active, required this.primary});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: active ? 16 : 6, height: 6,
    decoration: BoxDecoration(
      color: active ? primary : primary.withOpacity(0.25),
      borderRadius: BorderRadius.circular(99),
    ),
  );
}

class _LessonTile extends StatelessWidget {
  final Lesson lesson; final bool selected;
  final Color primary; final ThemeData theme;
  final VoidCallback onTap;
  const _LessonTile({
    required this.lesson, required this.selected,
    required this.primary, required this.theme, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    leading: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? primary : primary.withOpacity(0.08),
      ),
      child: Icon(selected ? Icons.check_rounded : Icons.book_outlined,
          size: 18, color: selected ? Colors.white : primary),
    ),
    title: Text(LanguageService.translateName(lesson.name),
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: selected ? primary : null,
        )),
    subtitle: lesson.teacher.isNotEmpty
        ? Text(LanguageService.translateName(lesson.teacher),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))
        : null,
  );
}

class _OutlineField extends StatelessWidget {
  final TextEditingController controller;
  final String label; final IconData icon;
  final ValueChanged<String>? onChanged;
  const _OutlineField({
    required this.controller, required this.label,
    required this.icon, this.onChanged,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller, onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label, prefixIcon: Icon(icon, size: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final ThemeData theme; final Widget child;
  const _SectionCard({required this.theme, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
    ),
    child: child,
  );
}

/// HH : MM time picker — two looping CupertinoPickers.
class _TimePickerRow extends StatelessWidget {
  final FixedExtentScrollController hourCtrl, minuteCtrl;
  final ValueChanged<int> onHourChanged, onMinuteChanged;
  final Color primary; final ThemeData theme;
  const _TimePickerRow({
    required this.hourCtrl, required this.minuteCtrl,
    required this.onHourChanged, required this.onMinuteChanged,
    required this.primary, required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const itemH = 44.0;
    Widget col({
      required FixedExtentScrollController ctrl, required int count,
      required ValueChanged<int> onChanged, required String Function(int) label,
      bool loop = true,
    }) => Expanded(child: SizedBox(
      height: itemH * 3,
      child: CupertinoPicker(
        scrollController: ctrl, itemExtent: itemH, looping: loop,
        selectionOverlay: _PickerOverlay(theme: theme, primary: primary),
        onSelectedItemChanged: (i) { HapticService.medium(); onChanged(i); },
        children: List.generate(count, (i) => Center(child: Text(label(i),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface)))),
      ),
    ));

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      col(ctrl: hourCtrl,   count: 24, onChanged: onHourChanged,
          label: (i) => i.toString().padLeft(2, '0')),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(' : ', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface)),
      ),
      col(ctrl: minuteCtrl, count: 60, onChanged: onMinuteChanged,
          label: (i) => i.toString().padLeft(2, '0')),
    ]);
  }
}

/// Room picker: Letter barrel (A/B/C) + Number barrel (1–30).
class _RoomPickerRow extends StatelessWidget {
  final FixedExtentScrollController letterCtrl, numberCtrl;
  final ValueChanged<int> onLetterChanged, onNumberChanged;
  final Color primary; final ThemeData theme;

  static const _letters = ['A', 'B', 'C'];

  const _RoomPickerRow({
    required this.letterCtrl, required this.numberCtrl,
    required this.onLetterChanged, required this.onNumberChanged,
    required this.primary, required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const itemH = 44.0;

    Widget col({
      required FixedExtentScrollController ctrl, required int count,
      required ValueChanged<int> onChanged, required String Function(int) label,
      bool loop = false, double fontSize = 22,
    }) => Expanded(child: SizedBox(
      height: itemH * 3,
      child: CupertinoPicker(
        scrollController: ctrl, itemExtent: itemH, looping: loop,
        selectionOverlay: _PickerOverlay(theme: theme, primary: primary),
        onSelectedItemChanged: (i) { HapticService.medium(); onChanged(i); },
        children: List.generate(count, (i) => Center(child: Text(label(i),
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface)))),
      ),
    ));

    return Row(children: [
      // Корпус A / B / C
      col(ctrl: letterCtrl, count: _letters.length,
          onChanged: onLetterChanged, label: (i) => _letters[i], fontSize: 26),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('–', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4))),
      ),
      // Номер 1–30
      col(ctrl: numberCtrl, count: 30, loop: true,
          onChanged: onNumberChanged, label: (i) => '${i + 1}', fontSize: 24),
    ]);
  }
}

/// Beautiful card-style selection highlight for CupertinoPickers.
/// Replaces the default thin-line overlay with a soft rounded rectangle.
class _PickerOverlay extends StatelessWidget {
  final ThemeData theme;
  final Color     primary;
  const _PickerOverlay({required this.theme, required this.primary});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: IgnorePointer(
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isDark
                ? primary.withOpacity(0.13)
                : primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary.withOpacity(isDark ? 0.30 : 0.20),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(isDark ? 0.08 : 0.05),
                blurRadius: 6, offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shimmer-прямоугольник для скелетона календаря ───────────────
class _CalSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _CalSkeletonBox({
    required this.width, required this.height,
    required this.radius, required this.base, required this.shine,
  });
  @override
  State<_CalSkeletonBox> createState() => _CalSkeletonBoxState();
}
class _CalSkeletonBoxState extends State<_CalSkeletonBox>
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
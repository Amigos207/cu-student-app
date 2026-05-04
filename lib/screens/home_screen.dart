// lib/screens/home_screen.dart
// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../models/lesson.dart';
import '../models/grade.dart';
import '../models/attendance.dart';
import '../models/exam_entry.dart';
import '../models/payment.dart';
import '../services/parser.dart';
import '../services/api.dart';
import '../services/data_service.dart';
import '../services/language.dart';
import '../services/mock_data.dart';
import '../utils/schedule_utils.dart';
import 'main_screen.dart';
import 'academic_screen.dart';
import 'payment_schedule_screen.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onAcademicTap;
  final VoidCallback? onGradesTap;
  final VoidCallback? onAttendanceTap;
  const HomeScreen({
    super.key,
    this.onAcademicTap,
    this.onGradesTap,
    this.onAttendanceTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;

  Lesson?      _nextLesson;
  GpaStats?    _gpaStats;
  double       _avgAttendance = 0;
  int          _attendedCount = 0;
  int          _totalCount    = 0;
  bool         _paymentPaid   = true; // default
  String       _firstName     = '';
  List<Lesson> _todayLessons  = [];
  ExamEntry?   _nextExam;

  String get _universityName => 'University'; // kept for potential future use

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (forceRefresh) DataService.instance.invalidateAll();
    setState(() => _loading = true);

    try {
      // Fire schedule, grades, and attendance in parallel.
      // DataService deduplicates the schedule fetch so that even if
      // ScheduleScreen is loading simultaneously, only one HTTP request goes out.
      final results = await Future.wait([
        DataService.instance.fetchSchedule(forceRefresh: forceRefresh),
        Parser.fetchGrades(),
        DataService.instance.fetchAttendance(forceRefresh: forceRefresh),
        _fetchFirstName(),
        Parser.fetchExams(),
        Parser.fetchDebtStatus(),
      ]);

      final schedule     = results[0] as List<Lesson>;
      final gradesResult = results[1] as (List<GradeSubject>, GpaStats?);
      final attendance   = results[2] as List<Attendance>;
      final firstName    = results[3] as String;
      final examResult   = results[4] as (List<ExamSemester>, List<ExamEntry>);
      final debtStatus   = results[5] as DebtStatus?;

      // Find the nearest upcoming exam across all entries.
      final nextExam = examResult.$2
          .where((e) => e.isUpcoming)
          .toList()
          .fold<ExamEntry?>(null, (best, e) =>
              best == null || e.sortKey.isBefore(best.sortKey) ? e : best);

      // Build teachersByDate from attendance records (same logic as CalendarScreen).
      final teachersByDate = <DateTime, Set<String>>{};
      for (final a in attendance) {
        final id = a.teacher.isNotEmpty ? a.teacher : a.subject;
        for (final r in a.records) {
          if (r.isDateReal && r.date.isNotEmpty) {
            final d = parseDateStr(r.date); // from schedule_utils.dart
            if (d != null && id.isNotEmpty) {
              teachersByDate.putIfAbsent(d, () => <String>{}).add(id);
            }
          }
        }
      }

      final nextLesson = _findNextLessonFromAttendance(schedule, teachersByDate);

      // Build today's lesson list (for mini-schedule card).
      final todayLessons = _buildTodayLessons(schedule, teachersByDate);

      double totalAtt = 0;
      int attCount = 0, totalLect = 0;
      for (final a in attendance) {
        totalAtt  += a.percentage;
        attCount  += a.attendedLectures;
        totalLect += a.passedLectures;
      }
      final avg = attendance.isEmpty ? 0.0 : totalAtt / attendance.length;

      if (mounted) {
        setState(() {
          _nextLesson    = nextLesson;
          _gpaStats      = gradesResult.$2;
          _avgAttendance = avg;
          _attendedCount = attCount;
          _totalCount    = totalLect;
          _paymentPaid   = debtStatus?.noDebt ?? true;
          _firstName     = firstName;
          _todayLessons  = todayLessons;
          _nextExam      = nextExam;
          _loading       = false;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen._loadData ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Finds the next upcoming lesson using attendance dates — same source as CalendarScreen.
  /// Falls back to weekday-based logic if attendance data is empty.
  Lesson? _findNextLessonFromAttendance(
      List<Lesson> lessons, Map<DateTime, Set<String>> teachersByDate) {
    if (teachersByDate.isEmpty) return _findNextLesson(lessons);

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Collect future dates (up to 30 days ahead) that have lectures
    final upcoming = teachersByDate.keys
        .where((d) => !d.isBefore(today))
        .toList()
      ..sort();

    if (upcoming.isEmpty) return _findNextLesson(lessons);

    // Group lessons by weekday name
    final grouped = <String, List<Lesson>>{};
    for (final l in lessons) {
      if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
    }
    grouped.forEach((_, list) => list.sort((a, b) => a.time.compareTo(b.time)));

    // Check today first: find upcoming lessons later today
    final todayDayName = kWeekDays[now.weekday - 1];
    if (teachersByDate.containsKey(today)) {
      final identifiers = teachersByDate[today]!;
      final todayLessons = grouped[todayDayName] ?? [];
      final nowMins = now.hour * 60 + now.minute;
      for (final l in todayLessons) {
        final startMins = parseTimeToMinutes(l.time);
        if (startMins != null && startMins > nowMins) {
          if (identifiers.any((id) =>
              teacherMatch(l.teacher, id) || teacherMatch(l.name, id))) {
            return l;
          }
        }
      }
    }

    // Find next upcoming date
    for (final date in upcoming) {
      if (date == today) continue;
      final dayName    = kWeekDays[date.weekday - 1];
      final dayLessons = grouped[dayName] ?? [];
      final identifiers = teachersByDate[date] ?? {};
      for (final l in dayLessons) {
        if (identifiers.isEmpty) return l;
        if (identifiers.any((id) =>
            teacherMatch(l.teacher, id) || teacherMatch(l.name, id))) {
          return l;
        }
      }
      if (dayLessons.isNotEmpty) return dayLessons.first;
    }

    return _findNextLesson(lessons);
  }

  Lesson? _findNextLesson(List<Lesson> lessons) {
    final now     = DateTime.now();
    final today   = kWeekDays[now.weekday - 1];
    final grouped = <String, List<Lesson>>{};
    for (final l in lessons) {
      if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
    }
    grouped.forEach((_, list) => list.sort((a, b) => a.time.compareTo(b.time)));

    final todayLessons = grouped[today] ?? [];
    final nowTime = now.hour * 60 + now.minute;
    for (final l in todayLessons) {
      final startTime = parseTimeToMinutes(l.time);
      if (startTime != null && startTime > nowTime) return l;
    }

    for (int i = 1; i < 7; i++) {
      final dayIdx  = (now.weekday - 1 + i) % 7;
      final dayName = kWeekDays[dayIdx];
      final dayLessons = grouped[dayName] ?? [];
      if (dayLessons.isNotEmpty) return dayLessons.first;
    }
    return lessons.isNotEmpty ? lessons.first : null;
  }

  String _formatNextTime(Lesson l) {
    final now     = DateTime.now();
    final today   = kWeekDays[now.weekday - 1];
    final isToday = l.day == today;

    final timeStr = l.time.contains('-')
        ? l.time.split('-').first.trim()
        : l.time;

    if (isToday) return timeStr;
    final dayTr = LanguageService.translateDay(l.day);
    return '$dayTr · $timeStr';
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  /// Returns all lessons scheduled for today, sorted by start time.
  /// Uses the same attendance-based date filtering as [_findNextLessonFromAttendance].
  List<Lesson> _buildTodayLessons(
      List<Lesson> schedule, Map<DateTime, Set<String>> teachersByDate) {
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final todayDay = kWeekDays[now.weekday - 1];

    // Group schedule by weekday
    final grouped = <String, List<Lesson>>{};
    for (final l in schedule) {
      if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
    }
    final dayLessons = List<Lesson>.from(grouped[todayDay] ?? [])
      ..sort((a, b) => a.time.compareTo(b.time));

    if (dayLessons.isEmpty) return [];

    // If attendance data has today, filter by matched identifiers
    if (teachersByDate.containsKey(today)) {
      final ids = teachersByDate[today]!;
      if (ids.isNotEmpty) {
        final filtered = dayLessons.where((l) =>
            ids.any((id) =>
                teacherMatch(l.teacher, id) || teacherMatch(l.name, id))).toList();
        if (filtered.isNotEmpty) return filtered;
      }
    }

    return dayLessons;
  }

  /// Fetches the profile and extracts the student's first name.
  /// Falls back to empty string on any error so the greeting still renders.
  Future<String> _fetchFirstName() async {
    try {
      Map<String, String> info;
      if (MockDataService.isActive) {
        info = MockDataService.mockProfile;
      } else {
        final html = await ApiService.fetchProfileHtml();
        if (html == null) return '';
        info = await Parser.parseProfile(html);
      }

      // Real portal: "გვარი, სახელი (ინგლისურად)" → "LASTNAME FIRSTNAME"
      final fullEn = info['გვარი, სახელი (ინგლისურად)'] ??
          info['გვარი,სახელი (ინგლისურად)'] ?? '';
      if (fullEn.isNotEmpty) {
        return LanguageService.extractFirstName(fullEn);
      }

      // Mock profile: plain "First Last" — extract first given name.
      final mockName = info['name'] ?? '';
      if (mockName.isNotEmpty) {
        return LanguageService.extractFirstName(mockName);
      }
    } catch (e) {
      debugPrint('HomeScreen._fetchFirstName ERROR: $e');
    }
    return '';
  }

  /// Returns the time-aware greeting key for [LanguageService.tr].
  ///   05:00 – 11:59  →  greeting_morning
  ///   12:00 – 17:59  →  greeting_afternoon
  ///   18:00 – 21:59  →  greeting_evening
  ///   22:00 – 04:59  →  greeting_night
  static String _greetingKey() {
    final h = DateTime.now().hour;
    if (h >= 5  && h < 12) return 'greeting_morning';
    if (h >= 12 && h < 18) return 'greeting_afternoon';
    if (h >= 18 && h < 22) return 'greeting_evening';
    return 'greeting_night';
  }

  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  List<Widget> _buildSkeletonItems(ThemeData theme, Color primary, bool isDark) {
    final base  = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _HomeSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Имитирует _NextClassCard — градиентный прямоугольник
    final nextCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF1A3D8C), Color(0xFF0E2454)])
            : const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF1E56D8), Color(0xFF2563EB)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: const Color(0xFF1E56D8).withOpacity(isDark ? 0.30 : 0.22),
          blurRadius: 20, offset: const Offset(0, 6),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // «NEXT CLASS» лейбл
          _HomeSkeletonBox(width: 80, height: 10, radius: 4,
              base: Colors.white.withOpacity(0.18),
              shine: Colors.white.withOpacity(0.28)),
          const SizedBox(height: 12),
          // Название предмета — 2 строки
          _HomeSkeletonBox(width: double.infinity, height: 20, radius: 6,
              base: Colors.white.withOpacity(0.18),
              shine: Colors.white.withOpacity(0.28)),
          const SizedBox(height: 8),
          _HomeSkeletonBox(width: 200, height: 18, radius: 6,
              base: Colors.white.withOpacity(0.18),
              shine: Colors.white.withOpacity(0.28)),
          const SizedBox(height: 12),
          // Аудитория + время
          Row(children: [
            _HomeSkeletonBox(width: 80, height: 12, radius: 4,
                base: Colors.white.withOpacity(0.14),
                shine: Colors.white.withOpacity(0.22)),
            const SizedBox(width: 16),
            _HomeSkeletonBox(width: 70, height: 12, radius: 4,
                base: Colors.white.withOpacity(0.14),
                shine: Colors.white.withOpacity(0.22)),
          ]),
          const SizedBox(height: 6),
          // Преподаватель
          _HomeSkeletonBox(width: 150, height: 12, radius: 4,
              base: Colors.white.withOpacity(0.14),
              shine: Colors.white.withOpacity(0.22)),
        ],
      ),
    );

    // Имитирует два _StatCard рядом
    Widget statCard({bool showProgress = false}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              box(40, 40, r: 12), // иконка
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  box(50, 9,  r: 4),  // лейбл
                  const SizedBox(height: 5),
                  box(60, 26, r: 6),  // значение
                ],
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 12),
            box(double.infinity, 4, r: 4),  // прогресс-бар
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: box(36, 8, r: 3),      // «X / Y»
            ),
          ],
        ],
      ),
    );

    final statsRow = Row(
      children: [
        Expanded(child: statCard(showProgress: true)),
        const SizedBox(width: 12),
        Expanded(child: statCard(showProgress: true)),
      ],
    );

    // Имитирует _PaymentCard
    final paymentCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          box(110, 12, r: 4),   // «Payment status»
          const Spacer(),
          box(80, 28, r: 20),   // статус-пилюля
        ],
      ),
    );

    // Имитирует _TodayScheduleCard — 3 строки расписания
    final scheduleCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(80, 10, r: 4),  // «СЕГОДНЯ»
          const SizedBox(height: 12),
          for (int i = 0; i < 3; i++) ...[
            Row(children: [
              _HomeSkeletonBox(width: 8, height: 8, radius: 4, base: base, shine: shine),
              const SizedBox(width: 10),
              box(44, 10, r: 4),
              const SizedBox(width: 12),
              box(120, 10, r: 4),
              const Spacer(),
              box(36, 10, r: 4),
            ]),
            if (i < 2) const SizedBox(height: 10),
          ],
        ],
      ),
    );

    return [
      nextCard,
      const SizedBox(height: 14),
      scheduleCard,
      const SizedBox(height: 14),
      statsRow,
      const SizedBox(height: 14),
      paymentCard,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) {
        final theme   = Theme.of(context);
        final isDark  = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;

        return Scaffold(
          body: RefreshIndicator(
            color: primary,
            onRefresh: () => _loadData(forceRefresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── App Bar ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          _UniversityLogo(isDark: isDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _loading
                                ? _GreetingSkeleton(isDark: isDark)
                                : _GreetingHeader(
                                    firstName: _firstName,
                                    isDark: isDark,
                                    primary: primary,
                                  ),
                          ),
                          const NotificationBell(),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Sandbox Banner (только для admin) ────────────
                if (MockDataService.isActive)
                  const SliverToBoxAdapter(child: _SandboxBanner()),

                SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, 120 + MediaQuery.of(context).viewPadding.bottom),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(_loading
                        ? _buildSkeletonItems(theme, primary, isDark)
                        : [
                        // ── Next Class Card ─────────────────────
                        _NextClassCard(
                          lesson: _nextLesson,
                          timeLabel: _nextLesson != null
                              ? _formatNextTime(_nextLesson!)
                              : '',
                          onTap: () {
                            HapticService.medium();
                            MainScreen.tabRequest.value = 0;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              AcademicScreen.scheduleRequest.value = true;
                            });
                          },
                          isDark: isDark,
                          primary: primary,
                        ),
                        const SizedBox(height: 14),

                        // ── Today's Schedule ─────────────────────
                        _TodayScheduleCard(
                          lessons: _todayLessons,
                          nextLesson: _nextLesson,
                          isDark: isDark,
                          primary: primary,
                          onTap: () {
                            HapticService.medium();
                            MainScreen.tabRequest.value = 0;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              AcademicScreen.scheduleRequest.value = true;
                            });
                          },
                        ),
                        const SizedBox(height: 14),

                        // ── Stats Row (GPA + Attendance) ─────────
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: LanguageService.tr('current_gpa'),
                                value: _gpaStats != null
                                    ? _gpaStats!.annualGpa.toStringAsFixed(2)
                                    : '—',
                                icon: Icons.school_rounded,
                                isDark: isDark,
                                primary: primary,
                                onTap: () {
                                  MainScreen.tabRequest.value = 1;
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    ProgressScreen.tabRequest.value = 0;
                                  });
                                },
                                progress: _gpaStats != null
                                    ? (_gpaStats!.annualGpa / 4.0).clamp(0.0, 1.0)
                                    : null,
                                progressLabel: _gpaStats != null
                                    ? '${_gpaStats!.annualGpa.toStringAsFixed(2)} / 4.00'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: LanguageService.tr('attendance'),
                                value: '${(_avgAttendance * 100).toInt()}%',
                                icon: Icons.fact_check_rounded,
                                isDark: isDark,
                                primary: primary,
                                onTap: () {
                                  MainScreen.tabRequest.value = 1;
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    ProgressScreen.tabRequest.value = 1;
                                  });
                                },
                                progress: _totalCount > 0
                                    ? _attendedCount / _totalCount
                                    : null,
                                progressLabel: _totalCount > 0
                                    ? '$_attendedCount / $_totalCount'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Upcoming Exam ───────────────────────
                        if (_nextExam != null) ...[
                          _UpcomingExamCard(
                            exam: _nextExam!,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ── Payment Status ─────────────────────
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticService.medium();
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PaymentScheduleScreen()));
                          },
                          child: _PaymentCard(
                            paid: _paymentPaid,
                            isDark: isDark,
                            primary: primary,
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── University Logo ─────────────────────────────────────────────

class _UniversityLogo extends StatelessWidget {
  final bool isDark;
  const _UniversityLogo({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1E56D8).withOpacity(isDark ? 0.3 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.account_balance_rounded, size: 20,
            color: Color(0xFF4E8DF5)),
      ),
    );
  }
}

// ─── Greeting Header ─────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String firstName;
  final bool   isDark;
  final Color  primary;

  const _GreetingHeader({
    required this.firstName,
    required this.isDark,
    required this.primary,
  });

  static String _formatDate() {
    final now  = DateTime.now();
    final lang = LanguageService.currentLang.value;

    final weekdays = lang == 'Русский'
        ? ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : lang == 'ქართული'
        ? ['ორშ', 'სამ', 'ოთხ', 'ხუთ', 'პარ', 'შაბ', 'კვი']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final months = lang == 'Русский'
        ? ['янв', 'фев', 'мар', 'апр', 'мая', 'июн',
           'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']
        : lang == 'ქართული'
        ? ['იან', 'თებ', 'მარ', 'აპრ', 'მაი', 'ივნ',
           'ივლ', 'აგვ', 'სექ', 'ოქტ', 'ნოვ', 'დეკ']
        : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
           'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final dow = weekdays[now.weekday - 1];
    return '$dow, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final greetingTr = LanguageService.tr(_HomeScreenState._greetingKey());
    final greeting   = firstName.isNotEmpty ? '$greetingTr, $firstName!' : '$greetingTr!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greeting,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            height: 1.2,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _formatDate(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─── Greeting Skeleton (shimmer placeholder while loading) ───────

class _GreetingSkeleton extends StatelessWidget {
  final bool isDark;
  const _GreetingSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base  = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HomeSkeletonBox(width: 160, height: 14, radius: 5, base: base, shine: shine),
        const SizedBox(height: 5),
        _HomeSkeletonBox(width: 60,  height: 10, radius: 4, base: base, shine: shine),
      ],
    );
  }
}

// ─── Next Class Card ─────────────────────────────────────────────

class _NextClassCard extends StatelessWidget {
  final Lesson? lesson;
  final String timeLabel;
  final VoidCallback? onTap;
  final bool isDark;
  final Color primary;

  const _NextClassCard({
    required this.lesson,
    required this.timeLabel,
    required this.onTap,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final gradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1A3D8C), Color(0xFF0E2454)])
        : const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1E56D8), Color(0xFF2563EB)]);

    return GestureDetector(
      onTap: onTap == null ? null : () { HapticService.medium(); onTap!(); },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E56D8).withOpacity(isDark ? 0.30 : 0.22),
              blurRadius: 20, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LanguageService.tr('next_class').toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.70),
                fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              lesson != null
                  ? LanguageService.translateName(lesson!.name)
                  : LanguageService.tr('no_data'),
              style: const TextStyle(
                color: Colors.white, fontSize: 26,
                fontWeight: FontWeight.w800, height: 1.15,
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (lesson?.room.isNotEmpty == true) ...[ 
                  const Icon(Icons.meeting_room_outlined,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    lesson!.room,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 16),
                ],
                if (timeLabel.isNotEmpty) ...[
                  const Icon(Icons.schedule_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
            if (lesson?.teacher.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      lesson!.teacher,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Today Schedule Card ─────────────────────────────────────────

enum _LessonStatus { past, ongoing, next, upcoming }

class _TodayScheduleCard extends StatelessWidget {
  final List<Lesson>  lessons;
  final Lesson?       nextLesson;
  final bool          isDark;
  final Color         primary;
  final VoidCallback? onTap;

  const _TodayScheduleCard({
    required this.lessons,
    required this.nextLesson,
    required this.isDark,
    required this.primary,
    this.onTap,
  });

  _LessonStatus _statusOf(Lesson l) {
    final now     = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    final parts = l.time.split('-');
    final startMins = parseTimeToMinutes(parts[0].trim());
    final endMins   = parts.length > 1
        ? parseTimeToMinutes(parts[1].trim())
        : (startMins != null ? startMins + 90 : null);

    if (startMins == null) return _LessonStatus.upcoming;

    if (endMins != null && nowMins >= startMins && nowMins < endMins) {
      return _LessonStatus.ongoing;
    }
    if (endMins != null && nowMins >= endMins) return _LessonStatus.past;
    if (nowMins < startMins) {
      // Is this the designated "next" lesson?
      if (nextLesson != null &&
          l.name == nextLesson!.name &&
          l.time == nextLesson!.time) {
        return _LessonStatus.next;
      }
      return _LessonStatus.upcoming;
    }
    return _LessonStatus.past;
  }

  String _startTime(Lesson l) {
    final t = l.time.contains('-') ? l.time.split('-').first.trim() : l.time;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Always render the card; show empty-state message when no lessons
    final empty = lessons.isEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
              blurRadius: 10, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────
            Row(
              children: [
                Text(
                  LanguageService.tr('today_schedule').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!empty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${lessons.length}',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // ── Empty state ──────────────────────────────────────
            if (empty) ...[
              const SizedBox(height: 10),
              Text(
                LanguageService.tr('no_classes_today'),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // ── Lesson rows ──────────────────────────────────────
            if (!empty) ...[
              const SizedBox(height: 10),
              ...() {
                const kMaxVisible = 4;
                final display = lessons.length > kMaxVisible
                    ? lessons.sublist(0, kMaxVisible)
                    : lessons;
                final hidden  = lessons.length - display.length;

                return [
                  ...display.asMap().entries.map((entry) {
                    final idx    = entry.key;
                    final lesson = entry.value;
                    final status = _statusOf(lesson);
                    final isPast = status == _LessonStatus.past;

                    final dotColor = switch (status) {
                      _LessonStatus.ongoing  => const Color(0xFF22C55E),
                      _LessonStatus.next     => primary,
                      _LessonStatus.upcoming => theme.colorScheme.onSurfaceVariant
                          .withOpacity(0.35),
                      _LessonStatus.past     => theme.colorScheme.onSurfaceVariant
                          .withOpacity(0.22),
                    };

                    final textColor = isPast
                        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.45)
                        : theme.colorScheme.onSurface;

                    final subColor = isPast
                        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.35)
                        : theme.colorScheme.onSurfaceVariant;

                    return Padding(
                      padding: EdgeInsets.only(bottom: idx < display.length - 1 || hidden > 0 ? 9 : 0),
                      child: Row(
                        children: [
                          // Dot
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                                color: dotColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),

                          // Time
                          SizedBox(
                            width: 46,
                            child: Text(
                              _startTime(lesson),
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: status == _LessonStatus.next ||
                                        status == _LessonStatus.ongoing
                                    ? primary
                                    : subColor,
                              ),
                            ),
                          ),

                          // Subject name
                          Expanded(
                            child: Text(
                              LanguageService.translateName(lesson.name),
                              style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Room / status badge
                          if (status == _LessonStatus.ongoing)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                LanguageService.tr('class_ongoing'),
                                style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFF22C55E),
                                ),
                              ),
                            )
                          else if (lesson.room.isNotEmpty)
                            Text(
                              lesson.room,
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500,
                                color: subColor,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),

                  // ── «ещё N» footer ─────────────────────────────
                  if (hidden > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const SizedBox(width: 17), // выравнивание под dot
                          Text(
                            LanguageService.tr('and_more')
                                .replaceAll('{n}', '$hidden'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded,
                              size: 12, color: primary),
                        ],
                      ),
                    ),
                ];
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card (GPA / Attendance) ───────────────────────────────

class _StatCard extends StatelessWidget {
  final String        label;
  final String        value;
  final IconData      icon;
  final bool          isDark;
  final Color         primary;
  final VoidCallback? onTap;
  /// 0.0–1.0. When non-null, a thin progress bar is drawn below the value.
  final double?       progress;
  /// Optional sub-label shown below the bar, e.g. «14 / 20».
  final String?       progressLabel;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    required this.primary,
    this.onTap,
    this.progress,
    this.progressLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () { HapticService.medium(); onTap!(); },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top row: icon + label/value ───────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: primary),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // ── Bottom: full-width progress bar ───────────────────
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: primary.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            if (progressLabel != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  progressLabel!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    ), // Container
    ); // GestureDetector
  }
}

// ─── Upcoming Exam Card ──────────────────────────────────────────

class _UpcomingExamCard extends StatelessWidget {
  final ExamEntry exam;
  final bool      isDark;

  const _UpcomingExamCard({required this.exam, required this.isDark});

  /// Days until exam (0 = today, 1 = tomorrow, …).
  int get _daysUntil {
    final today = DateTime.now();
    final d     = DateTime(today.year, today.month, today.day);
    final e     = DateTime(exam.date.year, exam.date.month, exam.date.day);
    return e.difference(d).inDays;
  }

  String _countdownLabel() {
    final days = _daysUntil;
    if (days == 0) return LanguageService.tr('exam_today');
    if (days == 1) return LanguageService.tr('exam_tomorrow');
    return LanguageService.tr('exam_in_days').replaceAll('{n}', '$days');
  }

  /// Urgency colour:
  ///   0–2 days  →  red
  ///   3–7 days  →  amber
  ///   8+ days   →  blue
  Color _accentColor() {
    final days = _daysUntil;
    if (days <= 2) return const Color(0xFFEF4444);
    if (days <= 7) return const Color(0xFFF59E0B);
    return const Color(0xFF3B82F6);
  }

  String _formattedDate() {
    final d = exam.date;
    final months = LanguageService.currentLang.value == 'Русский'
        ? ['янв','фев','мар','апр','мая','июн','июл','авг','сен','окт','ноя','дек']
        : LanguageService.currentLang.value == 'ქართული'
        ? ['იან','თებ','მარ','აპრ','მაი','ივნ','ივლ','აგვ','სექ','ოქტ','ნოვ','დეკ']
        : ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final accent  = _accentColor();
    final days    = _daysUntil;

    final subjectName = LanguageService.translateName(
        exam.nameEn.isNotEmpty ? exam.nameEn : exam.nameKa);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticService.medium();
        MainScreen.tabRequest.value = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AcademicScreen.examRequest.value = true;
        });
      },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withOpacity(isDark ? 0.35 : 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.12 : 0.07),
            blurRadius: 12, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Countdown circle ───────────────────────────────
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.18 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: days <= 1
                  ? Text(
                      _countdownLabel(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800,
                        color: accent, height: 1.2,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$days',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800,
                            color: accent, height: 1.0,
                          ),
                        ),
                        Text(
                          LanguageService.currentLang.value == 'Русский'
                              ? 'дн.'
                              : LanguageService.currentLang.value == 'ქართული'
                                  ? 'დღე'
                                  : 'days',
                          style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: accent.withOpacity(0.75),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // ── Subject + meta ─────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.tr('upcoming_exam').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: accent.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subjectName,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      _formattedDate(),
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (exam.time.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.schedule_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        exam.time,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (exam.room.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.meeting_room_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        exam.room,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ), // Container
    ); // GestureDetector
  }
}

// ─── Payment Status Card ─────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  final bool paid;
  final bool isDark;
  final Color primary;

  const _PaymentCard({
    required this.paid,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final statusColor = paid ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final label       = paid
        ? LanguageService.tr('paid')
        : LanguageService.tr('unpaid');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(isDark ? 0.20 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            LanguageService.tr('payment_status'),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: statusColor, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: statusColor, fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Sandbox banner — виден только при входе admin / 1234
// ═══════════════════════════════════════════════════════════════════
class _SandboxBanner extends StatelessWidget {
  const _SandboxBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'SANDBOX MODE — mock data only · real users unaffected',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.amber, letterSpacing: 0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('DEV', style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w900, color: Colors.amber)),
          ),
        ],
      ),
    );
  }
}

// ─── Shimmer-прямоугольник для скелетона главного экрана ─────────
class _HomeSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _HomeSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_HomeSkeletonBox> createState() => _HomeSkeletonBoxState();
}

class _HomeSkeletonBoxState extends State<_HomeSkeletonBox>
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
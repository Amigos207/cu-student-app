import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../models/grade.dart';
import '../models/lesson.dart';
import '../services/api.dart';
import '../services/parser.dart';
import '../services/data_service.dart';
import '../services/language.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GRADES SCREEN (главная, встроена в нижнюю панель)
// ─────────────────────────────────────────────────────────────────────────────

class GradesScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const GradesScreen({super.key, this.onMenuTap});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<GradeSubject> _subjects    = [];
  GpaStats?          _stats;
  bool               _loading     = true;
  bool               _loadStarted = false; // защита от повторной загрузки

  Map<String, String> _codeToEnName  = {};
  Map<String, String> _codeToTeacher = {};

  @override
  void initState() {
    super.initState();
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (forceRefresh) Parser.clearGradesCache();
    setState(() => _loading = true);

    // ── Fetch grades + schedule in parallel ───────────────────────
    // DataService.fetchSchedule() is deduplicated: if HomeScreen or
    // ScheduleScreen already fetched (or is fetching) schedule.php, this
    // joins that same future — no extra HTTP request.
    final results = await Future.wait([
      Parser.fetchGrades(),
      DataService.instance.fetchSchedule(forceRefresh: forceRefresh),
    ]);

    final gradesResult = results[0] as (List<GradeSubject>, GpaStats?);
    final currentSched = results[1] as List<Lesson>;

    // ── Previous-semester schedule ────────────────────────────────
    // Semesters are parsed from the HTML that fetchSchedule already cached —
    // ApiService.getHtml() is a guaranteed TTL-cache hit here (no extra request).
    List<Lesson> prevSched = [];
    try {
      final html = await ApiService.getHtml(ApiService.scheduleUrl);
      if (html != null) {
        final sems = Parser.parseSemesters(html);
        // sems sorted ascending by id; take the penultimate (previous semester)
        if (sems.length >= 2) {
          final prevSem = sems[sems.length - 2];
          prevSched = await Parser.parseScheduleForSemester(prevSem);
        }
      }
    } catch (_) {}

    // ── Build code → name / code → teacher maps ───────────────────
    // Priority order:
    //   1. Current semester schedule  (English, always reliable)
    //   2. Previous semester schedule (English, fills most gaps)
    //   3. Grades data itself         (English names for current-semester
    //      subjects are already present in the grades HTML — mining them
    //      lets older-semester entries with the same code resolve to English
    //      even when they fall outside the schedule window)
    final codeMap    = <String, String>{};
    final teacherMap = <String, String>{};

    void addLesson(Lesson l) {
      if (l.code.isEmpty) return;
      if (l.name.isNotEmpty)    codeMap[l.code]    = l.name;
      if (l.teacher.isNotEmpty) teacherMap[l.code] = l.teacher;
    }

    for (final l in currentSched) addLesson(l);
    for (final l in prevSched) {
      if (l.code.isNotEmpty) {
        codeMap.putIfAbsent(l.code, () => l.name.isNotEmpty ? l.name : l.code);
        teacherMap.putIfAbsent(l.code, () => l.teacher);
      }
    }

    // ── Mine English names from the grades payload itself ──────────
    // The portal already includes English subject names for current-semester
    // entries in the grades HTML.  For any grade subject whose name contains
    // no Georgian characters (i.e. it is Latin/English), add it to the map so
    // that the same course code from older semesters — where the portal only
    // returns the Georgian name — resolves to English in the UI.
    // putIfAbsent keeps schedule data at higher priority.
    for (final g in gradesResult.$1) {
      if (g.code.isNotEmpty &&
          g.name.isNotEmpty &&
          !_containsGeorgian(g.name)) {
        codeMap.putIfAbsent(g.code, () => g.name);
      }
    }

    if (!mounted) return;
    LanguageService.seedCodeMap(codeMap);
    setState(() {
      _subjects      = gradesResult.$1;
      _stats         = gradesResult.$2;
      _codeToEnName  = codeMap;
      _codeToTeacher = teacherMap;
      _loading       = false;
    });
  }

  /// Returns true when [text] contains at least one Georgian Unicode character
  /// (U+10D0–U+10FF).  Used to distinguish Georgian subject names from English
  /// ones so the correct source can be chosen for the display map.
  static bool _containsGeorgian(String text) =>
      RegExp(r'[\u10D0-\u10FF]').hasMatch(text);

  /// Нормализует код предмета для сравнения:
  /// "ACWR 0007E" → "acwr7e",  "CSC 1242" → "csc1242"
  static String _normalizeCode(String code) {
    // убираем пробелы и приводим к нижнему регистру
    var s = code.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    // убираем ведущие нули перед цифрами: 007 → 7, 0010 → 10
    s = s.replaceAllMapped(RegExp(r'0+(\d)'), (m) => m.group(1)!);
    return s;
  }

  /// Возвращает отображаемое название предмета с учётом языка интерфейса.
  String _getDisplayName(GradeSubject s) {
    final lang = LanguageService.currentLang.value;

    // Грузинский интерфейс → грузинское название прямо из портала
    if (lang == 'ქართული') {
      return s.name.isNotEmpty ? s.name : s.code;
    }

    // Английский / Русский → ищем английское название из расписания
    // Сначала точное совпадение нормализованного кода
    final normTarget = _normalizeCode(s.code);
    for (final entry in _codeToEnName.entries) {
      if (_normalizeCode(entry.key) == normTarget) return entry.value;
    }

    // Нечёткий fallback: совпадение буквенного префикса + близкий номер
    final prefix = RegExp(r'^[a-z]+').stringMatch(normTarget) ?? '';
    if (prefix.isNotEmpty) {
      for (final entry in _codeToEnName.entries) {
        final ep = RegExp(r'^[a-z]+').stringMatch(_normalizeCode(entry.key)) ?? '';
        if (ep == prefix && _normalizeCode(entry.key).contains(
            normTarget.replaceAll(prefix, ''))) {
          return entry.value;
        }
      }
    }

    // Последний вариант: если есть грузинское название — показываем его,
    // чтобы пользователь хоть что-то понял (лучше чем просто код)
    return s.name.isNotEmpty ? s.name : s.code;
  }

  /// Возвращает преподавателя по коду с той же нормализацией.
  String _getTeacher(GradeSubject s) {
    final normTarget = _normalizeCode(s.code);
    for (final entry in _codeToTeacher.entries) {
      if (_normalizeCode(entry.key) == normTarget) {
        // Always transliterate to Latin — both English and Russian UIs
        // should show readable Latin names, not Georgian script.
        return LanguageService.translateName(entry.value);
      }
    }
    return '';
  }

  // ── Цвет буквенной оценки (A=зелёный → F=красный) ───────────
  // Единая палитра для всех тем — цвет всегда несёт смысл
  static Color _letterColor(String letter) {
    switch (letter.replaceAll('+', '').toUpperCase()) {
      case 'A': return const Color(0xFF2E7D32); // тёмно-зелёный
      case 'B': return const Color(0xFF558B2F); // оливково-зелёный
      case 'C': return const Color(0xFFF9A825); // янтарный
      case 'D': return const Color(0xFFE65100); // оранжевый
      case 'F': return const Color(0xFFC62828); // красный
      default:  return Colors.grey;
    }
  }

  // ── Цвет по проценту от макс. балла (всегда зелёный/жёлтый/красный) ──
  static Color _ratioColor(double ratio) {
    if (ratio >= 0.8) return const Color(0xFF2E7D32);
    if (ratio >= 0.7) return const Color(0xFF558B2F);
    if (ratio >= 0.6) return const Color(0xFFF9A825);
    if (ratio >= 0.5) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) {
        final theme   = Theme.of(context);
        final primary = theme.colorScheme.primary;

        if (_loading) {
          return Scaffold(body: _buildSkeleton(theme, primary));
        }

        return Scaffold(
          body: RefreshIndicator(
            color: primary,
            onRefresh: () => _load(forceRefresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── GPA-карточка ─────────────────────────────────
                if (_stats != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: _GpaCard(stats: _stats!, primary: primary),
                    ),
                  ),

                // ── Список предметов ─────────────────────────────
                if (_subjects.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(LanguageService.tr('no_data'),
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16, 8, 16,
                      140 + MediaQuery.of(context).viewPadding.bottom
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _buildSubjectCard(_subjects[i], theme),
                        childCount: _subjects.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }


  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  Widget _buildSkeleton(ThemeData theme, Color primary) {
    final isDark = theme.brightness == Brightness.dark;
    final base   = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine  = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _GradeSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // GPA-карточка — имитирует _GpaCard
    Widget gpaCard() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary.withOpacity(isDark ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(36, 11, r: 4),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(60, 28, r: 6),
                    const SizedBox(height: 6),
                    box(80, 11, r: 4),
                    const SizedBox(height: 4),
                    box(60, 10, r: 4),
                  ],
                ),
              ),
              Container(width: 1, height: 56,
                  color: primary.withOpacity(0.15),
                  margin: const EdgeInsets.symmetric(horizontal: 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(60, 28, r: 6),
                    const SizedBox(height: 6),
                    box(80, 11, r: 4),
                    const SizedBox(height: 4),
                    box(60, 10, r: 4),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Карточка предмета — имитирует _buildSubjectCard
    Widget subjectCard({double nameWidth = double.infinity}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
        boxShadow: [if (!isDark) BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Бейдж оценки
              box(44, 44, r: 12),
              const SizedBox(width: 12),
              // Название + преподаватель
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(nameWidth, 15, r: 6),
                    const SizedBox(height: 5),
                    box(nameWidth == double.infinity ? 160 : nameWidth * 0.65, 14, r: 5),
                    const SizedBox(height: 5),
                    box(120, 11, r: 4),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Процент + GPA
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  box(48, 20, r: 6),
                  const SizedBox(height: 5),
                  box(56, 11, r: 4),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Прогресс-бар
          box(double.infinity, 6, r: 4),
          const SizedBox(height: 10),
          // Нижняя строка: кредиты + код + стрелка
          Row(
            children: [
              box(14, 13, r: 3),
              const SizedBox(width: 4),
              box(60, 12, r: 4),
              const Spacer(),
              box(56, 20, r: 6),
              const SizedBox(width: 4),
              box(18, 18, r: 4),
            ],
          ),
        ],
      ),
    );

    final bottomInset = 140 + MediaQuery.of(context).viewPadding.bottom;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gpaCard(),
          const SizedBox(height: 12),
          subjectCard(),
          subjectCard(nameWidth: 220),
          subjectCard(nameWidth: 260),
          subjectCard(),
          subjectCard(nameWidth: 200),
          subjectCard(nameWidth: 240),
        ],
      ),
    );
  }

  // ── Карточка предмета ─────────────────────────────────────────
  Widget _buildSubjectCard(GradeSubject s, ThemeData theme) {
    final hasGrade = s.letter.isNotEmpty;
    final lColor   = hasGrade ? _letterColor(s.letter) : Colors.grey;
    final pct      = (s.percentage / 100).clamp(0.0, 1.0);
    final enName   = _getDisplayName(s);
    final teacher  = _getTeacher(s);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: theme.brightness == Brightness.dark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // Всегда нейтральная рамка — цвет несёт только бейдж
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () { HapticService.medium(); Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: s)),
        ); },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LetterBadge(letter: s.letter, color: lColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   15,
                            color:      theme.colorScheme.onSurface,
                            height:     1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (teacher.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            teacher,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines:  1,
                            overflow:  TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hasGrade
                            ? '${s.percentage.toStringAsFixed(s.percentage % 1 == 0 ? 0 : 1)}%'
                            : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize:   18,
                          color:      lColor,
                        ),
                      ),
                      if (s.qualityPoints > 0)
                        Text(
                          'GPA ${s.qualityPoints.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color:    theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:           hasGrade ? pct : 0,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color:           lColor,
                  minHeight:       6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.stars_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${s.credits.toInt()} ${LanguageService.tr('credits')}',
                    style: TextStyle(
                      fontSize: 12,
                      color:    theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      // Нейтральный фон для кода — не lColor
                      color:        theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.code,
                      style: TextStyle(
                        fontSize:     11,
                        fontWeight:   FontWeight.w600,
                        color:        theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size:  18,
                      color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GPA-КАРТОЧКА
// ─────────────────────────────────────────────────────────────────────────────

class _GpaCard extends StatelessWidget {
  final GpaStats stats;
  final Color    primary;
  const _GpaCard({required this.stats, required this.primary});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary.withOpacity(0.15), primary.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GPA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GpaStat(
                  label: LanguageService.tr('annual'),
                  pct: stats.annualPercentage,
                  gpa: stats.annualGpa,
                  subjects: stats.annualSubjects,
                  credits: stats.annualCredits,
                  primary: primary,
                  theme: theme,
                ),
              ),
              Container(
                width: 1, height: 56,
                color: primary.withOpacity(0.2),
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: _GpaStat(
                  label: LanguageService.tr('cumulative'),
                  pct: stats.cumulativePercentage,
                  gpa: stats.cumulativeGpa,
                  subjects: stats.cumulativeSubjects,
                  credits: stats.cumulativeCredits,
                  primary: primary,
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GpaStat extends StatelessWidget {
  final String label;
  final double pct, gpa, credits;
  final int    subjects;
  final Color  primary;
  final ThemeData theme;
  const _GpaStat({
    required this.label, required this.pct, required this.gpa,
    required this.subjects, required this.credits,
    required this.primary, required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'GPA ${gpa.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$subjects ${LanguageService.tr('subjects')} · '
          '${credits.toInt()} ${LanguageService.tr('credits')}',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// БУКВЕННЫЙ ЗНАЧОК
// ─────────────────────────────────────────────────────────────────────────────

class _LetterBadge extends StatelessWidget {
  final String letter;
  final Color  color;
  const _LetterBadge({required this.letter, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: color,          // сплошная заливка — главный акцент
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:       color.withOpacity(0.35),
            blurRadius:  8,
            offset:      const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          letter.isEmpty ? '?' : letter,
          style: TextStyle(
            color:      Colors.white,
            fontWeight: FontWeight.bold,
            fontSize:   letter.length > 1 ? 14 : 18,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ЭКРАН ДЕТАЛИЗАЦИИ ПРЕДМЕТА
// ─────────────────────────────────────────────────────────────────────────────

class SubjectDetailScreen extends StatefulWidget {
  final GradeSubject subject;
  const SubjectDetailScreen({super.key, required this.subject});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  SubjectDetail? _detail;
  bool           _loading = true;
  bool           _error   = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    final detail = await Parser.fetchSubjectDetail(widget.subject.cxrId);
    if (!mounted) return;
    setState(() {
      _detail  = detail;
      _loading = false;
      _error   = (detail == null);
    });
  }

  Color _letterColor(String letter) {
    switch (letter.replaceAll('+', '').toUpperCase()) {
      case 'A': return const Color(0xFF2E7D32);
      case 'B': return const Color(0xFF558B2F);
      case 'C': return const Color(0xFFF9A825);
      case 'D': return const Color(0xFFE65100);
      case 'F': return const Color(0xFFC62828);
      default:  return Colors.grey;
    }
  }

  // Цвет строки экзамена — всегда зелёный/жёлтый/красный, независимо от общей оценки
  Color _examRowColor(double score, double maxScore) {
    if (maxScore <= 0) return Colors.grey;
    final ratio = score / maxScore;
    if (ratio >= 0.8) return const Color(0xFF2E7D32);
    if (ratio >= 0.7) return const Color(0xFF558B2F);
    if (ratio >= 0.6) return const Color(0xFFF9A825);
    if (ratio >= 0.5) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final s       = widget.subject;
    final lColor  = s.letter.isNotEmpty ? _letterColor(s.letter) : primary;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.code,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (_detail?.teacher.isNotEmpty == true)
              Text(
                _detail!.teacher,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : _error || _detail == null
              ? _buildError(primary)
              : RefreshIndicator(
                  color: primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
        // ── Итоговая карточка ──────────────────────
                      if (s.letter.isNotEmpty)
                        _buildSummaryHeader(s, lColor, theme, isDark),

                      const SizedBox(height: 16),

                      // ── Таблица экзаменов ──────────────────────
                      _buildExamTable(_detail!, theme, isDark, lColor),

                      // ── Итоги снизу (если есть данные) ────────
                      if (_detail!.hasData) ...[
                        const SizedBox(height: 16),
                        _buildBottomSummary(_detail!, theme, isDark, lColor),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError(Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48,
              color: primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(LanguageService.tr('no_data')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _load,
            child: Text(LanguageService.tr('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(
      GradeSubject s, Color lColor, ThemeData theme, bool isDark) {
    // Берём английское название из расписания через тот же механизм что в GradesScreen.
    // SubjectDetailScreen получает subject из GradesScreen, где уже прогружено расписание,
    // но здесь мы для надёжности просто используем s.code как fallback.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          _LetterBadge(letter: s.letter, color: lColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.code,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.percentage.toStringAsFixed(s.percentage % 1 == 0 ? 0 : 1)}%'
                  '  ·  ${s.credits.toInt()} ${LanguageService.tr('credits')}',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamTable(
      SubjectDetail d, ThemeData theme, bool isDark, Color lColor) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // Заголовок таблицы
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withOpacity(0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    LanguageService.tr('exam_type'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  LanguageService.tr('score'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Строки экзаменов
          ...d.exams.asMap().entries.map((e) {
            final i    = e.key;
            final exam = e.value;
            final isLast = i == d.exams.length - 1;
            return _buildExamRow(exam, theme, isDark, lColor, isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildExamRow(
      SubjectExam exam, ThemeData theme, bool isDark, Color lColor, bool isLast) {
    final isScored  = exam.isScored;
    final isFinal   = exam.isFinalType;
    final isFuture  = exam.isFuture;

    Color rowColor;
    if (!isScored) {
      rowColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.4);
    } else {
      // Цвет строки всегда зелёный/жёлтый/красный — не зависит от общей оценки предмета.
      // Это позволяет пользователю видеть хорошие работы зелёными даже в предмете с C/D.
      rowColor = _examRowColor(exam.score!, exam.maxScore);
    }

    final scoreText = isScored
        ? '${_formatScore(exam.score!)} / ${_formatScore(exam.maxScore)}'
        : '— / ${_formatScore(exam.maxScore)}';

    return Column(
      children: [
        Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.type,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isFinal ? FontWeight.bold : FontWeight.normal,
                        color: isFinal
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface
                                .withOpacity(isScored ? 1.0 : 0.55),
                      ),
                    ),
                    if (exam.date.isNotEmpty)
                      Text(
                        _formatDate(exam.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isScored
                      ? rowColor.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isScored
                      ? Border.all(color: rowColor.withOpacity(0.3))
                      : null,
                ),
                child: Text(
                  scoreText,
                  style: TextStyle(
                    fontWeight:
                        isScored ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                    color: isScored
                        ? rowColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSummary(
      SubjectDetail d, ThemeData theme, bool isDark, Color lColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: LanguageService.tr('interim_total'),
            value: '${_formatScore(d.interimTotal)} '
                '${LanguageService.tr('out_of')} '
                '${_formatScore(d.maxEntered)}',
            theme: theme,
          ),
          Divider(height: 16, color: theme.dividerColor.withOpacity(0.4)),
          _SummaryRow(
            label: LanguageService.tr('student_total'),
            value: _formatScore(d.studentTotal),
            theme: theme,
          ),
          Divider(height: 16, color: theme.dividerColor.withOpacity(0.4)),
          _SummaryRow(
            label: LanguageService.tr('final_percentage'),
            value: '${d.finalPercentage.toStringAsFixed(2)}%',
            theme: theme,
            valueColor: lColor,
            bold: true,
          ),
          if (d.finalGrade.isNotEmpty) ...[
            Divider(height: 16, color: theme.dividerColor.withOpacity(0.4)),
            _SummaryRow(
              label: LanguageService.tr('final_grade'),
              value: d.finalGrade,
              theme: theme,
              valueColor: lColor,
              bold: true,
              valueFontSize: 20,
            ),
          ],
        ],
      ),
    );
  }

  String _formatScore(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  String _formatDate(String raw) {
    // "2026-03-07" → "07.03.2026"
    final parts = raw.split('-');
    if (parts.length == 3) return '${parts[2]}.${parts[1]}.${parts[0]}';
    return raw;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String  label;
  final String  value;
  final ThemeData theme;
  final Color?  valueColor;
  final bool    bold;
  final double  valueFontSize;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
    this.bold          = false,
    this.valueFontSize = 14,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      );
}

// ─── Shimmer-прямоугольник для скелетона оценок ──────────────────
class _GradeSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _GradeSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_GradeSkeletonBox> createState() => _GradeSkeletonBoxState();
}

class _GradeSkeletonBoxState extends State<_GradeSkeletonBox>
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
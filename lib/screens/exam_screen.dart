import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../models/exam_entry.dart';
import '../services/parser.dart';
import '../services/language.dart';

class ExamScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const ExamScreen({super.key, this.onMenuTap});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  List<ExamSemester> _semesters    = [];
  List<ExamEntry>    _exams        = [];
  int?               _selectedSemId;

  bool _loading    = true;   // первичная загрузка (весь экран)
  bool _semLoading = false;  // смена семестра (тонкий progress bar)
  bool _hasError   = false;  // ошибка: нет сети / сервер вернул пусто
  bool _loadStarted = false; // защита от повторного вызова при rebuild родителя

  // ─── ИНИЦИАЛИЗАЦИЯ ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Кэш parser'а защищает от лишних сетевых запросов при последующих
    // пересозданиях экрана. _loadStarted защищает от второго вызова
    // в рамках одного жизненного цикла State.
    if (!_loadStarted) {
      _loadStarted = true;
      _loadData();
    }
  }

  /// Первичная загрузка.
  ///
  /// fetchExams() внутри:
  ///   1. Получает recovery-страницу
  ///   2. Парсит список семестров
  ///   3. Автоматически определяет новейший семестр (max ID)
  ///   4. Если он отличается от дефолтного (selected) — делает POST
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });

    try {
      // semId=null → fetchExams сам выберет новейший семестр
      final (sems, exams) = await Parser.fetchExams();
      if (!mounted) return;
      setState(() {
        _semesters     = sems;
        _exams         = exams;
        // Отображаем тот семестр, который реально вернули данные
        _selectedSemId = exams.isNotEmpty
            ? exams.first.semId
            : (sems.isNotEmpty ? sems.first.id : null);
        _loading       = false;
        _hasError      = sems.isEmpty;
      });
    } catch (e) {
      debugPrint('ExamScreen._loadData ERROR: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  /// Pull-to-refresh: сбрасываем кэш и загружаем заново.
  Future<void> _refresh() async {
    Parser.clearExamCache();
    if (_selectedSemId == null) return _loadData();
    await _loadExamsForSemester(_selectedSemId!);
  }

  /// Загружает экзамены для явно выбранного пользователем семестра.
  Future<void> _loadExamsForSemester(int semId) async {
    if (!mounted) return;
    setState(() { _semLoading = true; _hasError = false; });

    try {
      final (sems, exams) = await Parser.fetchExams(semId: semId);
      if (!mounted) return;
      setState(() {
        if (sems.isNotEmpty) _semesters = sems;
        _exams         = exams;
        _selectedSemId = semId;
        _semLoading    = false;
      });
    } catch (e) {
      debugPrint('ExamScreen._loadExamsForSemester ERROR: $e');
      if (mounted) setState(() => _semLoading = false);
    }
  }

  // ─── ВСПОМОГАТЕЛЬНЫЕ ───────────────────────────────────────────

  bool _isPink(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.primary == const Color(0xFFD81B60);

  String _countdownLabel(ExamEntry e) {
    if (!e.isUpcoming) return LanguageService.tr('exam_past');
    final now  = DateTime.now();
    final diff = DateTime(e.date.year, e.date.month, e.date.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (diff == 0) return LanguageService.tr('exam_today');
    if (diff == 1) return LanguageService.tr('exam_tomorrow');
    final prefix = LanguageService.tr('exam_in');
    final suffix = LanguageService.tr('exam_days');
    return prefix.isEmpty ? '$diff $suffix' : '$prefix $diff $suffix';
  }

  /// Красная гамма: ≤3 дней — насыщенный тёмно-красный,
  /// >30 дней — бледно-розовый. Прошедшие — серые.
  Color _badgeColor(ExamEntry e, BuildContext ctx) {
    if (!e.isUpcoming)
      return Theme.of(ctx).colorScheme.onSurface.withOpacity(0.30);

    final now  = DateTime.now();
    final days = DateTime(e.date.year, e.date.month, e.date.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;

    if (days <= 0)  return const Color(0xFFB71C1C); // сегодня/просрочен
    if (days <= 3)  return const Color(0xFFD32F2F); // ≤3 дн  — очень ярко
    if (days <= 7)  return const Color(0xFFE53935); // ≤7 дн  — ярко
    if (days <= 14) return const Color(0xFFEF5350); // ≤14 дн — средне
    if (days <= 30) return const Color(0xFFEF9A9A); // ≤30 дн — бледно
    return const Color(0xFFFFCDD2);                 // >30 дн — очень бледно
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ─── ВИДЖЕТЫ ───────────────────────────────────────────────────

  // Translates Georgian semester names (e.g. "2024 გაზაფხულის სემესტრი")
  // into the current UI language using existing sem_* keys.
  static const _geoToTrKey = <String, String>{
    'გაზაფხულის': 'sem_spring',
    'ზაფხულის':   'sem_summer',
    'შემოდგომის': 'sem_autumn',
    'ზამთრის':    'sem_winter',
    'სემესტრი':   'sem_semester',
  };

  static String _formatSemName(String rawName) {
    final lang = LanguageService.currentLang.value;
    String name = rawName.trim();
    if (lang != 'ქართული') {
      _geoToTrKey.forEach((geo, key) {
        if (name.contains(geo)) name = name.replaceAll(geo, LanguageService.tr(key));
      });
    }
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.length <= 28) return name;
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0]} ${parts[1]}';
    return '${name.substring(0, 24)}…';
  }

  Widget _buildSemesterSelector(ThemeData theme) {
    if (_semesters.isEmpty || _selectedSemId == null) return const SizedBox.shrink();
    final primary = theme.colorScheme.primary;
    final isDark  = theme.brightness == Brightness.dark;
    final selSem  = _semesters.firstWhere(
        (s) => s.id == _selectedSemId,
        orElse: () => _semesters.first);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
              Text(
                _formatSemName(selSem.name),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary),
              ),
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
        initialChildSize: 0.45,
        minChildSize: 0.25,
        maxChildSize: 0.75,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(LanguageService.tr('exams'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  shrinkWrap: true,
                  children: _semesters.map((sem) {
                    final selected = sem.id == _selectedSemId;
                    return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  onTap: () {
                    HapticService.medium();
                    Navigator.pop(context);
                    if (!selected && !_semLoading) _loadExamsForSemester(sem.id);
                  },
                  leading: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? primary : primary.withOpacity(0.08),
                    ),
                    child: Icon(
                      selected ? Icons.check_rounded : Icons.event_note_rounded,
                      size: 18,
                      color: selected ? Colors.white : primary,
                    ),
                  ),
                  title: Text(
                    _formatSemName(sem.name),
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? primary : theme.colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
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

  Widget _buildExamCard(ExamEntry exam, ThemeData theme) {
    final isDark     = theme.brightness == Brightness.dark;
    final past       = !exam.isUpcoming;
    final badgeColor = _badgeColor(exam, context);

    final displayName = LanguageService.currentLang.value == 'ქართული'
        ? (exam.nameKa.isNotEmpty ? exam.nameKa : exam.nameEn)
        : (exam.nameEn.isNotEmpty
            ? exam.nameEn
            : LanguageService.subjectDisplayName(exam.code, exam.nameKa));

    return Card(
      margin:    const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: past ? null : badgeColor.withOpacity(0.20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: past
            ? BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.3))
            : BorderSide(color: badgeColor.withOpacity(0.30), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Бейдж с датой ─────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: past
                        ? (isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : Colors.grey.shade100)
                        : badgeColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: past
                          ? theme.colorScheme.outlineVariant.withOpacity(0.3)
                          : badgeColor.withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        exam.date.day.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize:   22,
                          fontWeight: FontWeight.bold,
                          color:      past
                              ? theme.colorScheme.onSurface.withOpacity(0.35)
                              : badgeColor,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _monthAbbr(exam.date.month),
                        style: TextStyle(
                          fontSize: 12,
                          color:    past
                              ? theme.colorScheme.onSurface.withOpacity(0.30)
                              : badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 58,
                  child: Text(
                    _countdownLabel(exam),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize:   10,
                      fontWeight: FontWeight.w600,
                      color:      past
                          ? theme.colorScheme.onSurface.withOpacity(0.30)
                          : badgeColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 14),

            // ── Детали ────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.code,
                    style: TextStyle(
                      fontSize:      11,
                      fontWeight:    FontWeight.w600,
                      letterSpacing: 0.5,
                      color: past
                          ? theme.colorScheme.onSurface.withOpacity(0.40)
                          : badgeColor.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName.isNotEmpty ? displayName : exam.nameKa,
                    style: TextStyle(
                      fontSize:   15,
                      fontWeight: FontWeight.bold,
                      color:      past
                          ? theme.colorScheme.onSurface.withOpacity(0.45)
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (exam.teacher.isNotEmpty)
                    _infoRow(Icons.person_outline_rounded,
                        LanguageService.translateName(exam.teacher),
                        theme, past),
                  _infoRow(Icons.access_time_rounded,
                      '${_formatDate(exam.date)}  •  ${exam.time}',
                      theme, past),
                  if (exam.room.isNotEmpty)
                    _infoRow(Icons.location_on_outlined,
                        exam.room, theme, past),
                ],
              ),
            ),

            // ── Иконка — галочка для прошедших ───────────────
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                past
                    ? Icons.check_circle_rounded     // залитая галочка
                    : Icons.event_rounded,
                size:  20,
                color: past
                    ? const Color(0xFF16A34A)   // акцентный зелёный для прошедших
                    : badgeColor.withOpacity(0.80),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String text, ThemeData theme, bool past) {
    final color = past
        ? theme.colorScheme.onSurface.withOpacity(0.45)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style:    TextStyle(fontSize: 13, color: color),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String key, ThemeData theme, bool isPink) {
    final color = isPink
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(
            key == 'upcoming_exams'
                ? (isPink ? Icons.favorite_rounded : Icons.upcoming_rounded)
                : Icons.history_rounded,
            size: 16, color: color,
          ),
          const SizedBox(width: 6),
          Text(
            LanguageService.tr(key).toUpperCase(),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 0.8, color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  Widget _buildSkeleton(ThemeData theme, Color primary) {
    final isDark = theme.brightness == Brightness.dark;
    final base   = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine  = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _ExamSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Имитирует _buildSectionHeader — маленький лейбл с иконкой
    Widget sectionHeader() => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        box(16, 16, r: 4),
        const SizedBox(width: 6),
        box(110, 11, r: 4),
      ]),
    );

    // Имитирует _buildExamCard
    Widget examCard({double nameWidth = double.infinity}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.2 : 0.35)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Бейдж с датой (58px wide)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: primary.withOpacity(isDark ? 0.08 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    box(32, 24, r: 5),   // число
                    const SizedBox(height: 4),
                    box(28, 11, r: 4),   // месяц
                  ],
                ),
              ),
              const SizedBox(height: 5),
              box(50, 10, r: 4),         // countdown
            ],
          ),
          const SizedBox(width: 14),
          // Детали
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(60, 11, r: 4),       // код предмета
                const SizedBox(height: 4),
                box(nameWidth, 15, r: 6), // название
                const SizedBox(height: 4),
                box(nameWidth == double.infinity ? 180 : nameWidth * 0.7, 14, r: 5),
                const SizedBox(height: 10),
                // Строки с иконками: преподаватель, дата/время, аудитория
                Row(children: [box(14, 14, r: 3), const SizedBox(width: 6), box(130, 11, r: 4)]),
                const SizedBox(height: 6),
                Row(children: [box(14, 14, r: 3), const SizedBox(width: 6), box(150, 11, r: 4)]),
                const SizedBox(height: 6),
                Row(children: [box(14, 14, r: 3), const SizedBox(width: 6), box(80, 11, r: 4)]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Иконка справа
          box(20, 20, r: 10),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        // Пилюля семестра
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: box(170, 40, r: 20),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 120 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(),
                examCard(),
                examCard(nameWidth: 230),
                const SizedBox(height: 4),
                sectionHeader(),
                examCard(nameWidth: 210),
                examCard(),
                examCard(nameWidth: 250),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isPink  = _isPink(context);
    final primary = theme.colorScheme.primary;

    if (_loading) {
      return Scaffold(body: _buildSkeleton(theme, primary));
    }

    final upcoming = _exams.where((e) => e.isUpcoming).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = _exams.where((e) => !e.isUpcoming).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const SizedBox(height: 4),
          _buildSemesterSelector(theme),
          const SizedBox(height: 4),

          if (_semLoading)
            LinearProgressIndicator(
              color:           primary,
              backgroundColor: primary.withOpacity(0.15),
              minHeight:       2,
            )
          else
            const SizedBox(height: 2),

          Expanded(
            child: (_exams.isEmpty && !_semLoading) || _hasError
                ? _buildEmptyState(theme, isPink)
                : RefreshIndicator(
                    color:     primary,
                    onRefresh: _refresh,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 120 + MediaQuery.of(context).viewPadding.bottom),
                      children: [
                        if (upcoming.isNotEmpty) ...[
                          _buildSectionHeader('upcoming_exams', theme, isPink),
                          ...upcoming.map((e) => _buildExamCard(e, theme)),
                          const SizedBox(height: 4),
                        ],
                        if (past.isNotEmpty) ...[
                          _buildSectionHeader('past_exams', theme, isPink),
                          ...past.map((e) => _buildExamCard(e, theme)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isPink) {
    final primary = theme.colorScheme.primary;
    final semName = _selectedSemId != null && _semesters.isNotEmpty
        ? _semesters
            .firstWhere((s) => s.id == _selectedSemId,
                orElse: () => _semesters.first)
            .name
        : '';

    return RefreshIndicator(
      color:     primary,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 420,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        color:  primary.withOpacity(0.1),
                        shape:  BoxShape.circle,
                      ),
                      child: Icon(
                        _hasError
                            ? Icons.cloud_off_rounded
                            : (isPink
                                ? Icons.favorite_border_rounded
                                : Icons.event_busy_rounded),
                        size:  44,
                        color: primary.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      LanguageService.tr('no_data'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    if (semName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        semName,
                        style: TextStyle(
                          fontSize: 13,
                          color:    theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_hasError) ...[
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                        onPressed: () {
                          Parser.clearExamCache();
                          _loadData();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(LanguageService.tr('retry')),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _monthAbbr(int month) =>
      (month >= 1 && month <= 12) ? _monthsEn[month - 1] : '';
}

// ─── Shimmer-прямоугольник для скелетона экзаменов ───────────────
class _ExamSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _ExamSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_ExamSkeletonBox> createState() => _ExamSkeletonBoxState();
}

class _ExamSkeletonBoxState extends State<_ExamSkeletonBox>
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
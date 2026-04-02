import 'package:flutter/material.dart';
import '../models/lesson.dart';
import '../models/semester.dart';
import '../services/parser.dart';
import '../services/api.dart';
import '../services/language.dart';
import '../main.dart'; // для themeNotifier

class LessonPhase {
  final String nameKey;
  final int durationMins;
  final bool isBreak;
  final int? partNumber;
  const LessonPhase({
    required this.nameKey,
    required this.durationMins,
    required this.isBreak,
    this.partNumber,
  });
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  static void clearCache() {
    _ScheduleScreenState._cachedSchedule  = null;
    _ScheduleScreenState._cachedSemesters = null;
  }

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

  static const _weekDays = [
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ─── ЗАГРУЗКА ───────────────────────────────────────────────────

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final cacheValid = !forceRefresh &&
          _cachedSchedule != null && _cachedSchedule!.isNotEmpty &&
          _cachedSemesters != null;

      if (cacheValid) {
        _applyData(_cachedSchedule!, _cachedSemesters!);
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Один запрос вместо двух (ранее при html==null делался повторный вызов).
      final html = await ApiService.getHtml(ApiService.scheduleUrl);

      if (html == null || html.isEmpty) {
        _applyData([], []);
      } else {
        final sems    = Parser.parseSemesters(html);
        final lessons = Parser.parseScheduleFromHtml(html);
        if (lessons.isNotEmpty) {
          _cachedSchedule  = lessons;
          _cachedSemesters = sems;
        }
        _applyData(lessons, sems);
      }
    } catch (e) {
      debugPrint('ScheduleScreen._loadData ERROR: $e');
      _applyData([], []);
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _switchSemester(Semester sem) async {
    if (_selectedSem == sem || !mounted) return;
    setState(() { _semLoading = true; _selectedSem = sem; });
    try {
      final lessons = await Parser.parseScheduleForSemester(sem);
      _applyData(lessons, _semesters, preserveSemesters: true);
    } catch (e) {
      debugPrint('switchSemester ERROR: $e');
    }
    if (mounted) setState(() => _semLoading = false);
  }

  void _applyData(List<Lesson> lessons, List<Semester> sems,
      {bool preserveSemesters = false}) {
    final grouped = <String, List<Lesson>>{};
    for (final l in lessons) {
      if (l.day.isNotEmpty) grouped.putIfAbsent(l.day, () => []).add(l);
    }
    grouped.forEach((_, list) => list.sort((a, b) => a.time.compareTo(b.time)));

    final today      = _weekDays[DateTime.now().weekday - 1];
    final isVacation = lessons.isNotEmpty && !grouped.containsKey(today);
    final newSems    = preserveSemesters ? _semesters : sems;
    final newSel     = preserveSemesters
        ? _selectedSem
        : (newSems.isNotEmpty ? newSems.last : null);

    if (mounted) {
      setState(() {
        _groupedLessons = grouped;
        _semesters      = newSems;
        _selectedSem    = newSel;
        _isVacationDay  = isVacation;
      });
    }
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
    final currentDay = _weekDays[now.weekday - 1];
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
      phases.add(LessonPhase(
          nameKey: 'part', durationMins: dur, isBreak: false, partNumber: part));
      rem -= dur;
      if (rem > 0) {
        final bDur = rem > 10 ? 10 : rem;
        phases.add(LessonPhase(
            nameKey: 'break', durationMins: bDur, isBreak: true));
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 16),
              Text(LanguageService.tr('loading'),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final activeDays =
        _weekDays.where((d) => _groupedLessons.containsKey(d)).toList();

    return Scaffold(
      body: RefreshIndicator(
        color: primary,
        onRefresh: () => _loadData(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: _semesters.length > 1 ? 116 : 72,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              title: Text(
                LanguageService.tr('schedule'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
              ),
              centerTitle: false,
              flexibleSpace: _semesters.length > 1
                  ? FlexibleSpaceBar(
                      background: Align(
                        alignment: Alignment.bottomLeft,
                        child: _buildSemesterChips(),
                      ),
                      collapseMode: CollapseMode.pin,
                    )
                  : null,
              bottom: _semLoading
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(3),
                      child: LinearProgressIndicator(
                          color: primary, backgroundColor: Colors.transparent),
                    )
                  : null,
            ),

            if (_groupedLessons.isEmpty)
              SliverFillRemaining(
                child: Center(child: Text(LanguageService.tr('no_data'))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildDaySection(
                        activeDays[i],
                        _groupedLessons[activeDays[i]]!,
                        showBoth, isDark),
                    childCount: activeDays.length,
                  ),
                ),
              ),

            if (_isVacationDay && _groupedLessons.isNotEmpty)
              SliverToBoxAdapter(child: _buildVacationBanner(primary)),
          ],
        ),
      ),
    );
  }

  // ─── СЕМЕСТРЫ ────────────────────────────────────────────────────

  Widget _buildSemesterChips() {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _semesters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sem = _semesters[i];
          final sel = _selectedSem == sem;
          return FilterChip(
            selected: sel,
            label: Text(
              _formatSemName(sem.name),
              style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? primary : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            selectedColor: primary.withOpacity(0.15),
            checkmarkColor: primary,
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            side: BorderSide(
                color: sel ? primary : Colors.transparent, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onSelected: (_) => _switchSemester(sem),
          );
        },
      ),
    );
  }

  // FIX #2: Названия семестров приходят с портала CU на грузинском.
  // Переводим сезонные слова по текущему языку приложения.
  static const _semTranslations = <String, Map<String, String>>{
    // Грузинское слово → {en, ru}
    'გაზაფხულის': {'English': 'Spring',  'Русский': 'Весна'},
    'ზაფხულის':   {'English': 'Summer',  'Русский': 'Лето'},
    'შემოდგომის': {'English': 'Autumn',  'Русский': 'Осень'},
    'ზამთრის':    {'English': 'Winter',  'Русский': 'Зима'},
    'სემესტრი':   {'English': 'Semester','Русский': 'Семестр'},
    'სემ':        {'English': 'Sem',     'Русский': 'Сем'},
  };

  String _formatSemName(String rawName) {
    final lang = LanguageService.currentLang.value;
    String name = rawName.trim();

    // Для не-грузинских языков — заменяем грузинские слова переводами.
    if (lang != 'ქართული') {
      _semTranslations.forEach((geo, tr) {
        final translated = tr[lang];
        if (translated != null) {
          name = name.replaceAll(geo, translated);
        }
      });
    }

    // Убираем лишние пробелы после замены.
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Обрезаем если слишком длинное.
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
          Expanded(
            child: Text(
              LanguageService.tr('vacation_today'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ─── СЕКЦИЯ ДНЯ ─────────────────────────────────────────────────

  Widget _buildDaySection(
      String day, List<Lesson> lessons, bool showBoth, bool isDark) {
    final theme   = Theme.of(context);
    final now     = DateTime.now();
    final today   = _weekDays[now.weekday - 1];
    final isToday = day == today && !_isVacationDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4),
          child: Row(
            children: [
              if (isToday) ...[
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                LanguageService.translateDay(day),
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isToday
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    LanguageService.tr('today'),
                    style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ...lessons.map((l) => _buildLessonCard(l, showBoth, isDark)),
      ],
    );
  }

  // ─── КАРТОЧКА ЛЕКЦИИ ────────────────────────────────────────────

  Widget _buildLessonCard(Lesson lesson, bool showBoth, bool isDark) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final status  = _getLessonStatus(lesson.day, lesson.time);

    Color   accentColor = primary;
    Widget? badge;
    double  opacity     = 1.0;

    if (status == 1) {
      final tl    = _checkTimelineStatus(lesson.time);
      final isBrk = tl['isBreak'] as bool? ?? false;
      accentColor = isBrk ? Colors.blue : Colors.green;
      String ph   = LanguageService.tr(tl['nameKey'] as String? ?? 'part');
      final pNum  = tl['partNumber'];
      if (pNum != null) ph = '$ph $pNum';
      badge = _StatusBadge(label: ph, color: accentColor);
    } else if (status == 2) {
      accentColor = Colors.orange;
      badge = _StatusBadge(
          label: LanguageService.tr('soon'), color: accentColor);
    } else if (status == -1) {
      opacity     = 0.45;
      accentColor = theme.colorScheme.onSurface.withOpacity(0.3);
    }

    String displayTime = lesson.time;
    if (displayTime.contains('-')) {
      displayTime = showBoth
          ? '${displayTime.split('-')[0].trim()} – ${displayTime.split('-')[1].trim()}'
          : displayTime.split('-')[0].trim();
    }

    // FIX: IntrinsicHeight позволяет Row(crossAxisAlignment: stretch)
    // корректно работать внутри Column/SliverList с неограниченной высотой.
    // Без IntrinsicHeight Row получает h=Infinity и крашится с layout error.
    return Opacity(
      opacity: opacity,
      child: IntrinsicHeight(
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          // clipBehavior обрезает все дочерние виджеты по скруглённым углам
          // карточки. Без него цветная полоска слева выходила за рамки.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (status > 0 ? accentColor : Colors.black)
                    .withOpacity(isDark ? 0.12 : 0.07),
                blurRadius: status > 0 ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: status > 0
                ? Border.all(
                    color: accentColor.withOpacity(0.5), width: 1.5)
                : Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withOpacity(0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Цветная полоска слева — форму задаёт clipBehavior карточки
              Container(
                width: 4,
                color: accentColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 15, color: accentColor),
                          const SizedBox(width: 5),
                          Text(
                            displayTime,
                            style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14,
                              color: accentColor,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8), badge,
                          ],
                          const Spacer(),
                          if (lesson.room.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.meeting_room_outlined,
                                      size: 13, color: accentColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    lesson.room,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        LanguageService.translateName(lesson.name),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16, height: 1.2),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              LanguageService.translateName(lesson.teacher),
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      theme.colorScheme.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (status == 1)
                        _buildProgressBar(lesson.time, accentColor, isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ПРОГРЕСС-БАР ───────────────────────────────────────────────

  Widget _buildProgressBar(String timeStr, Color color, bool isDark) {
    final theme   = Theme.of(context);
    final status  = _checkTimelineStatus(timeStr);
    final elapsed = (status['elapsed'] as int?) ?? 0;
    final phases  = (status['phases'] as List?)?.cast<LessonPhase>() ?? [];
    final bgColor = theme.colorScheme.surfaceContainerHighest;

    if (phases.isEmpty) return const SizedBox.shrink();

    final barSegs = <Widget>[];
    final labels  = <Widget>[];
    int acc = 0;

    for (int i = 0; i < phases.length; i++) {
      final ph      = phases[i];
      final prog    = elapsed > acc
          ? ((elapsed - acc) / ph.durationMins).clamp(0.0, 1.0)
          : 0.0;
      final isFirst = i == 0;
      final isLast  = i == phases.length - 1;

      barSegs.add(Expanded(
        flex: ph.durationMins,
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft:     isFirst ? const Radius.circular(4) : Radius.zero,
            bottomLeft:  isFirst ? const Radius.circular(4) : Radius.zero,
            topRight:    isLast  ? const Radius.circular(4) : Radius.zero,
            bottomRight: isLast  ? const Radius.circular(4) : Radius.zero,
          ),
          child: LinearProgressIndicator(
            value: prog,
            backgroundColor: bgColor,
            color: ph.isBreak ? Colors.blue : Colors.green,
            minHeight: 6,
          ),
        ),
      ));

      if (!isLast) {
        barSegs.add(Container(
            width: 2, height: 6,
            color: theme.scaffoldBackgroundColor));
        labels.add(const SizedBox(width: 2));
      }

      labels.add(Expanded(
        flex: ph.durationMins,
        child: Center(
          child: Text(
            '${ph.durationMins}${LanguageService.tr('min')}',
            style: TextStyle(
              fontSize: 9,
              color: ph.isBreak
                  ? Colors.blue
                  : theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.clip,
            maxLines: 1,
          ),
        ),
      ));
      acc += ph.durationMins;
    }

    final nameKey  = status['nameKey'] as String? ?? 'part';
    final pNum     = status['partNumber'];
    String pLabel  = LanguageService.tr(nameKey);
    if (pNum != null) pLabel = '$pLabel $pNum';
    final timeLeft = (status['timeLeft'] as int?) ?? 0;
    final isBrk    = (status['isBreak'] as bool?) ?? false;

    return Column(
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$pLabel · $timeLeft ${LanguageService.tr('min')} ${LanguageService.tr('left')}',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
            if (isBrk)
              const Icon(Icons.coffee_rounded, size: 13, color: Colors.blue),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: barSegs),
        const SizedBox(height: 3),
        Row(children: labels),
      ],
    );
  }
}

// ─── BADGE ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.bold)),
      );
}

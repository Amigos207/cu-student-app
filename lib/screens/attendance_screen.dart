import 'package:flutter/material.dart';
import '../models/attendance.dart';
import '../services/data_service.dart';
import '../services/language.dart';
import '../utils/schedule_utils.dart';

class AttendanceScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const AttendanceScreen({super.key, this.onMenuTap});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Attendance> _data     = [];
  bool             _loading  = true;

  Map<String, String> _nameByTeacher  = {};  // simplifiedTeacher → englishName
  Map<String, String> _nameBySubject  = {};  // simplifiedSubject → englishName
  Map<String, String> _teacherByName  = {};  // simplifiedEnglishName → teacher

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
      // Both calls are deduplicated by DataService — if HomeScreen or
      // ScheduleScreen already fetched schedule/attendance, we get cached
      // results instantly with zero extra HTTP requests.
      final schedule = await DataService.instance.fetchSchedule(forceRefresh: forceRefresh);
      final data     = await DataService.instance.fetchAttendance(forceRefresh: forceRefresh);

      // Guard: don't overwrite existing data with an empty result
      // (network failure / expired session).
      if (data.isEmpty && _data.isNotEmpty && !forceRefresh) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final Map<String, String> nameByTeacher = {};
      final Map<String, String> nameBySubject  = {};
      final Map<String, String> teacherByName  = {};
      for (final l in schedule) {
        final tKey = simplify(l.teacher);  // from schedule_utils.dart
        final sKey = simplify(l.name);
        if (tKey.isNotEmpty) nameByTeacher[tKey] = l.name;
        if (sKey.isNotEmpty) nameBySubject[sKey]  = l.name;
        if (sKey.isNotEmpty && l.teacher.isNotEmpty) {
          teacherByName[sKey] = l.teacher;
        }
      }
      LanguageService.seedCodeMap({
        for (final l in schedule)
          if (l.code.isNotEmpty && l.name.isNotEmpty) l.code: l.name,
      });

      if (mounted) {
        setState(() {
          _data           = data;
          _nameByTeacher  = nameByTeacher;
          _nameBySubject  = nameBySubject;
          _teacherByName  = teacherByName;
          _loading        = false;
        });
      }
    } catch (e) {
      debugPrint('AttendanceScreen._loadData ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Возвращает имя преподавателя из расписания по английскому названию предмета.
  String _getTeacherFromSchedule(String displaySubject) {
    final key = simplify(displaySubject);
    if (_teacherByName.containsKey(key)) return _teacherByName[key]!;
    // Нечёткий поиск
    for (final e in _teacherByName.entries) {
      if (key.contains(e.key) || e.key.contains(key)) return e.value;
    }
    return '';
  }

  String _getBeautifulSubjectName(String subject, String teacher) {
    final tKey = simplify(teacher);
    final sKey = simplify(subject);

    // 1. Точное совпадение по преподавателю
    if (tKey.isNotEmpty && _nameByTeacher.containsKey(tKey)) {
      return _nameByTeacher[tKey]!;
    }
    // 2. Если teacher пустой — возможно subject и есть имя преподавателя
    //    (такое бывает когда портал записывает только препода, без названия)
    if (tKey.isEmpty && sKey.isNotEmpty && _nameByTeacher.containsKey(sKey)) {
      return _nameByTeacher[sKey]!;
    }
    // 3. Точное совпадение по названию предмета
    if (sKey.isNotEmpty && _nameBySubject.containsKey(sKey)) {
      return _nameBySubject[sKey]!;
    }
    // 4. Нечёткий поиск по преподавателю
    if (tKey.isNotEmpty) {
      for (final e in _nameByTeacher.entries) {
        if (tKey.contains(e.key) || e.key.contains(tKey)) return e.value;
      }
    }
    // 5. Нечёткий поиск: subject как имя преподавателя
    if (tKey.isEmpty && sKey.isNotEmpty) {
      for (final e in _nameByTeacher.entries) {
        if (sKey.contains(e.key) || e.key.contains(sKey)) return e.value;
      }
    }
    // 6. Нечёткий поиск по названию предмета
    if (sKey.isNotEmpty) {
      for (final e in _nameBySubject.entries) {
        if (sKey.contains(e.key) || e.key.contains(sKey)) return e.value;
      }
    }
    return subject;
  }

  // ─── ТЕМА ───────────────────────────────────────────────────────

  // FIX #3: Определяем розовую тему через Theme.of(context) —
  // это убирает отдельный ValueListenableBuilder<themeNotifier>
  // в build(), который вызывал ДВОЙНОЙ полный rebuild всего дерева
  // при каждой смене темы → заметный лаг.
  // MaterialApp уже пересобирает дерево при смене theme — одного
  // прохода достаточно.
  bool _isPink(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.primary == const Color(0xFFD81B60);

  Color _getColor(double perc, BuildContext ctx) {
    if (_isPink(ctx)) {
      if (perc >= 0.8) return const Color(0xFFD81B60);
      if (perc >= 0.6) return const Color(0xFFE91E8C).withOpacity(0.65);
      return const Color(0xFF880E4F);
    }
    if (perc >= 0.8) return Colors.green;
    if (perc >= 0.6) return Colors.orange;
    return Colors.red;
  }

  // ─── СТРОКА ЛЕКЦИИ ──────────────────────────────────────────────

  Widget _buildLectureRow(LectureRecord rec, BuildContext context) {
    final theme  = Theme.of(context);
    final isPink = _isPink(context);

    final IconData icon;
    final Color    iconColor;
    final String   statusText;

    if (!rec.isPast) {
      icon       = Icons.schedule;
      iconColor  = theme.colorScheme.onSurface.withOpacity(0.5);
      statusText = LanguageService.tr('upcoming');
    } else if (rec.isAbsent) {
      icon       = isPink ? Icons.heart_broken_rounded : Icons.cancel;
      iconColor  = isPink ? const Color(0xFF880E4F) : Colors.red;
      statusText = LanguageService.tr('missed');
    } else if (rec.isPending) {
      icon       = isPink ? Icons.favorite_border_rounded : Icons.hourglass_empty_rounded;
      iconColor  = isPink ? const Color(0xFFE91E8C) : Colors.orange;
      statusText = LanguageService.tr('pending');
    } else {
      icon       = isPink ? Icons.favorite_rounded : Icons.check_circle;
      iconColor  = isPink ? const Color(0xFFD81B60) : Colors.green;
      statusText = LanguageService.tr('attended_status');
    }

    final dateDisplay = rec.isDateReal
        ? rec.date
        : '${LanguageService.tr('lecture')} ${rec.date}';

    final checkColor = isPink ? const Color(0xFF880E4F) : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              dateDisplay,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                  color: iconColor, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: rec.checks.map((checked) {
              return Container(
                margin: const EdgeInsets.only(left: 4),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: checked ? checkColor : Colors.transparent,
                  border: Border.all(
                    color: checked ? checkColor : theme.dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: checked
                    ? const Icon(Icons.close, size: 10, color: Colors.white)
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── СКЕЛЕТОН ЗАГРУЗКИ ──────────────────────────────────────────

  Widget _buildSkeleton(ThemeData theme, bool isDark) {
    final primary = theme.colorScheme.primary;
    final base    = isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final shine   = isDark ? Colors.white.withOpacity(0.13) : Colors.black.withOpacity(0.11);

    Widget box(double w, double h, {double r = 8}) =>
        _AttendSkeletonBox(width: w, height: h, radius: r, base: base, shine: shine);

    // Имитирует одну карточку ExpansionTile посещаемости
    Widget attendCard({double nameWidth = double.infinity, bool twoLines = false}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.18 : 0.25)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Название предмета (1–2 строки)
            box(nameWidth, 16, r: 6),
            if (twoLines) ...[
              const SizedBox(height: 5),
              box(nameWidth == double.infinity ? 200 : nameWidth * 0.7, 14, r: 5),
            ],
            const SizedBox(height: 6),
            // Преподаватель
            box(150, 12, r: 4),
            const SizedBox(height: 14),
            // Прогресс-бар
            box(double.infinity, 8, r: 4),
            const SizedBox(height: 10),
            // Нижняя строка: статистика слева + процент справа
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(140, 12, r: 4),
                    const SizedBox(height: 5),
                    box(110, 12, r: 4),
                  ],
                ),
                const Spacer(),
                box(52, 22, r: 6),
              ],
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16, 8, 16,
        140 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        children: [
          attendCard(nameWidth: 240),
          attendCard(twoLines: true),
          attendCard(nameWidth: 200),
          attendCard(twoLines: true, nameWidth: 260),
          attendCard(nameWidth: 220),
          attendCard(twoLines: true),
        ],
      ),
    );
  }

  // ─── КАРТОЧКА ПОСЕЩАЕМОСТИ ──────────────────────────────────────

  Widget _buildAttendanceCard(Attendance item, bool isDark, BuildContext ctx) {
    final theme   = Theme.of(ctx);
    final isPink  = _isPink(ctx);
    final primary = theme.colorScheme.primary;

    final displaySubject = () {
      final s = _getBeautifulSubjectName(item.subject, item.teacher);
      return s.isNotEmpty ? s : LanguageService.tr('lecture');
    }();

    // Определяем имя преподавателя: берём из посещаемости, либо ищем в расписании
    final displayTeacher = item.teacher.isNotEmpty
        ? item.teacher
        : _getTeacherFromSchedule(displaySubject);

    final perc       = item.percentage;
    final percWorst  = item.percentageWorstCase;
    final color      = _getColor(perc, ctx);
    final colorWorst = _getColor(percWorst, ctx);
    final hasPending = item.pendingLectures > 0;

    final barBg = isPink
        ? const Color(0xFFFFD6E7)
        : theme.colorScheme.surfaceContainerHighest;

    final percColor = isPink ? primary : color;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPink ? 3 : 2,
      shadowColor: isPink ? primary.withOpacity(0.3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPink
            ? BorderSide(color: primary.withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LanguageService.translateName(displaySubject),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (displayTeacher.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  LanguageService.translateName(displayTeacher),
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.passedLectures > 0 ? perc : 0,
                  backgroundColor: barBg,
                  color: color,
                  minHeight: 8,
                ),
              ),

              if (hasPending) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percWorst,
                    backgroundColor: barBg,
                    color: colorWorst.withOpacity(0.4),
                    minHeight: 4,
                  ),
                ),
              ],

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isPink)
                          _buildPinkStatChips(item, ctx)
                        else
                          Text(
                            _buildStatsText(item),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPink) ...[
                            Icon(
                              perc >= 0.8
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: percColor,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${(perc * 100).toInt()}%',
                            style: TextStyle(
                              color: percColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      if (hasPending)
                        Text(
                          '≥ ${(percWorst * 100).toInt()}%',
                          style: TextStyle(
                            color: colorWorst.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPink
                    ? primary.withOpacity(0.06)
                    : (isDark
                        ? theme.colorScheme.onSurface.withOpacity(0.04)
                        : Colors.black.withOpacity(0.02)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPink)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.favorite_rounded,
                              size: 14, color: primary),
                        ),
                      Text(
                        LanguageService.tr('details'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isPink
                              ? primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    height: 24,
                    color: isPink ? primary.withOpacity(0.2) : null,
                  ),
                  ...item.records
                      .map((rec) => _buildLectureRow(rec, ctx)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinkStatChips(Attendance item, BuildContext ctx) {
    final primary = Theme.of(ctx).colorScheme.primary;

    Widget chip(String text, Color color, IconData icon) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(text,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        );

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip(
          '${LanguageService.tr('passed_lectures')}: '
              '${item.passedLectures}/${item.totalLectures}',
          primary,
          Icons.event_note_rounded,
        ),
        chip(
          '${LanguageService.tr('attended_count')}: ${item.attendedLectures}',
          const Color(0xFFD81B60),
          Icons.favorite_rounded,
        ),
        if (item.pendingLectures > 0)
          chip(
            '${LanguageService.tr('pending')}: ${item.pendingLectures}',
            const Color(0xFFE91E8C),
            Icons.favorite_border_rounded,
          ),
      ],
    );
  }

  String _buildStatsText(Attendance item) {
    final lines = <String>[
      '${LanguageService.tr('passed_lectures')}: ${item.passedLectures} '
          '${LanguageService.tr('out_of')} ${item.totalLectures}',
      '${LanguageService.tr('attended_count')}: ${item.attendedLectures}',
    ];
    if (item.pendingLectures > 0) {
      lines.add('${LanguageService.tr('pending')}: ${item.pendingLectures}');
    }
    return lines.join('\n');
  }

  // ─── BUILD ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // FIX #3: ValueListenableBuilder<themeNotifier> УБРАН.
    // Раньше: MaterialApp rebuild (смена темы) → attendance rebuild (themeNotifier)
    //         = два полных прохода по дереву → заметный лаг.
    // Теперь: только один rebuild через MaterialApp.
    // Розовая тема определяется через _isPink(context) → Theme.of(context),
    // который уже содержит актуальную тему после rebuild MaterialApp.
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(body: _buildSkeleton(theme, isDark));
    }

    return Scaffold(
      body: _data.isEmpty
          ? Center(child: Text(LanguageService.tr('no_data')))
          : RefreshIndicator(
              color: theme.colorScheme.primary,
              onRefresh: () => _loadData(forceRefresh: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 8,
                  left: 16,
                  right: 16,
                  bottom: 140 + MediaQuery.of(context).viewPadding.bottom,
                ),
                itemCount: _data.length,
                itemBuilder: (ctx, index) =>
                    _buildAttendanceCard(_data[index], isDark, ctx),
              ),
            ),
    );
  }
}

// ─── Shimmer-прямоугольник для скелетона посещаемости ────────────
class _AttendSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _AttendSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_AttendSkeletonBox> createState() => _AttendSkeletonBoxState();
}

class _AttendSkeletonBoxState extends State<_AttendSkeletonBox>
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
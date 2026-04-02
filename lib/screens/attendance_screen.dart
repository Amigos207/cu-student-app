import 'package:flutter/material.dart';
import '../models/attendance.dart';
import '../models/lesson.dart';
import '../services/parser.dart';
import '../services/language.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Attendance> _data     = [];
  List<Lesson>     _schedule = [];
  bool             _loading  = true;

  Map<String, String> _nameByTeacher = {};
  Map<String, String> _nameBySubject  = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final schedule = await Parser.parseSchedule();
      final data     = await Parser.parseAttendance(schedule);

      final Map<String, String> nameByTeacher = {};
      final Map<String, String> nameBySubject  = {};
      for (final l in schedule) {
        final tKey = _simplify(l.teacher);
        final sKey = _simplify(l.name);
        if (tKey.isNotEmpty) nameByTeacher[tKey] = l.name;
        if (sKey.isNotEmpty) nameBySubject[sKey]  = l.name;
      }

      if (mounted) {
        setState(() {
          _data          = data;
          _schedule      = schedule;
          _nameByTeacher = nameByTeacher;
          _nameBySubject = nameBySubject;
          _loading       = false;
        });
      }
    } catch (e) {
      debugPrint('AttendanceScreen._loadData ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── ВСПОМОГАТЕЛЬНЫЕ ────────────────────────────────────────────

  static String _simplify(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

  String _getBeautifulSubjectName(String subject, String teacher) {
    final tKey = _simplify(teacher);
    final sKey = _simplify(subject);
    if (tKey.isNotEmpty && _nameByTeacher.containsKey(tKey)) {
      return _nameByTeacher[tKey]!;
    }
    if (sKey.isNotEmpty && _nameBySubject.containsKey(sKey)) {
      return _nameBySubject[sKey]!;
    }
    if (tKey.isNotEmpty) {
      for (final e in _nameByTeacher.entries) {
        if (tKey.contains(e.key) || e.key.contains(tKey)) return e.value;
      }
    }
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

  // ─── КАРТОЧКА ПОСЕЩАЕМОСТИ ──────────────────────────────────────

  Widget _buildAttendanceCard(Attendance item, bool isDark, BuildContext ctx) {
    final theme   = Theme.of(ctx);
    final isPink  = _isPink(ctx);
    final primary = theme.colorScheme.primary;

    final displaySubject = () {
      final s = _getBeautifulSubjectName(item.subject, item.teacher);
      return s.isNotEmpty ? s : LanguageService.tr('lecture');
    }();

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
              if (item.teacher.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  LanguageService.translateName(item.teacher),
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
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.tr('attendance')),
        centerTitle: true,
      ),
      body: _data.isEmpty
          ? Center(child: Text(LanguageService.tr('no_data')))
          : RefreshIndicator(
              color: theme.colorScheme.primary,
              onRefresh: _loadData,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _data.length,
                itemBuilder: (ctx, index) =>
                    _buildAttendanceCard(_data[index], isDark, ctx),
              ),
            ),
    );
  }
}

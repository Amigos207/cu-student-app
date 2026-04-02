import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/lesson.dart';
import '../models/attendance.dart';
import '../models/semester.dart';
import 'api.dart';
import 'storage.dart';

class Parser {
  static const _daysMap = {
    'ორშ': 'Monday',   'სამ': 'Tuesday',  'სამშ': 'Tuesday',
    'ოთხ': 'Wednesday','ხუთ': 'Thursday', 'პარ':  'Friday',
    'შაბ': 'Saturday', 'კვ':  'Sunday',   'კვი':  'Sunday',
  };

  static const _confirmedBgColor = '#008000';

  static String _simplify(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

  // ─── СЕМЕСТРЫ ────────────────────────────────────────────────────

  /// Парсит список семестров из HTML страницы расписания.
  /// Ищет radio-кнопки с name="sem_id1" и соответствующие hidden-поля.
  static List<Semester> parseSemesters(String htmlBody) {
    final doc = parse(htmlBody);
    final result = <Semester>[];

    // Находим все radio input с name="sem_id1"
    final radios = doc.querySelectorAll('input[name="sem_id1"][type="radio"]');

    for (final radio in radios) {
      final idStr = radio.attributes['value'];
      if (idStr == null) continue;
      final id = int.tryParse(idStr);
      if (id == null) continue;

      // Ищем hidden-поле "semestri" в том же <table>/<tr> — оно следует сразу за radio
      // Портал CU: <input radio value="88">2026 გაზ...<input hidden name="semestri" value=" 2026 გაზ...">
      String name = '';

      // Попытка 1: текстовый узел после radio в родительском TD
      final parent = radio.parent;
      if (parent != null) {
        // Ищем скрытый input "semestri" в той же строке таблицы
        final tr = _findAncestor(parent, 'tr');
        if (tr != null) {
          final hidden = tr.querySelector('input[name="semestri"]');
          if (hidden != null) {
            name = (hidden.attributes['value'] ?? '').trim();
          }
        }
        // Fallback: берём текст из родительской ячейки, убираем числа
        if (name.isEmpty) {
          name = parent.text
              .replaceAll(RegExp(r'\d'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      }

      if (name.isNotEmpty) {
        result.add(Semester(id: id, name: name));
      }
    }

    // Сортируем по id: последний (наибольший) — текущий семестр
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  static Element? _findAncestor(Element el, String tag) {
    Element? current = el.parent;
    while (current != null) {
      if (current.localName?.toLowerCase() == tag) return current;
      current = current.parent;
    }
    return null;
  }

  // ─── ПАРСИНГ РАСПИСАНИЯ ─────────────────────────────────────────

  /// Загружает расписание текущего (активного) семестра.
  static Future<List<Lesson>> parseSchedule() async {
    try {
      final String html;
      if (Storage.getUser() == 'admin') {
        html = await rootBundle.loadString('assets/schedule.html');
      } else {
        final fetched = await ApiService.getHtml(ApiService.scheduleUrl);
        if (fetched == null || fetched.isEmpty) return [];
        html = fetched;
      }
      return _parseScheduleHtml(html);
    } catch (e) {
      print('parseSchedule ERROR: $e');
      return [];
    }
  }

  /// Парсит расписание из уже полученного HTML (без сетевого запроса).
  static List<Lesson> parseScheduleFromHtml(String html) => _parseScheduleHtml(html);

  /// Загружает расписание конкретного семестра через POST.
  static Future<List<Lesson>> parseScheduleForSemester(Semester sem) async {
    try {
      if (Storage.getUser() == 'admin') {
        return parseSchedule(); // В demo-режиме всегда одно расписание
      }
      final html = await ApiService.fetchScheduleForSemester(sem.id, sem.name);
      if (html == null || html.isEmpty) return [];
      return _parseScheduleHtml(html);
    } catch (e) {
      print('parseScheduleForSemester ERROR: $e');
      return [];
    }
  }

  static List<Lesson> _parseScheduleHtml(String htmlString) {
    final doc   = parse(htmlString);
    final table = _findTableByHeader(doc, 'საგნის კოდი');
    if (table == null) {
      print('parseSchedule: table not found');
      return [];
    }

    final rows   = table.getElementsByTagName('tr');
    final result = <Lesson>[];
    final seen   = <String>{};

    for (var i = 1; i < rows.length; i++) {
      final cols = rows[i].getElementsByTagName('td');
      if (cols.length < 4) continue;

      final name    = _cellText(cols.length > 1 ? cols[1] : cols[0]);
      final teacher = cols.length > 2 ? _cellText(cols[2]) : '';
      if (name.isEmpty) continue;

      final rawDays  = cols.length > 3 ? cols[3].text.trim().split('/') : <String>[];
      final rawTimes = cols.length > 4 ? cols[4].text.trim().split('/') : <String>[];
      final rawRooms = cols.length > 5 ? cols[5].text.trim().split('/') : <String>[];

      if (rawDays.isEmpty) {
        result.add(Lesson(name: name, teacher: teacher, day: '', time: '', room: ''));
        continue;
      }

      for (var j = 0; j < rawDays.length; j++) {
        final rawDay = rawDays[j].trim();
        final dayEn  = _daysMap[rawDay] ?? rawDay;
        final time   = j < rawTimes.length ? rawTimes[j].trim() : '';
        final room   = (j < rawRooms.length ? rawRooms[j].trim() : '')
            .replaceAll('მთავარი კამპუსი-', '');
        final key    = '$name|$dayEn|$time';
        if (!seen.contains(key)) {
          result.add(Lesson(name: name, teacher: teacher, day: dayEn, time: time, room: room));
          seen.add(key);
        }
      }
    }

    print('parseSchedule: ${result.length} lessons');
    return result;
  }

  // ─── ПАРСИНГ ПОСЕЩАЕМОСТИ ───────────────────────────────────────

  static Future<List<Attendance>> parseAttendance(List<Lesson> schedule) async {
    try {
      final String html;
      if (Storage.getUser() == 'admin') {
        html = await rootBundle.loadString('assets/attendance.html');
      } else {
        final fetched = await ApiService.getHtml(ApiService.attendanceUrl);
        if (fetched == null || fetched.isEmpty) return [];
        html = fetched;
      }
      return _parseAttendanceHtml(html, schedule);
    } catch (e) {
      print('parseAttendance ERROR: $e');
      return [];
    }
  }

  static List<Attendance> _parseAttendanceHtml(String htmlString, List<Lesson> schedule) {
    final doc    = parse(htmlString);
    final tables = doc.getElementsByTagName('table');
    if (tables.isEmpty) return [];

    final table = _findAttendanceTable(tables);
    if (table == null) {
      print('parseAttendance: table not found');
      return [];
    }

    // Строим O(1)-индексы
    final Map<String, Lesson> fullIndex    = {};
    final Map<String, Lesson> nameIndex    = {};
    final Map<String, Lesson> teacherIndex = {};
    for (final l in schedule) {
      final sk = '${_simplify(l.name)}|${_simplify(l.teacher)}';
      fullIndex.putIfAbsent(sk, () => l);
      nameIndex.putIfAbsent(_simplify(l.name), () => l);
      if (l.teacher.isNotEmpty) teacherIndex.putIfAbsent(_simplify(l.teacher), () => l);
    }

    final rows   = table.getElementsByTagName('tr');
    final result = <Attendance>[];
    final now    = DateTime.now();

    List<DateTime?> currentDates     = [];
    List<bool>      currentConfirmed = [];

    for (var i = 0; i < rows.length; i++) {
      final row     = rows[i];
      final rowText = row.text;

      if (_isHeaderRow(rowText)) {
        currentDates     = [];
        currentConfirmed = [];
        for (final cell in row.children) {
          final text    = cell.text.trim();
          final isGreen = cell.attributes['bgcolor']?.toUpperCase() == _confirmedBgColor;
          final full    = _parseFullDate(text);
          if (full != null) { currentDates.add(full); currentConfirmed.add(isGreen); continue; }
          final partial = _parsePartialDate(text, now);
          if (partial != null) { currentDates.add(partial); currentConfirmed.add(isGreen); continue; }
          if (cell.attributes['colspan'] != null) { currentDates.add(null); currentConfirmed.add(false); }
        }
        continue;
      }

      final checkboxes = row
          .getElementsByTagName('input')
          .where((e) => e.attributes['type']?.toLowerCase() == 'checkbox')
          .toList();
      if (checkboxes.isEmpty) continue;

      final cells = row.getElementsByTagName('td');
      if (cells.length < 3) continue;

      final (subjectName, teacherName) = _extractSubjectTeacher(cells);
      if (subjectName.isEmpty) continue;

      final matchedLesson = _findMatchingLesson(subjectName, teacherName, fullIndex, nameIndex, teacherIndex);
      final totalLectures = checkboxes.length ~/ 3;
      final records       = <LectureRecord>[];
      int passed = 0, attended = 0, pendingCount = 0;

      for (var k = 0; k < totalLectures; k++) {
        final idx         = k * 3;
        final isAbsent    = _isChecked(checkboxes, idx) || _isChecked(checkboxes, idx+1) || _isChecked(checkboxes, idx+2);
        final isConfirmed = k < currentConfirmed.length ? currentConfirmed[k] : false;

        String dateDisplay = '${k + 1}';
        bool   isDateReal  = false;
        bool   isDatePast  = false;

        if (k < currentDates.length && currentDates[k] != null) {
          final d     = currentDates[k]!;
          dateDisplay = _formatDate(d);
          isDateReal  = true;
          isDatePast  = now.isAfter(_getLectureEndTime(d, matchedLesson));
        }

        final bool isPast    = isDatePast || isAbsent || isConfirmed;
        final bool isPending = isPast && !isAbsent && !isConfirmed;

        records.add(LectureRecord(
          date: dateDisplay, isDateReal: isDateReal,
          isPast: isPast, isAbsent: isAbsent,
          isConfirmed: isConfirmed, isPending: isPending,
          checks: [_isChecked(checkboxes,idx), _isChecked(checkboxes,idx+1), _isChecked(checkboxes,idx+2)],
        ));

        if (isPast)    passed++;
        if (isPending) pendingCount++;
        if (isPast && !isAbsent && !isPending) attended++;
      }

      if (totalLectures > 0) {
        result.add(Attendance(
          subject: subjectName, teacher: teacherName,
          totalLectures: totalLectures, passedLectures: passed,
          attendedLectures: attended, pendingLectures: pendingCount,
          records: records,
        ));
      }
    }

    print('parseAttendance: ${result.length} subjects');
    return result;
  }

  // ─── ПОИСК ТАБЛИЦ ───────────────────────────────────────────────

  static Element? _findTableByHeader(Document doc, String headerText) {
    for (final table in doc.getElementsByTagName('table')) {
      final firstRow = table.querySelector('tr');
      if (firstRow != null && firstRow.text.contains(headerText)) return table;
    }
    return null;
  }

  static Element? _findAttendanceTable(List<Element> tables) {
    Element? best;
    int maxCb = 0;
    for (final t in tables) {
      final count = t.getElementsByTagName('input')
          .where((e) => e.attributes['type']?.toLowerCase() == 'checkbox').length;
      if (count > maxCb) { maxCb = count; best = t; }
    }
    return maxCb > 0 ? best : null;
  }

  // ─── ВСПОМОГАТЕЛЬНЫЕ ────────────────────────────────────────────

  static String _cellText(Element cell) =>
      cell.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isChecked(List<Element> boxes, int idx) =>
      idx < boxes.length && boxes[idx].attributes.containsKey('checked');

  static bool _isHeaderRow(String t) =>
      t.contains('საგნის დასახელება') || t.contains('Subject name') ||
      t.contains('Subject') || t.contains('ლექტორი') || t.contains('Lecturer');

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  static DateTime? _parseFullDate(String text) {
    final m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})').firstMatch(text);
    if (m == null) return null;
    try { return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)); }
    catch (_) { return null; }
  }

  static DateTime? _parsePartialDate(String text, DateTime now) {
    final m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})').firstMatch(text);
    if (m == null) return null;
    try {
      final day = int.parse(m.group(1)!), month = int.parse(m.group(2)!);
      int year = now.year;
      if (month > 8 && now.month < 6) year--;
      if (month < 6 && now.month > 8) year++;
      return DateTime(year, month, day);
    } catch (_) { return null; }
  }

  static (String, String) _extractSubjectTeacher(List<Element> cells) {
    final texts = <String>[];
    for (var c = 0; c < 5 && c < cells.length; c++) {
      var t = cells[c].text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isEmpty || RegExp(r'^\d+$').hasMatch(t) || t.contains('საგნის')) continue;
      t = t.replaceAll('ლექტორი','').replaceAll('Lecturer','').replaceAll(':','').trim();
      if (t.isNotEmpty && !texts.contains(t)) texts.add(t);
    }
    return (texts.isNotEmpty ? texts[0] : '', texts.length > 1 ? texts.sublist(1).join(', ') : '');
  }

  static Lesson? _findMatchingLesson(String sub, String teach,
      Map<String,Lesson> full, Map<String,Lesson> name, Map<String,Lesson> teacher) {
    final sN = _simplify(sub), tN = _simplify(teach);
    if (full.containsKey('$sN|$tN')) return full['$sN|$tN'];
    if (tN.isNotEmpty) {
      for (final e in teacher.entries) {
        if (tN.contains(e.key) || e.key.contains(tN)) return e.value;
      }
    }
    if (sN.isNotEmpty) {
      for (final e in name.entries) {
        if (sN.contains(e.key) || e.key.contains(sN)) return e.value;
      }
    }
    return null;
  }

  static DateTime _getLectureEndTime(DateTime date, Lesson? lesson) {
    if (lesson == null || lesson.time.isEmpty) {
      return DateTime(date.year, date.month, date.day, 23, 59);
    }
    final parts = lesson.time.split(RegExp(r'[-–]'));
    if (parts.length < 2) return DateTime(date.year, date.month, date.day, 23, 59);
    final tp = parts[1].trim().split(':');
    if (tp.length < 2) return DateTime(date.year, date.month, date.day, 23, 59);
    try {
      return DateTime(date.year, date.month, date.day, int.parse(tp[0]), int.parse(tp[1]));
    } catch (_) {
      return DateTime(date.year, date.month, date.day, 23, 59);
    }
  }
}
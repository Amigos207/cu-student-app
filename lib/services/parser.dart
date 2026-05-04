import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import '../models/lesson.dart';
import '../models/attendance.dart';
import '../models/semester.dart';
import '../models/grade.dart';
import '../models/exam_entry.dart';
import '../models/course_material.dart';
import 'api.dart';
import 'storage.dart';
import '../models/syllabus_subject.dart';
import '../models/payment.dart';
import 'mock_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Transfer objects used by the background isolate for attendance parsing.
// Only primitives, DateTime, and List<bool> — all safely transferable between
// Dart isolates via compute().
// ─────────────────────────────────────────────────────────────────────────────

/// Raw per-lecture data extracted by the background isolate.
/// The main thread uses [date] to compute [isPast] once lesson matching is done.
class _RawLecture {
  final DateTime? date;       // actual DateTime, or null if no date column
  final String dateDisplay;   // formatted "dd/mm/yyyy" or "${k+1}" (index)
  final bool isDateReal;
  final bool isAbsent;
  final bool isConfirmed;
  final List<bool> checks;    // always 3 elements

  const _RawLecture({
    required this.date,
    required this.dateDisplay,
    required this.isDateReal,
    required this.isAbsent,
    required this.isConfirmed,
    required this.checks,
  });
}

/// Raw per-subject data extracted by the background isolate.
class _RawSubjectRow {
  final String subjectName;
  final String teacherName;
  final List<_RawLecture> lectures;

  const _RawSubjectRow({
    required this.subjectName,
    required this.teacherName,
    required this.lectures,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-level isolate entry functions (required by compute()).
// These are top-level so that Dart can spawn them in a background isolate.
// They call Parser's private static helpers — valid because they are in the
// same library (same file) as the Parser class.
// ─────────────────────────────────────────────────────────────────────────────

/// Isolate entry: parses schedule HTML → List<Semester>.
List<Semester> _parseSemestersIsolate(String html) =>
    Parser.parseSemesters(html);

/// Isolate entry: parses schedule HTML → List<Lesson>.
/// Identical logic to the original Parser._parseScheduleHtml, minus the
/// parse-cache check (caching is handled by the main isolate).
List<Lesson> _parseScheduleIsolate(String htmlString) {
  final doc   = parse(htmlString);
  final table = Parser._findTableByHeader(doc, 'საგნის კოდი');
  if (table == null) return [];

  final rows   = table.getElementsByTagName('tr');
  final result = <Lesson>[];
  final seen   = <String>{};

  for (var i = 1; i < rows.length; i++) {
    final cols = rows[i].getElementsByTagName('td');
    if (cols.length < 4) continue;
    final code    = Parser._cellText(cols[0]);
    final name    = Parser._cellText(cols.length > 1 ? cols[1] : cols[0]);
    final teacher = cols.length > 2 ? Parser._cellText(cols[2]) : '';
    if (name.isEmpty) continue;

    final rawDays  = cols.length > 3 ? cols[3].text.trim().split('/') : <String>[];
    final rawTimes = cols.length > 4 ? cols[4].text.trim().split('/') : <String>[];
    final rawRooms = cols.length > 5 ? cols[5].text.trim().split('/') : <String>[];

    if (rawDays.isEmpty) {
      result.add(Lesson(code: code, name: name, teacher: teacher,
          day: '', time: '', room: ''));
      continue;
    }
    for (var j = 0; j < rawDays.length; j++) {
      final rawDay = rawDays[j].trim();
      final dayEn  = Parser._daysMap[rawDay] ?? rawDay;
      final time   = j < rawTimes.length ? rawTimes[j].trim() : '';
      final room   = (j < rawRooms.length ? rawRooms[j].trim() : '')
          .replaceAll('მთავარი კამპუსი-', '');
      final key = '$name|$dayEn|$time';
      if (!seen.contains(key)) {
        result.add(Lesson(code: code, name: name, teacher: teacher,
            day: dayEn, time: time, room: room));
        seen.add(key);
      }
    }
  }
  return result;
}

/// Isolate entry: parses attendance HTML → List<_RawSubjectRow>.
///
/// Performs all heavy DOM work (parse(), table traversal, checkbox scanning)
/// without requiring the schedule — the schedule is used only for lesson
/// end-time lookup, which the main thread performs after this returns.
List<_RawSubjectRow> _parseAttendanceIsolate(String htmlString) {
  final doc    = parse(htmlString);
  final tables = doc.getElementsByTagName('table');
  if (tables.isEmpty) return [];

  // Find the table with the most checkboxes (same logic as _findAttendanceTable)
  Element? table;
  int maxCb = 0;
  for (final t in tables) {
    final count = t
        .getElementsByTagName('input')
        .where((e) => e.attributes['type']?.toLowerCase() == 'checkbox')
        .length;
    if (count > maxCb) { maxCb = count; table = t; }
  }
  if (table == null || maxCb == 0) return [];

  final rows  = table.getElementsByTagName('tr');
  final result = <_RawSubjectRow>[];
  final now   = DateTime.now();

  List<DateTime?> currentDates     = [];
  List<bool>      currentConfirmed = [];

  for (var i = 0; i < rows.length; i++) {
    final row     = rows[i];
    final rowText = row.text;

    // ── Header row: extract lecture dates and confirmed flags ──────
    if (Parser._isHeaderRow(rowText)) {
      currentDates     = [];
      currentConfirmed = [];
      for (final cell in row.children) {
        final text    = cell.text.trim();
        final isGreen =
            cell.attributes['bgcolor']?.toUpperCase() == Parser._confirmedBgColor;
        final full = Parser._parseFullDate(text);
        if (full != null) {
          currentDates.add(full); currentConfirmed.add(isGreen); continue;
        }
        final partial = Parser._parsePartialDate(text, now);
        if (partial != null) {
          currentDates.add(partial); currentConfirmed.add(isGreen); continue;
        }
        if (cell.attributes['colspan'] != null) {
          currentDates.add(null); currentConfirmed.add(false);
        }
      }
      continue;
    }

    // ── Data row: extract subject/teacher + lecture records ────────
    final checkboxes = row
        .getElementsByTagName('input')
        .where((e) => e.attributes['type']?.toLowerCase() == 'checkbox')
        .toList();
    if (checkboxes.isEmpty) continue;

    final cells = row.getElementsByTagName('td');
    if (cells.length < 3) continue;

    final (subjectName, teacherName) = Parser._extractSubjectTeacher(cells);
    if (subjectName.isEmpty) continue;

    final totalLectures = checkboxes.length ~/ 3;
    final lectures      = <_RawLecture>[];

    for (var k = 0; k < totalLectures; k++) {
      final idx      = k * 3;
      final isAbsent = Parser._isChecked(checkboxes, idx) ||
          Parser._isChecked(checkboxes, idx + 1) ||
          Parser._isChecked(checkboxes, idx + 2);
      final isConfirmed =
          k < currentConfirmed.length ? currentConfirmed[k] : false;

      String   dateDisplay = '${k + 1}';
      bool     isDateReal  = false;
      DateTime? rawDate;

      if (k < currentDates.length && currentDates[k] != null) {
        final d     = currentDates[k]!;
        dateDisplay = Parser._formatDate(d);
        isDateReal  = true;
        rawDate     = d;
      }

      lectures.add(_RawLecture(
        date:        rawDate,
        dateDisplay: dateDisplay,
        isDateReal:  isDateReal,
        isAbsent:    isAbsent,
        isConfirmed: isConfirmed,
        checks: [
          Parser._isChecked(checkboxes, idx),
          Parser._isChecked(checkboxes, idx + 1),
          Parser._isChecked(checkboxes, idx + 2),
        ],
      ));
    }

    if (totalLectures > 0) {
      result.add(_RawSubjectRow(
        subjectName: subjectName,
        teacherName: teacherName,
        lectures:    lectures,
      ));
    }
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Additional isolate entry points — one per remaining heavy parser.
// Each is a top-level function so compute() can spawn it in a background
// isolate. The public Parser methods delegate here, keeping their signatures
// identical (except the four screen-facing parsers which become async).
// ─────────────────────────────────────────────────────────────────────────────

/// Isolate entry: parses grades HTML → (List<GradeSubject>, GpaStats?).
(List<GradeSubject>, GpaStats?) _parseGradesIsolate(String html) {
  final subjects  = <GradeSubject>[];
  final subjectRe = RegExp(
    r'name="cxr_id"[^>]+value="(\d+)"[^>]*>.*?'
    r'class="submit_masala"[^>]+value="([^"]+)"',
    dotAll: true,
  );
  final allMatches = subjectRe.allMatches(html).toList();
  for (int i = 0; i < allMatches.length; i++) {
    final m      = allMatches[i];
    final cxrId  = m.group(1) ?? '';
    final code   = m.group(2)?.trim() ?? '';
    if (cxrId.isEmpty || code.isEmpty) continue;
    final chunkEnd = i < allMatches.length - 1
        ? allMatches[i + 1].start : html.length;
    final chunk    = html.substring(m.end, chunkEnd);
    final ncMatch  = RegExp(
        r'</td>\s*<td>([^<]+)</td>\s*<td[^>]*>([\d.]+)</td>')
        .firstMatch(chunk);
    final name    = ncMatch?.group(1)?.trim() ?? '';
    final credits = double.tryParse(ncMatch?.group(2) ?? '') ?? 0;
    final prMatch = RegExp(r"name=pr value='([\d.]+)'").firstMatch(chunk);
    final pct     = double.tryParse(prMatch?.group(1) ?? '') ?? 0;
    final afterPr = prMatch != null ? chunk.substring(prMatch.end) : chunk;
    final tdMatches = RegExp(r'<td[^>]*>\s*([^<\s][^<]*?)\s*</td>')
        .allMatches(afterPr).toList();
    final letter  = tdMatches.isNotEmpty
        ? (tdMatches[0].group(1)?.trim() ?? '') : '';
    final quality = tdMatches.length > 1
        ? (double.tryParse(tdMatches[1].group(1)?.trim() ?? '') ?? 0) : 0;
    subjects.add(GradeSubject(
      cxrId: cxrId, code: code, name: name, credits: credits,
      percentage: pct, letter: letter, qualityPoints: quality.toDouble(),
    ));
  }

  final wprs  = RegExp(r"name=wpr value='([^']+)'")
      .allMatches(html)
      .map((m) => double.tryParse(m.group(1) ?? '') ?? 0.0).toList();
  final wgpas = RegExp(r"name=wgpa value='([^']+)'")
      .allMatches(html)
      .map((m) => double.tryParse(m.group(1) ?? '') ?? 0.0).toList();

  GpaStats? stats;
  if (wprs.length >= 4 && wgpas.length >= 4) {
    stats = GpaStats(
      annualSubjects:       wprs[0].toInt(),  annualCredits:        wgpas[0],
      annualPercentage:     wprs[1],           annualGpa:            wgpas[1],
      cumulativeSubjects:   wprs[2].toInt(),  cumulativeCredits:    wgpas[2],
      cumulativePercentage: wprs[3],           cumulativeGpa:        wgpas[3],
    );
  }
  return (subjects, stats);
}

/// Isolate entry: parses exam recovery HTML → List<ExamEntry>.
/// args = [html (String), semId (int)]
List<ExamEntry> _parseExamsIsolate(List<dynamic> args) {
  final html  = args[0] as String;
  final semId = args[1] as int;

  final doc    = parse(html);
  final result = <ExamEntry>[];

  final blocks = doc.querySelectorAll('ul.list-group');
  debugPrint('[parseExams] ul.list-group blocks found: ${blocks.length}');

  for (final ul in blocks) {
    try {
      final lis = ul.querySelectorAll('li');
      if (lis.isEmpty) continue;

      String code    = '';
      String nameKa  = '';
      String teacher = '';
      String dateStr = '';
      String time    = '';
      String room    = '';

      for (int i = 0; i < lis.length; i++) {
        final li     = lis[i];
        final strong = li.querySelector('strong');
        if (strong == null) continue;

        final label = strong.text.trim().toLowerCase();
        String value = Parser._extractLiValue(li, strong);

        if (value.isEmpty && i + 1 < lis.length) {
          final next = lis[i + 1];
          if (next.querySelector('strong') == null) {
            value = Parser._collapseWs(next.text);
          }
        }

        if (label.contains('კოდი')) {
          code = value;
        } else if (label.contains('დასახელება')) {
          nameKa = value;
        } else if (label.contains('ლექტორი')) {
          teacher = value.split('/').first.trim();
        } else if (label.contains('თარიღი')) {
          dateStr = value;
        } else if (label.contains('საათი')) {
          time = value;
        } else if (label.contains('აუდიტ')) {
          room = value;
        }
      }

      if (code.isEmpty) {
        debugPrint('[parseExams] SKIP ul: code empty | '
            'html: ${Parser._snippet(ul.outerHtml)}');
        continue;
      }
      if (!RegExp(r'^[A-Za-z]').hasMatch(code)) {
        debugPrint('[parseExams] SKIP ul: non-latin code "$code"');
        continue;
      }

      final date = Parser._parseExamDate(dateStr);
      if (date == null) {
        debugPrint('[parseExams] SKIP ul: bad date "$dateStr" | code=$code');
        continue;
      }

      result.add(ExamEntry(
        code:    code,
        nameKa:  nameKa.isNotEmpty ? nameKa : code,
        nameEn:  nameKa.isNotEmpty ? nameKa : code,
        teacher: teacher,
        date:    date,
        time:    time,
        room:    room,
        semId:   semId,
      ));

      debugPrint('[parseExams] +exam  code=$code  date=$dateStr  '
          'time=$time  teacher=$teacher');

    } catch (e, st) {
      debugPrint('[parseExams] ERROR on ul block: $e\n$st\n'
          'HTML: ${Parser._snippet(ul.outerHtml)}');
    }
  }

  debugPrint('[parseExams] total parsed: ${result.length}');

  final future = result.where((e) => e.isUpcoming).toList()
    ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  final past   = result.where((e) => !e.isUpcoming).toList()
    ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return [...future, ...past];
}

/// Isolate entry: parses profile HTML → Map<String, String>.
Map<String, String> _parseProfileIsolate(String html) {
  final cleaned = html.replaceFirst(
    RegExp(r'<html\s+lang[^>]*>.*?</html\s*>',
        dotAll: true, caseSensitive: false),
    '',
  );
  final doc    = parse(cleaned);
  final result = <String, String>{};

  final wideTd = doc.getElementsByTagName('td').where((td) {
    final w = td.attributes['width'];
    return w != null && (int.tryParse(w) ?? 0) >= 600;
  }).firstOrNull;
  final rows = wideTd != null
      ? wideTd.getElementsByTagName('tr')
      : doc.getElementsByTagName('tr');

  for (final row in rows) {
    final cells = row.children;
    if (cells.length < 2) continue;
    final labelCell = cells[0];
    final isLabel = labelCell.attributes['bgcolor']?.toUpperCase() == '#CCCCCC' ||
        labelCell.getElementsByTagName('b').isNotEmpty;
    if (!isLabel) continue;
    final key = labelCell.text.trim().replaceAll(':', '').trim();
    String value = cells[1].text.trim();
    if (value.isEmpty) {
      value = cells[1].innerHtml
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r"^'>?\s*"), '')
          .trim();
    }
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

/// Isolate entry: parses syllabus list HTML →
/// ({List<Semester> semesters, List<SyllabusSubject> subjects}).
({List<Semester> semesters, List<SyllabusSubject> subjects})
    _parseSyllabusListIsolate(String html) {
  final cleaned = html.replaceFirst(
    RegExp(r'<html\s+lang[^>]*>.*?</html\s*>',
        dotAll: true, caseSensitive: false),
    '',
  );
  final doc       = parse(cleaned);
  final semesters = Parser.parseSemesters(cleaned);

  final forms = doc.getElementsByTagName('form').where((f) {
    final action = f.attributes['action'] ?? '';
    return action.contains('Syllabus_pdfENG');
  }).toList();

  final subjects = <SyllabusSubject>[];
  for (final form in forms) {
    final idInput  = form.querySelector('input[name="id"]');
    final cxrInput = form.querySelector('input[name="cxr_id"]');
    if (idInput == null || cxrInput == null) continue;

    final studentId = (idInput.attributes['value']  ?? '').trim();
    final cxrId     = (cxrInput.attributes['value'] ?? '').trim();
    if (cxrId.isEmpty) continue;

    final row = Parser._findAncestor(form, 'tr');
    if (row == null) continue;

    final cells = row.getElementsByTagName('td');
    if (cells.length < 3) continue;

    final code    = cells[0].text.trim();
    final name    = cells[1].text.trim();
    final teacher = cells[2].text.trim();
    if (code.isEmpty && name.isEmpty) continue;

    subjects.add(SyllabusSubject(
      code:      code,
      name:      name,
      teacher:   teacher,
      studentId: studentId,
      cxrId:     cxrId,
    ));
  }

  return (semesters: semesters, subjects: subjects);
}

/// Isolate entry: parses materials list HTML →
/// ({List<Semester> semesters, List<CourseSubject> subjects}).
({List<Semester> semesters, List<CourseSubject> subjects})
    _parseMaterialsListIsolate(String html) {
  final cleaned = html.replaceFirst(
    RegExp(r'<html\s+lang[^>]*>.*?</html\s*>',
        dotAll: true, caseSensitive: false),
    '',
  );
  final doc       = parse(cleaned);
  final semesters = Parser.parseSemesters(cleaned);

  final forms = doc.getElementsByTagName('form').where((f) {
    final action = f.attributes['action'] ?? '';
    return action.contains('masalebi.php');
  }).toList();

  final subjects = <CourseSubject>[];
  for (final form in forms) {
    final cxrInput = form.querySelector('input[name="cxr_id"]');
    if (cxrInput == null) continue;
    final cxrId = (cxrInput.attributes['value'] ?? '').trim();
    if (cxrId.isEmpty) continue;

    final row = Parser._findAncestor(form, 'tr');
    if (row == null) continue;

    final cells = row.getElementsByTagName('td');
    if (cells.length < 3) continue;

    final code    = cells[0].text.trim();
    final name    = cells[1].text.trim();
    final teacher = cells[2].text.trim();
    if (code.isEmpty && name.isEmpty) continue;

    subjects.add(CourseSubject(
      code:    code,
      name:    name,
      teacher: teacher,
      payloadForDetails: {
        'cxr_id': cxrId,
        'submit':  'მასალების ჩამოტვირთვა',
      },
    ));
  }

  return (semesters: semesters, subjects: subjects);
}

/// Isolate entry: parses material details HTML →
/// ({String courseTitle, List<LectureGroup> groups}).
({String courseTitle, List<LectureGroup> groups})
    _parseMaterialDetailsIsolate(String html) {
  final doc = parse(html);

  final titleEl     = doc.querySelector('.titlehdr2');
  final courseTitle = titleEl?.text.trim() ?? '';

  final table = doc.querySelector('table');
  if (table == null) return (courseTitle: courseTitle, groups: []);

  final groups    = <LectureGroup>[];
  String curTitle = '';
  String curDate  = '';
  final  curFiles = <MaterialFile>[];

  void flush() {
    if (curTitle.isNotEmpty) {
      groups.add(LectureGroup(
        title: curTitle,
        date:  curDate,
        files: List<MaterialFile>.from(curFiles),
      ));
    }
    curFiles.clear();
  }

  for (final row in table.getElementsByTagName('tr')) {
    final cells = row.getElementsByTagName('td');
    if (cells.isEmpty) continue;

    final firstCell = cells.first;

    if (firstCell.className.contains('titlehdr4')) {
      final span  = firstCell.querySelector('.titlehdr3, .style81');
      final title = (span?.text ?? firstCell.text).trim();
      if (title.isNotEmpty) {
        flush();
        curTitle = title;
        curDate  = cells.length > 1
            ? (cells[1].querySelector('.titlehdr3')?.text ??
                   cells[1].text).trim()
            : '';
      }
      continue;
    }

    for (final cell in cells) {
      final link = cell.querySelector('a[href]');
      if (link == null) continue;
      final href = (link.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final name = link.text.trim();
      if (name.isEmpty) continue;
      final url = href.startsWith('http')
          ? href
          : 'https://programs.cu.edu.ge/students/$href';
      curFiles.add(MaterialFile(name: name, url: url));
    }
  }
  flush();

  return (courseTitle: courseTitle, groups: groups);
}

/// Isolate entry: parses payment history HTML → List<PaymentSemester>.
List<PaymentSemester> _parsePaymentHistoryIsolate(String html) {
  final cleaned = html.replaceFirst(
    RegExp(r'<html\s+lang[^>]*>.*?</html\s*>',
        dotAll: true, caseSensitive: false),
    '',
  );
  final doc    = parse(cleaned);
  final result = <PaymentSemester>[];

  Element? table;
  for (final t in doc.getElementsByTagName('table')) {
    if (t.text.contains('სემესტრი') || t.text.contains('გადასახდელი')) {
      table = t;
      break;
    }
  }
  if (table == null) {
    debugPrint('parsePaymentHistory: table not found');
    return result;
  }

  final rows = table.getElementsByTagName('tr');
  for (var i = 1; i < rows.length; i++) {
    final cells = rows[i].getElementsByTagName('td');
    if (cells.length < 6) continue;

    final name = cells[0].text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) continue;

    final totalAmount = Parser._parseDouble(cells[1].text);
    final examFee     = Parser._parseDouble(cells[2].text);
    final penalty     = Parser._parseDouble(cells[3].text);
    final paidAmount  = Parser._parseDouble(cells[4].text);
    final debtAmount  = Parser._parseDouble(cells[5].text);

    // Пропускаем строки, где все суммы нулевые — это пустые/итоговые строки таблицы
    if (totalAmount == 0 && examFee == 0 && penalty == 0 &&
        paidAmount == 0 && debtAmount == 0) continue;

    final transactions = <PaymentTransaction>[];
    if (cells.length > 6) {
      for (final option in cells[6].getElementsByTagName('option')) {
        final tx = Parser._parseTransaction(option.text);
        if (tx != null) transactions.add(tx);
      }
    }

    result.add(PaymentSemester(
      name:         name,
      totalAmount:  totalAmount,
      examFee:      examFee,
      penalty:      penalty,
      paidAmount:   paidAmount,
      debtAmount:   debtAmount,
      transactions: transactions,
    ));
  }

  return result.reversed.toList();
}

/// Isolate entry: parses subject detail HTML → SubjectDetail.
SubjectDetail _parseSubjectDetailIsolate(String html) {
  final doc      = parse(html);
  final headerRe = RegExp(
      r'<br>\s*([A-Z]{2,5}\s+\d{4}[A-Z]*)\s*<br>\s*([^\n<]+)');
  final hm      = headerRe.firstMatch(html);
  final code    = hm?.group(1)?.trim() ?? '';
  final teacher = hm?.group(2)?.trim() ?? '';

  final exams = <SubjectExam>[];
  double interimTotal = 0, maxEntered = 0, studentTotal = 0,
      finalPercentage = 0;
  String finalGrade = '';

  for (final row in doc.querySelectorAll('tbody tr')) {
    final tds          = row.querySelectorAll('td');
    if (tds.isEmpty) continue;
    final firstColspan = tds.first.attributes['colspan'];
    if (firstColspan == '2' && tds.length >= 2) {
      final label = tds[0].text.toLowerCase();
      final value = tds[1].text.trim();
      if (label.contains('interim') || label.contains('შუალედური'))
        interimTotal = double.tryParse(value) ?? 0;
      else if (label.contains('maximum') || label.contains('მაქსიმალური'))
        maxEntered = double.tryParse(value) ?? 0;
      else if (label.contains('total') || label.contains('მიღებული'))
        studentTotal = double.tryParse(value) ?? 0;
      else if (label.contains('per cent') || label.contains('პროცენტი'))
        finalPercentage = double.tryParse(value) ?? 0;
      else if (label.contains('final grade') || label.contains('საბოლოო'))
        finalGrade = value;
      continue;
    }
    if (tds.length >= 4) {
      final type = tds[1].text.trim();
      if (type.isEmpty) continue;
      final scoreStr = tds[3].text.trim();
      exams.add(SubjectExam(
        date:     tds[0].text.trim(), type: type,
        maxScore: double.tryParse(tds[2].text.trim()) ?? 0,
        score:    scoreStr.isEmpty ? null : double.tryParse(scoreStr),
      ));
    }
  }

  return SubjectDetail(
    code: code, teacher: teacher, exams: exams,
    interimTotal: interimTotal, maxEntered: maxEntered,
    studentTotal: studentTotal, finalPercentage: finalPercentage,
    finalGrade: finalGrade,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser
// ─────────────────────────────────────────────────────────────────────────────

class Parser {
  static const _daysMap = {
    'ორშ': 'Monday',   'სამ': 'Tuesday',  'სამშ': 'Tuesday',
    'ოთხ': 'Wednesday','ხუთ': 'Thursday', 'პარ':  'Friday',
    'შაბ': 'Saturday', 'კვ':  'Sunday',   'კვი':  'Sunday',
  };

  static const _confirmedBgColor = '#008000';

  static String _simplify(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

  // ─── СЕМЕСТРЫ (schedule.php) ──────────────────────────────────

  static List<Semester> parseSemesters(String htmlBody) {
    final doc    = parse(htmlBody);
    final result = <Semester>[];
    final radios = doc.querySelectorAll('input[name="sem_id1"][type="radio"]');

    for (final radio in radios) {
      final idStr = radio.attributes['value'];
      if (idStr == null) continue;
      final id = int.tryParse(idStr);
      if (id == null) continue;

      String name = '';
      final parent = radio.parent;
      if (parent != null) {
        final tr = _findAncestor(parent, 'tr');
        if (tr != null) {
          final hidden = tr.querySelector('input[name="semestri"]');
          if (hidden != null) name = (hidden.attributes['value'] ?? '').trim();
        }
        if (name.isEmpty) {
          name = parent.text
              .replaceAll(RegExp(r'\d'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      }
      if (name.isNotEmpty) result.add(Semester(id: id, name: name));
    }

    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// Async wrapper — offloads DOM parsing to a background isolate so the
  /// Flutter UI thread is not blocked. Use this everywhere possible.
  static Future<List<Semester>> parseSemestersAsync(String htmlBody) =>
      compute(_parseSemestersIsolate, htmlBody);

  static Element? _findAncestor(Element el, String tag) {
    Element? current = el.parent;
    while (current != null) {
      if (current.localName?.toLowerCase() == tag) return current;
      current = current.parent;
    }
    return null;
  }

  // ─── РАСПИСАНИЕ ЗАНЯТИЙ ──────────────────────────────────────

  static Future<List<Lesson>> parseSchedule() async {
    try {
      final String html;
      if (Storage.getUser() == 'admin') {
        html = await rootBundle.loadString('assets/schedule.html');
      } else {
        final fetched = await ApiService.getHtmlWithRetry(ApiService.scheduleUrl);
        if (fetched == null || fetched.isEmpty) return [];
        html = fetched;
      }
      return _parseScheduleHtml(html);
    } catch (e) {
      print('parseSchedule ERROR: $e');
      return [];
    }
  }

  /// Public async entry — callers that already have the HTML use this.
  /// Changed from sync to async so the heavy DOM parse runs in a background
  /// isolate via compute(), keeping the UI thread free.
  static Future<List<Lesson>> parseScheduleFromHtml(String html) =>
      _parseScheduleHtml(html);

  static Future<List<Lesson>> parseScheduleForSemester(Semester sem) async {
    try {
      if (Storage.getUser() == 'admin') return parseSchedule();
      final html =
          await ApiService.fetchScheduleForSemester(sem.id, sem.name);
      if (html == null || html.isEmpty) return [];
      return _parseScheduleHtml(html);
    } catch (e) {
      print('parseScheduleForSemester ERROR: $e');
      return [];
    }
  }

  // Parse-result cache — prevents redundant isolate spawns when HomeScreen
  // and ScheduleScreen request the same HTML in the same session.
  static List<Lesson>? _scheduleParseCache;
  static int?          _scheduleParseHash;

  /// Checks the parse-level cache; if stale, offloads DOM work to a background
  /// isolate via compute() and stores the result back on the main isolate.
  static Future<List<Lesson>> _parseScheduleHtml(String htmlString) async {
    final hash = htmlString.length ^ htmlString.hashCode;
    if (_scheduleParseCache != null && _scheduleParseHash == hash) {
      debugPrint('parseSchedule: parse-cache hit (${_scheduleParseCache!.length} lessons)');
      return _scheduleParseCache!;
    }

    // Heavy DOM work happens in the background isolate.
    // Only the raw HTML string is passed — no DOM objects or custom classes.
    final result = await compute(_parseScheduleIsolate, htmlString);

    debugPrint('parseSchedule: ${result.length} lessons');
    _scheduleParseCache = result;
    _scheduleParseHash  = hash;
    return result;
  }

  // ─── ПОСЕЩАЕМОСТЬ ────────────────────────────────────────────

  static Future<List<Attendance>> parseAttendance(
      List<Lesson> schedule) async {
    try {
      final String html;
      if (Storage.getUser() == 'admin') {
        html = await rootBundle.loadString('assets/attendance.html');
      } else {
        final fetched = await ApiService.getHtmlWithRetry(ApiService.attendanceUrl);
        if (fetched == null || fetched.isEmpty) return [];
        html = fetched;
      }
      return _parseAttendanceHtml(html, schedule);
    } catch (e) {
      print('parseAttendance ERROR: $e');
      return [];
    }
  }

  static List<Attendance>? _attendanceParseCache;
  static int?              _attendanceParseHash;

  /// Offloads the heavy DOM parsing to a background isolate, then performs
  /// the quick lesson-matching step on the main isolate.
  ///
  /// Split rationale:
  ///   • Isolate:    parse() + table traversal + checkbox scanning — CPU-bound.
  ///   • Main thread: Map lookups against the in-memory schedule — O(n) fast.
  static Future<List<Attendance>> _parseAttendanceHtml(
      String htmlString, List<Lesson> schedule) async {
    final hash = htmlString.length ^ htmlString.hashCode;
    if (_attendanceParseCache != null && _attendanceParseHash == hash) {
      debugPrint('parseAttendance: parse-cache hit (${_attendanceParseCache!.length} subjects)');
      return _attendanceParseCache!;
    }

    // Phase 1 (background isolate): DOM parsing — only raw HTML string passed in.
    final rawRows = await compute(_parseAttendanceIsolate, htmlString);

    // Phase 2 (main thread): lesson matching + isPast/isPending arithmetic.
    final result = _buildAttendanceFromRaw(rawRows, schedule);

    debugPrint('parseAttendance: ${result.length} subjects');
    _attendanceParseCache = result;
    _attendanceParseHash  = hash;
    return result;
  }

  /// Main-thread phase of attendance parsing.
  /// Matches raw rows against the schedule and computes attendance statistics.
  /// All operations here are O(n) Map lookups — fast, appropriate for the UI thread.
  static List<Attendance> _buildAttendanceFromRaw(
      List<_RawSubjectRow> rawRows, List<Lesson> schedule) {
    final now = DateTime.now();

    final Map<String, Lesson> fullIndex    = {};
    final Map<String, Lesson> nameIndex    = {};
    final Map<String, Lesson> teacherIndex = {};
    for (final l in schedule) {
      final sk = '${_simplify(l.name)}|${_simplify(l.teacher)}';
      fullIndex.putIfAbsent(sk, () => l);
      nameIndex.putIfAbsent(_simplify(l.name), () => l);
      if (l.teacher.isNotEmpty)
        teacherIndex.putIfAbsent(_simplify(l.teacher), () => l);
    }

    final result = <Attendance>[];

    for (final row in rawRows) {
      final matchedLesson = _findMatchingLesson(
          row.subjectName, row.teacherName, fullIndex, nameIndex, teacherIndex);

      final records      = <LectureRecord>[];
      int passed = 0, attended = 0, pendingCount = 0;

      for (final lec in row.lectures) {
        // isPast depends on the matched lesson's end time — done here on main thread.
        final bool isDatePast = lec.date != null &&
            now.isAfter(_getLectureEndTime(lec.date!, matchedLesson));
        final bool isPast    = isDatePast || lec.isAbsent || lec.isConfirmed;
        final bool isPending = isPast && !lec.isAbsent && !lec.isConfirmed;

        records.add(LectureRecord(
          date:        lec.dateDisplay,
          isDateReal:  lec.isDateReal,
          isPast:      isPast,
          isAbsent:    lec.isAbsent,
          isConfirmed: lec.isConfirmed,
          isPending:   isPending,
          checks:      lec.checks,
        ));

        if (isPast)    passed++;
        if (isPending) pendingCount++;
        if (isPast && !lec.isAbsent && !isPending) attended++;
      }

      result.add(Attendance(
        subject:          row.subjectName,
        teacher:          row.teacherName,
        totalLectures:    row.lectures.length,
        passedLectures:   passed,
        attendedLectures: attended,
        pendingLectures:  pendingCount,
        records:          records,
      ));
    }

    return result;
  }

  // ─── ОЦЕНКИ (GPA) ───────────────────────────────────────────

  static (List<GradeSubject>, GpaStats?)? _gradesCache;
  static DateTime? _gradesCacheAt;
  static const _gradesCacheTtl = Duration(minutes: 10);

  static void clearGradesCache() {
    _gradesCache   = null;
    _gradesCacheAt = null;
    debugPrint('fetchGrades: cache cleared');
  }

  static Future<(List<GradeSubject>, GpaStats?)> fetchGrades() async {
    // ── ADMIN SANDBOX ──────────────────────────────────────────
    if (MockDataService.isActive) {
      debugPrint('fetchGrades: sandbox mock');
      return MockDataService.buildMockGrades();
    }
    // ──────────────────────────────────────────────────────────
    final now = DateTime.now();
    if (_gradesCache != null &&
        _gradesCacheAt != null &&
        now.difference(_gradesCacheAt!) < _gradesCacheTtl) {
      debugPrint('fetchGrades: cache hit');
      return _gradesCache!;
    }

    try {
      final html = await ApiService.fetchCalculatedGradesHtml();
      if (html == null || html.isEmpty) return (<GradeSubject>[], null);
      // Heavy regex scanning runs in a background isolate.
      final result = await compute(_parseGradesIsolate, html);
      _gradesCache   = result;
      _gradesCacheAt = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('fetchGrades ERROR: $e');
      return (<GradeSubject>[], null);
    }
  }

  /// Synchronous helper — kept for callers that already hold the HTML.
  /// The fetch path uses compute(_parseGradesIsolate) to avoid UI jank.
  static (List<GradeSubject>, GpaStats?) parseGrades(String html) =>
      _parseGradesIsolate(html);

  static Future<SubjectDetail?> fetchSubjectDetail(String cxrId) async {
    // ── ADMIN SANDBOX ──────────────────────────────────────────
    if (MockDataService.isActive) {
      debugPrint('fetchSubjectDetail: sandbox mock cxrId=$cxrId');
      return MockDataService.buildMockSubjectDetail(cxrId);
    }
    // ──────────────────────────────────────────────────────────
    try {
      final html = await ApiService.getSubjectDetailHtml(cxrId);
      if (html == null || html.isEmpty) return null;
      // DOM parse in background isolate.
      return compute(_parseSubjectDetailIsolate, html);
    } catch (e) {
      debugPrint('fetchSubjectDetail ERROR ($cxrId): $e');
      return null;
    }
  }

  /// Synchronous helper — kept for callers that already hold the HTML.
  static SubjectDetail parseSubjectDetail(String html) =>
      _parseSubjectDetailIsolate(html);

  // ─── РАСПИСАНИЕ ЭКЗАМЕНОВ ──────────────────────────────────────

  static (List<ExamSemester>, List<ExamEntry>)? _examCache;
  static int? _examCacheSemId;
  static DateTime? _examCacheAt;
  static const _examCacheTtl = Duration(minutes: 10);

  static void clearExamCache() {
    _examCache            = null;
    _examCacheSemId       = null;
    _examCacheAt          = null;
    _scheduleParseCache   = null;
    _scheduleParseHash    = null;
    _attendanceParseCache = null;
    _attendanceParseHash  = null;
    debugPrint('Parser: all caches cleared');
  }

  /// Извлекает CSRF-токен из <meta name="csrf-token" content="...">
  static String parseCsrfToken(String html) {
    final m = RegExp(
      r'''<meta\s+name=["']csrf-token["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (m != null) return m.group(1) ?? '';
    final m2 = RegExp(
      r'''<meta\s+content=["']([^"']+)["'][^>]+name=["']csrf-token["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return m2?.group(1) ?? '';
  }

  /// Парсит список семестров из <select> на странице student_exam_recovery.
  static List<ExamSemester> parseExamSemesters(String html) {
    final doc    = parse(html);
    final select = doc.querySelector('select');
    if (select == null) return [];
    final result = <ExamSemester>[];
    for (final option in select.querySelectorAll('option')) {
      final id = int.tryParse(option.attributes['value'] ?? '');
      if (id == null) continue;
      final name = option.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isNotEmpty) result.add(ExamSemester(id: id, name: name));
    }
    result.sort((a, b) => b.id.compareTo(a.id));
    return result;
  }

  /// Основной метод загрузки экзаменов.
  static Future<(List<ExamSemester>, List<ExamEntry>)> fetchExams({
    int? semId,
  }) async {
    // ── ADMIN SANDBOX ──────────────────────────────────────────
    if (MockDataService.isActive) {
      debugPrint('fetchExams: sandbox mock semId=$semId');
      return MockDataService.buildMockExams(semId: semId);
    }
    // ──────────────────────────────────────────────────────────
    final now = DateTime.now();
    if (_examCache != null &&
        _examCacheSemId == semId &&
        _examCacheAt != null &&
        now.difference(_examCacheAt!) < _examCacheTtl) {
      debugPrint('fetchExams: cache hit (semId=$semId)');
      return _examCache!;
    }

    try {
      final myAccountHtml = await ApiService.withSessionRetry(
          () => ApiService.fetchMyAccountHtml());
      if (myAccountHtml == null) {
        debugPrint('fetchExams: myaccount.php failed');
        return (<ExamSemester>[], <ExamEntry>[]);
      }

      final tokenUrl = ApiService.extractStudentExamUrl(myAccountHtml);
      if (tokenUrl == null) {
        debugPrint('fetchExams: exam URL not found');
        return (<ExamSemester>[], <ExamEntry>[]);
      }
      final studId = ApiService.extractStudId(tokenUrl);
      debugPrint('fetchExams: tokenUrl=$tokenUrl  studId=$studId');

      final recoveryHtml = await ApiService.fetchExamRecoveryPage(tokenUrl);
      if (recoveryHtml == null || recoveryHtml.isEmpty) {
        debugPrint('fetchExams: recovery page empty');
        return (<ExamSemester>[], <ExamEntry>[]);
      }

      final semesters = parseExamSemesters(recoveryHtml);
      if (semesters.isEmpty) {
        debugPrint('fetchExams: no semesters found');
        return (<ExamSemester>[], <ExamEntry>[]);
      }

      final newestSem    = semesters.first;
      final defaultSemId = _parseSelectedSemId(recoveryHtml);
      final targetSemId  = semId ?? newestSem.id;

      debugPrint('fetchExams: newestId=${newestSem.id}  '
          'defaultId=$defaultSemId  targetId=$targetSemId');

      final csrfToken = parseCsrfToken(recoveryHtml);
      debugPrint('fetchExams: POSTing filterExamSemester semId=$targetSemId  '
          'csrf=${csrfToken.isNotEmpty ? csrfToken.substring(0, 8) + "…" : "(empty!)"}');

      final tableFragment = await ApiService.fetchExamSemesterHtml(
        semId:     targetSemId,
        studId:    studId,
        csrfToken: csrfToken,
      );

      String tableHtml;
      if (tableFragment == null || tableFragment.isEmpty) {
        debugPrint('fetchExams: filterExamSemester empty, '
            'falling back to raw recoveryHtml');
        tableHtml = recoveryHtml;
      } else {
        tableHtml = tableFragment;
        debugPrint('fetchExams: tableFragment len=${tableFragment.length}');
      }

      // DOM parse runs in a background isolate; args packed as List<dynamic>.
      final exams = await compute(_parseExamsIsolate, [tableHtml, targetSemId]);
      debugPrint('fetchExams: semId=$targetSemId → ${exams.length} exams');

      final result    = (semesters, exams);
      _examCache      = result;
      _examCacheSemId = semId;
      _examCacheAt    = now;
      return result;

    } catch (e) {
      debugPrint('fetchExams ERROR: $e');
      return (<ExamSemester>[], <ExamEntry>[]);
    }
  }

  static int? _parseSelectedSemId(String html) {
    final m = RegExp(
      r'''<option[^>]+value=["'](\d+)["'][^>]+selected''',
      caseSensitive: false,
    ).firstMatch(html);
    if (m != null) return int.tryParse(m.group(1) ?? '');
    final m2 = RegExp(
      r'''<option[^>]+selected[^>]*value=["'](\d+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return m2 != null ? int.tryParse(m2.group(1) ?? '') : null;
  }

  /// Synchronous helper — kept for callers that already hold the HTML.
  /// The fetch path uses compute(_parseExamsIsolate) to avoid UI jank.
  static List<ExamEntry> parseExamsFromRecovery(String html, int semId) =>
      _parseExamsIsolate([html, semId]);

  static String _extractLiValue(Element li, Element strong) {
    String raw = li.text.replaceFirst(strong.text, '');
    raw = raw.replaceFirst(RegExp(r'^[\s\-–—]+'), '');
    return _collapseWs(raw);
  }

  static String _collapseWs(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _snippet(String s) =>
      s.length > 300 ? '${s.substring(0, 300)}…' : s;

  // Alias for backward compatibility
  static List<ExamEntry> parseExams(String html, int semId) =>
      parseExamsFromRecovery(html, semId);

  static DateTime? _parseExamDate(String text) {
    final m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})').firstMatch(text);
    if (m == null) return null;
    try {
      return DateTime(
          int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    } catch (_) { return null; }
  }

  // ─── TABLE SEARCH UTILITIES ───────────────────────────────────

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
      final count = t
          .getElementsByTagName('input')
          .where((e) => e.attributes['type']?.toLowerCase() == 'checkbox')
          .length;
      if (count > maxCb) { maxCb = count; best = t; }
    }
    return maxCb > 0 ? best : null;
  }

  // ─── SHARED HELPERS ──────────────────────────────────────────

  static String _cellText(Element cell) =>
      cell.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isChecked(List<Element> boxes, int idx) =>
      idx < boxes.length && boxes[idx].attributes.containsKey('checked');

  static bool _isHeaderRow(String t) =>
      t.contains('საგნის დასახელება') || t.contains('Subject name') ||
      t.contains('Subject') || t.contains('ლექტორი') || t.contains('Lecturer');

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static DateTime? _parseFullDate(String text) {
    final m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})').firstMatch(text);
    if (m == null) return null;
    try {
      return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
    } catch (_) { return null; }
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
      if (t.isEmpty || RegExp(r'^\d+$').hasMatch(t) ||
          t.contains('საგნის')) continue;
      t = t.replaceAll('ლექტორი', '').replaceAll('Lecturer', '')
          .replaceAll(':', '').trim();
      if (t.isNotEmpty && !texts.contains(t)) texts.add(t);
    }
    return (
      texts.isNotEmpty ? texts[0] : '',
      texts.length > 1 ? texts.sublist(1).join(', ') : '',
    );
  }

  static Lesson? _findMatchingLesson(
      String sub, String teach,
      Map<String, Lesson> full,
      Map<String, Lesson> name,
      Map<String, Lesson> teacher) {
    final sN = _simplify(sub), tN = _simplify(teach);
    if (full.containsKey('$sN|$tN')) return full['$sN|$tN'];
    if (tN.isNotEmpty) {
      for (final e in teacher.entries)
        if (tN.contains(e.key) || e.key.contains(tN)) return e.value;
    }
    if (sN.isNotEmpty) {
      for (final e in name.entries)
        if (sN.contains(e.key) || e.key.contains(sN)) return e.value;
    }
    return null;
  }

  static DateTime _getLectureEndTime(DateTime date, Lesson? lesson) {
    if (lesson == null || lesson.time.isEmpty)
      return DateTime(date.year, date.month, date.day, 23, 59);
    final parts = lesson.time.split(RegExp(r'[-–]'));
    if (parts.length < 2)
      return DateTime(date.year, date.month, date.day, 23, 59);
    final tp = parts[1].trim().split(':');
    if (tp.length < 2)
      return DateTime(date.year, date.month, date.day, 23, 59);
    try {
      return DateTime(date.year, date.month, date.day,
          int.parse(tp[0]), int.parse(tp[1]));
    } catch (_) {
      return DateTime(date.year, date.month, date.day, 23, 59);
    }
  }

  /// Parses the student profile page (piradi_menu.php) into a key→value map.
  /// Now returns Future — DOM parse runs in a background isolate via compute().
  static Future<Map<String, String>> parseProfile(String html) =>
      compute(_parseProfileIsolate, html);

  // ─── СИЛЛАБУСЫ (sylab.php) ────────────────────────────────────

  /// Parses sylab.php → semesters + subjects.
  /// Now returns Future — DOM parse runs in a background isolate via compute().
  static Future<({
    List<Semester>        semesters,
    List<SyllabusSubject> subjects,
  })> parseSyllabusList(String html) =>
      compute(_parseSyllabusListIsolate, html);

  // ─── МАТЕРИАЛЫ (masalebi_1.php + masalebi.php) ────────────────

  /// Parses masalebi_1.php → semester list + subject list.
  /// Now returns Future — DOM parse runs in a background isolate via compute().
  static Future<({
    List<Semester>      semesters,
    List<CourseSubject> subjects,
  })> parseMaterialsList(String html) =>
      compute(_parseMaterialsListIsolate, html);

  /// Parses masalebi.php → course title + lecture groups with files.
  /// Now returns Future — DOM parse runs in a background isolate via compute().
  static Future<({
    String             courseTitle,
    List<LectureGroup> groups,
  })> parseMaterialDetails(String html) =>
      compute(_parseMaterialDetailsIsolate, html);

  // ─── СТАТУС ДОЛГА (C_PaymentSchedule.php) ────────────────────

  static DebtStatus parseDebtStatus(String html) {
    const noDebtPhrase = 'ვალი არ გაქვთ';
    if (html.contains(noDebtPhrase)) {
      return DebtStatus(noDebt: true, rawText: noDebtPhrase);
    }
    final doc     = parse(html);
    final rawText = doc.body?.text.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return DebtStatus(noDebt: false, rawText: rawText);
  }

  static Future<DebtStatus?> fetchDebtStatus() async {
    // ── ADMIN SANDBOX ──────────────────────────────────────────
    if (MockDataService.isActive) {
      debugPrint('fetchDebtStatus: sandbox mock');
      return MockDataService.buildMockPayment().$1;
    }
    // ──────────────────────────────────────────────────────────
    try {
      final html = await ApiService.fetchPaymentScheduleHtml();
      if (html == null || html.isEmpty) return null;
      return parseDebtStatus(html);
    } catch (e) {
      debugPrint('fetchDebtStatus ERROR: $e');
      return null;
    }
  }

  // ─── ИСТОРИЯ ПЛАТЕЖЕЙ (gadaxda.php) ──────────────────────────

  /// Synchronous helper — kept for callers that already hold the HTML.
  /// The fetch path uses compute(_parsePaymentHistoryIsolate) to avoid UI jank.
  static List<PaymentSemester> parsePaymentHistory(String html) =>
      _parsePaymentHistoryIsolate(html);

  static PaymentTransaction? _parseTransaction(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(
      r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+([\d.]+)',
    ).firstMatch(text);
    if (m == null) return null;
    final dt     = m.group(1)!.trim();
    final amount = double.tryParse(m.group(2) ?? '');
    if (amount == null) return null;
    return PaymentTransaction(dateTime: dt, amount: amount);
  }

  static double _parseDouble(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  static Future<List<PaymentSemester>> fetchPaymentHistory() async {
    // ── ADMIN SANDBOX ──────────────────────────────────────────
    if (MockDataService.isActive) {
      debugPrint('fetchPaymentHistory: sandbox mock');
      return MockDataService.buildMockPayment().$2;
    }
    // ──────────────────────────────────────────────────────────
    try {
      final html = await ApiService.fetchPaymentHistoryHtml();
      if (html == null || html.isEmpty) return [];
      // DOM parse runs in a background isolate.
      return compute(_parsePaymentHistoryIsolate, html);
    } catch (e) {
      debugPrint('fetchPaymentHistory ERROR: $e');
      return [];
    }
  }
}
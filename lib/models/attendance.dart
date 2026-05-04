class LectureRecord {
  final String date;
  final bool isDateReal; // true → реальная дата "24/03/2026", false → просто номер
  final bool isPast;     // лекция уже прошла (по дате или подтверждена/пропущена)
  final bool isAbsent;   // преподаватель отметил «н» (пропуск)
  final bool isConfirmed; // преподаватель подтвердил присутствие (зелёная ячейка)
  final bool isPending;  // дата прошла, но преподаватель ещё ничего не выставил
  final List<bool> checks;

  LectureRecord({
    required this.date,
    required this.isDateReal,
    required this.isPast,
    required this.isAbsent,
    required this.isConfirmed,
    this.isPending = false,
    required this.checks,
  });
}

class Attendance {
  final String subject;
  final String teacher;
  final int totalLectures;

  /// passedLectures  — лекции, у которых дата уже прошла (включая pending)
  final int passedLectures;

  /// attendedLectures — лекции, где преподаватель подтвердил присутствие
  final int attendedLectures;

  /// pendingLectures — дата прошла, но статус ещё не выставлен
  final int pendingLectures;

  final List<LectureRecord> records;

  Attendance({
    required this.subject,
    required this.teacher,
    required this.totalLectures,
    required this.passedLectures,
    required this.attendedLectures,
    required this.pendingLectures,
    required this.records,
  });

  /// Процент из ПОДТВЕРЖДЁННЫХ лекций (не учитываем pending в знаменателе).
  /// Если преподаватель ещё не выставил — не штрафуем студента.
  double get percentage {
    final confirmed = passedLectures - pendingLectures;
    if (confirmed <= 0) return 1.0; // все ещё pending — показываем 100%
    return (attendedLectures / confirmed).clamp(0.0, 1.0);
  }

  /// «Честный» процент с учётом pending в знаменателе (для отображения минимума).
  double get percentageWorstCase {
    if (passedLectures <= 0) return 1.0;
    return (attendedLectures / passedLectures).clamp(0.0, 1.0);
  }
}
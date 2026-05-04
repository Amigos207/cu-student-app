class ExamSemester {
  final int    id;
  final String name; // "2026 გაზაფხულის სემესტრი"

  const ExamSemester({required this.id, required this.name});
}

class ExamEntry {
  final String   code;      // "ENGL 0009E"
  final String   nameKa;   // Georgian name from table
  final String   nameEn;   // English name from hidden input (may equal nameKa)
  final String   teacher;
  final DateTime date;
  final String   time;     // "15:45"
  final String   room;
  final int      semId;

  const ExamEntry({
    required this.code,
    required this.nameKa,
    required this.nameEn,
    required this.teacher,
    required this.date,
    required this.time,
    required this.room,
    required this.semId,
  });

  /// true если экзамен ещё не прошёл (с запасом в 2 часа)
  bool get isUpcoming {
    final now      = DateTime.now();
    final examTime = _parseTime();
    if (examTime == null) return date.isAfter(now);
    final examEnd  = examTime.add(const Duration(hours: 2));
    return examEnd.isAfter(now);
  }

  DateTime? _parseTime() {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    try {
      return DateTime(
        date.year, date.month, date.day,
        int.parse(parts[0]), int.parse(parts[1]),
      );
    } catch (_) { return null; }
  }

  /// Дата+время для сортировки
  DateTime get sortKey =>
      _parseTime() ?? DateTime(date.year, date.month, date.day, 23, 59);
}

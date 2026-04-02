class Lesson {
  final String name;
  final String teacher;
  final String day;   // English: "Monday", "Tuesday", ...
  final String time;  // "11:15-13:10"
  final String room;

  Lesson({
    required this.name,
    required this.teacher,
    required this.day,
    required this.time,
    required this.room,
  });

  /// Нормализованный ключ для O(1)-поиска при мэтчинге посещаемости.
  /// Совпадает с ключом, который строит AttendanceMatcher.
  String get matchKey => _simplify(name) + '|' + _simplify(teacher);

  /// Ключ только по названию (для fallback-поиска)
  String get nameKey => _simplify(name);

  /// Ключ только по преподавателю (для fallback-поиска)
  String get teacherKey => _simplify(teacher);

  static String _simplify(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');
}
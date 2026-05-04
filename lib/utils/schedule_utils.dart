// lib/utils/schedule_utils.dart
//
// Shared helpers used by HomeScreen, ScheduleScreen, AttendanceScreen,
// CalendarScreen and any future screen that works with schedule / time data.
// Previously every screen copy-pasted these — centralising eliminates drift.

/// ISO weekday-name list (index 0 = Monday, matching DateTime.weekday - 1).
const List<String> kWeekDays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

/// Collapses whitespace and lowercases — used for fuzzy subject/teacher matching.
String simplify(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

/// Parses "dd/mm/yyyy" attendance date strings into [DateTime].
/// Returns null if the string is malformed.
DateTime? parseDateStr(String s) {
  final parts = s.split('/');
  if (parts.length != 3) return null;
  try {
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  } catch (_) {
    return null;
  }
}

/// Normalises a teacher name for fuzzy matching (lower-case, no whitespace).
String normTeacher(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Returns true when two teacher strings refer to the same person (substring match).
bool teacherMatch(String a, String b) {
  final na = normTeacher(a), nb = normTeacher(b);
  return na.isNotEmpty && nb.isNotEmpty && (na.contains(nb) || nb.contains(na));
}

/// Parses "HH:mm-HH:mm" (or "HH:mm") and returns start time in minutes since midnight.
/// Returns null if the string cannot be parsed.
int? parseTimeToMinutes(String t) {
  try {
    final part = t.split('-').first.trim().split(':');
    if (part.length < 2) return null;
    return int.parse(part[0]) * 60 + int.parse(part[1]);
  } catch (_) {
    return null;
  }
}

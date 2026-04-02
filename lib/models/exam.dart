class Exam {
  final String subject;
  final String date; // Например: "24/05/2026"
  final String time; // Например: "14:00"
  final String room;
  final String teacher;

  Exam({
    required this.subject,
    required this.date,
    required this.time,
    required this.room,
    required this.teacher,
  });
}
/// Models for the Materials (მასალები) feature.

class CourseSubject {
  final String code;
  final String name;
  final String teacher;
  /// Hidden-form fields needed to POST to masalebi.php for this subject's files.
  final Map<String, String> payloadForDetails;

  const CourseSubject({
    required this.code,
    required this.name,
    required this.teacher,
    required this.payloadForDetails,
  });
}

class MaterialFile {
  final String name;
  final String url;

  const MaterialFile({required this.name, required this.url});

  /// Guesses the file type from the URL for icon selection.
  String get extension {
    final lower = url.toLowerCase();
    if (lower.contains('drive.google.com') ||
        lower.contains('docs.google.com')) return 'gdrive';
    final dot = lower.lastIndexOf('.');
    if (dot == -1) return '';
    return lower.substring(dot + 1);
  }
}

class LectureGroup {
  final String title; // e.g. "ლექცია-1"
  final String date;  // e.g. "18/02/2026"
  final List<MaterialFile> files;

  const LectureGroup({
    required this.title,
    required this.date,
    required this.files,
  });

  bool get hasFiles => files.isNotEmpty;
}

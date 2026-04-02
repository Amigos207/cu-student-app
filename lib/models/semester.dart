/// Семестр, полученный с портала CU.
/// [id]   — value радиокнопки (86, 87, 88 …)
/// [name] — полное название из скрытого поля "semestri"
class Semester {
  final int    id;
  final String name;

  const Semester({required this.id, required this.name});

  @override
  bool operator ==(Object other) => other is Semester && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
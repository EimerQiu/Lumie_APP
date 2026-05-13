// Splits a single text input ("Salmon, Rice, Cabbage") into individual food
// item names. Used by both the Log screen and the Detail screen so a user can
// paste or type a comma-separated list and get one chip per item.
//
// Whitespace and empties are stripped; case and order are preserved.
List<String> splitFoodInput(String input) {
  if (input.trim().isEmpty) return const [];
  // Common visual separators users might type: comma, Chinese comma, semicolon,
  // newline. Split on any of them so paste-in lists work without manual
  // re-typing.
  final pattern = RegExp(r'[,\n;、，]+');
  return input
      .split(pattern)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Build a readable meal name from a list of food item names.
///
/// Produces an Oxford-comma–free "A, B and C" string for immediate display
/// before the LLM re-derives a richer name on save. Returns an empty string
/// when [names] is empty so callers can fall back gracefully.
///
/// Examples:
///   ["Salmon"]                            → "Salmon"
///   ["Bread", "Almond butter"]            → "Bread and Almond butter"
///   ["Rice", "Tuna in water", "Kimchi"]   → "Rice, Tuna in water and Kimchi"
String deriveMealNameFromFoods(List<String> names) {
  final items = names
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList();
  if (items.isEmpty) return '';
  if (items.length == 1) return items[0];
  if (items.length == 2) return '${items[0]} and ${items[1]}';
  final last = items.last;
  final rest = items.sublist(0, items.length - 1).join(', ');
  final full = '$rest and $last';
  // Backend meal_name field caps at 120 chars; truncate with ellipsis if needed.
  if (full.length <= 120) return full;
  return '${full.substring(0, 117)}…';
}

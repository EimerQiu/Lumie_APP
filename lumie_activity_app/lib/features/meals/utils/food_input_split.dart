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

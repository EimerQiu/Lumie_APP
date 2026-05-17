// Splits a single text input into individual food item names.
//
// Detects whatever separator the user naturally typed and splits on it.
// If multiple separator types appear in the same input they are all used.
//
// Recognised separators
//   Strong (unambiguous): , ; \n + & / | · 、，  em-dash  en-dash
//                         spaced hyphen " - "
//   Weak (only when used ≥2 times in input, so single "and" in
//   compound names like "bread and butter" is preserved):  "and"
//
// Oxford-comma "and" at the start of a segment after strong-splitting
// is stripped ("eggs, ham, and toast" → ["eggs", "ham", "toast"]).
//
// Whitespace and empty items are stripped; case and order are preserved.
List<String> splitFoodInput(String input) {
  if (input.trim().isEmpty) return const [];

  // Strong separators. Spaced-hyphen and em/en-dash need word-boundary
  // treatment to avoid breaking hyphenated compound names like "low-fat".
  //   \s+-\s+   → space(s) + hyphen + space(s)
  //   \s*[—–]\s* → em-dash or en-dash with optional surrounding spaces
  const strong = r'[,+&/;|\n、，·]|\s+-\s+|\s*[—–]\s*';
  final strongRe = RegExp(strong);

  List<String> items;

  if (strongRe.hasMatch(input)) {
    items = input
        .split(strongRe)
        .map((s) => s.trim())
        // Strip Oxford-comma "and" that lands at the start of a segment,
        // e.g. the last chunk of "eggs, ham, and toast" becomes "toast".
        .map((s) =>
            s.replaceFirst(RegExp(r'^and\s+', caseSensitive: false), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  } else {
    // No strong separator found. Only treat "and" as a separator when it
    // appears at least twice — one occurrence most likely belongs to a
    // compound food name (e.g. "bread and butter", "mac and cheese").
    final andRe = RegExp(r'\s+and\s+', caseSensitive: false);
    if (andRe.allMatches(input).length >= 2) {
      items = input
          .split(andRe)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      // Single item (or "and" is part of a food name).
      final trimmed = input.trim();
      items = trimmed.isNotEmpty ? [trimmed] : const [];
    }
  }

  return items;
}

// ─── Context-aware split (post-analysis edit) ────────────────────────────────

/// Splits [input] into food item name(s), using [originalItemName] as context
/// so that edits to a composite food item stay correctly grouped.
///
/// Composite detection uses explicit compound indicators in [originalItemName]:
///   "with"  "and"  "+"  "/" → the original was a multi-component dish
///
/// When the original item is composite, [input] is returned as a single entry
/// regardless of any separators the user typed — the user is refining the
/// sub-components of the dish, not splitting it into sibling items.
///
/// When the original item is simple (or [originalItemName] is null), falls
/// back to [splitFoodInput] and respects all separators normally.
///
/// Examples (original item in parentheses):
///   "Whole wheat bread + PB + banana"  ("Bread with PB and banana")
///       → ["Whole wheat bread + PB + banana"]   ← one chip, stays composite
///   "Salmon, Rice, Cabbage"            ("Salmon")
///       → ["Salmon", "Rice", "Cabbage"]         ← standard split
///   "scrambled eggs + cheese + spinach" ("Fried egg")
///       → ["scrambled eggs", "cheese", "spinach"] ← standard split
List<String> splitFoodInputWithContext(
  String input,
  String? originalItemName,
) {
  // No prior analysis context → use standard smart-separator split.
  if (originalItemName == null || originalItemName.trim().isEmpty) {
    return splitFoodInput(input);
  }

  // For composite original items, the user is refining internal components.
  // Return the raw input as a single chip so it stays grouped correctly.
  if (isCompositeItemName(originalItemName)) {
    final trimmed = input.trim();
    return trimmed.isNotEmpty ? [trimmed] : const [];
  }

  // Simple original item → standard split.
  return splitFoodInput(input);
}

/// True when [name] contains explicit indicators that it is a composite food
/// item (a dish made of multiple named components), not a single ingredient.
///
/// Matches: "Bread with PB and banana", "Yogurt + berries + granola",
///          "Salmon / rice / cabbage" — all compound.
/// Does not match: "Salmon", "Fried egg", "Greek yogurt", "RX Bar".
bool isCompositeItemName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains(' with ')) return true;
  if (lower.contains(' and ')) return true;
  if (lower.contains('+')) return true;
  // Forward slash only counts when it clearly separates named ingredients
  // (e.g. "salmon / rice"), not when it's part of a measurement ("1/2 cup").
  if (lower.contains('/') && !RegExp(r'\d+/\d+').hasMatch(lower)) return true;
  return false;
}

// ─── Meal name derivation ─────────────────────────────────────────────────────

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

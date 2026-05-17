// Meal Feature models — mirror backend app/models/meal.py.
// Macro ratios are categorical (low/moderate/high); numeric grams never reach the client.

import 'package:flutter/material.dart' show Color;

// Backend uses datetime.utcnow().isoformat() which does NOT append 'Z'.
String _ensureUtcSuffix(String dateStr) {
  if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
    return '${dateStr}Z';
  }
  return dateStr;
}

enum MacroLevel {
  low,
  moderate,
  high;

  String get apiValue {
    switch (this) {
      case MacroLevel.low:
        return 'low';
      case MacroLevel.moderate:
        return 'moderate';
      case MacroLevel.high:
        return 'high';
    }
  }

  String get displayName {
    switch (this) {
      case MacroLevel.low:
        return 'Low';
      case MacroLevel.moderate:
        return 'Moderate';
      case MacroLevel.high:
        return 'High';
    }
  }

  static MacroLevel fromString(String? value) {
    switch (value) {
      case 'low':
        return MacroLevel.low;
      case 'high':
        return MacroLevel.high;
      case 'moderate':
      default:
        return MacroLevel.moderate;
    }
  }
}

enum MealVisibility {
  private,
  team;

  String get apiValue => this == MealVisibility.private ? 'private' : 'team';

  static MealVisibility fromString(String? value) =>
      value == 'team' ? MealVisibility.team : MealVisibility.private;
}

/// Layout for the portion editor — mirrors backend `MealStructure`.
///
/// `multiItem` (default): each food in `food_items` gets its own portion bar
/// at the item level. `singleItemWithIngredients`: there is exactly one entry
/// in `food_items`, and its `ingredients` list is what the portion bar
/// operates on.
enum MealStructure {
  multiItem,
  singleItemWithIngredients;

  String get apiValue {
    switch (this) {
      case MealStructure.multiItem:
        return 'multi_item';
      case MealStructure.singleItemWithIngredients:
        return 'single_item_with_ingredients';
    }
  }

  static MealStructure fromString(String? value) {
    switch (value) {
      case 'single_item_with_ingredients':
        return MealStructure.singleItemWithIngredients;
      case 'multi_item':
      default:
        return MealStructure.multiItem;
    }
  }
}

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack;

  String get apiValue {
    switch (this) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
      case MealType.snack:
        return 'Snack';
    }
  }

  String get displayName => apiValue;

  static MealType fromString(String? value) {
    switch (value) {
      case 'Breakfast':
        return MealType.breakfast;
      case 'Lunch':
        return MealType.lunch;
      case 'Dinner':
        return MealType.dinner;
      case 'Snack':
      default:
        return MealType.snack;
    }
  }
}

enum NutritionLevel {
  limited,
  fair,
  good,
  nutritious;

  String get apiValue {
    switch (this) {
      case NutritionLevel.limited:
        return 'Limited';
      case NutritionLevel.fair:
        return 'Fair';
      case NutritionLevel.good:
        return 'Good';
      case NutritionLevel.nutritious:
        return 'Nutritious';
    }
  }

  String get displayName => apiValue;

  /// Position on the 4-point scale, 0.0 (Limited) to 1.0 (Nutritious).
  /// Used by the home-screen trend chart and the detail-screen slider.
  double get fraction {
    switch (this) {
      case NutritionLevel.limited:
        return 0.0;
      case NutritionLevel.fair:
        return 1 / 3;
      case NutritionLevel.good:
        return 2 / 3;
      case NutritionLevel.nutritious:
        return 1.0;
    }
  }

  /// Slice 7A §3 colour palette — warm, never alarming.
  /// Progression: muted/neutral at Limited → vivid gold at Nutritious.
  /// Used for the slider dot + active fill, the breakdown bar fills, and the
  /// level label on cards.
  Color get color {
    switch (this) {
      case NutritionLevel.nutritious:
        return const Color(0xFFF59E0B); // primaryLemonDark — vivid gold
      case NutritionLevel.good:
        return const Color(0xFFFBBF24); // primaryYellow — soft yellow-gold
      case NutritionLevel.fair:
        return const Color(0xFFD4A574); // warm muted amber
      case NutritionLevel.limited:
        return const Color(0xFFA8A29E); // calm grey-beige (no warning)
    }
  }

  static NutritionLevel fromString(String? value) {
    switch (value) {
      case 'Limited':
        return NutritionLevel.limited;
      case 'Fair':
        return NutritionLevel.fair;
      case 'Nutritious':
        return NutritionLevel.nutritious;
      case 'Good':
      default:
        return NutritionLevel.good;
    }
  }
}

/// Continuous 0.0–1.0 scores for each of the six macro/quality fields.
///
/// Ranges: 0.0–0.33 = Low, 0.34–0.66 = Moderate, 0.67–1.0 = High.
/// Used to fill the smooth breakdown bar. When scores are absent (legacy data),
/// they are derived from the categorical [MacroLevel] labels.
class MacroScores {
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double processingLevel;
  final double addedSugar;

  const MacroScores({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.processingLevel,
    required this.addedSugar,
  });

  factory MacroScores.fromJson(Map<String, dynamic> json) {
    double v(dynamic raw, double fallback) {
      if (raw is double) return raw.clamp(0.0, 1.0);
      if (raw is int) return raw.toDouble().clamp(0.0, 1.0);
      if (raw is String) return (double.tryParse(raw) ?? fallback).clamp(0.0, 1.0);
      return fallback;
    }
    return MacroScores(
      protein: v(json['protein'], 0.5),
      carbs: v(json['carbs'], 0.5),
      fat: v(json['fat'], 0.5),
      fiber: v(json['fiber'], 0.5),
      processingLevel: v(json['processing_level'], 0.5),
      addedSugar: v(json['added_sugar'], 0.5),
    );
  }

  Map<String, dynamic> toJson() => {
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'processing_level': processingLevel,
        'added_sugar': addedSugar,
      };

  /// Derive approximate scores from categorical levels when the backend
  /// hasn't supplied precise values (legacy meals).
  static double scoreFromLevel(MacroLevel level) => const {
        MacroLevel.low: 0.17,
        MacroLevel.moderate: 0.50,
        MacroLevel.high: 0.83,
      }[level]!;

  factory MacroScores.fromLevels({
    required MacroLevel protein,
    required MacroLevel carbs,
    required MacroLevel fat,
    required MacroLevel fiber,
    required MacroLevel processingLevel,
    required MacroLevel addedSugar,
  }) =>
      MacroScores(
        protein: scoreFromLevel(protein),
        carbs: scoreFromLevel(carbs),
        fat: scoreFromLevel(fat),
        fiber: scoreFromLevel(fiber),
        processingLevel: scoreFromLevel(processingLevel),
        addedSugar: scoreFromLevel(addedSugar),
      );
}

class MacroRatio {
  final MacroLevel protein;
  final MacroLevel carbs;
  final MacroLevel fat;
  final MacroLevel fiber;

  const MacroRatio({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  factory MacroRatio.fromJson(Map<String, dynamic> json) {
    return MacroRatio(
      protein: MacroLevel.fromString(json['protein'] as String?),
      carbs: MacroLevel.fromString(json['carbs'] as String?),
      fat: MacroLevel.fromString(json['fat'] as String?),
      fiber: MacroLevel.fromString(json['fiber'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'protein': protein.apiValue,
        'carbs': carbs.apiValue,
        'fat': fat.apiValue,
        'fiber': fiber.apiValue,
      };

  MacroRatio copyWith({
    MacroLevel? protein,
    MacroLevel? carbs,
    MacroLevel? fat,
    MacroLevel? fiber,
  }) {
    return MacroRatio(
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
    );
  }
}

/// A component of a single composite food item (e.g. granola in a yogurt
/// bowl). Only meaningful when the parent meal's [MealStructure] is
/// `singleItemWithIngredients`. Carries only a name and a relative portion
/// weight — no grams or calories ever cross the wire.
class Ingredient {
  final String name;
  final int portionWeight;

  const Ingredient({required this.name, this.portionWeight = 1});

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final weight = json['portion_weight'];
    int parsedWeight = 1;
    if (weight is int) {
      parsedWeight = weight;
    } else if (weight is double) {
      parsedWeight = weight.round();
    } else if (weight is String) {
      parsedWeight = int.tryParse(weight) ?? 1;
    }
    if (parsedWeight < 1) parsedWeight = 1;
    return Ingredient(
      name: (json['name'] as String?) ?? '',
      portionWeight: parsedWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'portion_weight': portionWeight,
      };

  Ingredient copyWith({String? name, int? portionWeight}) {
    return Ingredient(
      name: name ?? this.name,
      portionWeight: portionWeight ?? this.portionWeight,
    );
  }
}

class FoodItem {
  final String name;
  final MacroRatio? macroRatio;

  /// Relative portion weight on the plate. Always integer ≥1. The visible
  /// width of each segment in the portion bar is `portionWeight / Σweights`.
  /// No grams, no calories — pure relative ratio.
  final int portionWeight;

  /// Components of a composite dish. Populated only when the parent meal's
  /// [MealStructure] is `singleItemWithIngredients`. Null/empty otherwise.
  final List<Ingredient>? ingredients;

  const FoodItem({
    required this.name,
    this.macroRatio,
    this.portionWeight = 1,
    this.ingredients,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final ratio = json['macro_ratio'];
    final weight = json['portion_weight'];
    int parsedWeight = 1;
    if (weight is int) {
      parsedWeight = weight;
    } else if (weight is double) {
      parsedWeight = weight.round();
    } else if (weight is String) {
      parsedWeight = int.tryParse(weight) ?? 1;
    }
    if (parsedWeight < 1) parsedWeight = 1;
    final rawIngredients = json['ingredients'];
    List<Ingredient>? ingredients;
    if (rawIngredients is List) {
      final parsed = rawIngredients
          .whereType<Map<String, dynamic>>()
          .map(Ingredient.fromJson)
          .where((i) => i.name.trim().isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) ingredients = parsed;
    }
    return FoodItem(
      name: (json['name'] as String?) ?? '',
      macroRatio: ratio is Map<String, dynamic>
          ? MacroRatio.fromJson(ratio)
          : null,
      portionWeight: parsedWeight,
      ingredients: ingredients,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (macroRatio != null) 'macro_ratio': macroRatio!.toJson(),
        'portion_weight': portionWeight,
        if (ingredients != null && ingredients!.isNotEmpty)
          'ingredients': ingredients!.map((i) => i.toJson()).toList(),
      };

  FoodItem copyWith({
    String? name,
    MacroRatio? macroRatio,
    int? portionWeight,
    List<Ingredient>? ingredients,
    bool clearIngredients = false,
  }) {
    return FoodItem(
      name: name ?? this.name,
      macroRatio: macroRatio ?? this.macroRatio,
      portionWeight: portionWeight ?? this.portionWeight,
      ingredients:
          clearIngredients ? null : (ingredients ?? this.ingredients),
    );
  }
}

/// One persisted image attached to a meal. Mirrors `TaskAttachment` shape
/// (image-only — videos are not allowed for meals).
class MealAttachment {
  final String attachmentId;
  final String filename;
  final String contentType;
  final int sizeBytes;
  final String path;
  final String url;
  final String? thumbnailPath;
  final String? thumbnailUrl;
  final String uploadedAt;

  const MealAttachment({
    required this.attachmentId,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.path,
    required this.url,
    this.thumbnailPath,
    this.thumbnailUrl,
    required this.uploadedAt,
  });

  factory MealAttachment.fromJson(Map<String, dynamic> json) {
    return MealAttachment(
      attachmentId: (json['attachment_id'] as String?) ?? '',
      filename: (json['filename'] as String?) ?? '',
      contentType: (json['content_type'] as String?) ?? 'image/jpeg',
      sizeBytes: (json['size_bytes'] as int?) ?? 0,
      path: (json['path'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      thumbnailPath: json['thumbnail_path'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      uploadedAt: (json['uploaded_at'] as String?) ?? '',
    );
  }
}

/// Result of `POST /meals/analyze`. The meal document is NOT yet persisted —
/// the caller must `POST /meals` with the same `mealId` to confirm.
class MealAnalyzeResult {
  final String mealId;
  final List<MealAttachment> images;
  final List<FoodItem> foodItems;
  final MacroRatio macroRatio;
  final MealStructure structure;
  final String? mealName;
  final NutritionLevel? nutritionLevel;
  final String? advisorInsight;
  final MacroLevel? processingLevel;
  final MacroLevel? addedSugar;

  final MacroScores? macroScores;
  final bool isPackaged;
  final String? detectedBrand;
  final String? detectedProduct;

  const MealAnalyzeResult({
    required this.mealId,
    required this.images,
    required this.foodItems,
    required this.macroRatio,
    this.structure = MealStructure.multiItem,
    this.macroScores,
    this.mealName,
    this.nutritionLevel,
    this.advisorInsight,
    this.processingLevel,
    this.addedSugar,
    this.isPackaged = false,
    this.detectedBrand,
    this.detectedProduct,
  });

  factory MealAnalyzeResult.fromJson(Map<String, dynamic> json) {
    return MealAnalyzeResult(
      mealId: json['meal_id'] as String,
      images: ((json['images'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MealAttachment.fromJson)
          .toList(),
      foodItems: ((json['food_items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FoodItem.fromJson)
          .toList(),
      macroRatio: MacroRatio.fromJson(
        (json['macro_ratio'] as Map<String, dynamic>?) ?? const {},
      ),
      structure: MealStructure.fromString(json['structure'] as String?),
      macroScores: json['macro_scores'] is Map<String, dynamic>
          ? MacroScores.fromJson(json['macro_scores'] as Map<String, dynamic>)
          : null,
      isPackaged: (json['is_packaged'] as bool?) ?? false,
      detectedBrand: json['detected_brand'] as String?,
      detectedProduct: json['detected_product'] as String?,
      mealName: json['meal_name'] as String?,
      nutritionLevel: json['nutrition_level'] is String
          ? NutritionLevel.fromString(json['nutrition_level'] as String?)
          : null,
      advisorInsight: json['advisor_insight'] as String?,
      processingLevel: json['processing_level'] is String
          ? MacroLevel.fromString(json['processing_level'] as String?)
          : null,
      addedSugar: json['added_sugar'] is String
          ? MacroLevel.fromString(json['added_sugar'] as String?)
          : null,
    );
  }
}

class Meal {
  final String mealId;
  final String userId;
  final String? userName;
  final List<MealAttachment> images;
  final List<FoodItem> foodItems;
  final MacroRatio macroRatio;
  final MealStructure structure;
  final String? note;
  final MealVisibility visibility;
  final String? teamId;
  final String? linkedTaskId;
  final String? mealName;
  final MealType? mealType;
  final DateTime? mealTime;
  final NutritionLevel? nutritionLevel;
  final String? advisorInsight;
  final MacroLevel? processingLevel;
  final MacroLevel? addedSugar;
  final DateTime createdAt;
  final DateTime updatedAt;

  final MacroScores? macroScores;
  final bool isPackaged;
  final String? detectedBrand;
  final String? detectedProduct;

  const Meal({
    required this.mealId,
    required this.userId,
    this.userName,
    this.images = const [],
    required this.foodItems,
    required this.macroRatio,
    this.structure = MealStructure.multiItem,
    this.macroScores,
    this.isPackaged = false,
    this.detectedBrand,
    this.detectedProduct,
    this.note,
    required this.visibility,
    this.teamId,
    this.linkedTaskId,
    this.mealName,
    this.mealType,
    this.mealTime,
    this.nutritionLevel,
    this.advisorInsight,
    this.processingLevel,
    this.addedSugar,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Meal.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptional(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return DateTime.parse(_ensureUtcSuffix(raw));
      } catch (_) {
        return null;
      }
    }

    return Meal(
      mealId: json['meal_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String?,
      images: ((json['images'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MealAttachment.fromJson)
          .toList(),
      foodItems: ((json['food_items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FoodItem.fromJson)
          .toList(),
      macroRatio: MacroRatio.fromJson(
        (json['macro_ratio'] as Map<String, dynamic>?) ?? const {},
      ),
      structure: MealStructure.fromString(json['structure'] as String?),
      macroScores: json['macro_scores'] is Map<String, dynamic>
          ? MacroScores.fromJson(json['macro_scores'] as Map<String, dynamic>)
          : null,
      isPackaged: (json['is_packaged'] as bool?) ?? false,
      detectedBrand: json['detected_brand'] as String?,
      detectedProduct: json['detected_product'] as String?,
      note: json['note'] as String?,
      visibility: MealVisibility.fromString(json['visibility'] as String?),
      teamId: json['team_id'] as String?,
      linkedTaskId: json['linked_task_id'] as String?,
      mealName: json['meal_name'] as String?,
      mealType: json['meal_type'] is String
          ? MealType.fromString(json['meal_type'] as String?)
          : null,
      mealTime: parseOptional(json['meal_time'] as String?),
      nutritionLevel: json['nutrition_level'] is String
          ? NutritionLevel.fromString(json['nutrition_level'] as String?)
          : null,
      advisorInsight: json['advisor_insight'] as String?,
      processingLevel: json['processing_level'] is String
          ? MacroLevel.fromString(json['processing_level'] as String?)
          : null,
      addedSugar: json['added_sugar'] is String
          ? MacroLevel.fromString(json['added_sugar'] as String?)
          : null,
      createdAt: DateTime.parse(_ensureUtcSuffix(json['created_at'] as String)),
      updatedAt: DateTime.parse(_ensureUtcSuffix(json['updated_at'] as String)),
    );
  }

  bool get isTeamMeal => visibility == MealVisibility.team && teamId != null;

  /// Best-effort display name. Falls back to first 1–2 food items when the
  /// backend didn't supply mealName (legacy or partial meals).
  String get displayName {
    final name = mealName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (foodItems.isEmpty) return 'Meal';
    if (foodItems.length == 1) return foodItems.first.name;
    return '${foodItems[0].name} & ${foodItems[1].name}';
  }

  /// The user-eaten time for grouping/display, falling back to createdAt.
  DateTime get effectiveTime => mealTime ?? createdAt;
}

class MealListResponse {
  final List<Meal> meals;
  final int total;
  final String? nextCursor;

  const MealListResponse({
    required this.meals,
    required this.total,
    this.nextCursor,
  });

  factory MealListResponse.fromJson(Map<String, dynamic> json) {
    return MealListResponse(
      meals: ((json['meals'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Meal.fromJson)
          .toList(),
      total: (json['total'] as int?) ?? 0,
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class MealCorrectionResponse {
  final String correctionId;
  final String mealId;
  final String userId;
  final String createdAt;

  const MealCorrectionResponse({
    required this.correctionId,
    required this.mealId,
    required this.userId,
    required this.createdAt,
  });

  factory MealCorrectionResponse.fromJson(Map<String, dynamic> json) {
    return MealCorrectionResponse(
      correctionId: json['correction_id'] as String,
      mealId: json['meal_id'] as String,
      userId: json['user_id'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}

// ─── Weekly trend (home-screen chart) ────────────────────────────────────────

class MealTrendDay {
  /// YYYY-MM-DD in the user's local timezone.
  final String date;

  /// Average nutrition level for the day; null when there were zero meals.
  final NutritionLevel? level;

  final int mealCount;

  const MealTrendDay({
    required this.date,
    this.level,
    required this.mealCount,
  });

  factory MealTrendDay.fromJson(Map<String, dynamic> json) {
    return MealTrendDay(
      date: json['date'] as String,
      level: json['level'] is String
          ? NutritionLevel.fromString(json['level'] as String?)
          : null,
      mealCount: (json['meal_count'] as int?) ?? 0,
    );
  }

  /// Calendar date as DateTime at local midnight.
  DateTime get dateTime {
    final parts = date.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}

class MealTrendResponse {
  /// Oldest first; the last entry is today.
  final List<MealTrendDay> days;

  const MealTrendResponse({required this.days});

  factory MealTrendResponse.fromJson(Map<String, dynamic> json) {
    return MealTrendResponse(
      days: ((json['days'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MealTrendDay.fromJson)
          .toList(),
    );
  }
}

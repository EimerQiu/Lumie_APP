// Meal Feature models — mirror backend app/models/meal.py.
// Macro ratios are categorical (low/moderate/high); numeric grams never reach the client.

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

class FoodItem {
  final String name;
  final MacroRatio? macroRatio;

  const FoodItem({required this.name, this.macroRatio});

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final ratio = json['macro_ratio'];
    return FoodItem(
      name: (json['name'] as String?) ?? '',
      macroRatio: ratio is Map<String, dynamic>
          ? MacroRatio.fromJson(ratio)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (macroRatio != null) 'macro_ratio': macroRatio!.toJson(),
      };

  FoodItem copyWith({String? name, MacroRatio? macroRatio}) {
    return FoodItem(
      name: name ?? this.name,
      macroRatio: macroRatio ?? this.macroRatio,
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
  final String? mealName;
  final NutritionLevel? nutritionLevel;
  final String? advisorInsight;

  const MealAnalyzeResult({
    required this.mealId,
    required this.images,
    required this.foodItems,
    required this.macroRatio,
    this.mealName,
    this.nutritionLevel,
    this.advisorInsight,
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
      mealName: json['meal_name'] as String?,
      nutritionLevel: json['nutrition_level'] is String
          ? NutritionLevel.fromString(json['nutrition_level'] as String?)
          : null,
      advisorInsight: json['advisor_insight'] as String?,
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
  final String? note;
  final MealVisibility visibility;
  final String? teamId;
  final String? linkedTaskId;
  final String? mealName;
  final MealType? mealType;
  final DateTime? mealTime;
  final NutritionLevel? nutritionLevel;
  final String? advisorInsight;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Meal({
    required this.mealId,
    required this.userId,
    this.userName,
    this.images = const [],
    required this.foodItems,
    required this.macroRatio,
    this.note,
    required this.visibility,
    this.teamId,
    this.linkedTaskId,
    this.mealName,
    this.mealType,
    this.mealTime,
    this.nutritionLevel,
    this.advisorInsight,
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

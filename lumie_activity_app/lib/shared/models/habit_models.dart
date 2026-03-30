/// Habit Tracker daily entry models.

class HabitEntry {
  final String userId;
  final String date;
  final int? mood;               // 1–5
  final String? energy;          // "low" | "moderate" | "high"
  final String? hunger;          // "low" | "normal" | "high"
  final String? workload;        // "light" | "moderate" | "heavy"
  final String? fatigue;         // "low" | "moderate" | "high"
  final double? conditionMetric;
  final DateTime updatedAt;

  const HabitEntry({
    required this.userId,
    required this.date,
    this.mood,
    this.energy,
    this.hunger,
    this.workload,
    this.fatigue,
    this.conditionMetric,
    required this.updatedAt,
  });

  factory HabitEntry.fromJson(Map<String, dynamic> json) {
    return HabitEntry(
      userId: json['user_id'] as String,
      date: json['date'] as String,
      mood: json['mood'] as int?,
      energy: json['energy'] as String?,
      hunger: json['hunger'] as String?,
      workload: json['workload'] as String?,
      fatigue: json['fatigue'] as String?,
      conditionMetric: json['condition_metric'] != null
          ? (json['condition_metric'] as num).toDouble()
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}

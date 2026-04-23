// Rest days data models for managing user rest days.
import 'package:flutter/foundation.dart';

/// Rest day settings configuration.
class RestDaySettings {
  /// Days of week that are recurring rest days (0=Monday, 6=Sunday).
  final List<int> weeklyRestDays;

  /// Specific dates that are one-time rest days.
  final List<DateTime> specificDates;

  /// When this configuration was last updated.
  final DateTime updatedAt;

  const RestDaySettings({
    required this.weeklyRestDays,
    required this.specificDates,
    required this.updatedAt,
  });

  /// Create from JSON response.
  factory RestDaySettings.fromJson(Map<String, dynamic> json) {
    return RestDaySettings(
      weeklyRestDays: List<int>.from(json['weekly_rest_days'] ?? []),
      specificDates: (json['specific_dates'] as List<dynamic>?)
              ?.map((d) => DateTime.parse(d))
              .toList() ??
          [],
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  /// Convert to JSON for API requests.
  Map<String, dynamic> toJson() {
    return {
      'weekly_rest_days': weeklyRestDays,
      'specific_dates': specificDates
          .map((d) => d.toIso8601String().split('T')[0])
          .toList(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Check if a given date is a rest day.
  bool isRestDay(DateTime date) {
    // Check weekly recurring rest days (0=Monday, 6=Sunday)
    if (weeklyRestDays.contains(date.weekday % 7)) {
      return true;
    }

    // Check specific dates (date-only comparison)
    final dateOnly = DateTime(date.year, date.month, date.day);
    return specificDates.any((d) {
      final dOnly = DateTime(d.year, d.month, d.day);
      return dOnly == dateOnly;
    });
  }

  /// Create a copy with updated fields.
  RestDaySettings copyWith({
    List<int>? weeklyRestDays,
    List<DateTime>? specificDates,
    DateTime? updatedAt,
  }) {
    return RestDaySettings(
      weeklyRestDays: weeklyRestDays ?? this.weeklyRestDays,
      specificDates: specificDates ?? this.specificDates,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RestDaySettings &&
        listEquals(other.weeklyRestDays, weeklyRestDays) &&
        listEquals(other.specificDates, specificDates) &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      weeklyRestDays.hashCode ^
      specificDates.hashCode ^
      updatedAt.hashCode;
}

/// Rest day suggestion based on sleep quality.
class RestDaySuggestion {
  /// Whether a rest day should be suggested.
  final bool shouldSuggest;

  /// Reason for the suggestion (e.g., 'poor_sleep').
  final String reason;

  /// Sleep quality score that triggered the suggestion.
  final double sleepQuality;

  /// User-friendly message explaining the suggestion.
  final String message;

  const RestDaySuggestion({
    required this.shouldSuggest,
    required this.reason,
    required this.sleepQuality,
    required this.message,
  });

  /// Create from JSON response.
  factory RestDaySuggestion.fromJson(Map<String, dynamic> json) {
    return RestDaySuggestion(
      shouldSuggest: json['should_suggest'] ?? false,
      reason: json['reason'] ?? '',
      sleepQuality: (json['sleep_quality'] ?? 100).toDouble(),
      message: json['message'] ?? '',
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'should_suggest': shouldSuggest,
      'reason': reason,
      'sleep_quality': sleepQuality,
      'message': message,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RestDaySuggestion &&
        other.shouldSuggest == shouldSuggest &&
        other.reason == reason &&
        other.sleepQuality == sleepQuality &&
        other.message == message;
  }

  @override
  int get hashCode =>
      shouldSuggest.hashCode ^
      reason.hashCode ^
      sleepQuality.hashCode ^
      message.hashCode;
}

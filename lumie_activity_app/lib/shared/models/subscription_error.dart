/// Subscription error response models for team limit handling

class SubscriptionInfo {
  final String currentTier;
  final String requiredTier;
  final bool upgradeRequired;

  const SubscriptionInfo({
    required this.currentTier,
    required this.requiredTier,
    required this.upgradeRequired,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      currentTier: json['current_tier'] as String,
      requiredTier: json['required_tier'] as String,
      upgradeRequired: json['upgrade_required'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_tier': currentTier,
      'required_tier': requiredTier,
      'upgrade_required': upgradeRequired,
    };
  }
}

class SubscriptionAction {
  final String type;
  final String label;
  final String destination;

  const SubscriptionAction({
    required this.type,
    required this.label,
    required this.destination,
  });

  factory SubscriptionAction.fromJson(Map<String, dynamic> json) {
    return SubscriptionAction(
      type: json['type'] as String,
      label: json['label'] as String,
      destination: json['destination'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'label': label,
      'destination': destination,
    };
  }
}

class SubscriptionErrorResponse {
  final String code;
  final String message;
  final String detail;
  final SubscriptionInfo subscription;
  final SubscriptionAction action;

  const SubscriptionErrorResponse({
    required this.code,
    required this.message,
    required this.detail,
    required this.subscription,
    required this.action,
  });

  factory SubscriptionErrorResponse.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>;
    return SubscriptionErrorResponse(
      code: error['code'] as String,
      message: error['message'] as String,
      detail: error['detail'] as String,
      subscription: SubscriptionInfo.fromJson(error['subscription']),
      action: SubscriptionAction.fromJson(error['action']),
    );
  }

  bool get isSubscriptionError => code == 'SUBSCRIPTION_LIMIT_REACHED';
}

/// Exception thrown when subscription limit is reached
class SubscriptionLimitException implements Exception {
  final SubscriptionErrorResponse errorResponse;

  SubscriptionLimitException(this.errorResponse);

  @override
  String toString() => errorResponse.message;
}

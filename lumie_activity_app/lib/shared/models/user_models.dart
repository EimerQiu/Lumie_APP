// User and Profile data models for Lumie App

enum AccountRole {
  teen,
  parent;

  String get displayName {
    switch (this) {
      case AccountRole.teen:
        return 'Teen';
      case AccountRole.parent:
        return 'Parent';
    }
  }

  String get description {
    switch (this) {
      case AccountRole.teen:
        return 'I am a teen (13-21) managing my health';
      case AccountRole.parent:
        return 'I am a parent supporting my teen';
    }
  }
}

enum HeightUnit {
  cm,
  ftIn;

  String get displayName {
    switch (this) {
      case HeightUnit.cm:
        return 'cm';
      case HeightUnit.ftIn:
        return 'ft/in';
    }
  }
}

enum WeightUnit {
  kg,
  lb;

  String get displayName {
    switch (this) {
      case WeightUnit.kg:
        return 'kg';
      case WeightUnit.lb:
        return 'lb';
    }
  }
}

class HeightData {
  final double value;
  final HeightUnit unit;

  const HeightData({
    required this.value,
    required this.unit,
  });

  factory HeightData.fromJson(Map<String, dynamic> json) {
    return HeightData(
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] == 'cm' ? HeightUnit.cm : HeightUnit.ftIn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'unit': unit == HeightUnit.cm ? 'cm' : 'ft_in',
    };
  }

  String get displayValue {
    if (unit == HeightUnit.cm) {
      return '${value.toStringAsFixed(0)} cm';
    } else {
      final feet = (value / 12).floor();
      final inches = (value % 12).round();
      return '$feet\' $inches"';
    }
  }
}

class WeightData {
  final double value;
  final WeightUnit unit;

  const WeightData({
    required this.value,
    required this.unit,
  });

  factory WeightData.fromJson(Map<String, dynamic> json) {
    return WeightData(
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] == 'kg' ? WeightUnit.kg : WeightUnit.lb,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'unit': unit == WeightUnit.kg ? 'kg' : 'lb',
    };
  }

  String get displayValue {
    return '${value.toStringAsFixed(1)} ${unit.displayName}';
  }
}

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;
  final AccountRole? role;
  final bool profileComplete;

  const AuthResponse({
    required this.accessToken,
    this.tokenType = 'bearer',
    required this.userId,
    required this.email,
    this.role,
    required this.profileComplete,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    AccountRole? role;
    if (json['role'] != null) {
      role = json['role'] == 'teen' ? AccountRole.teen : AccountRole.parent;
    }

    return AuthResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      userId: json['user_id'] as String,
      email: json['email'] as String,
      role: role,
      profileComplete: json['profile_complete'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
      'user_id': userId,
      'email': email,
      'role': role?.name,
      'profile_complete': profileComplete,
    };
  }
}

class UserProfile {
  final String userId;
  final String email;
  final AccountRole role;
  final String name;
  final int? age;
  final HeightData? height;
  final WeightData? weight;
  final String? icd10Code;
  final String? advisorName;
  final bool profileComplete;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.role,
    required this.name,
    this.age,
    this.height,
    this.weight,
    this.icd10Code,
    this.advisorName,
    required this.profileComplete,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      role: json['role'] == 'teen' ? AccountRole.teen : AccountRole.parent,
      name: json['name'] as String,
      age: json['age'] as int?,
      height: json['height'] != null ? HeightData.fromJson(json['height']) : null,
      weight: json['weight'] != null ? WeightData.fromJson(json['weight']) : null,
      icd10Code: json['icd10_code'] as String?,
      advisorName: json['advisor_name'] as String?,
      profileComplete: json['profile_complete'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'role': role.name,
      'name': name,
      'age': age,
      'height': height?.toJson(),
      'weight': weight?.toJson(),
      'icd10_code': icd10Code,
      'advisor_name': advisorName,
      'profile_complete': profileComplete,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ICD10Code {
  final String code;
  final String description;
  final String category;

  const ICD10Code({
    required this.code,
    required this.description,
    required this.category,
  });

  factory ICD10Code.fromJson(Map<String, dynamic> json) {
    return ICD10Code(
      code: json['code'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
    );
  }
}

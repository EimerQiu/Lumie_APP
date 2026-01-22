import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/user_models.dart';

/// Profile service for managing user profiles
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Create a teen profile
  Future<UserProfile> createTeenProfile({
    required String name,
    required int age,
    required HeightData height,
    required WeightData weight,
    String? icd10Code,
    String? advisorName,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/profile/teen'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'age': age,
        'height': height.toJson(),
        'weight': weight.toJson(),
        'icd10_code': icd10Code,
        'advisor_name': advisorName,
      }),
    );

    if (response.statusCode == 200) {
      final profile = UserProfile.fromJson(json.decode(response.body));
      await _authService.updateUserState(profileComplete: true);
      return profile;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['detail'] ?? 'Failed to create profile');
    }
  }

  /// Create a parent profile
  Future<UserProfile> createParentProfile({
    required String name,
    int? age,
    HeightData? height,
    WeightData? weight,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/profile/parent'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'age': age,
        'height': height?.toJson(),
        'weight': weight?.toJson(),
      }),
    );

    if (response.statusCode == 200) {
      final profile = UserProfile.fromJson(json.decode(response.body));
      await _authService.updateUserState(profileComplete: true);
      return profile;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['detail'] ?? 'Failed to create profile');
    }
  }

  /// Get user profile
  Future<UserProfile> getProfile() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/profile'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return UserProfile.fromJson(json.decode(response.body));
    } else {
      final error = json.decode(response.body);
      throw Exception(error['detail'] ?? 'Failed to get profile');
    }
  }

  /// Update user profile
  Future<UserProfile> updateProfile({
    String? name,
    int? age,
    HeightData? height,
    WeightData? weight,
    String? icd10Code,
    String? advisorName,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (age != null) body['age'] = age;
    if (height != null) body['height'] = height.toJson();
    if (weight != null) body['weight'] = weight.toJson();
    if (icd10Code != null) body['icd10_code'] = icd10Code;
    if (advisorName != null) body['advisor_name'] = advisorName;

    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/profile'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return UserProfile.fromJson(json.decode(response.body));
    } else {
      final error = json.decode(response.body);
      throw Exception(error['detail'] ?? 'Failed to update profile');
    }
  }

  /// Search ICD-10 codes
  Future<List<ICD10Code>> searchICD10Codes(String query, {int limit = 20}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/profile/icd10/search?query=$query&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((json) => ICD10Code.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to search ICD-10 codes');
    }
  }
}

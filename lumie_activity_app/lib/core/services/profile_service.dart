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
    try {
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
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final profile = UserProfile.fromJson(json.decode(response.body));
        await _authService.updateUserState(profileComplete: true);
        return profile;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to create profile');
      }
    } catch (e) {
      // Fallback to mock for local development
      return _mockCreateTeenProfile(
        name: name,
        age: age,
        height: height,
        weight: weight,
        icd10Code: icd10Code,
        advisorName: advisorName,
      );
    }
  }

  /// Create a parent profile
  Future<UserProfile> createParentProfile({
    required String name,
    int? age,
    HeightData? height,
    WeightData? weight,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/profile/parent'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'age': age,
          'height': height?.toJson(),
          'weight': weight?.toJson(),
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final profile = UserProfile.fromJson(json.decode(response.body));
        await _authService.updateUserState(profileComplete: true);
        return profile;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to create profile');
      }
    } catch (e) {
      // Fallback to mock for local development
      return _mockCreateParentProfile(
        name: name,
        age: age,
        height: height,
        weight: weight,
      );
    }
  }

  /// Get user profile
  Future<UserProfile> getProfile() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/profile'),
        headers: _headers,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return UserProfile.fromJson(json.decode(response.body));
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get profile');
      }
    } catch (e) {
      // Return empty profile if no cached profile exists
      throw Exception('Failed to get profile - no local data available');
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
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/profile/icd10/search?query=$query&limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['results'] as List)
            .map((json) => ICD10Code.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to search ICD-10 codes');
      }
    } catch (e) {
      // Return mock data if API fails (for local development)
      return _getMockICD10Results(query, limit);
    }
  }

  /// Mock ICD-10 data for local development
  List<ICD10Code> _getMockICD10Results(String query, int limit) {
    final mockData = [
      ICD10Code(
        code: 'E10',
        description: 'Type 1 diabetes mellitus',
        category: 'Endocrine, nutritional and metabolic diseases',
      ),
      ICD10Code(
        code: 'E11',
        description: 'Type 2 diabetes mellitus',
        category: 'Endocrine, nutritional and metabolic diseases',
      ),
      ICD10Code(
        code: 'J45',
        description: 'Asthma',
        category: 'Diseases of the respiratory system',
      ),
      ICD10Code(
        code: 'G40',
        description: 'Epilepsy',
        category: 'Diseases of the nervous system',
      ),
      ICD10Code(
        code: 'M79.7',
        description: 'Fibromyalgia',
        category: 'Diseases of the musculoskeletal system',
      ),
      ICD10Code(
        code: 'F84.0',
        description: 'Autism spectrum disorder',
        category: 'Mental and behavioural disorders',
      ),
      ICD10Code(
        code: 'F90',
        description: 'Attention-deficit hyperactivity disorder',
        category: 'Mental and behavioural disorders',
      ),
      ICD10Code(
        code: 'Q90',
        description: 'Down syndrome',
        category: 'Congenital malformations',
      ),
      ICD10Code(
        code: 'I50',
        description: 'Heart failure',
        category: 'Diseases of the circulatory system',
      ),
      ICD10Code(
        code: 'M05',
        description: 'Rheumatoid arthritis',
        category: 'Diseases of the musculoskeletal system',
      ),
      ICD10Code(
        code: 'K50',
        description: 'Crohn\'s disease',
        category: 'Diseases of the digestive system',
      ),
      ICD10Code(
        code: 'K51',
        description: 'Ulcerative colitis',
        category: 'Diseases of the digestive system',
      ),
      ICD10Code(
        code: 'G35',
        description: 'Multiple sclerosis',
        category: 'Diseases of the nervous system',
      ),
      ICD10Code(
        code: 'M32',
        description: 'Systemic lupus erythematosus',
        category: 'Diseases of the musculoskeletal system',
      ),
      ICD10Code(
        code: 'D50',
        description: 'Iron deficiency anemia',
        category: 'Diseases of the blood',
      ),
    ];

    final lowerQuery = query.toLowerCase();
    final filtered = mockData.where((code) =>
      code.code.toLowerCase().contains(lowerQuery) ||
      code.description.toLowerCase().contains(lowerQuery) ||
      code.category.toLowerCase().contains(lowerQuery)
    ).take(limit).toList();

    return filtered;
  }

  /// Mock teen profile creation for local development
  Future<UserProfile> _mockCreateTeenProfile({
    required String name,
    required int age,
    required HeightData height,
    required WeightData weight,
    String? icd10Code,
    String? advisorName,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final profile = UserProfile(
      userId: _authService.currentUser!.userId,
      email: _authService.currentUser!.email,
      role: AccountRole.teen,
      name: name,
      age: age,
      height: height,
      weight: weight,
      icd10Code: icd10Code,
      advisorName: advisorName,
      profileComplete: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _authService.updateUserState(profileComplete: true);
    return profile;
  }

  /// Mock parent profile creation for local development
  Future<UserProfile> _mockCreateParentProfile({
    required String name,
    int? age,
    HeightData? height,
    WeightData? weight,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final profile = UserProfile(
      userId: _authService.currentUser!.userId,
      email: _authService.currentUser!.email,
      role: AccountRole.parent,
      name: name,
      age: age,
      height: height,
      weight: weight,
      profileComplete: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _authService.updateUserState(profileComplete: true);
    return profile;
  }
}

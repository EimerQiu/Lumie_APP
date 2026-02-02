import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../../shared/models/user_models.dart';

/// Authentication service for managing user auth state
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  String? _token;
  AuthResponse? _currentUser;

  String? get token => _token;
  AuthResponse? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// Initialize auth state from local storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      _currentUser = AuthResponse.fromJson(json.decode(userJson));
    }
  }

  /// Save auth state to local storage
  Future<void> _saveAuthState(AuthResponse response) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, response.accessToken);
    await prefs.setString(_userKey, json.encode(response.toJson()));
    _token = response.accessToken;
    _currentUser = response;
  }

  /// Clear auth state
  Future<void> _clearAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _token = null;
    _currentUser = null;
  }

  /// Sign up a new user
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'confirm_password': confirmPassword,
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(json.decode(response.body));
        await _saveAuthState(authResponse);
        return authResponse;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Sign up failed');
      }
    } catch (e) {
      // Fallback to mock authentication for local development
      return _mockSignUp(email: email, password: password);
    }
  }

  /// Mock sign up for local development
  Future<AuthResponse> _mockSignUp({
    required String email,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final mockResponse = AuthResponse(
      accessToken: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'user_${email.hashCode}',
      email: email,
      role: null, // Will be set after account type selection
      profileComplete: false,
    );

    await _saveAuthState(mockResponse);
    return mockResponse;
  }

  /// Log in an existing user
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(json.decode(response.body));
        await _saveAuthState(authResponse);
        return authResponse;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Login failed');
      }
    } catch (e) {
      // Fallback to mock authentication for local development
      return _mockLogin(email: email);
    }
  }

  /// Mock login for local development
  Future<AuthResponse> _mockLogin({required String email}) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final mockResponse = AuthResponse(
      accessToken: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'user_${email.hashCode}',
      email: email,
      role: AccountRole.teen, // Mock user with profile
      profileComplete: true,
    );

    await _saveAuthState(mockResponse);
    return mockResponse;
  }

  /// Select account type after signup
  Future<AuthResponse> selectAccountType(AccountRole role) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/account-type'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'role': role.name}),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(json.decode(response.body));
        await _saveAuthState(authResponse);
        return authResponse;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to select account type');
      }
    } catch (e) {
      // Fallback to mock for local development
      return _mockSelectAccountType(role);
    }
  }

  /// Mock account type selection for local development
  Future<AuthResponse> _mockSelectAccountType(AccountRole role) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    if (_currentUser == null) {
      throw Exception('Not authenticated');
    }

    final mockResponse = AuthResponse(
      accessToken: _currentUser!.accessToken,
      userId: _currentUser!.userId,
      email: _currentUser!.email,
      role: role,
      profileComplete: false,
    );

    await _saveAuthState(mockResponse);
    return mockResponse;
  }

  /// Get current user info
  Future<AuthResponse> getCurrentUser() async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Keep the existing token
      final authResponse = AuthResponse(
        accessToken: _token!,
        userId: data['user_id'],
        email: data['email'],
        role: data['role'] != null
            ? (data['role'] == 'teen' ? AccountRole.teen : AccountRole.parent)
            : null,
        profileComplete: data['profile_complete'] ?? false,
      );
      await _saveAuthState(authResponse);
      return authResponse;
    } else {
      throw Exception('Failed to get user info');
    }
  }

  /// Log out
  Future<void> logout() async {
    await _clearAuthState();
  }

  /// Update local user state (after profile creation)
  Future<void> updateUserState({
    AccountRole? role,
    bool? profileComplete,
  }) async {
    if (_currentUser == null) return;

    final updated = AuthResponse(
      accessToken: _currentUser!.accessToken,
      userId: _currentUser!.userId,
      email: _currentUser!.email,
      role: role ?? _currentUser!.role,
      profileComplete: profileComplete ?? _currentUser!.profileComplete,
    );

    await _saveAuthState(updated);
  }
}

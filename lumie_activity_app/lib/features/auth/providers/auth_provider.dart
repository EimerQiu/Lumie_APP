import 'package:flutter/foundation.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../shared/models/user_models.dart';

enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
  needsAccountType,
  needsProfile,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();

  AuthState _state = AuthState.initial;
  String? _errorMessage;
  AuthResponse? _user;
  UserProfile? _profile;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  AuthResponse? get user => _user;
  UserProfile? get profile => _profile;
  bool get isAuthenticated => _state == AuthState.authenticated;

  /// Initialize auth state from local storage
  Future<void> init() async {
    _state = AuthState.loading;
    notifyListeners();

    try {
      await _authService.init();

      if (_authService.isAuthenticated) {
        _user = _authService.currentUser;

        // Determine next state based on user status
        if (_user!.role == null) {
          _state = AuthState.needsAccountType;
        } else if (!_user!.profileComplete) {
          _state = AuthState.needsProfile;
        } else {
          // Try to load profile
          try {
            _profile = await _profileService.getProfile();
            _state = AuthState.authenticated;
          } catch (_) {
            _state = AuthState.needsProfile;
          }
        }
      } else {
        _state = AuthState.unauthenticated;
      }
    } catch (e) {
      _state = AuthState.unauthenticated;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// Sign up a new user
  Future<bool> signUp({
    required String email,
    required String password,
    required String confirmPassword,
    required AccountRole role,
  }) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.signUp(
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        role: role,
      );
      // After signup, user needs to verify email before they can complete profile
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Log in an existing user
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.login(
        email: email,
        password: password,
      );

      // Determine next state
      if (_user!.role == null) {
        _state = AuthState.needsAccountType;
      } else if (!_user!.profileComplete) {
        _state = AuthState.needsProfile;
      } else {
        try {
          _profile = await _profileService.getProfile();
          _state = AuthState.authenticated;
        } catch (_) {
          _state = AuthState.needsProfile;
        }
      }

      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Select account type
  Future<bool> selectAccountType(AccountRole role) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.selectAccountType(role);
      _state = AuthState.needsProfile;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Create teen profile
  Future<bool> createTeenProfile({
    required String name,
    required int age,
    required HeightData height,
    required WeightData weight,
    String? icd10Code,
    String? advisorName,
  }) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _profileService.createTeenProfile(
        name: name,
        age: age,
        height: height,
        weight: weight,
        icd10Code: icd10Code,
        advisorName: advisorName,
      );
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.needsProfile;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Create parent profile
  Future<bool> createParentProfile({
    required String name,
    int? age,
    HeightData? height,
    WeightData? weight,
  }) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _profileService.createParentProfile(
        name: name,
        age: age,
        height: height,
        weight: weight,
      );
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.needsProfile;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Update profile
  Future<bool> updateProfile({
    String? name,
    int? age,
    HeightData? height,
    WeightData? weight,
    String? icd10Code,
    String? advisorName,
  }) async {
    try {
      _profile = await _profileService.updateProfile(
        name: name,
        age: age,
        height: height,
        weight: weight,
        icd10Code: icd10Code,
        advisorName: advisorName,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Log out
  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _profile = null;
    _state = AuthState.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }
}

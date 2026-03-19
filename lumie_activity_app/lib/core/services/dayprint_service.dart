import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/dayprint_models.dart';

class DayprintService {
  static final DayprintService _instance = DayprintService._internal();
  factory DayprintService() => _instance;
  DayprintService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Fetch today's Dayprint. Returns null if no events logged yet.
  Future<Dayprint?> getTodayDayprint() async {
    final response = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.dayprint}'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final body = response.body.trim();
      if (body == 'null' || body.isEmpty) return null;
      final data = json.decode(body);
      if (data == null) return null;
      return Dayprint.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to load Dayprint: ${response.statusCode}');
  }
}

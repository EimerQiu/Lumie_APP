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

  /// Fetch paginated dayprint history (newest date first).
  Future<DayprintHistoryPage> getDayprintHistory({
    int limit = 14,
    String? beforeDate,
  }) async {
    var url =
        '${ApiConstants.baseUrl}${ApiConstants.dayprint}/history?limit=$limit';
    if (beforeDate != null && beforeDate.isNotEmpty) {
      url += '&before_date=${Uri.encodeComponent(beforeDate)}';
    }

    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return DayprintHistoryPage.fromJson(data);
    }
    throw Exception('Failed to load Dayprint history: ${response.statusCode}');
  }
}

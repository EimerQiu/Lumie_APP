import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../services/auth_service.dart';
import '../../shared/models/heart_rate_models.dart';

// ignore_for_file: avoid_print

/// Saves completed HR measurement sessions to the backend.
///
/// POST /api/v1/hr/sessions — creates one hr_sessions summary record and
/// N hr_timeseries bucket documents (5-minute windows, server-side).
class HrSessionService {
  static final HrSessionService _instance = HrSessionService._internal();
  factory HrSessionService() => _instance;
  HrSessionService._internal();
  Future<String?>? _lastSaveSessionFuture;

  Future<String?>? get lastSaveSessionFuture => _lastSaveSessionFuture;

  /// Upload a finished session. Returns the server-assigned session_id, or
  /// null if the user is not authenticated.
  ///
  /// Throws on network / server errors so callers can `.catchError()`.
  Future<String?> saveSession({
    required DateTime startedAt,
    required DateTime endedAt,
    required int avgBpm,
    required int minBpm,
    required int maxBpm,
    required List<HrSessionPoint> readings,
  }) async {
    final token = AuthService().token;
    if (token == null) return null;

    final payload = {
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'avg_bpm': avgBpm,
      'min_bpm': minBpm,
      'max_bpm': maxBpm,
      'readings': readings
          .map(
            (r) => {
              'timestamp': r.time.toUtc().toIso8601String(),
              // Send smoothed BPM — this is what the user saw on screen
              // and what avg/min/max are computed from.
              'bpm': r.smoothedBpm.round(),
            },
          )
          .toList(),
    };

    final future = http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/hr/sessions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(payload),
        )
        .timeout(ApiConstants.receiveTimeout)
        .then((response) {
          if (response.statusCode == 201) {
            final data = json.decode(response.body) as Map<String, dynamic>;
            final sessionId = data['session_id'] as String?;
            debugPrint(
              '[HR] Session saved — id=$sessionId '
              'buckets=${data['inserted_buckets']} '
              'readings=${data['reading_count']}',
            );
            return sessionId;
          }

          throw Exception(
            'Failed to save HR session: HTTP ${response.statusCode} — ${response.body}',
          );
        });
    _lastSaveSessionFuture = future;
    return future;
  }

  Future<void> uploadSessionGraph({
    required String sessionId,
    required File graphFile,
  }) async {
    final token = AuthService().token;
    if (token == null) return;

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConstants.baseUrl}/hr/sessions/$sessionId/graph'),
    );
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      await http.MultipartFile.fromPath('graph_file', graphFile.path),
    );

    final streamed = await req.send().timeout(ApiConstants.receiveTimeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(
        'Failed to upload HR graph: HTTP ${streamed.statusCode} — $body',
      );
    }
  }

  Future<List<HrSessionSummary>> listSessions({int limit = 20}) async {
    final token = AuthService().token;
    if (token == null) return [];

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}/hr/sessions',
    ).replace(queryParameters: {'limit': '$limit'});

    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list
          .map((e) => HrSessionSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load HR sessions: HTTP ${response.statusCode}');
  }

  Future<HrSessionTimeseries> getSessionTimeseries(String sessionId) async {
    final token = AuthService().token;
    if (token == null) {
      return HrSessionTimeseries(sessionId: sessionId, readings: []);
    }

    final response = await http
        .get(
          Uri.parse(
            '${ApiConstants.baseUrl}/hr/sessions/$sessionId/timeseries',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return HrSessionTimeseries.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
      'Failed to load HR timeseries: HTTP ${response.statusCode}',
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/analysis_models.dart';

/// Service for polling analysis job status and results.
class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();
  factory AnalysisService() => _instance;
  AnalysisService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Poll a job until it completes or times out.
  ///
  /// Polls every 2 seconds, up to [maxWaitSeconds] (default 60).
  /// Returns the completed [AnalysisJob], or a failed stub on timeout.
  Future<AnalysisJob> pollJobResult(
    String jobId, {
    int maxWaitSeconds = 60,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));

    while (DateTime.now().isBefore(deadline)) {
      try {
        final job = await getJob(jobId);
        if (job.isComplete) return job;
      } catch (_) {
        // Continue polling on transient errors
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    // Timeout — return a failed job
    return AnalysisJob(
      jobId: jobId,
      status: 'failed',
      prompt: '',
      error: 'Analysis timed out. Please try again.',
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  /// Fetch a single job by ID.
  Future<AnalysisJob> getJob(String jobId) async {
    final response = await http
        .get(
          Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.analysisJobs}/$jobId'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return AnalysisJob.fromJson(data);
    }
    throw Exception('Failed to fetch job status: ${response.statusCode}');
  }

  /// Cancel a running job.
  Future<void> cancelJob(String jobId) async {
    await http
        .post(
          Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.analysisJobs}/$jobId/cancel'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);
  }
}

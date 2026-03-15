/// Models for the AI data analysis system.
library;

class AnalysisResult {
  final String summary;
  final Map<String, dynamic>? data;
  final String? chartBase64;

  const AnalysisResult({
    required this.summary,
    this.data,
    this.chartBase64,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      summary: json['summary'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>?,
      chartBase64: json['chart_base64'] as String?,
    );
  }
}

class AnalysisJob {
  final String jobId;
  final String status;
  final String prompt;
  final AnalysisResult? result;
  final String? error;
  final String createdAt;
  final String? startedAt;
  final String? finishedAt;

  const AnalysisJob({
    required this.jobId,
    required this.status,
    required this.prompt,
    this.result,
    this.error,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  factory AnalysisJob.fromJson(Map<String, dynamic> json) {
    return AnalysisJob(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      prompt: json['prompt'] as String? ?? '',
      result: json['result'] != null
          ? AnalysisResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      startedAt: json['started_at'] as String?,
      finishedAt: json['finished_at'] as String?,
    );
  }

  bool get isComplete =>
      status == 'success' || status == 'failed' || status == 'cancelled';

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
}

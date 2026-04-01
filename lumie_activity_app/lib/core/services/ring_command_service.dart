import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import 'ring_ble_service.dart';

/// Polls the backend for pending ring live commands, executes the corresponding
/// BLE operation, and posts the result back.
///
/// Called by RingProvider on connect and on app foreground resume.
/// Fire-and-forget: errors are logged, never thrown.
class RingCommandService {
  static final RingCommandService _instance = RingCommandService._internal();
  factory RingCommandService() => _instance;
  RingCommandService._internal();

  bool _running = false;

  /// Check for a pending command and execute it if present.
  /// [bleService] must be connected when this is called.
  Future<void> checkAndExecute(RingBleService bleService) async {
    if (_running) {
      print('[RCMD] checkAndExecute skipped: already running');
      return;
    }
    if (!bleService.isConnected) {
      print('[RCMD] checkAndExecute skipped: BLE not connected');
      return;
    }

    final token = AuthService().token;
    if (token == null) {
      print('[RCMD] checkAndExecute skipped: auth token missing');
      return;
    }

    _running = true;
    try {
      // Poll for a pending command
      final response = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/ring/command/pending'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      print('[RCMD] pending response: status=${response.statusCode}');
      if (response.statusCode != 200) return;

      final body = response.body.trim();
      if (body == 'null' || body.isEmpty) {
        print('[RCMD] no pending command');
        return;
      }

      final doc = json.decode(body) as Map<String, dynamic>;
      final requestId = doc['request_id'] as String;
      final commandType = doc['command_type'] as String;
      final durationSeconds = (doc['duration_seconds'] as num?)?.toInt() ?? 10;

      print('[RCMD] Executing $commandType (id=$requestId)');
      await _execute(
        bleService: bleService,
        requestId: requestId,
        commandType: commandType,
        durationSeconds: durationSeconds,
        token: token,
      );
    } catch (e) {
      print('[RCMD] checkAndExecute error: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _execute({
    required RingBleService bleService,
    required String requestId,
    required String commandType,
    required int durationSeconds,
    required String token,
  }) async {
    Map<String, dynamic> resultData = {};
    bool success = false;
    String? error;

    try {
      switch (commandType) {
        case 'hr_measure':
          final result = await bleService.measureHeartRate(
            durationSeconds: durationSeconds,
          );
          if (result != null) {
            success = true;
            resultData = {
              'avg_bpm': result.avgBpm,
              'min_bpm': result.minBpm,
              'max_bpm': result.maxBpm,
              'duration_seconds': result.durationSeconds,
              'readings': result.readings,
            };
          } else {
            error = 'No HR readings received from ring';
          }
          break;

        case 'temperature':
          final result = await bleService.fetchRingTemperatureLive();
          if (result != null) {
            success = true;
            resultData = {
              'highest_temp_c': result.highestTempC,
              'ntc1_c': result.ntc1C,
              'ntc2_c': result.ntc2C,
              'ntc3_c': result.ntc3C,
            };
          } else {
            error = 'No temperature reading received from ring';
          }
          break;

        default:
          error = 'Unknown command type: $commandType';
      }
    } catch (e) {
      error = e.toString();
      print('[RCMD] BLE execution error: $e');
    }

    // Post result back to backend
    try {
      await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/ring/command/$requestId/result'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'success': success,
              'data': resultData,
              'error': error,
            }),
          )
          .timeout(const Duration(seconds: 10));
      print('[RCMD] Result posted for $requestId: success=$success');
    } catch (e) {
      print('[RCMD] Failed to post result: $e');
    }
  }
}

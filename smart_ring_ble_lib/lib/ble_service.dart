// ble_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// =============================
// Time models (top-level)
// =============================
class RingTimeResult {
  final DateTime ringTime;
  final int weekday; // 1=Mon..7=Sun (unreliable per protocol)
  final int maxMtu;

  RingTimeResult({
    required this.ringTime,
    required this.weekday,
    required this.maxMtu,
  });

  @override
  String toString() {
    final iso = ringTime.toIso8601String();
    return 'RingTime: $iso (weekday=$weekday, MTU=$maxMtu)';
  }
}

class SyncTimeResult {
  final DateTime phoneSentAt;
  final DateTime? ringReadback;
  final int? maxMtu;

  SyncTimeResult({
    required this.phoneSentAt,
    this.ringReadback,
    this.maxMtu,
  });

  /// Difference in seconds between phone time sent and ring readback.
  int? get driftSeconds {
    if (ringReadback == null) return null;
    return ringReadback!.difference(phoneSentAt).inSeconds;
  }

  @override
  String toString() {
    final sent = phoneSentAt.toIso8601String();
    final rb = ringReadback?.toIso8601String() ?? 'N/A';
    final drift = driftSeconds;
    return 'SyncTime: sent=$sent readback=$rb drift=${drift != null ? "${drift}s" : "N/A"}';
  }
}

// =============================
// HRV model (top-level)
// =============================
class HrvRecord {
  final int index; // ID1
  final int page; // ID2
  final DateTime timestamp; // direct values YY MM DD HH mm SS -> 2000+YY
  final int hrvMs; // D1
  final int heartRateBpm; // D3
  final int fatigue; // D4
  final int systolic; // P1
  final int diastolic; // P2

  HrvRecord({
    required this.index,
    required this.page,
    required this.timestamp,
    required this.hrvMs,
    required this.heartRateBpm,
    required this.fatigue,
    required this.systolic,
    required this.diastolic,
  });

  @override
  String toString() =>
      'HRV[$index/$page] ${timestamp.toIso8601String()} HRV=${hrvMs}ms HR=${heartRateBpm} BPM Fatigue=$fatigue BP=$systolic/$diastolic';
}

// =============================
// Sleep model (top-level)
// =============================
class SleepRecord {
  final int index; // ID1
  final int page; // ID2
  final DateTime startTimestamp; // start time
  final int durationMinutes; // validLength
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;
  final List<int> stages; // per-minute: 1=Deep,2=Light,3=REM,else Awake

  SleepRecord({
    required this.index,
    required this.page,
    required this.startTimestamp,
    required this.durationMinutes,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.stages,
  });

  @override
  String toString() {
    final iso = startTimestamp.toIso8601String();
    return 'Sleep[$index/$page] $iso Duration=${durationMinutes}min Deep=$deepMinutes Light=$lightMinutes REM=$remMinutes Awake=$awakeMinutes';
  }
}

// Merge multiple per-record sleep segments into nightly sessions.
// A "night" is defined by a bucket that starts at 18:00 local time and ends at next day 12:00 (noon).
// Segments are merged if they fall into the same night bucket and the gap between consecutive segments is <= 60 minutes.
List<SleepRecord> _mergeSleepByNight(List<SleepRecord> records) {
  if (records.isEmpty) return records;
  // Sort by start time to ensure deterministic order
  final sorted = List<SleepRecord>.from(records)
    ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));

  DateTime nightBucket(DateTime ts) {
    // If ts.hour >= 18, bucket is that day's 18:00; else bucket is previous day 18:00
    final dateOnly = DateTime(ts.year, ts.month, ts.day);
    if (ts.hour >= 18) return dateOnly.add(const Duration(hours: 18));
    return dateOnly
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 18));
  }

  final merged = <SleepRecord>[];
  SleepRecord? cur;
  DateTime? curEnd;
  DateTime? curBucket;

  for (final r in sorted) {
    final rStart = r.startTimestamp;
    final rEnd = rStart.add(Duration(minutes: r.durationMinutes));
    final rBucket = nightBucket(rStart);

    if (cur == null) {
      cur = r;
      curEnd = rEnd;
      curBucket = rBucket;
      continue;
    }

    final sameBucket = curBucket == rBucket;
    final gapMin = rStart.difference(curEnd!).inMinutes;
    final smallGap = gapMin <= 60; // allow up to 1 hour gap inside same night

    if (sameBucket && smallGap) {
      // Merge r into cur
      final mergedStages = <int>[]
        ..addAll(cur!.stages)
        ..addAll(r.stages);
      final mergedRec = SleepRecord(
        index: cur!.index,
        page: cur!.page,
        startTimestamp: cur!.startTimestamp,
        durationMinutes: cur!.durationMinutes + r.durationMinutes,
        deepMinutes: cur!.deepMinutes + r.deepMinutes,
        lightMinutes: cur!.lightMinutes + r.lightMinutes,
        remMinutes: cur!.remMinutes + r.remMinutes,
        awakeMinutes: cur!.awakeMinutes + r.awakeMinutes,
        stages: mergedStages,
      );
      cur = mergedRec;
      curEnd = rEnd;
      // bucket unchanged
    } else {
      // Flush current and start new
      merged.add(cur!);
      cur = r;
      curEnd = rEnd;
      curBucket = rBucket;
    }
  }
  if (cur != null) merged.add(cur);
  return merged;
}

class BleService {
  // Smart Ring specific constants
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String writeCharacteristicUuid =
      '0000fff6-0000-1000-8000-00805f9b34fb';
  static const String notifyCharacteristicUuid =
      '0000fff7-0000-1000-8000-00805f9b34fb';

  // Configurable targets (from UI)
  String? _targetDeviceName; // optional exact match
  String? _targetMacAddress; // optional exact match (uppercase form preferred)
  String? get targetDeviceName => _targetDeviceName;
  String? get targetMacAddress => _targetMacAddress;
  List<String> _fuzzyNameHints =
      []; // optional: contains() hints when no exact target
  List<String> get fuzzyNameHints => List.unmodifiable(_fuzzyNameHints);

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  bool _isConnecting = false;

  final StreamController<String> _connectionStatusController =
      StreamController<String>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<String> get messageStream => _messageController.stream;

  Timer? _reconnectTimer;
  bool _isDisposed = false;

  BleService({String? deviceName, String? macAddress}) {
    // Targets are supplied by UI; can be null until user sets them
    _targetDeviceName = deviceName;
    _targetMacAddress = macAddress?.toUpperCase();
    _initializeBluetooth();
  }

  /// Bulk download: Send all 8 data commands sequentially (2s delay between each),
  /// collect mixed responses, classify by command type, and return structured package.
  /// [onProgress] callback receives progress updates during the download process.
  Future<Map<String, dynamic>> bulkDownloadAllData(
      {Function(String)? onProgress}) async {
    print('🚀 Starting bulk download of all data...');
    onProgress?.call('🚀 Starting bulk download of all data...');

    // Data structure to collect all messages by command type
    final Map<int, List<List<int>>> collectedData = {
      0x51: [], // Total step count
      0x52: [], // Detailed step count
      0x53: [], // Sleep history
      0x54: [], // Heart rate details
      0x55: [], // Heart rate history
      0x56: [], // HRV data
      0x62: [], // Temperature
      0x66: [], // Blood oxygen
    };

    late final StreamSubscription<String> sub;
    Timer? inactivityTimer;
    final completer = Completer<Map<String, dynamic>>();

    void resetInactivityTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(const Duration(seconds: 5), () async {
        final msg = '⏱️ No messages for 5 seconds, finishing download...';
        print(msg);
        onProgress?.call(msg);
        await sub.cancel();
        if (!completer.isCompleted) {
          onProgress?.call('📊 Processing collected data...');
          completer.complete(_processBulkData(collectedData));
        }
      });
    }

    // Listen to all incoming messages
    sub = messageStream.listen(
        (msg) {
          final bytes = _extractHexBytes(msg);
          if (bytes.isEmpty) return;

          // Classify by first byte (command type)
          final cmd = bytes[0];
          if (collectedData.containsKey(cmd)) {
            collectedData[cmd]!.add(bytes);
            final progressMsg =
                '📥 Received ${cmd.toRadixString(16).toUpperCase()} message (${collectedData[cmd]!.length} total)';
            print(progressMsg);
            onProgress?.call(progressMsg);
          }

          // Reset inactivity timer on each message
          resetInactivityTimer();
        },
        onError: (_) {},
        onDone: () {
          if (!completer.isCompleted) {
            onProgress?.call('📊 Processing collected data...');
            completer.complete(_processBulkData(collectedData));
          }
        });

    try {
      // Start inactivity timer
      resetInactivityTimer();

      // Send commands sequentially with 2-second delays
      String msg = '📤 Sending 0x51 (Total Steps)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetTotalStepCountCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x52 (Detailed Steps)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetDetailedStepCountCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x53 (Sleep Data)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetSleepDataCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x54 (Heart Rate Details)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetDetailedHeartRateCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x55 (Heart Rate History)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetHeartRateHistoryCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x56 (HRV Data)...';
      print(msg);
      onProgress?.call(msg);
      await sendHrvCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x62 (Temperature)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetTemperatureDataCommand();
      await Future.delayed(const Duration(seconds: 2));

      msg = '📤 Sending 0x66 (Blood Oxygen)...';
      print(msg);
      onProgress?.call(msg);
      await sendGetBloodOxygenDataCommand();

      msg = '✅ All commands sent, waiting for responses...';
      print(msg);
      onProgress?.call(msg);
    } catch (e) {
      print('❌ Error sending commands: $e');
      inactivityTimer?.cancel();
      await sub.cancel();
      rethrow;
    }

    final result = await completer.future;
    inactivityTimer?.cancel();
    await sub.cancel();

    print('🎉 Bulk download completed!');
    return result;
  }

  /// Process collected bulk data and generate structured output
  Map<String, dynamic> _processBulkData(
      Map<int, List<List<int>>> collectedData) {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'commands': <String, dynamic>{},
    };

    int totalRecords = 0;

    // Process 0x51 - Total Steps (27-byte records with BCD timestamps)
    if (collectedData[0x51]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x51]!) {
        if (bytes.length >= 27 && bytes[0] == 0x51) {
          final year = 2000 + _bcdToDecimal(bytes[2]);
          final month = _bcdToDecimal(bytes[3]);
          final day = _bcdToDecimal(bytes[4]);
          final steps =
              (bytes[8] << 24) | (bytes[7] << 16) | (bytes[6] << 8) | bytes[5];
          final exerciseTime = (bytes[12] << 24) |
              (bytes[11] << 16) |
              (bytes[10] << 8) |
              bytes[9];
          final distance = (bytes[16] << 24) |
              (bytes[15] << 16) |
              (bytes[14] << 8) |
              bytes[13];
          final calories = (bytes[20] << 24) |
              (bytes[19] << 16) |
              (bytes[18] << 8) |
              bytes[17];
          records.add({
            'date':
                '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
            'steps': steps,
            'exercise_time': exerciseTime,
            'calories': calories / 100.0,
            'distance': distance / 100.0,
          });
        }
      }
      result['commands']
          ['total_steps'] = {'count': records.length, 'records': records};
      totalRecords += records.length;
    }

    // Process 0x52 - Detailed Steps (25-byte records with BCD timestamps)
    if (collectedData[0x52]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x52]!) {
        int i = 0;
        while (i + 25 <= bytes.length) {
          if (bytes[i] == 0x52) {
            final year = 2000 + _bcdToDecimal(bytes[i + 3]);
            final month = _bcdToDecimal(bytes[i + 4]);
            final day = _bcdToDecimal(bytes[i + 5]);
            final hour = _bcdToDecimal(bytes[i + 6]);
            final minute = _bcdToDecimal(bytes[i + 7]);
            final second = _bcdToDecimal(bytes[i + 8]);
            final totalSteps = (bytes[i + 10] << 8) | bytes[i + 9];
            final calories = (bytes[i + 12] << 8) | bytes[i + 11];
            final distance = (bytes[i + 14] << 8) | bytes[i + 13];
            records.add({
              'timestamp':
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
              'steps': totalSteps,
              'calories': calories / 100.0,
              'distance': distance / 100.0,
            });
            i += 25;
          } else {
            i++;
          }
        }
      }
      result['commands']
          ['detailed_steps'] = {'count': records.length, 'records': records};
      totalRecords += records.length;
    }

    // Process 0x53 - Sleep Data
    if (collectedData[0x53]!.isNotEmpty) {
      final allBytes = <int>[];
      for (final bytes in collectedData[0x53]!) {
        allBytes.addAll(bytes);
      }
      final sleepRecords =
          _parseSleepRecordsFromBytes(allBytes, mergeByNight: false);
      result['commands']['sleep'] = {
        'count': sleepRecords.length,
        'records': sleepRecords
            .map((r) => {
                  'timestamp': r.startTimestamp.toIso8601String(),
                  'duration_minutes': r.durationMinutes,
                  'deep': r.deepMinutes,
                  'light': r.lightMinutes,
                  'rem': r.remMinutes,
                  'awake': r.awakeMinutes,
                })
            .toList(),
      };
      totalRecords += sleepRecords.length;
    }

    // Process 0x54 - Heart Rate Details (21-byte records with BCD timestamps)
    if (collectedData[0x54]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x54]!) {
        int i = 0;
        while (i + 21 <= bytes.length) {
          if (bytes[i] == 0x54) {
            final year = 2000 + _bcdToDecimal(bytes[i + 3]);
            final month = _bcdToDecimal(bytes[i + 4]);
            final day = _bcdToDecimal(bytes[i + 5]);
            final hour = _bcdToDecimal(bytes[i + 6]);
            final minute = _bcdToDecimal(bytes[i + 7]);
            final second = _bcdToDecimal(bytes[i + 8]);
            final heartRates = <int>[];
            for (int j = 9; j < 24 && i + j < bytes.length; j++) {
              heartRates.add(bytes[i + j]);
            }
            records.add({
              'timestamp':
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
              'heart_rates': heartRates,
            });
            i += 21;
          } else {
            i++;
          }
        }
      }
      result['commands']['heart_rate_details'] = {
        'count': records.length,
        'records': records
      };
      totalRecords += records.length;
    }

    // Process 0x55 - Heart Rate History (10-byte records with BCD timestamps)
    if (collectedData[0x55]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x55]!) {
        int i = 0;
        while (i + 10 <= bytes.length) {
          if (bytes[i] == 0x55) {
            final year = 2000 + _bcdToDecimal(bytes[i + 3]);
            final month = _bcdToDecimal(bytes[i + 4]);
            final day = _bcdToDecimal(bytes[i + 5]);
            final hour = _bcdToDecimal(bytes[i + 6]);
            final minute = _bcdToDecimal(bytes[i + 7]);
            final second = _bcdToDecimal(bytes[i + 8]);
            final heartRate = bytes[i + 9];
            records.add({
              'timestamp':
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
              'heart_rate': heartRate,
            });
            i += 10;
          } else {
            i++;
          }
        }
      }
      result['commands']['heart_rate_history'] = {
        'count': records.length,
        'records': records
      };
      totalRecords += records.length;
    }

    // Process 0x56 - HRV Data (15-byte records)
    if (collectedData[0x56]!.isNotEmpty) {
      final allBytes = <int>[];
      for (final bytes in collectedData[0x56]!) {
        allBytes.addAll(bytes);
      }
      final hrvRecords = _parseHrvRecordsFromBytes(allBytes);
      result['commands']['hrv'] = {
        'count': hrvRecords.length,
        'records': hrvRecords
            .map((r) => {
                  'timestamp': r.timestamp.toIso8601String(),
                  'hrv_ms': r.hrvMs,
                  'heart_rate': r.heartRateBpm,
                  'fatigue': r.fatigue,
                  'bp': '${r.systolic}/${r.diastolic}',
                })
            .toList(),
      };
      totalRecords += hrvRecords.length;
    }

    // Process 0x62 - Temperature (15-byte records with BCD timestamps)
    if (collectedData[0x62]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x62]!) {
        int i = 0;
        while (i + 15 <= bytes.length) {
          if (bytes[i] == 0x62) {
            final year = 2000 + _bcdToDecimal(bytes[i + 3]);
            final month = _bcdToDecimal(bytes[i + 4]);
            final day = _bcdToDecimal(bytes[i + 5]);
            final hour = _bcdToDecimal(bytes[i + 6]);
            final minute = _bcdToDecimal(bytes[i + 7]);
            final second = _bcdToDecimal(bytes[i + 8]);
            final temperatures = <double>[];
            for (int j = 9; j < bytes.length - 1 && j < i + 15; j += 2) {
              if (i + j + 1 < bytes.length) {
                final tempRaw = (bytes[i + j + 1] << 8) | bytes[i + j];
                temperatures.add(tempRaw / 10.0);
              }
            }
            records.add({
              'timestamp':
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
              'temperatures': temperatures,
            });
            i += 15;
          } else {
            i++;
          }
        }
      }
      result['commands']
          ['temperature'] = {'count': records.length, 'records': records};
      totalRecords += records.length;
    }

    // Process 0x66 - Blood Oxygen (10-byte records with BCD timestamps)
    if (collectedData[0x66]!.isNotEmpty) {
      final records = <Map<String, dynamic>>[];
      for (final bytes in collectedData[0x66]!) {
        int i = 0;
        while (i + 10 <= bytes.length) {
          if (bytes[i] == 0x66) {
            final year = 2000 + _bcdToDecimal(bytes[i + 3]);
            final month = _bcdToDecimal(bytes[i + 4]);
            final day = _bcdToDecimal(bytes[i + 5]);
            final hour = _bcdToDecimal(bytes[i + 6]);
            final minute = _bcdToDecimal(bytes[i + 7]);
            final second = _bcdToDecimal(bytes[i + 8]);
            final bloodOxygen = bytes[i + 9];
            records.add({
              'timestamp':
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
              'spo2': bloodOxygen,
            });
            i += 10;
          } else {
            i++;
          }
        }
      }
      result['commands']
          ['blood_oxygen'] = {'count': records.length, 'records': records};
      totalRecords += records.length;
    }

    result['total_records'] = totalRecords;
    result['summary'] = _generateBulkSummary(result);

    return result;
  }

  /// Generate a human-readable summary of bulk download results
  String _generateBulkSummary(Map<String, dynamic> data) {
    final buf = StringBuffer();
    buf.writeln('📊 BULK DOWNLOAD SUMMARY');
    buf.writeln('=' * 50);
    buf.writeln('⏰ Downloaded at: ${data['timestamp']}');
    buf.writeln('📈 Total Records: ${data['total_records']}');
    buf.writeln('');

    final commands = data['commands'] as Map<String, dynamic>;

    if (commands.containsKey('total_steps')) {
      buf.writeln(
          '👣 Total Steps: ${commands['total_steps']['count']} daily records');
    }
    if (commands.containsKey('detailed_steps')) {
      buf.writeln(
          '📊 Detailed Steps: ${commands['detailed_steps']['count']} 10-min segments');
    }
    if (commands.containsKey('sleep')) {
      buf.writeln(
          '😴 Sleep Data: ${commands['sleep']['count']} sleep sessions');
    }
    if (commands.containsKey('heart_rate_details')) {
      buf.writeln(
          '❤️ HR Details: ${commands['heart_rate_details']['count']} detailed measurements');
    }
    if (commands.containsKey('heart_rate_history')) {
      buf.writeln(
          '💓 HR History: ${commands['heart_rate_history']['count']} single measurements');
    }
    if (commands.containsKey('hrv')) {
      buf.writeln('📈 HRV Data: ${commands['hrv']['count']} HRV records');
    }
    if (commands.containsKey('temperature')) {
      buf.writeln(
          '🌡️ Temperature: ${commands['temperature']['count']} temperature readings');
    }
    if (commands.containsKey('blood_oxygen')) {
      buf.writeln(
          '🩸 Blood O₂: ${commands['blood_oxygen']['count']} SpO2 readings');
    }

    buf.writeln('=' * 50);
    return buf.toString();
  }

  /// Send 0x53 and collect parsed Sleep records for [timeout].
  Future<List<SleepRecord>> fetchSleepData(
      {Duration timeout = const Duration(seconds: 2)}) async {
    final Map<String, SleepRecord> dedup = {};

    SleepRecord _selectPreferred(SleepRecord incoming, SleepRecord existing) {
      final incomingLen = incoming.stages.length;
      final existingLen = existing.stages.length;
      if (incomingLen > existingLen) return incoming;
      if (incomingLen < existingLen) return existing;
      if (incoming.durationMinutes > existing.durationMinutes) return incoming;
      if (incoming.durationMinutes < existing.durationMinutes) return existing;
      // If identical length/duration, prefer the latest arriving record
      return incoming;
    }

    late final StreamSubscription<String> sub;
    final completer = Completer<List<SleepRecord>>();
    Timer? t;

    void finish() {
      if (completer.isCompleted) return;
      final rawList = dedup.values.toList()
        ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));
      final merged = _mergeSleepByNight(rawList);
      completer.complete(List.unmodifiable(merged));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      final records = _parseSleepRecordsFromBytes(bytes, mergeByNight: false);
      for (final record in records) {
        final key =
            '${record.index}-${record.page}-${record.startTimestamp.toIso8601String()}';
        final existing = dedup[key];
        if (existing == null) {
          dedup[key] = record;
        } else {
          dedup[key] = _selectPreferred(record, existing);
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetSleepDataCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Parse concatenated 0x53 sleep records.
  /// Heuristic framing: [0]=0x53, [1]=ID1, [2]=ID2, [3..8]=YY MM DD HH mm SS (BCD), [9]=validLength minutes (N), [10..10+N-1]=stages.
  /// Many firmwares send a fixed 130-byte frame (N up to 120). If exact size isn't present, parse a single record if possible.
  List<SleepRecord> _parseSleepRecordsFromBytes(List<int> bytes,
      {bool mergeByNight = true}) {
    final List<SleepRecord> out = [];
    int i = 0;
    while (i + 10 <= bytes.length) {
      if (bytes[i] != 0x53) {
        i++;
        continue;
      }
      // Try fixed-frame first (130 bytes)
      bool parsed = false;
      if (i + 130 <= bytes.length) {
        final frame = bytes.sublist(i, i + 130);
        final rec = _tryParseSleepFrame(frame);
        if (rec != null) {
          out.add(rec);
          i += 130;
          parsed = true;
          continue;
        }
      }
      // Variable-length based on [9]
      final n = bytes[i + 9];
      final size = 10 + n;
      if (n > 0 && n <= 120 && i + size <= bytes.length) {
        final frame = bytes.sublist(i, i + size);
        final rec = _tryParseSleepFrame(frame);
        if (rec != null) {
          out.add(rec);
          i += size;
          parsed = true;
          continue;
        }
      }
      if (!parsed) {
        // Fallback: attempt single-record parse from the remaining bytes and stop
        final rec = _tryParseSleepFrame(bytes.sublist(i));
        if (rec != null) out.add(rec);
        break;
      }
    }
    // Optionally merge per-night sessions for immediate consumption in callers other than fetchSleepData
    return mergeByNight ? _mergeSleepByNight(out) : out;
  }

  SleepRecord? _tryParseSleepFrame(List<int> bytes) {
    if (bytes.length < 10) return null;
    if (bytes[0] != 0x53) return null;
    try {
      final id1 = bytes[1];
      final id2 = bytes[2];
      final year = 2000 + _bcdToDecimal(bytes[3]);
      final month = _bcdToDecimal(bytes[4]);
      final day = _bcdToDecimal(bytes[5]);
      final hour = _bcdToDecimal(bytes[6]);
      final minute = _bcdToDecimal(bytes[7]);
      final second = _bcdToDecimal(bytes[8]);
      final n = bytes[9];
      if (n <= 0 || n > 120) return null;
      final end = math.min(10 + n, bytes.length);
      final stageBytes = bytes.sublist(10, end);
      int deep = 0, light = 0, rem = 0, awake = 0;
      final stages = <int>[];
      for (final s in stageBytes) {
        stages.add(s);
        if (s == 1)
          deep++;
        else if (s == 2)
          light++;
        else if (s == 3)
          rem++;
        else
          awake++;
      }
      final ts = DateTime(year, month, day, hour, minute, second);
      return SleepRecord(
        index: id1,
        page: id2,
        startTimestamp: ts,
        durationMinutes: stageBytes.length,
        deepMinutes: deep,
        lightMinutes: light,
        remMinutes: rem,
        awakeMinutes: awake,
        stages: stages,
      );
    } catch (_) {
      return null;
    }
  }

  void setTarget({String? deviceName, String? macAddress}) {
    _targetDeviceName = deviceName;
    _targetMacAddress = macAddress?.toUpperCase();
    _connectionStatusController.add('Target updated: '
        '${_targetDeviceName ?? '-'} / ${_targetMacAddress ?? '-'}');
  }

  void setFuzzyNameHints(List<String> hints) {
    // Normalize: trim and drop empties
    _fuzzyNameHints =
        hints.map((h) => h.trim()).where((h) => h.isNotEmpty).toList();
    _connectionStatusController
        .add('Fuzzy hints updated: ${_fuzzyNameHints.join(', ')}');
  }

  // =============================
  // Structured Fetch Methods
  // =============================

  // ---------- Single-response commands ----------

  /// Fetch battery status (0x13). Returns map with battery_level, charging, voltage.
  Future<Map<String, dynamic>?> fetchBattery({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 5 && bytes[0] == 0x13) {
        final batteryLevel = bytes[1];
        final charging = bytes[2] == 1;
        final voltageHigh = _bcdToDecimal(bytes[3]) / 10.0;
        final voltageLow = _bcdToDecimal(bytes[4]) / 10.0;
        result = {
          'battery_level': batteryLevel,
          'charging': charging,
          'voltage_high': voltageHigh,
          'voltage_low': voltageLow,
          'raw_byte3': bytes[3],
          'raw_byte4': bytes[4],
        };
      } else if (bytes.length >= 1 && bytes[0] == 0x93) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetBatteryCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch MAC address (0x22). Returns map with mac_address string.
  Future<Map<String, dynamic>?> fetchMacAddress({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 7 && bytes[0] == 0x22) {
        final mac = bytes.sublist(1, 7)
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(':');
        result = {'mac': mac};
      } else if (bytes.length >= 1 && bytes[0] == 0xA2) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetMacAddressCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch firmware version (0x27). Returns map with version and build_date.
  Future<Map<String, dynamic>?> fetchFirmwareVersion({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 8 && bytes[0] == 0x27) {
        final a = _bcdToDecimal(bytes[1]);
        final b = _bcdToDecimal(bytes[2]);
        final c = _bcdToDecimal(bytes[3]);
        final d = _bcdToDecimal(bytes[4]);
        final yy = _bcdToDecimal(bytes[5]);
        final mm = _bcdToDecimal(bytes[6]);
        final dd = _bcdToDecimal(bytes[7]);
        result = {
          'version': '$a.$b.$c.$d',
          'build_date': '20${yy.toString().padLeft(2, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}',
        };
      } else if (bytes.length >= 1 && bytes[0] == 0xA7) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetFirmwareVersionCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch measurement interval (0x2B). Returns map with measurement_type, working_mode, schedule, interval, weekday_bits.
  Future<Map<String, dynamic>?> fetchMeasurementInterval(int measurementType, {Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 10 && bytes[0] == 0x2B) {
        final mType = bytes[1];
        final workingMode = bytes[2]; // 0=Off, 2=Interval
        final String modeStr = workingMode == 0 ? 'off' : (workingMode == 2 ? 'interval' : 'unknown($workingMode)');
        int startHour, startMin, endHour, endMin, interval;
        if (bytes[6] == 0xFF) {
          // FF-variant
          startHour = _bcdToDecimal(bytes[3]);
          startMin = 0;
          endHour = _bcdToDecimal(bytes[4]);
          endMin = _bcdToDecimal(bytes[5]);
          interval = bytes[8];
        } else {
          // Standard
          startHour = _bcdToDecimal(bytes[3]);
          startMin = _bcdToDecimal(bytes[4]);
          endHour = _bcdToDecimal(bytes[5]);
          endMin = _bcdToDecimal(bytes[6]);
          interval = bytes[8] | (bytes[9] << 8);
        }
        final weekdayBits = bytes[7];
        result = {
          'measurement_type': mType,
          'working_mode': modeStr,
          'start_hour': startHour,
          'start_min': startMin,
          'end_hour': endHour,
          'end_min': endMin,
          'interval_minutes': interval,
          'weekday_bits': weekdayBits,
        };
      } else if (bytes.length >= 1 && bytes[0] == 0xAB) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetMeasurementIntervalCommand(measurementType);
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch exercise status (0x19). Returns map with status, is_active, timestamp.
  Future<Map<String, dynamic>?> fetchExerciseStatus({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 9 && bytes[0] == 0x19) {
        final status = bytes[1];
        final isActive = status == 0x01;
        final hasTimestamp = (bytes[3] | bytes[4] | bytes[5] | bytes[6] | bytes[7] | bytes[8]) != 0;
        String? timestamp;
        if (hasTimestamp) {
          final year = 2000 + _bcdToDecimal(bytes[3]);
          final month = _bcdToDecimal(bytes[4]);
          final day = _bcdToDecimal(bytes[5]);
          final hour = _bcdToDecimal(bytes[6]);
          final minute = _bcdToDecimal(bytes[7]);
          final second = _bcdToDecimal(bytes[8]);
          timestamp = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
        }
        result = {
          'status': status,
          'is_active': isActive,
          'has_timestamp': hasTimestamp,
          'timestamp': timestamp,
        };
      } else if (bytes.length >= 1 && bytes[0] == 0xA6) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetExerciseDataCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch user info (0x42). Returns map with gender, age, height_cm, weight_kg, step_len_cm, ring_id.
  Future<Map<String, dynamic>?> fetchUserInfo({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 12 && bytes[0] == 0x42) {
        final genderRaw = bytes[1];
        final gender = genderRaw == 0 ? 'female' : 'male';
        final age = bytes[2];
        final heightCm = bytes[3];
        final weightKg = bytes[4];
        final stepLenCm = bytes[5];
        // Sanitize ring ID: keep printable ASCII (0x20..0x7E), replace others with '?'
        final idSlice = bytes.sublist(6, math.min(12, bytes.length));
        final chars = idSlice.map((b) => (b >= 0x20 && b <= 0x7E) ? b : 0x3F).toList();
        final ringId = String.fromCharCodes(chars).trim();
        result = {
          'gender': genderRaw,
          'gender_name': gender,
          'age': age,
          'height_cm': heightCm,
          'weight_kg': weightKg,
          'step_len_cm': stepLenCm,
          'ring_id': ringId,
        };
      } else if (bytes.length >= 1 && bytes[0] == 0xC2) {
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetUserInfoCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Fetch ring temperature (0x14). Returns map with highest_temp, decimal_temp, ntc1, ntc2, ntc3.
  Future<Map<String, dynamic>?> fetchRingTemperature({Duration timeout = const Duration(seconds: 2)}) async {
    Map<String, dynamic>? result;
    late final StreamSubscription<String> sub;
    final completer = Completer<Map<String, dynamic>?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 11 && bytes[0] == 0x14) {
        final highestTemp = ((bytes[2] << 8) | bytes[1]) / 10.0;
        final cc = _bcdToDecimal(bytes[3]);
        final dd = _bcdToDecimal(bytes[4]);
        final decimalTemp = (cc * 100 + dd) / 10.0;
        final ntc1 = ((bytes[6] << 8) | bytes[5]) / 10.0;
        final ntc2 = ((bytes[8] << 8) | bytes[7]) / 10.0;
        final ntc3 = ((bytes[10] << 8) | bytes[9]) / 10.0;
        result = {
          'highest_temp': highestTemp,
          'decimal_temp': decimalTemp,
          'ntc1': ntc1,
          'ntc2': ntc2,
          'ntc3': ntc3,
        };
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetRingTemperatureCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  // ---------- Multi-record commands ----------

  /// Fetch total step counts (0x51). 27-byte records, end marker 0x51 0xFF.
  Future<List<Map<String, dynamic>>> fetchTotalSteps({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 27 <= bytes.length) {
        if (bytes[i] == 0x51) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 2]);
          final month = _bcdToDecimal(bytes[i + 3]);
          final day = _bcdToDecimal(bytes[i + 4]);
          final steps = (bytes[i + 8] << 24) | (bytes[i + 7] << 16) | (bytes[i + 6] << 8) | bytes[i + 5];
          final exerciseTime = (bytes[i + 12] << 24) | (bytes[i + 11] << 16) | (bytes[i + 10] << 8) | bytes[i + 9];
          final distance = (bytes[i + 16] << 24) | (bytes[i + 15] << 16) | (bytes[i + 14] << 8) | bytes[i + 13];
          final calories = (bytes[i + 20] << 24) | (bytes[i + 19] << 16) | (bytes[i + 18] << 8) | bytes[i + 17];
          out.add({
            'date': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
            'steps': steps,
            'exercise_time_seconds': exerciseTime,
            'distance_km': distance / 100.0,
            'calories_kcal': calories / 100.0,
          });
          i += 27;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetTotalStepCountCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch detailed step counts (0x52). 25-byte records, end marker 0x52 0xFF.
  Future<List<Map<String, dynamic>>> fetchDetailedSteps({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 25 <= bytes.length) {
        if (bytes[i] == 0x52) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final totalSteps = (bytes[i + 10] << 8) | bytes[i + 9];
          final calories = (bytes[i + 12] << 8) | bytes[i + 11];
          final distance = (bytes[i + 14] << 8) | bytes[i + 13];
          final perMinute = bytes.sublist(i + 15, i + 25);
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'steps': totalSteps,
            'calories': calories / 100.0,
            'distance': distance / 100.0,
            'per_minute': List<int>.from(perMinute),
          });
          i += 25;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetDetailedStepCountCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch detailed heart rate (0x54). 24-byte records, end marker 0x54 0xFF.
  Future<List<Map<String, dynamic>>> fetchDetailedHeartRate({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 24 <= bytes.length) {
        if (bytes[i] == 0x54) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final heartRates = <int>[];
          for (int j = 9; j < 24; j++) {
            heartRates.add(bytes[i + j]);
          }
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'heart_rates': heartRates,
          });
          i += 24;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetDetailedHeartRateCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch heart rate history (0x55). 10-byte records, end marker 0x55 0xFF.
  Future<List<Map<String, dynamic>>> fetchHeartRateHistory({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 10 <= bytes.length) {
        if (bytes[i] == 0x55) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final heartRate = bytes[i + 9];
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'heart_rate': heartRate,
          });
          i += 10;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetHeartRateHistoryCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch temperature data (0x62). 15-byte records, end marker 0x62 0xFF.
  Future<List<Map<String, dynamic>>> fetchTemperatureData({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 15 <= bytes.length) {
        if (bytes[i] == 0x62) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          // Temperature values in little-endian format (divide by 10 for C)
          final temperatures = <double>[];
          for (int j = 9; j < 15 && (i + j + 1) < bytes.length; j += 2) {
            int tempRaw = (bytes[i + j + 1] << 8) | bytes[i + j];
            temperatures.add(tempRaw / 10.0);
          }
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'temperatures': temperatures,
          });
          i += 15;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetTemperatureDataCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch blood oxygen data (0x66). 10-byte records, end marker 0x66 0xFF.
  Future<List<Map<String, dynamic>>> fetchBloodOxygenData({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 10 <= bytes.length) {
        if (bytes[i] == 0x66) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final spo2 = bytes[i + 9];
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'spo2': spo2,
          });
          i += 10;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetBloodOxygenDataCommand();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  static const List<String> _exerciseTypeNames = [
    'Running', 'Walking', 'Cycling', 'Hiking', 'Yoga',
    'Basketball', 'Football', 'Badminton', 'Table Tennis',
    'Rope Skipping', 'Sit-ups', 'Push-ups', 'Swimming',
  ];

  /// Fetch exercise mode history (0x5C) — latest. 27-byte records with per-record CRC, end marker 0x5C 0xFF.
  Future<List<Map<String, dynamic>>> fetchExerciseLatest({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 27 <= bytes.length) {
        if (bytes[i] == 0x5C) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          // CRC validation: sum of bytes[0..25] & 0xFF == bytes[26]
          int crcCalc = 0;
          for (int j = 0; j < 26; j++) {
            crcCalc = (crcCalc + bytes[i + j]) & 0xFF;
          }
          if (crcCalc != bytes[i + 26]) {
            i += 27; // skip invalid record
            continue;
          }
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final exerciseType = bytes[i + 9];
          final heartRate = bytes[i + 10];
          final duration = (bytes[i + 12] << 8) | bytes[i + 11];
          final steps = (bytes[i + 14] << 8) | bytes[i + 13];
          final paceMin = _bcdToDecimal(bytes[i + 15]);
          final paceSec = _bcdToDecimal(bytes[i + 16]);
          final calories = _toFloat32Le(bytes[i + 17], bytes[i + 18], bytes[i + 19], bytes[i + 20]);
          final distance = _toFloat32Le(bytes[i + 21], bytes[i + 22], bytes[i + 23], bytes[i + 24]);
          final typeName = exerciseType < _exerciseTypeNames.length ? _exerciseTypeNames[exerciseType] : 'Unknown($exerciseType)';
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'exercise_type': exerciseType,
            'exercise_type_name': typeName,
            'heart_rate': heartRate,
            'duration_seconds': duration,
            'steps': steps,
            'pace': '${paceMin.toString().padLeft(2, '0')}:${paceSec.toString().padLeft(2, '0')}',
            'calories': calories,
            'distance': distance,
          });
          i += 27;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetExerciseModeDataLatest();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Fetch exercise mode history (0x5C) — continue reading next segment.
  Future<List<Map<String, dynamic>>> fetchExerciseContinue({Duration timeout = const Duration(seconds: 4)}) async {
    final List<Map<String, dynamic>> out = [];
    late final StreamSubscription<String> sub;
    final completer = Completer<List<Map<String, dynamic>>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      int i = 0;
      while (i + 27 <= bytes.length) {
        if (bytes[i] == 0x5C) {
          if (bytes[i + 1] == 0xFF) { i += 2; continue; } // end marker
          int crcCalc = 0;
          for (int j = 0; j < 26; j++) {
            crcCalc = (crcCalc + bytes[i + j]) & 0xFF;
          }
          if (crcCalc != bytes[i + 26]) {
            i += 27;
            continue;
          }
          final year = 2000 + _bcdToDecimal(bytes[i + 3]);
          final month = _bcdToDecimal(bytes[i + 4]);
          final day = _bcdToDecimal(bytes[i + 5]);
          final hour = _bcdToDecimal(bytes[i + 6]);
          final minute = _bcdToDecimal(bytes[i + 7]);
          final second = _bcdToDecimal(bytes[i + 8]);
          final exerciseType = bytes[i + 9];
          final heartRate = bytes[i + 10];
          final duration = (bytes[i + 12] << 8) | bytes[i + 11];
          final steps = (bytes[i + 14] << 8) | bytes[i + 13];
          final paceMin = _bcdToDecimal(bytes[i + 15]);
          final paceSec = _bcdToDecimal(bytes[i + 16]);
          final calories = _toFloat32Le(bytes[i + 17], bytes[i + 18], bytes[i + 19], bytes[i + 20]);
          final distance = _toFloat32Le(bytes[i + 21], bytes[i + 22], bytes[i + 23], bytes[i + 24]);
          final typeName = exerciseType < _exerciseTypeNames.length ? _exerciseTypeNames[exerciseType] : 'Unknown($exerciseType)';
          out.add({
            'timestamp': '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
            'exercise_type': exerciseType,
            'exercise_type_name': typeName,
            'heart_rate': heartRate,
            'duration_seconds': duration,
            'steps': steps,
            'pace': '${paceMin.toString().padLeft(2, '0')}:${paceSec.toString().padLeft(2, '0')}',
            'calories': calories,
            'distance': distance,
          });
          i += 27;
        } else {
          i++;
        }
      }
    }, onError: (_) {}, onDone: finish);

    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendGetExerciseModeDataContinue();
    } catch (e) {
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Delete exercise mode history (0x5C 0x99). Returns true on success, false on timeout.
  Future<bool> deleteExerciseHistory({Duration timeout = const Duration(seconds: 2)}) async {
    bool? success;
    late final StreamSubscription<String> sub;
    final completer = Completer<bool>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 2 && bytes[0] == 0x5C) {
        // Any response from 0x5C after delete command indicates acknowledgement
        success = true;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(success ?? false);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(success ?? false);
    });

    try {
      await sendDeleteExerciseModeDetails();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  // =============================
  // Time: Structured Request/Parse
  // =============================

  /// Send 0x41 (Get Time) and parse the ring's current time from the response.
  /// Returns a [RingTimeResult] with the ring's clock, or null on timeout/failure.
  Future<RingTimeResult?> fetchTime(
      {Duration timeout = const Duration(seconds: 2)}) async {
    RingTimeResult? result;

    late final StreamSubscription<String> sub;
    final completer = Completer<RingTimeResult?>();

    sub = messageStream.listen((msg) {
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      if (bytes.length >= 16 && bytes[0] == 0x41) {
        final year = 2000 + _bcdToDecimal(bytes[1]);
        final month = _bcdToDecimal(bytes[2]);
        final day = _bcdToDecimal(bytes[3]);
        final hour = _bcdToDecimal(bytes[4]);
        final minute = _bcdToDecimal(bytes[5]);
        final second = _bcdToDecimal(bytes[6]);
        final weekday = bytes[7]; // 1=Mon..7=Sun (unreliable per protocol)
        final maxMtu = bytes[8];
        result = RingTimeResult(
          ringTime: DateTime(year, month, day, hour, minute, second),
          weekday: weekday,
          maxMtu: maxMtu,
        );
      } else if (bytes.length >= 1 && bytes[0] == 0xC1) {
        // Failure response
        result = null;
      }
    }, onError: (_) {}, onDone: () {
      if (!completer.isCompleted) completer.complete(result);
    });

    final t = Timer(timeout, () async {
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    try {
      await sendGetTimeCommand();
    } catch (e) {
      t.cancel();
      await sub.cancel();
      rethrow;
    }

    final res = await completer.future;
    t.cancel();
    await sub.cancel();
    return res;
  }

  /// Send 0x01 (Set Time) with the current phone time, then read back with 0x41
  /// to verify. Returns a [SyncTimeResult] with both the sent and verified times.
  Future<SyncTimeResult> syncTimeAndVerify(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final phoneSentAt = DateTime.now();

    // Send 0x01 to set time
    await sendSetCurrentTimeCommand();

    // Small delay for ring to process
    await Future.delayed(const Duration(milliseconds: 500));

    // Read back with 0x41
    final readback = await fetchTime(timeout: timeout);

    return SyncTimeResult(
      phoneSentAt: phoneSentAt,
      ringReadback: readback?.ringTime,
      maxMtu: readback?.maxMtu,
    );
  }

  // =============================
  // HRV: Structured Request/Parse
  // =============================

  /// Send 0x56 and collect parsed HRV records for [timeout].
  /// Returns zero or more structured [HrvRecord].
  Future<List<HrvRecord>> fetchHrvData(
      {Duration timeout = const Duration(seconds: 2)}) async {
    final List<HrvRecord> out = [];

    // Temporary listener on messageStream to capture incoming hex and parse 0x56 records
    late final StreamSubscription<String> sub;
    final completer = Completer<List<HrvRecord>>();
    Timer? t;

    void finish() {
      if (!completer.isCompleted) completer.complete(List.unmodifiable(out));
    }

    sub = messageStream.listen((msg) {
      // Extract hex-like content from the message and parse out 0x56 records
      final bytes = _extractHexBytes(msg);
      if (bytes.isEmpty) return;
      out.addAll(_parseHrvRecordsFromBytes(bytes));
    }, onError: (_) {}, onDone: finish);

    // Arm timeout
    t = Timer(timeout, () async {
      await sub.cancel();
      finish();
    });

    try {
      await sendHrvCommand();
    } catch (e) {
      // If send fails, clean up and rethrow
      t?.cancel();
      await sub.cancel();
      rethrow;
    }

    final results = await completer.future;
    t?.cancel();
    await sub.cancel();
    return results;
  }

  /// Extracts a list of bytes from a message line that may contain hex like '56-00-..' or with prefixes.
  List<int> _extractHexBytes(String message) {
    // Find the longest hex-with-dashes sequence in the message
    final reg = RegExp(r'((?:[0-9A-Fa-f]{2}-)+[0-9A-Fa-f]{2})');
    final match = reg.firstMatch(message);
    if (match == null) return const [];
    final hex = match.group(1)!;
    try {
      return _parseHexString(hex);
    } catch (_) {
      return const [];
    }
  }

  /// Parses concatenated 0x56 records from [bytes]. Each record is 15 bytes:
  /// [0]=0x56 [1]=ID1 [2]=ID2 [3]=YY [4]=MM [5]=DD [6]=HH [7]=mm [8]=SS [9]=HRV [10]=00 [11]=HR [12]=Fatigue [13]=SBP [14]=DBP
  List<HrvRecord> _parseHrvRecordsFromBytes(List<int> bytes) {
    final List<HrvRecord> out = [];
    int i = 0;
    while (i + 15 <= bytes.length) {
      // Find next 0x56
      if (bytes[i] != 0x56) {
        i++;
        continue;
      }
      final rec = bytes.sublist(i, i + 15);
      // Basic sanity: pos10 should be 0x00 per spec
      if (rec[10] != 0x00) {
        // Not a valid 0x56 record, skip this byte
        i++;
        continue;
      }
      final id1 = rec[1];
      final id2 = rec[2];
      // Use BCD decoding for HRV timestamp to match message parser
      final int year = 2000 + _bcdToInt(rec[3]);
      final int month = _bcdToInt(rec[4]);
      final int day = _bcdToInt(rec[5]);
      final int hour = _bcdToInt(rec[6]);
      final int minute = _bcdToInt(rec[7]);
      final int second = _bcdToInt(rec[8]);
      DateTime ts;
      try {
        ts = DateTime(year, month, day, hour, minute, second);
      } catch (_) {
        // Fallback to now if invalid
        ts = DateTime.now();
      }
      final hrv = rec[9];
      final hr = rec[11];
      final fatigue = rec[12];
      final sbp = rec[13];
      final dbp = rec[14];

      out.add(HrvRecord(
        index: id1,
        page: id2,
        timestamp: ts,
        hrvMs: hrv,
        heartRateBpm: hr,
        fatigue: fatigue,
        systolic: sbp,
        diastolic: dbp,
      ));

      i += 15;
    }
    return out;
  }

  int _bcdToInt(int b) {
    return ((b >> 4) & 0x0F) * 10 + (b & 0x0F);
  }

  // 🧪 Multi-parameter comprehensive measurement (0x28)
  // Modes: 0x01 = HRV/BP, 0x02 = Heart Rate
  // BB: 0x01 start, 0x00 stop; CC DD: duration seconds (LE), min 30s enforced by device
  Future<void> sendStartMultiParamMeasurement(
      {required int mode, int durationSeconds = 30}) async {
    // Format: 28 AA BB 00 00 CC DD 00 00 00 00 00 00 00 00 CRC
    int dur = durationSeconds < 30 ? 30 : durationSeconds;
    int cc = dur & 0xFF;
    int dd = (dur >> 8) & 0xFF;
    List<int> bytes = [
      0x28,
      mode & 0xFF,
      0x01,
      0x00,
      0x00,
      cc,
      dd,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🏃‍♂️ 0x5C Obtain exercise data from various exercise modes (history/detail)
  // Command format: 5C AA BB CC 00 00 00 00 00 00 00 00 00 00 00 CRC
  // AA:
  //  - 0x00: Read latest exercise data (starting from timestamp YY MM DD HH mm SS; all zeros for first sync)
  //  - 0x02: Continue reading next segment
  //  - 0x99: Delete exercise detailed data
  Future<void> sendGetExerciseModeDataLatest({
    int yearYY = 0x00,
    int month = 0x00,
    int day = 0x00,
    int hour = 0x00,
    int minute = 0x00,
    int second = 0x00,
  }) async {
    // We only have AA, BB, CC then zeros per spec. Many firmwares accept AA=0x00 and the following
    // 14 bytes zero to mean "from beginning". We'll follow the example and send zeros.
    List<int> bytes = [
      0x5C,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> sendGetExerciseModeDataContinue() async {
    List<int> bytes = [
      0x5C,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> sendDeleteExerciseModeDetails() async {
    List<int> bytes = [
      0x5C,
      0x99,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🌡️ 0x14 Real-time Temperature Reading of the Ring
  // Command Format: 14 00 00 00 00 00 00 00 00 00 00 00 00 00 00 CRC
  Future<void> sendGetRingTemperatureCommand() async {
    List<int> bytes = [
      0x14,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> sendStopMultiParamMeasurement({required int mode}) async {
    // Format: 28 AA 00 00 00 00 00 00 00 00 00 00 00 00 00 CRC
    List<int> bytes = [
      0x28,
      mode & 0xFF,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> sendQueryMultiParamStatus() async {
    // Format: 28 80 00 00 00 00 00 00 00 00 00 00 00 00 00 CRC
    List<int> bytes = [
      0x28,
      0x80,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> _initializeBluetooth() async {
    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isAvailable == false) {
        _connectionStatusController.add('Bluetooth not available (Emulator)');
        return;
      }

      // Check if Bluetooth is on
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        _connectionStatusController.add('Bluetooth is off (Emulator)');
        return;
      }

      _connectionStatusController.add('Bluetooth ready');
    } catch (e) {
      _connectionStatusController
          .add('Bluetooth initialization failed: $e (Emulator)');
    }
  }

  Future<void> connectToSmartRing() async {
    // Prevent multiple simultaneous connection attempts
    if (_isConnecting || _connectedDevice != null) {
      print('Already connecting or connected, skipping...');
      return;
    }

    _isConnecting = true;

    try {
      _connectionStatusController.add('Searching for Smart Ring...');

      // First try to connect to a previously connected device
      List<BluetoothDevice> connectedDevices = FlutterBluePlus.connectedDevices;
      print('Found ${connectedDevices.length} connected devices');
      for (BluetoothDevice device in connectedDevices) {
        print(
            'Checking connected device: ${device.platformName} (${device.remoteId.str})');
        final devMacUp = device.remoteId.str.toUpperCase();
        final name = device.platformName;
        final macMatch = (_targetMacAddress != null &&
            _targetMacAddress!.isNotEmpty &&
            devMacUp == _targetMacAddress);
        final nameMatch = (_targetDeviceName != null &&
            _targetDeviceName!.isNotEmpty &&
            name.toUpperCase().contains(_targetDeviceName!.toUpperCase()));
        if (macMatch || nameMatch) {
          print('Found target device in connected devices!');
          await _connectToDevice(device);
          return;
        }
      }

      // If not found in connected devices, start scanning
      print('Starting scan for Smart Ring...');
      await scanAndConnect();
    } catch (e) {
      print('Connection error: $e');
      _connectionStatusController.add('Connection failed: $e');
      _startReconnectTimer();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> scanAndConnect() async {
    try {
      _connectionStatusController.add('Scanning...');

      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen to scan results
      StreamSubscription<List<ScanResult>>? scanSubscription;
      Completer<void> scanCompleter = Completer<void>();

      scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          String deviceName = result.device.platformName;
          String deviceMac = result.device.remoteId.str;

          print('Found device: $deviceName ($deviceMac)');

          // Check if this is our target device
          bool macMatch = _targetMacAddress != null &&
              _targetMacAddress!.isNotEmpty &&
              deviceMac.toUpperCase() == _targetMacAddress;
          bool nameMatch = _targetDeviceName != null &&
              _targetDeviceName!.isNotEmpty &&
              deviceName
                  .toUpperCase()
                  .contains(_targetDeviceName!.toUpperCase());
          bool fuzzyMatch = false;
          // Optional fallback fuzzy match when no explicit target provided, using UI-provided hints
          if (!macMatch &&
              !nameMatch &&
              (_targetMacAddress == null || _targetMacAddress!.isEmpty) &&
              (_targetDeviceName == null || _targetDeviceName!.isEmpty) &&
              _fuzzyNameHints.isNotEmpty) {
            fuzzyMatch =
                _fuzzyNameHints.any((hint) => deviceName.contains(hint));
          }
          if (macMatch || nameMatch || fuzzyMatch) {
            print('Target device found: $deviceName ($deviceMac)');

            // Stop scanning
            await FlutterBluePlus.stopScan();
            scanSubscription?.cancel();

            // Connect to the device
            await _connectToDevice(result.device);

            if (!scanCompleter.isCompleted) {
              scanCompleter.complete();
            }
            return;
          }
        }
      });

      // Wait for scan to complete or timeout
      Timer(const Duration(seconds: 12), () {
        if (!scanCompleter.isCompleted) {
          scanCompleter.complete();
          // Only update status if we're not already connected
          if (_connectedDevice == null) {
            _connectionStatusController.add('Smart Ring not found in scan');
          }
        }
      });

      await scanCompleter.future;
      scanSubscription?.cancel();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _connectionStatusController.add('Scan failed: $e');
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _connectionStatusController
          .add('Connecting to ${device.platformName}...');
      print(
          'Attempting to connect to ${device.platformName} (${device.remoteId.str})');

      // Check if already connected
      BluetoothConnectionState currentState =
          await device.connectionState.first;
      print('Current connection state: $currentState');

      if (currentState != BluetoothConnectionState.connected) {
        // Connect to device
        print('Connecting to device...');
        await device.connect(timeout: const Duration(seconds: 15));
      } else {
        print('Device already connected!');
      }

      _connectedDevice = device;

      // Discover services
      _connectionStatusController.add('Discovering services...');
      print('Discovering services...');
      List<BluetoothService> services = await device.discoverServices();
      print('Found ${services.length} services');

      // Find our target service and characteristics
      BluetoothService? targetService;
      print('Looking for service UUID: $serviceUuid');
      for (BluetoothService service in services) {
        String serviceUuidStr = service.uuid.toString().toLowerCase();
        print('Found service: $serviceUuidStr');

        // Check both short form (fff0) and long form (0000fff0-0000-1000-8000-00805f9b34fb)
        if (serviceUuidStr == serviceUuid.toLowerCase() ||
            serviceUuidStr == 'fff0' ||
            serviceUuidStr.contains('fff0')) {
          targetService = service;
          print('Target service found! (UUID: $serviceUuidStr)');
          break;
        }
      }

      if (targetService == null) {
        print('Target service not found! Available services:');
        for (BluetoothService service in services) {
          print('  - ${service.uuid.toString()}');
        }
        throw Exception('Target service not found');
      }

      // Find characteristics
      print('Looking for characteristics in service ${targetService.uuid}');
      for (BluetoothCharacteristic characteristic
          in targetService.characteristics) {
        String charUuid = characteristic.uuid.toString().toLowerCase();
        print('Found characteristic: $charUuid');

        // Check for write characteristic (fff6)
        if (charUuid == writeCharacteristicUuid.toLowerCase() ||
            charUuid == 'fff6' ||
            charUuid.contains('fff6')) {
          _writeCharacteristic = characteristic;
          print('Write characteristic found: $charUuid');
        }
        // Check for notify characteristic (fff7)
        else if (charUuid == notifyCharacteristicUuid.toLowerCase() ||
            charUuid == 'fff7' ||
            charUuid.contains('fff7')) {
          _notifyCharacteristic = characteristic;
          print('Notify characteristic found: $charUuid');

          // Enable notifications
          await characteristic.setNotifyValue(true);

          // Listen to notifications
          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              String hexString = value
                  .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                  .join('-')
                  .toUpperCase();
              String parsedResponse = _parseMultiRecordResponse(value);
              _messageController.add('$hexString\n$parsedResponse');
            }
          });
        }
      }

      if (_writeCharacteristic == null || _notifyCharacteristic == null) {
        throw Exception('Required characteristics not found');
      }

      _connectionStatusController.add('Connected');
      print('Successfully connected to Smart Ring!');

      // Listen for disconnection
      device.connectionState.listen((state) {
        print('Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _connectionStatusController.add('Disconnected');
          _connectedDevice = null;
          _writeCharacteristic = null;
          _notifyCharacteristic = null;
          _isConnecting = false;
          _startReconnectTimer();
        }
      });
    } catch (e) {
      print('Connection to device failed: $e');
      _connectionStatusController.add('Connection failed: $e');
      _connectedDevice = null;
      _writeCharacteristic = null;
      _notifyCharacteristic = null;
      _isConnecting = false;
      _startReconnectTimer();
    }
  }

  void _startReconnectTimer() {
    if (_isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isDisposed && _connectedDevice == null) {
        connectToSmartRing();
      }
    });
  }

  Future<void> sendMessage(String hexMessage) async {
    // Check if we're in demo mode
    if (_writeCharacteristic == null) {
      // Simulate sending in demo mode
      print('Demo mode: Simulating send of $hexMessage');

      // Simulate a response after a short delay
      Timer(const Duration(milliseconds: 500), () {
        if (hexMessage.startsWith('56')) {
          // Simulate HRV data response
          String response =
              '56-01-00-25-06-30-${DateTime.now().hour.toRadixString(16).padLeft(2, '0')}-${DateTime.now().minute.toRadixString(16).padLeft(2, '0')}-${DateTime.now().second.toRadixString(16).padLeft(2, '0')}-2F-00-52-28-75-40-A1';
          _messageController.add(response);
        }
      });
      return;
    }

    try {
      // Parse hex string to bytes
      List<int> bytes = _parseHexString(hexMessage);

      // Send the message
      await _writeCharacteristic!.write(bytes, withoutResponse: false);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendHrvCommand() async {
    // Send the HRV data request command (0x56)
    // Format: 56-01-00-00-00-00-00-00-00-00-00-00-00-00-00-57
    String hrvCommand = '56-01-00-00-00-00-00-00-00-00-00-00-00-00-00-57';
    await sendMessage(hrvCommand);
  }

  Future<void> sendGetUserInfoCommand() async {
    // Send get user personal information command (0x42)
    // Format: 42-00-00-00-00-00-00-00-00-00-00-00-00-00-00-CRC
    List<int> bytes = [
      0x42,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    // Calculate checksum for first 15 bytes
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // ✍️ Set user personal information (0x02)
  // Payload layout (observed from 0x42 response mapping):
  // [1]=Gender (0: Female, 1: Male)
  // [2]=Age (years)
  // [3]=Height (cm)
  // [4]=Weight (kg)
  // [5]=Step length (cm)
  // [6..11]=Ring ID ASCII (6 chars), e.g., '000000' (0x30 0x30 ...)
  // [12..14]=Reserved (0x00)
  Future<void> sendSetUserInfoCommand({
    required int gender,
    required int age,
    required int heightCm,
    required int weightKg,
    required int stepLengthCm,
    String ringId = '000000',
  }) async {
    // Sanitize inputs to 0..255 byte range where applicable
    int g = (gender & 0xFF);
    int a = (age & 0xFF);
    int h = (heightCm & 0xFF);
    int w = (weightKg & 0xFF);
    int s = (stepLengthCm & 0xFF);

    // Prepare ringId as up to 6 ASCII bytes; pad with '0'
    String rid = ringId;
    if (rid.length > 6) rid = rid.substring(0, 6);
    while (rid.length < 6) rid = rid + '0';
    List<int> ridBytes = rid.codeUnits;

    List<int> bytes = [
      0x02,
      g,
      a,
      h,
      w,
      s,
      ridBytes[0],
      ridBytes[1],
      ridBytes[2],
      ridBytes[3],
      ridBytes[4],
      ridBytes[5],
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum = bytes.sublist(0, 15).fold(0, (sum, b) => sum + b) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  int _decimalToBcd(int value) => ((value ~/ 10) << 4) | (value % 10);

  // 🕐 Set Time Command (0x01)
  Future<void> sendSetCurrentTimeCommand() async {
    final now = DateTime.now();
    final year = now.year - 2000;
    // Observed on device: BCD-encoded values actually apply, while plain decimal may ACK without updating RTC.
    List<int> bytes = [
      0x01,
      _decimalToBcd(year),
      _decimalToBcd(now.month),
      _decimalToBcd(now.day),
      _decimalToBcd(now.hour),
      _decimalToBcd(now.minute),
      _decimalToBcd(now.second),
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🕐 Get Time Command (0x41)
  Future<void> sendGetTimeCommand() async {
    List<int> bytes = [
      0x41,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🔋 Get Battery Level Command (0x13)
  Future<void> sendGetBatteryCommand() async {
    List<int> bytes = [
      0x13,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 📍 Get MAC Address Command (0x22)
  Future<void> sendGetMacAddressCommand() async {
    List<int> bytes = [
      0x22,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🔧 Get Firmware Version Command (0x27)
  Future<void> sendGetFirmwareVersionCommand() async {
    List<int> bytes = [
      0x27,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // ⏱️ Get Measurement Interval Command (0x2B)
  Future<void> sendGetMeasurementIntervalCommand(int measurementType) async {
    // measurementType: 1=Heart Rate, 2=Blood Oxygen, 4=HRV
    List<int> bytes = [
      0x2B,
      measurementType,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // ⏲️ Set Measurement Interval Command (0x2A)
  // Layout mirrors 0x2B getter fields:
  // [0]=0x2A, [1]=measurementType(1=HR,2=SpO2,4=HRV), [2]=workingMode(0=Off,2=Interval)
  // [3]=startHour(BCD), [4]=startMinute(BCD), [5]=endHour(BCD), [6]=endMinute(BCD)
  // [7]=weekday bits (bit0=Sun ... bit6=Sat), [8]=intervalHigh, [9]=intervalLow
  // [10..14]=0x00, [15]=CRC(sum of [0..14] & 0xFF)
  Future<void> sendSetMeasurementIntervalCommand({
    required int measurementType,
    required int workingMode,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int weekdayBits,
    required int intervalMinutes,
  }) async {
    int bcd(int v) => ((v ~/ 10) << 4) | (v % 10);
    int ih = (intervalMinutes >> 8) & 0xFF;
    int il = intervalMinutes & 0xFF;
    // Default (standard) layout
    int b3 = bcd(startHour & 0xFF);
    int b4 = bcd(startMinute & 0xFF);
    int b5 = bcd(endHour & 0xFF);
    int b6 = bcd(endMinute & 0xFF);
    // Variant: full-day window uses FF-marker layout seen in getter responses
    // If 00:00 - 23:59, send [3]=startHour, [4]=endHour, [5]=endMinute, [6]=0xFF
    bool useFfVariant = (startHour == 0) &&
        (startMinute == 0) &&
        (endHour == 23) &&
        (endMinute == 59);
    if (useFfVariant) {
      b3 = bcd(0);
      b4 = bcd(23);
      b5 = bcd(59);
      b6 = 0xFF;
    }
    List<int> bytes = [
      0x2A,
      measurementType & 0xFF,
      workingMode & 0xFF,
      b3,
      b4,
      b5,
      b6,
      weekdayBits & 0xFF,
      // Interval: FF-variant uses 1 byte at [8]; standard uses 16-bit LE at [8..9]
      if (useFfVariant) (intervalMinutes & 0xFF) else il,
      if (useFfVariant) 0x00 else ih,
      0x00, 0x00, 0x00, 0x00, 0x00,
      0x00,
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 📡 Real-time Step/HR/SpO2/Temperature Transmission Mode (0x09)
  Future<void> sendStartRealtimeMode({bool enableTemperature = true}) async {
    // 0x09 AA BB ... where AA=1 start, BB=1 enable temp, 0 disable
    List<int> bytes = [
      0x09,
      0x01,
      enableTemperature ? 0x01 : 0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  Future<void> sendStopRealtimeMode() async {
    // 0x09 AA BB ... where AA=0 stop, BB can be 0
    List<int> bytes = [
      0x09,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🏃 Query Exercise Status Command (0x19)
  Future<void> sendGetExerciseDataCommand() async {
    // 0x19 AA BB CC DD ... where AA=5 (Query status), BB=0 (default), CC=0, DD=0
    List<int> bytes = [
      0x19,
      0x05,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🏃 Start Exercise Command (0x19)
  Future<void> sendStartExerciseCommand() async {
    // 0x19 AA BB CC DD ... where AA=1 (Start), BB=0 (Running), CC=0, DD=0
    List<int> bytes = [
      0x19,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🛑 End Exercise Command (0x19)
  Future<void> sendEndExerciseCommand() async {
    // 0x19 AA BB CC DD ... where AA=4 (End), BB=0 (default), CC=0, DD=0
    List<int> bytes = [
      0x19,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 👣 Get Total Step Count Command (0x51)
  Future<void> sendGetTotalStepCountCommand() async {
    List<int> bytes = [
      0x51,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 📊 Get Detailed Step Count Command (0x52)
  Future<void> sendGetDetailedStepCountCommand() async {
    List<int> bytes = [
      0x52,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 😴 Get Sleep Data Command (0x53)
  Future<void> sendGetSleepDataCommand() async {
    List<int> bytes = [
      0x53,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // ❤️ Get Detailed Heart Rate Command (0x54)
  Future<void> sendGetDetailedHeartRateCommand() async {
    List<int> bytes = [
      0x54,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 💓 Get Heart Rate History Command (0x55)
  Future<void> sendGetHeartRateHistoryCommand() async {
    List<int> bytes = [
      0x55,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🌡️ Get Temperature Data Command (0x62)
  Future<void> sendGetTemperatureDataCommand() async {
    List<int> bytes = [
      0x62,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // 🩸 Get Blood Oxygen Data Command (0x66)
  Future<void> sendGetBloodOxygenDataCommand() async {
    List<int> bytes = [
      0x66,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ];
    int checksum =
        bytes.sublist(0, 15).fold(0, (sum, byte) => sum + byte) & 0xFF;
    bytes[15] = checksum;
    String command = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
    await sendMessage(command);
  }

  // Helper function to convert BCD (Binary Coded Decimal) to decimal
  // e.g., 0x25 BCD = 25 decimal, 0x59 BCD = 59 decimal
  int _bcdToDecimal(int bcd) => ((bcd >> 4) * 10) + (bcd & 0x0F);

  // Helper: convert 4 bytes (LE) to IEEE754 float32
  double _toFloat32Le(int b0, int b1, int b2, int b3) {
    final bytes =
        Uint8List.fromList([b0 & 0xFF, b1 & 0xFF, b2 & 0xFF, b3 & 0xFF]);
    return ByteData.sublistView(bytes).getFloat32(0, Endian.little);
  }

  // Helper: format seconds as H:MM:SS or M:SS
  String _formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  // Helper: map exercise type code to human-readable string
  String _exerciseTypeString(int type) {
    switch (type) {
      case 0x00:
        return 'Running';
      case 0x01:
        return 'Walking';
      case 0x02:
        return 'Cycling';
      case 0x03:
        return 'Hiking';
      case 0x04:
        return 'Yoga';
      case 0x05:
        return 'Basketball';
      case 0x06:
        return 'Football';
      case 0x07:
        return 'Badminton';
      case 0x08:
        return 'Table Tennis';
      case 0x09:
        return 'Rope Skipping';
      case 0x0A:
        return 'Sit-ups';
      case 0x0B:
        return 'Push-ups';
      case 0x0C:
        return 'Swimming';
      default:
        return 'Unknown ($type)';
    }
  }

  String _parseMultiRecordResponse(List<int> bytes) {
    if (bytes.isEmpty) return 'Empty response';

    // Check if this is a multi-record response (multiple commands concatenated)
    List<String> parsedRecords = [];
    int offset = 0;

    // First, try to detect the pattern by looking for repeated command bytes
    int firstCommand = bytes[0];
    List<int> commandPositions = [0];

    // Preferred: split strictly by 16-byte frames validated by checksum
    List<String> checksumFramed = [];
    if (bytes.length >= 32) {
      for (int i = 0; i + 16 <= bytes.length; i += 16) {
        List<int> frame = bytes.sublist(i, i + 16);
        int calc = frame.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
        int crc = frame[15];
        if (calc == crc) {
          String parsed = _parseResponse(frame);
          if (parsed != 'Unknown command') {
            checksumFramed.add(parsed);
          }
        } else {
          // Break if checksum invalid; fallback to heuristic method below
          checksumFramed.clear();
          break;
        }
        if (checksumFramed.length > 15) break;
      }
    }

    if (checksumFramed.isNotEmpty) {
      return '📊 Multi-Record Response (${checksumFramed.length} records):\n\n' +
          checksumFramed
              .asMap()
              .entries
              .map((entry) => '📋 Record ${entry.key + 1}:\n${entry.value}')
              .join('\n\n');
    }

    // Special framing for 0x5C: records are 27 bytes (1 cmd + 25 payload + 1 CRC) with per-record checksum
    if (firstCommand == 0x5C && bytes.length >= 27) {
      final parts = <String>[];
      int off = 0;
      int safety27 = 0;
      while (off + 27 <= bytes.length && safety27 < 20) {
        safety27++;
        final rec = bytes.sublist(off, off + 27);
        // Validate structure and CRC
        if (rec[0] != 0x5C) {
          break;
        }
        final calc = rec.sublist(0, 26).fold(0, (s, b) => s + b) & 0xFF;
        if (rec[26] != calc) {
          // If first record fails CRC, fall back to single parse to allow tolerant parsing
          if (off == 0) {
            break;
          } else {
            // stop framing further
            break;
          }
        }
        final parsed = _parseResponse(rec);
        if (parsed != 'Unknown command') parts.add(parsed);
        off += 27;
        if (parts.length > 15) break;
      }
      if (parts.isNotEmpty) {
        return '📊 Multi-Record Response (${parts.length} records):\n\n' +
            parts
                .asMap()
                .entries
                .map((e) => '📋 Record ${e.key + 1}:\n${e.value}')
                .join('\n\n');
      }
      // If 27-byte framing failed (e.g., single record or CRC-tolerant case), parse as a single response
      return _parseResponse(bytes);
    }

    // If the first command is 0x09 (real-time stream), avoid heuristic splitting because
    // payload may contain 0x09 bytes and frames can be aggregated; parse as a single record.
    if (firstCommand == 0x09) {
      return _parseResponse(bytes);
    }

    // Heuristic fallback: Look for repeated command byte positions (legacy logic)
    for (int i = 1; i < bytes.length; i++) {
      if (bytes[i] == firstCommand) {
        commandPositions.add(i);
      }
    }
    int detectedRecordSize = 16;
    if (commandPositions.length > 1) {
      detectedRecordSize = commandPositions[1] - commandPositions[0];
    }
    for (int i = 0; i < commandPositions.length; i++) {
      int recordStart = commandPositions[i];
      int recordEnd = (i + 1 < commandPositions.length)
          ? commandPositions[i + 1]
          : bytes.length;
      List<int> record = bytes.sublist(recordStart, recordEnd);
      String parsed = _parseResponse(record);
      if (parsed != 'Unknown command') {
        parsedRecords.add(parsed);
      }
      if (parsedRecords.length > 15) break;
    }

    if (parsedRecords.isNotEmpty) {
      return '📊 Multi-Record Response (${parsedRecords.length} records):\n\n' +
          parsedRecords
              .asMap()
              .entries
              .map((entry) => '📋 Record ${entry.key + 1}:\n${entry.value}')
              .join('\n\n');
    }

    // Fall back to single record parsing
    return _parseResponse(bytes);
  }

  String _parseResponse(List<int> bytes) {
    if (bytes.isEmpty) return 'Empty response';

    int command = bytes[0];

    switch (command) {
      case 0x5C: // Exercise mode history/detail (variable-length)
        // Very short EOF/No-Data indicator observed as 5C-FF
        if (bytes.length == 2 && bytes[1] == 0xFF) {
          return '🏃 Exercise Control (0x5C) • No more records (EOF)';
        }
        // Some subcommands (e.g., 0x99 Delete) return a 16-byte ACK frame
        if (bytes.length == 16) {
          int sub = bytes.length > 1 ? bytes[1] : -1;
          int status = bytes.length > 2 ? bytes[2] : 0x00; // often 0x00
          int calc = bytes.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
          bool crcOk = (bytes[15] == calc);
          String subStr;
          switch (sub) {
            case 0x99:
              subStr = 'Delete Details (0x99)';
              break;
            case 0x00:
              subStr = 'Request Latest (0x00)';
              break;
            case 0x02:
              subStr = 'Continue (0x02)';
              break;
            default:
              subStr =
                  'Subcmd 0x${sub.toRadixString(16).padLeft(2, '0').toUpperCase()}';
          }
          return '🏃 Exercise Control ACK (0x5C) • $subStr\n'
              '🔢 Status: 0x${status.toRadixString(16).padLeft(2, '0').toUpperCase()} • '
              '${crcOk ? '✅ CRC OK' : '⚠️ CRC Mismatch'}';
        }

        // Try to parse one or more 27-byte records (1 cmd + 25 payload + 1 tail)
        if (bytes.length < 27)
          return '🏃 Exercise Mode Data (0x5C): insufficient length (${bytes.length})';
        final records = <String>[];
        int offset = 0;
        int safety = 0;
        while (offset + 27 <= bytes.length && safety < 20) {
          safety++;
          final chunk = bytes.sublist(offset, offset + 27);
          // Basic structure check: first byte should be 0x5C
          if (chunk[0] != 0x5C) {
            break; // stop if misaligned
          }
          // IDs
          int id1 = chunk[1];
          int id2 = chunk[2];
          // Timestamp appears BCD-encoded for 0x5C (unlike 0x52/0x56)
          int yy = chunk[3];
          int year = (yy == 0x25) ? 2025 : (2000 + _bcdToDecimal(yy));
          int month = _bcdToDecimal(chunk[4]);
          int day = _bcdToDecimal(chunk[5]);
          int hour = _bcdToDecimal(chunk[6]);
          int minute = _bcdToDecimal(chunk[7]);
          int second = _bcdToDecimal(chunk[8]);
          // Type and HR
          int type = chunk[9];
          int hr = chunk[10];
          // Duration 2 bytes LE (seconds) — empirical mapping for this device variant
          int dur = chunk[11] | (chunk[12] << 8);
          // Steps 2 bytes LE
          int steps = chunk[13] | (chunk[14] << 8);
          // Pace minutes/seconds per km (BCD)
          int paceMin = _bcdToDecimal(chunk[15]);
          int paceSec = _bcdToDecimal(chunk[16]);
          // Calories float32 LE at [17..20]
          double kcal =
              _toFloat32Le(chunk[17], chunk[18], chunk[19], chunk[20]);
          // Distance float32 LE (km) at [21..24]
          double distKm =
              _toFloat32Le(chunk[21], chunk[22], chunk[23], chunk[24]);
          // Tail bytes [21..26] observed; checksum variant unknown → do not flag mismatch

          String typeStr = _exerciseTypeString(type);
          String ts =
              '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
          String rec =
              '📄 ID: ${id1.toString().padLeft(2, '0')}${id2.toRadixString(16).padLeft(2, '0').toUpperCase()} • '
              '🕒 $ts • 🏷️ $typeStr • ❤️ $hr bpm\n'
              '⏱️ ${_formatDuration(dur)} • 🦶 $steps steps • 🏃 Pace ${paceMin}:${paceSec.toString().padLeft(2, '0')}/km\n'
              '🔥 ${kcal.toStringAsFixed(1)} kcal • 📏 ${distKm.toStringAsFixed(2)} km';
          records.add(rec);
          offset += 27;
        }
        if (records.isEmpty) {
          return '🏃 Exercise Mode Data (0x5C): unable to parse records (len=${bytes.length})';
        }
        if (records.length == 1) {
          return '🏃 Exercise Mode Data (0x5C)\n${records.first}';
        }
        final buf = StringBuffer(
            '📊 Exercise Mode Data (0x5C) • ${records.length} records\n');
        for (int i = 0; i < records.length; i++) {
          buf.writeln('--- Record ${i + 1} ---');
          buf.writeln(records[i]);
        }
        return buf.toString().trimRight();
      case 0x14: // Real-time Temperature Reading of the Ring
        // Expected 16 bytes with checksum; tolerate >16 by using first 16.
        if (bytes.length >= 16) {
          if (bytes.length > 16) {
            bytes = bytes.sublist(0, 16);
          }
          // Verify checksum if present
          int calc = bytes.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
          if (bytes[15] != calc) {
            // If checksum fails, still attempt to parse payload but mark warning
          }
          // AA BB: highest temp (LE) in tenths of °C
          int highestRaw = bytes[1] | (bytes[2] << 8);
          double highestC = highestRaw / 10.0;
          // CC DD: decimal temperature digits packed as BCD per spec example (e.g., 03 28 -> 32.8)
          int ccDec = _bcdToDecimal(bytes[3]);
          int ddDec = _bcdToDecimal(bytes[4]);
          int decimalDigits = (ccDec * 100) + ddDec; // e.g., 3*100 + 28 = 328
          double decimalC = decimalDigits / 10.0;
          // EE FF, GG HH, II JJ: NTC temps LE in tenths of °C
          int ntc1Raw = bytes[5] | (bytes[6] << 8);
          int ntc2Raw = bytes[7] | (bytes[8] << 8);
          int ntc3Raw = bytes[9] | (bytes[10] << 8);
          double ntc1 = ntc1Raw / 10.0;
          double ntc2 = ntc2Raw / 10.0;
          double ntc3 = ntc3Raw / 10.0;

          return '🌡️ Ring Temperature (0x14):\n'
              '🔥 Highest: ${highestC.toStringAsFixed(1)} °C\n'
              '🔢 Decimal fmt: ${decimalC.toStringAsFixed(1)} °C\n'
              '🧪 NTC1: ${ntc1.toStringAsFixed(1)} °C, '
              'NTC2: ${ntc2.toStringAsFixed(1)} °C, '
              'NTC3: ${ntc3.toStringAsFixed(1)} °C';
        }
        break;

      case 0x2A: // Set measurement interval ACK/response
        if (bytes.length >= 16) {
          int calc = bytes.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
          bool crcOk = (bytes[15] == calc);
          return '✅ Set Measurement Interval (0x2A) ACK\n' +
              (crcOk ? 'CRC OK' : '⚠️ CRC mismatch');
        }
        break;
      case 0x19: // Exercise status response
        // Expected 16 bytes with checksum; some firmwares place a reserved byte after status
        if (bytes.length >= 16) {
          // Optional checksum check
          int calc = bytes.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
          bool crcOk = (bytes[15] == calc);

          int status = bytes[1]; // 0x01 active, 0x00 ended/inactive
          // Layout observed: [0]=0x19, [1]=status, [2]=reserved(0x00), [3..8]=YY MM DD HH mm SS
          int yy = bytes[3];
          int year = (yy == 0x25) ? 2025 : (2000 + _bcdToDecimal(yy));
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          if (status == 0x01) {
            return '🏃 Exercise Status:\n'
                '✅ Exercise mode is ACTIVE\n'
                '🕰️ Started: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
                '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}'
                '${crcOk ? '' : '\n⚠️ CRC mismatch'}';
          } else {
            // If not active, still show last timestamp if any
            bool hasTs = (yy != 0 ||
                bytes[4] != 0 ||
                bytes[5] != 0 ||
                bytes[6] != 0 ||
                bytes[7] != 0 ||
                bytes[8] != 0);
            if (hasTs) {
              return '🏃 Exercise Status:\n'
                  '⏹️ Exercise mode ENDED\n'
                  '🕰️ Last session ended: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
                  '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}'
                  '${crcOk ? '' : '\n⚠️ CRC mismatch'}';
            }
            return '🏃 Exercise Status:\n❌ No active exercise mode';
          }
        }
        break;

      case 0x09: // Real-time Step/HR/SpO2/Temperature response
        // Two possible layouts have been observed.
        // A) 16-byte frame (with checksum): 09 S1 S2 S3 S4 C1 C2 C3 C4 D1 D2 D3 D4 HR T1 T2 [CRC]
        //    Steps S1..S4 LE, Calories C1..C4 LE (kcal*100), Distance D1..D4 LE (km*100), HR, Temp T1T2 LE (0.1°C). SpO2 may be provided via separate frame/field.
        // B) Extended (>=26 bytes) concatenated layout as per doc when not framing; keep legacy parse for backwards compatibility.
        if (bytes.length == 16) {
          // Verify checksum if present (we're called with exactly 16 bytes from checksum framing)
          int calc = bytes.sublist(0, 15).fold(0, (s, b) => s + b) & 0xFF;
          if (bytes[15] == calc) {
            int steps = bytes[1] |
                (bytes[2] << 8) |
                (bytes[3] << 16) |
                (bytes[4] << 24);
            int calRaw = bytes[5] |
                (bytes[6] << 8) |
                (bytes[7] << 16) |
                (bytes[8] << 24);
            double calories = calRaw / 100.0;
            int distRaw = bytes[9] |
                (bytes[10] << 8) |
                (bytes[11] << 16) |
                (bytes[12] << 24);
            double distanceKm = distRaw / 100.0;
            int heartRate = bytes[13];
            int t1 = bytes[14];
            int t2 =
                0; // No room for full temp or SpO2 in 16 payload if CRC occupies last; some firmwares pack temp in 1 byte.
            double temp = t1 / 10.0;
            return '📡 Real-time Mode:\n'
                '🟢 Stream ACTIVE\n'
                '👣 Steps: $steps\n'
                '🔥 Calories: ${calories.toStringAsFixed(2)} kcal\n'
                '📏 Distance: ${distanceKm.toStringAsFixed(2)} km\n'
                '❤️ HR: $heartRate BPM\n'
                '🌡️ Temperature: ${temp.toStringAsFixed(1)} °C';
          }
        } else if (bytes.length >= 26) {
          // Some notifications aggregate extra padding/frames; only use first 26 bytes per doc
          if (bytes.length > 26) {
            bytes = bytes.sublist(0, 26);
          }
          int steps =
              bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
          int calRaw =
              bytes[5] | (bytes[6] << 8) | (bytes[7] << 16) | (bytes[8] << 24);
          double calories = calRaw / 100.0;
          int distRaw = bytes[9] |
              (bytes[10] << 8) |
              (bytes[11] << 16) |
              (bytes[12] << 24);
          double distanceKm = distRaw / 100.0;
          int heartRate = bytes[21];
          int t1 = bytes[22];
          int t2 = bytes[23];
          double tempDelta = (t1 | (t2 << 8)) / 10.0;
          int spo2 = bytes[24];
          return '📡 Real-time Mode:\n'
              '🟢 Stream ACTIVE\n'
              '👣 Steps: $steps\n'
              '🔥 Calories: ${calories.toStringAsFixed(2)} kcal\n'
              '📏 Distance: ${distanceKm.toStringAsFixed(2)} km\n'
              '❤️ HR: $heartRate BPM\n'
              '🌡️ Temperature: ${tempDelta.toStringAsFixed(1)} °C\n'
              '🩸 SpO2: $spo2%';
        }
        break;

      case 0x18: // Exercise data packet (received automatically during exercise)
        if (bytes.length >= 16) {
          int heartRate = bytes[1];
          // S1 S2 S3 S4: Step count (little-endian)
          int steps =
              bytes[2] | (bytes[3] << 8) | (bytes[4] << 16) | (bytes[5] << 24);
          // K1 K2 K3 K4: Calories (IEEE 754 32-bit float, little-endian)
          var caloriesBytes =
              Uint8List.fromList([bytes[6], bytes[7], bytes[8], bytes[9]]);
          double calories =
              ByteData.sublistView(caloriesBytes).getFloat32(0, Endian.little);
          // T1 T2 T3 T4: Exercise duration (little-endian)
          int duration = bytes[10] |
              (bytes[11] << 8) |
              (bytes[12] << 16) |
              (bytes[13] << 24);
          // D1 D2 D3 D4: Distance (IEEE 754 32-bit float, little-endian). Protocol doc lists as D1..D4.
          // Empirically, interpreting as float resolves unrealistic large integers.
          var distanceBytes = Uint8List.fromList([
            bytes[14],
            bytes.length > 15 ? bytes[15] : 0,
            bytes.length > 16 ? bytes[16] : 0,
            bytes.length > 17 ? bytes[17] : 0,
          ]);
          // Treat the float as kilometers and convert to meters (matches observed ranges)
          double distanceKm =
              ByteData.sublistView(distanceBytes).getFloat32(0, Endian.little);
          double distance = distanceKm * 1000.0;

          String status = '';
          if (heartRate == 0xFF) {
            status = '🛑 Exercise mode ended';
          } else {
            status = '🏃 Exercise in progress';
          }

          return '🏃 Live Exercise Data:\n'
              '$status\n'
              '❤️ Heart Rate: ${heartRate == 0xFF ? 'N/A' : '$heartRate BPM'}\n'
              '👣 Steps: $steps\n'
              '🔥 Calories: ${calories.toStringAsFixed(1)} kcal\n'
              '⏱️ Duration: ${(duration / 60).toStringAsFixed(1)} min\n'
              '📏 Distance: ${distance.toStringAsFixed(1)} m';
        }
        break;

      case 0x56: // HRV data response
        if (bytes.length >= 15) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          // Protocol: YY MM DD HH mm SS (direct values, not BCD)
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          int hrv = bytes[9]; // D1: HRV value
          // bytes[10] is always 00 according to protocol
          int heartRate = bytes[11]; // D3: Heart rate value
          int fatigue = bytes[12]; // D4: Fatigue level
          int systolic = bytes[13]; // P1: Systolic blood pressure
          int diastolic = bytes[14]; // P2: Diastolic blood pressure

          return '📊 Health Data:\n'
              '🕒 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '💓 HRV: ${hrv}ms\n'
              '❤️ Heart Rate: ${heartRate} BPM\n'
              '😰 Stress: $fatigue\n'
              '🩸 Blood Pressure: $systolic/$diastolic mmHg\n'
              '📄 Page: $id2, Index: $id1';
        }
        break;

      case 0x42: // Get user info response
        if (bytes.length >= 12) {
          int gender = bytes[1];
          int age = bytes[2];
          int height = bytes[3];
          int weight = bytes[4];
          int stepLength = bytes[5];
          String ringIdAscii = 'N/A';
          if (bytes.length >= 12) {
            final idSlice = bytes.sublist(6, math.min(12, bytes.length));
            // Convert to ASCII, keep printable chars 0x20..0x7E, else replace with '?'
            final chars = idSlice
                .map((b) => (b >= 0x20 && b <= 0x7E) ? b : 0x3F)
                .toList();
            ringIdAscii = String.fromCharCodes(chars).trim();
          }

          return '👤 User Information:\n'
              '⚧️ Gender: ${gender == 0 ? 'Female' : 'Male'}\n'
              '🎂 Age: $age years\n'
              '📏 Height: ${height}cm\n'
              '⚖️ Weight: ${weight}kg\n'
              '👣 Step Length: ${stepLength}cm\n'
              '🆔 Ring ID: $ringIdAscii';
        }
        break;

      case 0x2B: // Get measurement interval response
        if (bytes.length >= 10) {
          int measurementType = bytes[1];
          int workingMode = bytes[2];
          // Time values are BCD; handle observed variant where [6] is 0xFF and endHour sits in [4].
          int startHour = _bcdToDecimal(bytes[3]);
          int startMinute = _bcdToDecimal(bytes[4]);
          int endHour = _bcdToDecimal(bytes[5]);
          int endMinute = _bcdToDecimal(bytes[6]);
          int weekdayBits = bytes[7];
          int intervalMinutes = 0;
          // FF-variant: [6]==0xFF implies layout [3]=startHH, [4]=endHH, [5]=endmm, [6]=FF, [8]=interval(1B)
          if (bytes[6] == 0xFF) {
            startMinute = 0;
            endHour = _bcdToDecimal(bytes[4]);
            endMinute = _bcdToDecimal(bytes[5]);
            intervalMinutes = bytes[8];
          } else {
            // Standard: interval is 16-bit little-endian at [8..9]
            intervalMinutes =
                bytes.length >= 10 ? (bytes[8] | (bytes[9] << 8)) : 0;
          }

          String measurementName = measurementType == 1
              ? 'Heart Rate'
              : measurementType == 2
                  ? 'Blood Oxygen'
                  : measurementType == 4
                      ? 'HRV'
                      : 'Unknown';

          String workingModeStr = workingMode == 0
              ? 'Off'
              : workingMode == 2
                  ? 'Interval Mode'
                  : 'Unknown';

          List<String> enabledDays = [];
          List<String> dayNames = [
            'Sun',
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat'
          ];
          for (int i = 0; i < 7; i++) {
            if ((weekdayBits & (1 << i)) != 0) {
              enabledDays.add(dayNames[i]);
            }
          }

          return '⏰ Measurement Settings ($measurementName):\n'
              '🔧 Mode: $workingModeStr\n'
              '🕐 Time: ${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')} - ${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}\n'
              '📅 Days: ${enabledDays.join(', ')}\n'
              '⏱️ Interval: ${intervalMinutes} minutes';
        }
        break;

      case 0x01: // Set time response
        final mtu = bytes.length > 1 ? bytes[1] : null;
        return mtu != null
            ? '✅ Ring time synced successfully\n📶 Reported MTU: $mtu bytes'
            : '✅ Ring time synced successfully';

      case 0x81: // Error response for set time
        return '❌ Failed to sync ring time';

      case 0x02: // Set user info response
        return '✅ User information set successfully';

      case 0x82: // Error response for set user info
        return '❌ Failed to set user information';

      case 0xC2: // Error response for get user info
        return '❌ Failed to get user information';

      case 0x41: // Get time response
        if (bytes.length >= 8) {
          // Parse according to protocol: YY MM DD HH mm SS WD
          // All values are in BCD format (e.g., 0x25 = 25 -> 2025, 0x10 = 10)
          int year = 2000 + _bcdToDecimal(bytes[1]);
          int month = _bcdToDecimal(bytes[2]);
          int day = _bcdToDecimal(bytes[3]);
          int hour = _bcdToDecimal(bytes[4]);
          int minute = _bcdToDecimal(bytes[5]);
          int second = _bcdToDecimal(bytes[6]);

          // Note: Weekday byte (bytes[7]) is ignored as Smart Ring's weekday may be incorrect

          return '🕐 Ring Time:\n'
              '📅 Date: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}\n'
              '⏰ Time: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
        }
        break;

      case 0x13: // Get battery response
        if (bytes.length >= 8) {
          // AA: Battery level (in hexadecimal), value from 0 to 100
          // BB: Charging status, 1 means charging, 0 means not charging
          // CC DD: Voltage value, in decimal format (BCD)
          int batteryLevel = bytes[1]; // Raw hex value 0-100
          int chargingStatus = bytes[2];

          // Voltage values are in BCD format like other protocol values
          double voltageCC =
              _bcdToDecimal(bytes[3]) / 10.0; // CC in BCD -> X.Y volts
          double voltageDD =
              _bcdToDecimal(bytes[4]) / 10.0; // DD in BCD -> X.Y volts

          return '🔋 Battery Status:\n'
              '⚡ Level: ${batteryLevel}%\n'
              '🔌 Charging: ${chargingStatus == 1 ? 'Yes' : 'No'}\n'
              '⚡ Voltage 1: ${voltageCC.toStringAsFixed(1)}V\n'
              '⚡ Voltage 2: ${voltageDD.toStringAsFixed(1)}V\n'
              '🔍 Raw: 0x${bytes[3].toRadixString(16).padLeft(2, '0')} 0x${bytes[4].toRadixString(16).padLeft(2, '0')}';
        }
        break;

      case 0x22: // Get MAC address response
        if (bytes.length >= 8) {
          String macAddress = bytes
              .sublist(1, 7)
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(':');

          return '📍 MAC Address:\n'
              '🔗 Address: $macAddress';
        }
        break;

      case 0x27: // Get firmware version response
        if (bytes.length >= 8) {
          // AA BB CC DD represent the software version number (in hexadecimal BCD format)
          // EE FF GG represent the corresponding time in year, month, and day
          int versionA = _bcdToDecimal(bytes[1]);
          int versionB = _bcdToDecimal(bytes[2]);
          int versionC = _bcdToDecimal(bytes[3]);
          int versionD = _bcdToDecimal(bytes[4]);
          int year = 2000 + _bcdToDecimal(bytes[5]);
          int month = _bcdToDecimal(bytes[6]);
          int day = _bcdToDecimal(bytes[7]);

          return '🔧 Firmware Info:\n'
              '📱 Version: $versionA.$versionB.$versionC.$versionD\n'
              '📅 Build Date: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
        break;

      case 0x51: // Get total step count response
        if (bytes.length >= 27) {
          int id = bytes[1];
          // Protocol: YY MM DD (direct values, not BCD)
          int year = 2000 + _bcdToDecimal(bytes[2]);
          int month = _bcdToDecimal(bytes[3]);
          int day = _bcdToDecimal(bytes[4]);

          // Little-endian format: S1 S2 S3 S4, T1 T2 T3 T4, D1 D2 D3 D4, K1 K2 K3 K4
          int steps =
              (bytes[8] << 24) | (bytes[7] << 16) | (bytes[6] << 8) | bytes[5];
          int exerciseTime = (bytes[12] << 24) |
              (bytes[11] << 16) |
              (bytes[10] << 8) |
              bytes[9];
          int distance = (bytes[16] << 24) |
              (bytes[15] << 16) |
              (bytes[14] << 8) |
              bytes[13];
          int calories = (bytes[20] << 24) |
              (bytes[19] << 16) |
              (bytes[18] << 8) |
              bytes[17];

          return '👣 Total Step Count:\n'
              '📅 Date: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}\n'
              '🚶 Steps: ${steps.toString()}\n'
              '⏱️ Exercise Time: ${exerciseTime}s\n'
              '📏 Distance: ${(distance / 100.0).toStringAsFixed(2)} km\n'
              '🔥 Calories: ${(calories / 100.0).toStringAsFixed(2)} kcal\n'
              '🏷️ ID: $id';
        }
        break;

      case 0x52: // Get detailed step count response (variable length)
        if (bytes.length >= 25) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          // For command 0x52, time values are used directly (not BCD)
          // Format: YY MM DD HH mm SS (direct values)
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);
          int totalSteps = (bytes[10] << 8) | bytes[9]; // Little-endian
          int calories = (bytes[12] << 8) | bytes[11];
          int distance = (bytes[14] << 8) | bytes[13];

          // Step counts for each minute (up to 10 minutes)
          List<int> minuteSteps = [];
          for (int i = 15; i < bytes.length && i < 25; i++) {
            if (bytes[i] > 0) minuteSteps.add(bytes[i]);
          }

          return '📊 Detailed Step Count:\n'
              '📅 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '🚶 Total Steps: $totalSteps\n'
              '🔥 Calories: ${(calories / 100.0).toStringAsFixed(2)} kcal\n'
              '📏 Distance: ${(distance / 100.0).toStringAsFixed(2)} km\n'
              '📈 Per Minute: ${minuteSteps.join(', ')}';
        }
        break;

      case 0x53: // Get sleep data response (variable length)
        if (bytes.length >= 130) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          // Protocol: YY MM DD HH mm SS (direct values, not BCD)
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          int validLength = bytes[9];

          // Sleep quality data (1=Deep, 2=Light, 3=REM, others=Awake)
          List<String> sleepStages = [];
          int deepSleep = 0, lightSleep = 0, remSleep = 0, awake = 0;

          for (int i = 10; i < 10 + validLength && i < bytes.length; i++) {
            switch (bytes[i]) {
              case 1:
                sleepStages.add('💤');
                deepSleep++;
                break;
              case 2:
                sleepStages.add('😴');
                lightSleep++;
                break;
              case 3:
                sleepStages.add('🌙');
                remSleep++;
                break;
              default:
                sleepStages.add('😐');
                awake++;
                break;
            }
          }

          return '😴 Sleep Data:\n'
              '📅 Start: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '⏱️ Duration: ${validLength} minutes\n'
              '💤 Deep: ${deepSleep}min, 😴 Light: ${lightSleep}min\n'
              '🌙 REM: ${remSleep}min, 😐 Awake: ${awake}min\n'
              '📊 Pattern: ${sleepStages.take(20).join('')}${sleepStages.length > 20 ? '...' : ''}\n'
              '🏷️ ID: $id1-$id2';
        }
        break;

      case 0x54: // Get detailed heart rate response (variable length)
        if (bytes.length >= 21) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          // Heart rate values every 5 seconds (SD1-SD15, exactly 15 values = 75 seconds)
          List<int> heartRates = [];
          for (int i = 9; i < 24 && i < bytes.length; i++) {
            heartRates
                .add(bytes[i]); // Include all values, even 0 (no filtering)
          }

          // Calculate stats only from non-zero values
          List<int> validRates = heartRates.where((hr) => hr > 0).toList();
          double avgHR = validRates.isNotEmpty
              ? validRates.reduce((a, b) => a + b) / validRates.length
              : 0;
          int minHR = validRates.isNotEmpty
              ? validRates.reduce((a, b) => a < b ? a : b)
              : 0;
          int maxHR = validRates.isNotEmpty
              ? validRates.reduce((a, b) => a > b ? a : b)
              : 0;

          return '❤️ Detailed Heart Rate:\n'
              '📅 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '⏱️ Duration: 75 seconds (15 readings @ 5s intervals)\n'
              '📊 Avg: ${avgHR.toStringAsFixed(1)} BPM (${validRates.length}/15 valid)\n'
              '📈 Range: $minHR - $maxHR BPM\n'
              '🔢 Values: ${heartRates.join(', ')}\n'
              '🏷️ ID: $id1-$id2';
        }
        break;

      case 0x55: // Get heart rate history response (variable length)
        if (bytes.length >= 10) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          int heartRate = bytes[9];
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          return '💓 Heart Rate History:\n'
              '📅 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '❤️ Heart Rate: $heartRate BPM';
        }
        break;

      case 0x62: // Get temperature data response (variable length)
        if (bytes.length >= 15) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          // Temperature values in little-endian format (divide by 10 for °C)
          List<double> temperatures = [];
          for (int i = 9; i < bytes.length - 1; i += 2) {
            if (i + 1 < bytes.length) {
              int tempRaw = (bytes[i + 1] << 8) | bytes[i]; // Little-endian
              temperatures.add(tempRaw / 10.0);
            }
          }

          double avgTemp = temperatures.isNotEmpty
              ? temperatures.reduce((a, b) => a + b) / temperatures.length
              : 0;

          return '🌡️ Temperature Data:\n'
              '📅 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '🌡️ Average: ${avgTemp.toStringAsFixed(1)}°C\n'
              '📊 Readings: ${temperatures.map((t) => '${t.toStringAsFixed(1)}°C').take(5).join(', ')}${temperatures.length > 5 ? '...' : ''}';
        }
        break;

      case 0x66: // Get blood oxygen data response (variable length)
        if (bytes.length >= 10) {
          int id1 = bytes[1];
          int id2 = bytes[2];
          int year = 2000 + _bcdToDecimal(bytes[3]);
          int month = _bcdToDecimal(bytes[4]);
          int day = _bcdToDecimal(bytes[5]);
          int hour = _bcdToDecimal(bytes[6]);
          int minute = _bcdToDecimal(bytes[7]);
          int second = _bcdToDecimal(bytes[8]);

          int bloodOxygen = bytes[9];

          String oxygenStatus = bloodOxygen >= 95
              ? '✅ Normal'
              : bloodOxygen >= 90
                  ? '⚠️ Low'
                  : '🚨 Critical';

          return '🩸 Blood Oxygen Data:\n'
              '📅 Time: $year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}\n'
              '🫁 SpO2: $bloodOxygen%\n'
              '📊 Status: $oxygenStatus';
        }
        break;

      // Error responses
      case 0x93: // Battery command error
        return '❌ Failed to get battery level';
      case 0xA2: // MAC address command error
        return '❌ Failed to get MAC address';
      case 0xA7: // Firmware version command error
        return '❌ Failed to get firmware version';

      default:
        return '📦 Raw response (Command: 0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()})';
    }

    return '📦 Unknown response format';
  }

  List<int> _parseHexString(String hexString) {
    // Remove spaces and dashes
    String cleanHex = hexString.replaceAll(RegExp(r'[\s\-]'), '');

    // Ensure even length
    if (cleanHex.length % 2 != 0) {
      throw Exception('Invalid hex string length');
    }

    List<int> bytes = [];
    for (int i = 0; i < cleanHex.length; i += 2) {
      String hexByte = cleanHex.substring(i, i + 2);
      bytes.add(int.parse(hexByte, radix: 16));
    }

    return bytes;
  }

  // Public disconnect method
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _writeCharacteristic = null;
      _connectionStatusController.add('Disconnected');
    }
  }

  // Public method to start scanning
  Future<void> startScan() async {
    await scanAndConnect();
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _connectedDevice?.disconnect();
    _connectionStatusController.close();
    _messageController.close();
  }
}

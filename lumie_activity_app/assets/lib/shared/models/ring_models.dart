// Ring data models for Lumie App
// Matches the BLE protocol described in SMART_RING_PROTOCOL.md

enum RingConnectionStatus {
  connected,
  disconnected,
  neverPaired;

  String get displayName {
    switch (this) {
      case RingConnectionStatus.connected:
        return 'Connected';
      case RingConnectionStatus.disconnected:
        return 'Disconnected';
      case RingConnectionStatus.neverPaired:
        return 'Not paired';
    }
  }
}

/// Paired ring information stored in user profile and locally
class RingInfo {
  final String? ringDeviceId;   // Unique hardware identifier (MAC address)
  final String? ringName;       // Display name (e.g., "Lumie Ring A3F2")
  final RingConnectionStatus connectionStatus;
  final DateTime? pairedAt;
  final DateTime? lastSyncAt;
  final String? firmwareVersion;
  final int? batteryLevel;      // 0–100 percent

  const RingInfo({
    this.ringDeviceId,
    this.ringName,
    this.connectionStatus = RingConnectionStatus.neverPaired,
    this.pairedAt,
    this.lastSyncAt,
    this.firmwareVersion,
    this.batteryLevel,
  });

  bool get isPaired => ringDeviceId != null;

  factory RingInfo.fromJson(Map<String, dynamic> json) {
    return RingInfo(
      ringDeviceId: json['ring_device_id'] as String?,
      ringName: json['ring_name'] as String?,
      connectionStatus: _parseStatus(json['connection_status'] as String?),
      pairedAt: json['paired_at'] != null
          ? DateTime.parse(json['paired_at'] as String)
          : null,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      firmwareVersion: json['firmware_version'] as String?,
      batteryLevel: json['battery_level'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ring_device_id': ringDeviceId,
      'ring_name': ringName,
      'connection_status': connectionStatus.name,
      'paired_at': pairedAt?.toIso8601String(),
      'last_sync_at': lastSyncAt?.toIso8601String(),
      'firmware_version': firmwareVersion,
      'battery_level': batteryLevel,
    };
  }

  static RingConnectionStatus _parseStatus(String? value) {
    switch (value) {
      case 'connected':
        return RingConnectionStatus.connected;
      case 'disconnected':
        return RingConnectionStatus.disconnected;
      default:
        return RingConnectionStatus.neverPaired;
    }
  }

  RingInfo copyWith({
    String? ringDeviceId,
    String? ringName,
    RingConnectionStatus? connectionStatus,
    DateTime? pairedAt,
    DateTime? lastSyncAt,
    String? firmwareVersion,
    int? batteryLevel,
  }) {
    return RingInfo(
      ringDeviceId: ringDeviceId ?? this.ringDeviceId,
      ringName: ringName ?? this.ringName,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }
}

/// A discovered BLE ring device during scanning
class DiscoveredRing {
  final String deviceId;     // BLE device ID
  final String displayName;  // User-friendly name
  final int rssi;            // Signal strength

  const DiscoveredRing({
    required this.deviceId,
    required this.displayName,
    required this.rssi,
  });

  String get signalLabel {
    if (rssi >= -60) return 'Excellent';
    if (rssi >= -75) return 'Good';
    if (rssi >= -90) return 'Fair';
    return 'Weak';
  }

  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -90) return 2;
    return 1;
  }
}

/// Raw sleep session data parsed from ring command 0x53.
/// One record = one contiguous sleep session.
class RingRawSleepRecord {
  final DateTime sessionStart;  // BCD timestamp from ring
  final DateTime sessionEnd;    // sessionStart + N minutes
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int awakeMinutes;
  final int id1;   // ring record index byte — used for deduplication
  final int id2;   // ring page byte — used for deduplication

  const RingRawSleepRecord({
    required this.sessionStart,
    required this.sessionEnd,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    this.id1 = 0,
    this.id2 = 0,
  });

  int get totalSleepMinutes => lightMinutes + deepMinutes + remMinutes;
  int get totalMinutes => totalSleepMinutes + awakeMinutes;
}

/// Raw daily step record parsed from ring command 0x51.
/// One record = one calendar day (ID=0 today, ID=1 yesterday, etc.).
/// The ring resets today's counters at midnight automatically.
class RingRawDailySteps {
  final DateTime date;            // local calendar date from ring BCD
  final int steps;
  final int exerciseTimeSeconds;  // ring's active-movement time for the day
  final double distanceKm;

  const RingRawDailySteps({
    required this.date,
    required this.steps,
    required this.exerciseTimeSeconds,
    required this.distanceKm,
  });
}

/// Raw HRV / stress / blood pressure record from ring command 0x56.
/// One record = one measurement snapshot (ring takes these periodically).
class RingRawHrvRecord {
  final DateTime timestamp;   // BCD timestamp from ring
  final int hrvMs;            // Heart rate variability in milliseconds
  final int heartRateBpm;     // Heart rate at time of measurement
  final int fatigue;          // Stress / fatigue level (0–100)
  final int systolicMmhg;     // Systolic blood pressure
  final int diastolicMmhg;    // Diastolic blood pressure

  const RingRawHrvRecord({
    required this.timestamp,
    required this.hrvMs,
    required this.heartRateBpm,
    required this.fatigue,
    required this.systolicMmhg,
    required this.diastolicMmhg,
  });
}

/// Temperature record from ring command 0x62.
/// One record = one snapshot with 3 sensor readings.
class RingRawTemperatureRecord {
  final DateTime timestamp;
  final double temp1C;
  final double temp2C;
  final double temp3C;

  const RingRawTemperatureRecord({
    required this.timestamp,
    required this.temp1C,
    required this.temp2C,
    required this.temp3C,
  });
}

/// SpO2 (blood oxygen) record from ring command 0x66.
/// One record = one measurement snapshot.
class RingRawSpo2Record {
  final DateTime timestamp;
  final int spo2Percent;   // Oxygen saturation 0–100%

  const RingRawSpo2Record({
    required this.timestamp,
    required this.spo2Percent,
  });
}

/// Live temperature reading from ring command 0x14.
/// One snapshot with highest temp + three NTC sensor values.
class RingLiveTemperature {
  final double highestTempC;   // Highest of the three sensors
  final double ntc1C;
  final double ntc2C;
  final double ntc3C;

  const RingLiveTemperature({
    required this.highestTempC,
    required this.ntc1C,
    required this.ntc2C,
    required this.ntc3C,
  });
}

/// Ring clock info from command 0x41.
class RingTimeInfo {
  final DateTime ringTime;   // Current time as stored on the ring
  final int weekday;         // 1=Mon … 7=Sun
  final int maxMtu;

  const RingTimeInfo({
    required this.ringTime,
    required this.weekday,
    required this.maxMtu,
  });
}

/// User info stored on the ring from command 0x42.
class RingUserInfo {
  final int gender;      // 0=female, 1=male
  final int age;
  final int heightCm;
  final int weightKg;
  final int stepLengthCm;
  final String ringId;   // 6-char ASCII ring identifier

  const RingUserInfo({
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.stepLengthCm,
    required this.ringId,
  });
}

/// Detailed per-minute step record from ring command 0x52.
/// One record = one time slot with 10 per-minute step readings.
class RingDetailedStepRecord {
  final DateTime timestamp;
  final int steps;
  final int calories;
  final double distanceKm;
  final List<int> perMinuteSteps;   // 10 one-minute buckets

  const RingDetailedStepRecord({
    required this.timestamp,
    required this.steps,
    required this.calories,
    required this.distanceKm,
    required this.perMinuteSteps,
  });
}

/// Exercise session record from ring command 0x5C.
class RingExerciseRecord {
  final DateTime startTime;
  final int exerciseType;       // Ring exercise type code
  final int avgHeartRate;
  final int durationSeconds;
  final int steps;
  final double paceMinPerKm;
  final double calories;
  final double distanceKm;

  const RingExerciseRecord({
    required this.startTime,
    required this.exerciseType,
    required this.avgHeartRate,
    required this.durationSeconds,
    required this.steps,
    required this.paceMinPerKm,
    required this.calories,
    required this.distanceKm,
  });
}

/// Measurement interval config from ring command 0x2B.
class RingMeasurementInterval {
  final int measureType;      // 1=HR, 2=SpO2, 3=Temperature, 4=HRV/BP
  final int mode;             // 0=off, 1=manual, 2=auto
  final int intervalMinutes;  // Auto-measurement interval
  final int weekdayBits;      // Bitmask: bit0=Mon … bit6=Sun
  final String startTime;     // "HH:mm"
  final String endTime;       // "HH:mm"

  const RingMeasurementInterval({
    required this.measureType,
    required this.mode,
    required this.intervalMinutes,
    required this.weekdayBits,
    required this.startTime,
    required this.endTime,
  });
}

/// Result of a live HR measurement (command 0x28 + 0x09 for N seconds).
class RingHrMeasurementResult {
  final int avgBpm;
  final int minBpm;
  final int maxBpm;
  final int durationSeconds;
  final List<int> readings;   // Individual readings during measurement

  const RingHrMeasurementResult({
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.durationSeconds,
    required this.readings,
  });
}

/// Real-time data streamed from ring (command 0x09)
class RingStreamData {
  final int steps;
  final double calories;
  final double distanceKm;
  final int heartRate;
  final double temperature;
  final int? spo2;

  const RingStreamData({
    required this.steps,
    required this.calories,
    required this.distanceKm,
    required this.heartRate,
    required this.temperature,
    this.spo2,
  });
}

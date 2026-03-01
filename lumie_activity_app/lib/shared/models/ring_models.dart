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

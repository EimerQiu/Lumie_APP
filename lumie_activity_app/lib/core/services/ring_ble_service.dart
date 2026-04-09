// BLE communication service for the Lumie Smart Ring (X6B)
// Protocol details: see docs/SMART_RING_PROTOCOL.md
//
// GATT Service:    0000fff0-0000-1000-8000-00805f9b34fb
// Write char:      0000fff6-0000-1000-8000-00805f9b34fb
// Notify char:     0000fff7-0000-1000-8000-00805f9b34fb

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../shared/models/ring_models.dart';
import '../../shared/models/heart_rate_models.dart';
import 'ring_service.dart';

class RingBleService {
  final RingService _ringService = RingService();
  static const String _writeCharFragment = 'fff6';
  static const String _notifyCharFragment = 'fff7';

  // Scan timeout per PRD: 30 seconds
  static const Duration _scanTimeout = Duration(seconds: 30);
  // Response wait timeout
  static const Duration _responseTimeout = Duration(seconds: 5);

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySubscription;

  // HR streaming state (command 0x09)
  StreamController<int>? _hrStreamController;
  StreamSubscription<List<int>>? _hrStreamSub;

  // Connection state monitoring
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  VoidCallback? onDisconnected;

  // Keep-alive timer (command 0x2A sent every 30 seconds while connected)
  Timer? _keepAliveTimer;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  bool get isConnected => _connectedDevice != null && _writeChar != null;
  String? get connectedBleDeviceId => _connectedDevice?.remoteId.str;
  String? get connectedBleDeviceName => _connectedDevice?.platformName;

  // ─── Scanning ────────────────────────────────────────────────────────────

  bool _isX6bName(String name) => name.toUpperCase().startsWith('X6B');

  bool _isLikelyRing(ScanResult result) {
    final platformName = result.device.platformName;
    final advName = result.advertisementData.advName;
    return _isX6bName(platformName) || _isX6bName(advName);
  }

  String _displayNameForResult(ScanResult result) {
    final platformName = result.device.platformName.trim();
    if (platformName.isNotEmpty) return platformName;
    final advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) return advName;
    return result.device.remoteId.str;
  }

  /// Scan for nearby Lumie Rings (filtered by device name prefix "X6B").
  Future<void> startScan({
    required void Function(DiscoveredRing ring) onFound,
    required void Function() onTimeout,
  }) async {
    debugPrint('[Ring BLE] startScan: stopping any existing scan');
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    final found = <String>{};

    // Subscribe before starting scan so we don't miss early advertisements.
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!_isLikelyRing(result)) continue;

        final id = result.device.remoteId.str;
        if (found.contains(id)) continue;
        found.add(id);
        final displayName = _displayNameForResult(result);

        debugPrint(
          '[Ring BLE] Found ring: $displayName ($id) RSSI=${result.rssi}',
        );
        onFound(
          DiscoveredRing(
            deviceId: id,
            displayName: displayName,
            rssi: result.rssi,
          ),
        );
      }
    });

    await FlutterBluePlus.startScan(timeout: _scanTimeout);

    try {
      await FlutterBluePlus.isScanning
          .where((s) => !s)
          .first
          .timeout(
            _scanTimeout + const Duration(seconds: 2),
            onTimeout: () => false,
          );
    } finally {
      await _scanResultsSub?.cancel();
      _scanResultsSub = null;
    }
    debugPrint('[Ring BLE] Scan complete, found ${found.length} ring(s)');
    onTimeout();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
  }

  // ─── Connection ──────────────────────────────────────────────────────────

  /// Connect to a discovered ring device and perform handshake.
  Future<RingInfo> connectAndPair({
    required DiscoveredRing ring,
    required int gender,
    required int age,
    required int heightCm,
    required int weightKg,
  }) async {
    debugPrint(
      '[Ring BLE] connectAndPair: ${ring.deviceId} (${ring.displayName})',
    );
    final device = BluetoothDevice.fromId(ring.deviceId);

    await device.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 15),
    );
    _connectedDevice = device;
    debugPrint('[Ring BLE] BLE connected to ${ring.deviceId}');

    final services = await device.discoverServices();
    debugPrint('[Ring BLE] Discovered ${services.length} services');
    BluetoothService? lumieService;
    for (final s in services) {
      if (s.serviceUuid.str.toLowerCase().contains('fff0')) {
        lumieService = s;
        break;
      }
    }
    if (lumieService == null) {
      debugPrint('[Ring BLE] ERROR: Lumie service (fff0) not found');
      await disconnect();
      throw Exception('Not a Lumie Ring: required service not found.');
    }

    for (final c in lumieService.characteristics) {
      final uuid = c.characteristicUuid.str.toLowerCase();
      if (uuid.contains(_writeCharFragment)) _writeChar = c;
      if (uuid.contains(_notifyCharFragment)) _notifyChar = c;
    }

    if (_writeChar == null || _notifyChar == null) {
      debugPrint('[Ring BLE] ERROR: write/notify characteristics not found');
      await disconnect();
      throw Exception('Not a Lumie Ring: required characteristics not found.');
    }
    debugPrint('[Ring BLE] Write char: ${_writeChar!.characteristicUuid}');
    debugPrint('[Ring BLE] Notify char: ${_notifyChar!.characteristicUuid}');

    await _notifyChar!.setNotifyValue(true);
    debugPrint('[Ring BLE] Notifications enabled');
    _subscribeRawNotifyLog();

    final timeSynced = await setTime();
    debugPrint('[Ring BLE] Time sync ${timeSynced ? "ok" : "failed"} (0x01)');

    final mac = await _getMacAddress();
    debugPrint('[Ring BLE] MAC address: $mac');

    await setUserInfo(
      gender: gender,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
    );
    debugPrint(
      '[Ring BLE] User info set (0x02): gender=$gender age=$age h=${heightCm}cm w=${weightKg}kg',
    );

    final firmwareVersion = await _getFirmwareVersion();
    debugPrint('[Ring BLE] Firmware: $firmwareVersion');

    final batteryLevel = await _getBatteryLevel();
    debugPrint('[Ring BLE] Battery: $batteryLevel%');

    final macFormatted = mac ?? ring.deviceId;
    final ringName =
        'Lumie Ring ${macFormatted.length >= 5 ? macFormatted.substring(macFormatted.length - 5).replaceAll(':', '') : macFormatted}';

    _subscribeToConnectionState(device);
    _startKeepAlive();
    debugPrint('[Ring BLE] Pairing complete: $ringName');

    return RingInfo(
      ringDeviceId: macFormatted,
      ringName: ringName,
      connectionStatus: RingConnectionStatus.connected,
      pairedAt: DateTime.now(),
      firmwareVersion: firmwareVersion,
      batteryLevel: batteryLevel,
    );
  }

  Future<void> disconnect() async {
    debugPrint('[Ring BLE] disconnect called');
    _stopKeepAlive();
    // Cancel connection state subscription first to avoid spurious callbacks
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    await _hrStreamSub?.cancel();
    _hrStreamSub = null;
    await _hrStreamController?.close();
    _hrStreamController = null;
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    try {
      if (_notifyChar != null) {
        await _notifyChar!.setNotifyValue(false);
      }
    } catch (_) {}
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _writeChar = null;
    _notifyChar = null;
    debugPrint('[Ring BLE] Disconnected and cleaned up');
  }

  void _subscribeToConnectionState(BluetoothDevice device) {
    // Cancel previous subscription before creating new one
    _connectionStateSub?.cancel();
    _connectionStateSub = device.connectionState.listen((state) {
      debugPrint('[Ring BLE] Connection state changed: $state');
      if (state == BluetoothConnectionState.disconnected) {
        _stopKeepAlive();
        // Cancel subscription BEFORE nulling it, so it's properly disposed
        _connectionStateSub?.cancel();
        _connectionStateSub = null;
        _writeChar = null;
        _notifyChar = null;
        _connectedDevice = null;
        debugPrint('[Ring BLE] Unexpected disconnect — notifying provider');
        onDisconnected?.call();
      }
    });
  }

  // ─── Keep-alive (command 0x2A) ────────────────────────────────────────────

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendActivityPing();
    });
    debugPrint('[Ring BLE] Keep-alive timer started (0x2A every 30s)');
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Command 0x2A — Request current activity data (step count ping).
  /// Fire-and-forget; ring responds asynchronously via notify channel.
  void _sendActivityPing() {
    if (_writeChar == null) return;
    final payload = List<int>.filled(15, 0);
    payload[0] = 0x2A;
    _writeCommand(payload).catchError((e) {
      debugPrint('[Ring BLE] 0x2A ping error: $e');
    });
  }

  /// Public wrapper so the provider can read battery level after reconnect.
  Future<int?> fetchBatteryLevel() => _getBatteryLevel();

  /// Scan-based reconnect fallback — used when [reconnect] fails.
  /// Scans for up to 10 s looking for an X6B ring. Prefers an exact device-ID
  /// match; falls back to the first X6B found (covers iOS where the platform
  /// device ID is a CoreBluetooth UUID rather than the MAC address).
  Future<void> scanAndReconnect(String storedDeviceId) async {
    debugPrint('[Ring BLE] scanAndReconnect: scanning for $storedDeviceId');
    await FlutterBluePlus.stopScan();

    String? firstX6bId;
    final exactMatch = Completer<String>();
    StreamSubscription<List<ScanResult>>? scanSub;

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!_isLikelyRing(result)) continue;
        final id = result.device.remoteId.str;
        firstX6bId ??= id;
        if (id == storedDeviceId && !exactMatch.isCompleted) {
          exactMatch.complete(id);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    String deviceId;
    try {
      deviceId = await exactMatch.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      final fallback = firstX6bId;
      if (fallback == null) throw Exception('Ring not found during scan');
      debugPrint(
        '[Ring BLE] scanAndReconnect: no exact match, using first X6B ($fallback)',
      );
      deviceId = fallback;
    } finally {
      await scanSub.cancel();
      await FlutterBluePlus.stopScan();
    }

    debugPrint('[Ring BLE] scanAndReconnect: found $deviceId — connecting');
    await reconnect(deviceId);
  }

  /// Scan-based reconnect by advertised BLE device name.
  /// Useful on iOS where the platform device ID may change across launches.
  Future<void> scanAndReconnectByName(String storedDeviceName) async {
    debugPrint(
      '[Ring BLE] scanAndReconnectByName: scanning for $storedDeviceName',
    );
    await FlutterBluePlus.stopScan();

    String? firstX6bId;
    final exactMatch = Completer<String>();
    StreamSubscription<List<ScanResult>>? scanSub;

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!_isLikelyRing(result)) continue;
        final name = result.device.platformName;
        final advName = result.advertisementData.advName;
        final id = result.device.remoteId.str;
        firstX6bId ??= id;
        final sameName =
            name == storedDeviceName || advName == storedDeviceName;
        if (sameName && !exactMatch.isCompleted) {
          exactMatch.complete(id);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    String deviceId;
    try {
      deviceId = await exactMatch.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      final fallback = firstX6bId;
      if (fallback == null) throw Exception('Ring not found during scan');
      debugPrint(
        '[Ring BLE] scanAndReconnectByName: no exact name match, using first X6B ($fallback)',
      );
      deviceId = fallback;
    } finally {
      await scanSub.cancel();
      await FlutterBluePlus.stopScan();
    }

    debugPrint(
      '[Ring BLE] scanAndReconnectByName: found $deviceId — connecting',
    );
    await reconnect(deviceId);
  }

  /// Reconnect to a previously paired ring by device ID (no full handshake).
  /// Discovers GATT, enables notifications, and re-syncs time.
  Future<void> reconnect(String deviceId) async {
    debugPrint('[Ring BLE] reconnect: $deviceId');
    final device = BluetoothDevice.fromId(deviceId);

    // Cancel stale connection state sub before connecting
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;

    await device.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 10),
    );
    _connectedDevice = device;
    debugPrint('[Ring BLE] BLE reconnected to $deviceId');

    final services = await device.discoverServices();
    BluetoothService? lumieService;
    for (final s in services) {
      if (s.serviceUuid.str.toLowerCase().contains('fff0')) {
        lumieService = s;
        break;
      }
    }
    if (lumieService == null) {
      debugPrint('[Ring BLE] ERROR: service not found during reconnect');
      await disconnect();
      throw Exception('Service not found during reconnect');
    }

    for (final c in lumieService.characteristics) {
      final uuid = c.characteristicUuid.str.toLowerCase();
      if (uuid.contains(_writeCharFragment)) _writeChar = c;
      if (uuid.contains(_notifyCharFragment)) _notifyChar = c;
    }

    if (_writeChar == null || _notifyChar == null) {
      debugPrint(
        '[Ring BLE] ERROR: characteristics not found during reconnect',
      );
      await disconnect();
      throw Exception('Characteristics not found during reconnect');
    }

    await _notifyChar!.setNotifyValue(true);
    _subscribeRawNotifyLog();
    final timeSynced = await setTime();
    debugPrint(
      '[Ring BLE] Reconnect complete, time sync ${timeSynced ? "ok" : "failed"}',
    );
    _subscribeToConnectionState(device);
    _startKeepAlive();
  }

  // ─── Heart Rate ───────────────────────────────────────────────────────────

  /// Command 0x55 — Fetch stored HR history from the ring with timestamp filter.
  Future<List<HrDataPoint>> fetchHrHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrHistory: not connected');
      return [];
    }

    // Get last sync timestamp or use epoch
    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchHrHistory: last sync at $lastSync, sending 0x55',
    );

    final results = <HrDataPoint>[];
    final completer = Completer<List<HrDataPoint>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x55) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint(
          '[Ring BLE] HR history end marker — ${results.length} record(s)',
        );
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 10) return;

      final hr = data[9];
      if (hr == 0 || hr >= 250) return;

      final recordTime = _parseRingTimestamp(data, 3);
      if (recordTime == null) return;

      if (recordTime.isAfter(lastSync)) {
        results.add(HrDataPoint(time: recordTime, bpm: hr));
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x55;
      payload[1] = 0x00; // First request (AA=0x00)

      // Encode timestamp as BCD at bytes [3-8]
      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      final newRecords = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
            '[Ring BLE] HR history timeout, got ${results.length} records',
          );
          return results;
        },
      );

      // Update sync timestamp to now
      if (newRecords.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }
      return newRecords;
    } catch (e) {
      debugPrint('[Ring BLE] fetchHrHistory error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Command 0x55 (paged) — Fetch HR history in [start, end] range.
  /// Uses AA=0x00 for first page and AA=0x02 for continuation pages.
  Future<List<HrDataPoint>> fetchHrHistoryRange({
    required DateTime start,
    DateTime? end,
  }) async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrHistoryRange: not connected');
      return [];
    }

    final results = <HrDataPoint>[];
    const maxPages = 20;
    var aa = 0x00;

    for (var page = 0; page < maxPages; page++) {
      final pageResult = await _fetchHrHistoryPage(
        aa: aa,
        start: start,
        end: end,
      );
      results.addAll(pageResult.points);
      if (pageResult.endReached || pageResult.points.isEmpty) break;
      aa = 0x02;
    }

    return results;
  }

  /// Command 0x56 — Fetch stored HRV / stress / blood pressure history with timestamp filter.
  Future<List<RingRawHrvRecord>> fetchHrvHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrvHistory: not connected');
      return [];
    }

    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchHrvHistory: last sync at $lastSync, sending 0x56',
    );

    final results = <RingRawHrvRecord>[];
    final completer = Completer<List<RingRawHrvRecord>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x56) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint(
          '[Ring BLE] HRV history end marker — ${results.length} record(s)',
        );
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 15) return;
      if (data[10] != 0x00) return;

      final timestamp = _parseRingTimestamp(data, 3);
      if (timestamp == null || !timestamp.isAfter(lastSync)) return;

      final hrv = data[9];
      final hr = data[11];
      final fatigue = data[12];
      final systolic = data[13];
      final diastolic = data[14];

      if (hrv == 0 && hr == 0 && systolic == 0) return;

      results.add(
        RingRawHrvRecord(
          timestamp: timestamp,
          hrvMs: hrv,
          heartRateBpm: hr,
          fatigue: fatigue,
          systolicMmhg: systolic,
          diastolicMmhg: diastolic,
        ),
      );
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x56;
      payload[1] = 0x00;

      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      final newRecords = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
            '[Ring BLE] HRV history timeout, got ${results.length} records',
          );
          return results;
        },
      );

      if (newRecords.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }
      return newRecords;
    } catch (e) {
      debugPrint('[Ring BLE] fetchHrvHistory error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Command 0x54 — Fetch detailed HR history with timestamp filter.
  Future<List<HrDataPoint>> fetchHrDetails() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrDetails: not connected');
      return [];
    }

    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchHrDetails: last sync at $lastSync, sending 0x54',
    );

    final results = <HrDataPoint>[];
    final completer = Completer<List<HrDataPoint>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x54) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint(
          '[Ring BLE] HR details end marker — ${results.length} point(s)',
        );
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 24) return;

      final startTime = _parseRingTimestamp(data, 3);
      if (startTime == null) return;

      for (int j = 0; j < 15; j++) {
        final bpm = data[9 + j];
        if (bpm == 0 || bpm >= 250) continue;
        final pointTime = startTime.add(Duration(seconds: j * 5));
        if (pointTime.isAfter(lastSync)) {
          results.add(HrDataPoint(time: pointTime, bpm: bpm));
        }
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x54;
      payload[1] = 0x00;

      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      final newRecords = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
            '[Ring BLE] HR details timeout, got ${results.length} points',
          );
          return results;
        },
      );

      if (newRecords.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }
      return newRecords;
    } catch (e) {
      debugPrint('[Ring BLE] fetchHrDetails error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Command 0x54 (paged) — Fetch detailed HR points in [start, end] range.
  /// Uses AA=0x00 for first page and AA=0x02 for continuation pages.
  Future<List<HrDataPoint>> fetchHrDetailsRange({
    required DateTime start,
    DateTime? end,
  }) async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrDetailsRange: not connected');
      return [];
    }

    final results = <HrDataPoint>[];
    const maxPages = 20;
    var aa = 0x00;

    for (var page = 0; page < maxPages; page++) {
      final pageResult = await _fetchHrDetailsPage(
        aa: aa,
        start: start,
        end: end,
      );
      results.addAll(pageResult.points);
      if (pageResult.endReached || pageResult.points.isEmpty) break;
      aa = 0x02;
    }

    return results;
  }

  Future<({List<HrDataPoint> points, bool endReached})> _fetchHrHistoryPage({
    required int aa,
    required DateTime start,
    DateTime? end,
  }) async {
    final upperBound = end;
    final points = <HrDataPoint>[];
    var endReached = false;
    final completer = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      var i = 0;
      while (i < data.length) {
        if (data[i] != 0x55) {
          i++;
          continue;
        }
        if (i + 1 < data.length && data[i + 1] == 0xFF) {
          endReached = true;
          if (!completer.isCompleted) completer.complete();
          i += 2;
          continue;
        }
        if (i + 10 > data.length) break;
        final frame = data.sublist(i, i + 10);
        final hr = frame[9];
        final ts = _parseRingTimestamp(frame, 3);
        if (hr > 0 && hr < 250 && ts != null) {
          final inRange =
              (ts.isAtSameMomentAs(start) || ts.isAfter(start)) &&
              (upperBound == null ||
                  ts.isBefore(upperBound) ||
                  ts.isAtSameMomentAs(upperBound));
          if (inRange) {
            points.add(HrDataPoint(time: ts, bpm: hr));
          }
        }
        i += 10;
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x55;
      payload[1] = aa;
      final bcdTs = _encodeBcdTimestamp(start);
      for (var j = 0; j < 6; j++) {
        payload[3 + j] = bcdTs[j];
      }
      await _writeCommand(payload);
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          return;
        },
      );
      return (points: points, endReached: endReached);
    } catch (e) {
      debugPrint('[Ring BLE] _fetchHrHistoryPage error: $e');
      return (points: points, endReached: endReached);
    } finally {
      await sub.cancel();
    }
  }

  Future<({List<HrDataPoint> points, bool endReached})> _fetchHrDetailsPage({
    required int aa,
    required DateTime start,
    DateTime? end,
  }) async {
    final upperBound = end;
    final points = <HrDataPoint>[];
    var endReached = false;
    final completer = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      var i = 0;
      while (i < data.length) {
        if (data[i] != 0x54) {
          i++;
          continue;
        }
        if (i + 1 < data.length && data[i + 1] == 0xFF) {
          endReached = true;
          if (!completer.isCompleted) completer.complete();
          i += 2;
          continue;
        }
        if (i + 24 > data.length) break;
        final frame = data.sublist(i, i + 24);
        final startTime = _parseRingTimestamp(frame, 3);
        if (startTime != null) {
          for (var j = 0; j < 15; j++) {
            final bpm = frame[9 + j];
            if (bpm <= 0 || bpm >= 250) continue;
            final ts = startTime.add(Duration(seconds: j * 5));
            final inRange =
                (ts.isAtSameMomentAs(start) || ts.isAfter(start)) &&
                (upperBound == null ||
                    ts.isBefore(upperBound) ||
                    ts.isAtSameMomentAs(upperBound));
            if (inRange) {
              points.add(HrDataPoint(time: ts, bpm: bpm));
            }
          }
        }
        i += 24;
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x54;
      payload[1] = aa;
      final bcdTs = _encodeBcdTimestamp(start);
      for (var j = 0; j < 6; j++) {
        payload[3 + j] = bcdTs[j];
      }
      await _writeCommand(payload);
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          return;
        },
      );
      return (points: points, endReached: endReached);
    } catch (e) {
      debugPrint('[Ring BLE] _fetchHrDetailsPage error: $e');
      return (points: points, endReached: endReached);
    } finally {
      await sub.cancel();
    }
  }

  /// Command 0x62 — Fetch temperature history with timestamp filter.
  Future<List<RingRawTemperatureRecord>> fetchTemperatureHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchTemperatureHistory: not connected');
      return [];
    }

    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchTemperatureHistory: last sync at $lastSync, sending 0x62',
    );

    final results = <RingRawTemperatureRecord>[];
    final completer = Completer<List<RingRawTemperatureRecord>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x62) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint(
          '[Ring BLE] Temperature end marker — ${results.length} record(s)',
        );
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 15) return;

      final timestamp = _parseRingTimestamp(data, 3);
      if (timestamp == null || !timestamp.isAfter(lastSync)) return;

      final temp1 = ((data[10] << 8) | data[9]) / 10.0;
      final temp2 = ((data[12] << 8) | data[11]) / 10.0;
      final temp3 = ((data[14] << 8) | data[13]) / 10.0;

      if (temp1 == 0.0 && temp2 == 0.0 && temp3 == 0.0) return;

      results.add(
        RingRawTemperatureRecord(
          timestamp: timestamp,
          temp1C: temp1,
          temp2C: temp2,
          temp3C: temp3,
        ),
      );
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x62;
      payload[1] = 0x00;

      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      final newRecords = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
            '[Ring BLE] Temperature timeout, got ${results.length} records',
          );
          return results;
        },
      );

      if (newRecords.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }
      return newRecords;
    } catch (e) {
      debugPrint('[Ring BLE] fetchTemperatureHistory error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Command 0x66 — Fetch SpO2 (blood oxygen) history with timestamp filter.
  Future<List<RingRawSpo2Record>> fetchSpo2History() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchSpo2History: not connected');
      return [];
    }

    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchSpo2History: last sync at $lastSync, sending 0x66',
    );

    final results = <RingRawSpo2Record>[];
    final completer = Completer<List<RingRawSpo2Record>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x66) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint('[Ring BLE] SpO2 end marker — ${results.length} record(s)');
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 10) return;

      final timestamp = _parseRingTimestamp(data, 3);
      if (timestamp == null || !timestamp.isAfter(lastSync)) return;

      final spo2 = data[9];
      if (spo2 == 0 || spo2 > 100) return;

      results.add(RingRawSpo2Record(timestamp: timestamp, spo2Percent: spo2));
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x66;
      payload[1] = 0x00;

      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      final newRecords = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[Ring BLE] SpO2 timeout, got ${results.length} records');
          return results;
        },
      );

      if (newRecords.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }
      return newRecords;
    } catch (e) {
      debugPrint('[Ring BLE] fetchSpo2History error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Start continuous HR streaming.
  /// Sends 0x28 (HR mode, max duration) + 0x09 (realtime) + 0x19 (exercise
  /// mode). The 0x19 exercise mode causes the ring to emit 0x18 packets with
  /// fresh optical HR at Byte[1] every ~1 s. 0x09 packets are used as fallback.
  /// Call [stopHrStreaming] to tear everything down.
  Stream<int> startHrStreaming() {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] startHrStreaming: not connected');
      return const Stream.empty();
    }
    debugPrint('[Ring BLE] startHrStreaming: starting 0x28 + 0x09 + 0x19');

    _hrStreamController?.close();
    _hrStreamController = StreamController<int>.broadcast();

    final notifyChar = _notifyChar!;
    _hrStreamSub?.cancel();
    _hrStreamSub = notifyChar.onValueReceived.listen(
      (data) {
        if (data.isEmpty || data[0] != 0x18) return;
        // 0x18 exercise push packet: live optical HR at byte[1].
        // byte[1] == 0xFF means ring ended exercise; byte[1] == 0x00 means sensor
        // is still warming up (no valid reading yet) — both are ignored.
        if (data.length < 2 || data[1] == 0xFF || data[1] == 0x00) return;
        final hr = data[1];
        // duration counter (seconds, LE) for log context
        final secs = data.length >= 14
            ? data[10] | (data[11] << 8) | (data[12] << 16) | (data[13] << 24)
            : 0;
        debugPrint('[Ring HR] 0x18 → $hr BPM (t=${secs}s)');
        if (hr > 0 && hr < 250 && _hrStreamController?.isClosed == false) {
          _hrStreamController!.add(hr);
        }
      },
      onError: (e) => debugPrint('[Ring HR] notify stream error: $e'),
      cancelOnError: false,
    );

    // 0x28: activate optical sensor, max 90 min = 5400 s
    final measurePayload = List<int>.filled(15, 0);
    measurePayload[0] = 0x28;
    measurePayload[1] = 0x02; // HR mode
    measurePayload[2] = 0x01; // start
    measurePayload[5] = 0x18; // 5400 & 0xFF
    measurePayload[6] = 0x15; // 5400 >> 8
    _writeCommand(measurePayload).catchError((e) {
      debugPrint('[Ring BLE] startHrStreaming 0x28 error: $e');
    });

    // 0x09: realtime streaming (fallback HR source)
    final streamPayload = List<int>.filled(15, 0);
    streamPayload[0] = 0x09;
    streamPayload[1] = 0x01;
    streamPayload[2] = 0x01; // enable temperature
    _writeCommand(streamPayload).catchError((e) {
      debugPrint('[Ring BLE] startHrStreaming 0x09 error: $e');
    });

    // 0x19: exercise mode — triggers live 0x18 push packets
    final exercisePayload = List<int>.filled(15, 0);
    exercisePayload[0] = 0x19;
    exercisePayload[1] = 0x01; // start
    exercisePayload[2] = 0x09; // mode
    _writeCommand(exercisePayload).catchError((e) {
      debugPrint('[Ring BLE] startHrStreaming 0x19 error: $e');
    });

    return _hrStreamController!.stream;
  }

  /// Stop the continuous HR streaming started by [startHrStreaming].
  Future<void> stopHrStreaming() async {
    debugPrint('[Ring BLE] stopHrStreaming');

    // Stop exercise mode first
    try {
      final stopExercise = List<int>.filled(15, 0);
      stopExercise[0] = 0x19;
      stopExercise[1] = 0x04; // end
      stopExercise[2] = 0x09;
      await _writeCommand(stopExercise);
    } catch (e) {
      debugPrint('[Ring BLE] stopHrStreaming 0x19 stop error: $e');
    }

    try {
      final measurePayload = List<int>.filled(15, 0);
      measurePayload[0] = 0x28;
      measurePayload[1] = 0x02;
      measurePayload[2] = 0x00; // stop
      await _writeCommand(measurePayload);
    } catch (e) {
      debugPrint('[Ring BLE] stopHrStreaming 0x28 stop error: $e');
    }

    try {
      final streamPayload = List<int>.filled(15, 0);
      streamPayload[0] = 0x09;
      streamPayload[1] = 0x00; // stop
      await _writeCommand(streamPayload);
    } catch (e) {
      debugPrint('[Ring BLE] stopHrStreaming 0x09 stop error: $e');
    }

    await _hrStreamSub?.cancel();
    _hrStreamSub = null;
    await _hrStreamController?.close();
    _hrStreamController = null;
    debugPrint('[Ring BLE] HR streaming stopped');
  }

  // ─── Sleep ────────────────────────────────────────────────────────────────

  /// Command 0x53 — Fetch stored sleep sessions with timestamp filter.
  Future<({List<RingRawSleepRecord> records, bool isComplete})>
  fetchSleepHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchSleepHistory: not connected');
      return (records: <RingRawSleepRecord>[], isComplete: false);
    }

    final lastSync =
        await _ringService.loadLastSyncAt() ?? DateTime(2000, 1, 1);
    debugPrint(
      '[Ring BLE] fetchSleepHistory: last sync at $lastSync, sending 0x53',
    );

    // Dedup map: key = "id1-id2-timestamp"
    final Map<String, RingRawSleepRecord> dedup = {};
    bool isComplete = false;
    final completer = Completer<void>();
    StreamSubscription<List<int>>? sub;
    Timer? inactivityTimer;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    void resetTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(const Duration(seconds: 8), finish);
    }

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x53) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint('[Ring BLE] Sleep end marker received');
        isComplete = true;
        finish();
        return;
      }

      resetTimer();

      final parsed = _parseSleepNotification(data);
      for (final rec in parsed) {
        // Filter by timestamp
        if (rec.sessionStart.isAfter(lastSync)) {
          final key =
              '${rec.id1}-${rec.id2}-${rec.sessionStart.toIso8601String()}';
          final existing = dedup[key];
          if (existing == null ||
              rec.totalSleepMinutes > existing.totalSleepMinutes) {
            dedup[key] = rec;
          }
        }
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x53;
      payload[1] = 0x00;

      final bcdTs = _encodeBcdTimestamp(lastSync);
      for (var i = 0; i < 6; i++) {
        payload[3 + i] = bcdTs[i];
      }

      await _writeCommand(payload);
      resetTimer();

      await completer.future;
      final records = dedup.values.toList()
        ..sort((a, b) => a.sessionStart.compareTo(b.sessionStart));
      debugPrint(
        '[Ring BLE] fetchSleepHistory done — ${records.length} segment(s), complete=$isComplete',
      );

      if (records.isNotEmpty) {
        await _ringService.saveLastSyncAt(DateTime.now());
      }

      return (records: records, isComplete: isComplete);
    } catch (e) {
      debugPrint('[Ring BLE] fetchSleepHistory error: $e');
      final records = dedup.values.toList()
        ..sort((a, b) => a.sessionStart.compareTo(b.sessionStart));
      return (records: records, isComplete: false);
    } finally {
      inactivityTimer?.cancel();
      await sub.cancel();
    }
  }

  /// Parse one BLE notification from the 0x53 command.
  /// Tries 130-byte fixed frame first (firmware pads to 130), then variable-length.
  List<RingRawSleepRecord> _parseSleepNotification(List<int> data) {
    final List<RingRawSleepRecord> out = [];
    int i = 0;
    while (i + 10 <= data.length) {
      if (data[i] != 0x53) {
        i++;
        continue;
      }

      RingRawSleepRecord? rec;

      // Try fixed 130-byte frame first
      if (i + 130 <= data.length) {
        rec = _tryParseSleepFrame(data, i, 130);
        if (rec != null) {
          out.add(rec);
          i += 130;
          continue;
        }
      }

      // Variable-length: 10 + N bytes
      final n = data[i + 9];
      final size = 10 + n;
      if (n >= 1 && n <= 120 && i + size <= data.length) {
        rec = _tryParseSleepFrame(data, i, size);
        if (rec != null) {
          out.add(rec);
          i += size;
          continue;
        }
      }

      // Fallback: try from here to end of buffer
      rec = _tryParseSleepFrame(data, i, data.length - i);
      if (rec != null) out.add(rec);
      break;
    }
    return out;
  }

  RingRawSleepRecord? _tryParseSleepFrame(
    List<int> data,
    int offset,
    int frameLen,
  ) {
    if (offset + frameLen > data.length || frameLen < 10) return null;
    if (data[offset] != 0x53) return null;
    try {
      final id1 = data[offset + 1];
      final id2 = data[offset + 2];
      final sessionStart = _parseRingTimestamp(data, offset + 3);
      if (sessionStart == null) return null;
      final n = data[offset + 9];
      if (n < 1 || n > 120) return null;
      final end = (offset + 10 + n).clamp(0, offset + frameLen);
      int deep = 0, light = 0, rem = 0, awake = 0;
      for (var j = offset + 10; j < end; j++) {
        final stage = data[j];
        if (stage == 0x01)
          deep++;
        else if (stage == 0x02)
          light++;
        else if (stage == 0x03)
          rem++;
        else
          awake++;
      }
      final sessionEnd = sessionStart.add(Duration(minutes: n));
      debugPrint(
        '[Ring BLE] Sleep segment: $sessionStart N=$n '
        'deep=${deep}m light=${light}m rem=${rem}m awake=${awake}m',
      );
      return RingRawSleepRecord(
        sessionStart: sessionStart,
        sessionEnd: sessionEnd,
        lightMinutes: light,
        deepMinutes: deep,
        remMinutes: rem,
        awakeMinutes: awake,
        id1: id1,
        id2: id2,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Steps ───────────────────────────────────────────────────────────────

  /// Command 0x51 — Fetch daily step totals from the ring (up to 15 days).
  ///
  /// Each response record is 27 bytes; multiple records may be concatenated
  /// inside a single BLE notification (MTU = 244 bytes).  All incoming bytes
  /// are buffered until the end-of-data marker `0x51 0xFF` arrives, then the
  /// buffer is parsed into fixed 27-byte records.
  ///
  /// ID=0 is today (resets at midnight on the ring), ID=1 yesterday, etc.
  Future<List<RingRawDailySteps>> fetchStepHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchStepHistory: not connected');
      return [];
    }
    debugPrint('[Ring BLE] fetchStepHistory: sending 0x51');

    final buffer = <int>[];
    final endMarker = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x51) return;

      // Scan for end-of-data marker 0x51 0xFF within this notification
      for (var i = 0; i < data.length - 1; i++) {
        if (data[i] == 0x51 && data[i + 1] == 0xFF) {
          buffer.addAll(data.sublist(0, i));
          if (!endMarker.isCompleted) endMarker.complete();
          return;
        }
      }
      buffer.addAll(data);
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x51;
      payload[1] = 0x00; // read all stored days
      await _writeCommand(payload);

      try {
        await endMarker.future.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        debugPrint(
          '[Ring BLE] fetchStepHistory timeout, parsing buffered bytes',
        );
      }
    } catch (e) {
      debugPrint('[Ring BLE] fetchStepHistory error: $e');
      return [];
    } finally {
      await sub.cancel();
    }

    // Parse complete 27-byte records from the accumulated buffer
    final records = <RingRawDailySteps>[];
    var offset = 0;
    while (offset + 27 <= buffer.length) {
      if (buffer[offset] != 0x51) {
        offset++;
        continue;
      }
      final date = _parseStepDate(buffer, offset + 2);
      if (date != null) {
        final steps = _leInt32(buffer, offset + 5);
        final exerciseSecs = _leInt32(buffer, offset + 9);
        final distRaw = _leInt32(buffer, offset + 13);
        records.add(
          RingRawDailySteps(
            date: date,
            steps: steps,
            exerciseTimeSeconds: exerciseSecs,
            distanceKm: distRaw / 100.0,
          ),
        );
        debugPrint(
          '[Ring BLE] Step record: $date  steps=$steps  '
          'exercise=${exerciseSecs}s  dist=${distRaw / 100.0}km',
        );
      }
      offset += 27;
    }
    debugPrint('[Ring BLE] fetchStepHistory: ${records.length} day(s)');
    return records;
  }

  // ─── Live measurements ────────────────────────────────────────────────────

  /// Command 0x14 — Read live ring temperature.
  ///
  /// Response is 11 bytes:
  ///   [0]=0x14 [1-2]=highestTemp LE16/10 [3]=decimalTemp BCD
  ///   [4-5]=ntc1 LE16/10 [6-7]=ntc2 LE16/10 [8-9]=ntc3 LE16/10 [10]=CRC
  Future<RingLiveTemperature?> fetchRingTemperatureLive() async {
    try {
      final response = await _sendCommandWithResponse(0x14);
      if (response == null || response.length < 10) return null;
      final highest = ((response[2] << 8) | response[1]) / 10.0;
      final ntc1 = ((response[5] << 8) | response[4]) / 10.0;
      final ntc2 = ((response[7] << 8) | response[6]) / 10.0;
      final ntc3 = ((response[9] << 8) | response[8]) / 10.0;
      if (highest == 0.0 && ntc1 == 0.0) return null;
      debugPrint(
        '[Ring BLE] Live temp: highest=${highest}°C ntc1=${ntc1} ntc2=${ntc2} ntc3=${ntc3}',
      );
      return RingLiveTemperature(
        highestTempC: highest,
        ntc1C: ntc1,
        ntc2C: ntc2,
        ntc3C: ntc3,
      );
    } catch (e) {
      debugPrint('[Ring BLE] fetchRingTemperatureLive error: $e');
      return null;
    }
  }

  /// Command 0x28 + 0x09 + 0x19 — Live HR measurement for [durationSeconds] seconds.
  ///
  /// Starts HR mode (0x28), realtime streaming (0x09), and exercise mode (0x19).
  /// Exercise mode causes the ring to emit 0x18 packets with live optical HR at
  /// bytes[1]. 0x09 streaming alone returns the ring's stale cached background HR.
  /// Returns avg/min/max + raw readings.
  Future<RingHrMeasurementResult?> measureHeartRate({
    int durationSeconds = 10,
  }) async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] measureHeartRate: not connected');
      return null;
    }
    final protocolDurationSeconds = durationSeconds < 30 ? 30 : durationSeconds;
    debugPrint(
      '[Ring BLE] measureHeartRate: starting ${durationSeconds}s measurement '
      '(protocol duration ${protocolDurationSeconds}s)',
    );

    final readings = <int>[];
    int lastHr = 0;
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty) return;
      if (data[0] == 0x09 ||
          data[0] == 0x18 ||
          data[0] == 0x28 ||
          data[0] == 0xA8) {
        print(
          '[Ring BLE] measureHeartRate RX: cmd=0x${data[0].toRadixString(16)} len=${data.length} data=${_hexDump(data)}',
        );
      }

      int hr = 0;
      if (data[0] == 0x18) {
        // 0x18 exercise packet: live optical HR at bytes[1]
        if (data.length >= 2 && data[1] != 0xFF) hr = data[1];
      } else if (data[0] == 0x09) {
        if (data.length == 16) {
          hr = data[13];
        } else if (data.length >= 23) {
          hr = data[22];
        }
      }

      if (hr > 0 && hr < 250 && hr != lastHr) {
        print(
          '[Ring BLE] measureHeartRate: reading $hr bpm (cmd=0x${data[0].toRadixString(16)})',
        );
        readings.add(hr);
        lastHr = hr;
      }
    });

    try {
      // Start HR measurement. Protocol requires a minimum duration of 30 s.
      final measurePayload = List<int>.filled(15, 0);
      measurePayload[0] = 0x28;
      measurePayload[1] = 0x02; // HR mode
      measurePayload[2] = 0x01; // start
      measurePayload[5] = protocolDurationSeconds & 0xFF;
      measurePayload[6] = (protocolDurationSeconds >> 8) & 0xFF;
      print('[Ring BLE] measureHeartRate: sending 0x28 start');
      await _writeCommand(measurePayload);

      await Future.delayed(const Duration(seconds: 1));

      // Enable realtime streaming
      final streamPayload = List<int>.filled(15, 0);
      streamPayload[0] = 0x09;
      streamPayload[1] = 0x01; // start
      streamPayload[2] = 0x01; // enable temperature
      print('[Ring BLE] measureHeartRate: sending 0x09 start');
      await _writeCommand(streamPayload);

      // Start exercise mode (0x19, mode=0x09) — triggers 0x18 packets with live HR
      final exercisePayload = List<int>.filled(15, 0);
      exercisePayload[0] = 0x19;
      exercisePayload[1] = 0x01; // start
      exercisePayload[2] = 0x09; // mode
      print('[Ring BLE] measureHeartRate: sending 0x19 exercise start');
      await _writeCommand(exercisePayload);

      print(
        '[Ring BLE] measureHeartRate: collecting for ${protocolDurationSeconds}s',
      );
      await Future.delayed(Duration(seconds: protocolDurationSeconds));

      // Stop exercise mode
      final stopExercise = List<int>.filled(15, 0);
      stopExercise[0] = 0x19;
      stopExercise[1] = 0x04; // end
      stopExercise[2] = 0x09;
      print('[Ring BLE] measureHeartRate: sending 0x19 exercise stop');
      await _writeCommand(stopExercise);

      // Stop HR measurement
      final stopMeasure = List<int>.filled(15, 0);
      stopMeasure[0] = 0x28;
      stopMeasure[1] = 0x02;
      stopMeasure[2] = 0x00; // stop
      print('[Ring BLE] measureHeartRate: sending 0x28 stop');
      await _writeCommand(stopMeasure);

      final stopStream = List<int>.filled(15, 0);
      stopStream[0] = 0x09;
      stopStream[1] = 0x00; // stop
      print('[Ring BLE] measureHeartRate: sending 0x09 stop');
      await _writeCommand(stopStream);

      if (readings.isEmpty) {
        debugPrint('[Ring BLE] measureHeartRate: no readings received');
        return null;
      }

      readings.sort();
      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      debugPrint(
        '[Ring BLE] measureHeartRate done: avg=$avg min=${readings.first} max=${readings.last} (${readings.length} readings)',
      );
      return RingHrMeasurementResult(
        avgBpm: avg,
        minBpm: readings.first,
        maxBpm: readings.last,
        durationSeconds: protocolDurationSeconds,
        readings: List.unmodifiable(readings),
      );
    } catch (e) {
      debugPrint('[Ring BLE] measureHeartRate error: $e');
      return null;
    } finally {
      await sub.cancel();
    }
  }

  // ─── Ring info ────────────────────────────────────────────────────────────

  /// Command 0x41 — Get current ring time and MTU.
  ///
  /// Response is 16 bytes:
  ///   [0]=0x41 [1-6]=BCD timestamp [7]=weekday [8-9]=maxMtu LE16 …
  Future<RingTimeInfo?> fetchRingTime() async {
    try {
      final response = await _sendCommandWithResponse(0x41);
      if (response == null || response.length < 10) return null;
      final time = _parseRingTimestamp(response, 1);
      if (time == null) return null;
      final weekday = response[7];
      final maxMtu = response[8] | (response[9] << 8);
      return RingTimeInfo(ringTime: time, weekday: weekday, maxMtu: maxMtu);
    } catch (e) {
      debugPrint('[Ring BLE] fetchRingTime error: $e');
      return null;
    }
  }

  /// Command 0x42 — Get user info stored on ring.
  ///
  /// Response is 12 bytes:
  ///   [0]=0x42 [1]=gender [2]=age [3]=heightCm [4]=weightKg
  ///   [5]=stepLenCm [6-11]=ringId ASCII
  Future<RingUserInfo?> fetchUserInfo() async {
    try {
      final response = await _sendCommandWithResponse(0x42);
      if (response == null || response.length < 12) return null;
      final ringId = String.fromCharCodes(response.sublist(6, 12));
      return RingUserInfo(
        gender: response[1],
        age: response[2],
        heightCm: response[3],
        weightKg: response[4],
        stepLengthCm: response[5],
        ringId: ringId,
      );
    } catch (e) {
      debugPrint('[Ring BLE] fetchUserInfo error: $e');
      return null;
    }
  }

  // ─── Exercise ─────────────────────────────────────────────────────────────

  /// Command 0x19 subcommand 0x05 — Get current exercise status.
  ///
  /// Response is 9 bytes:
  ///   [0]=0x19 [1]=status (0=idle,1=active) [2-7]=BCD start timestamp [8]=CRC
  Future<({int status, DateTime? startTime})> getExerciseStatus() async {
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x19;
      payload[1] = 0x05;
      final completer = Completer<List<int>>();
      StreamSubscription<List<int>>? sub;
      sub = _notifyChar!.onValueReceived.listen((data) {
        if (data.isNotEmpty && data[0] == 0x19 && !completer.isCompleted) {
          completer.complete(data);
        }
      });
      try {
        await _writeCommand(payload);
        final response = await completer.future.timeout(_responseTimeout);
        final status = response.length > 1 ? response[1] : 0;
        final startTime = response.length >= 8
            ? _parseRingTimestamp(response, 2)
            : null;
        return (status: status, startTime: startTime);
      } finally {
        await sub.cancel();
      }
    } catch (e) {
      debugPrint('[Ring BLE] getExerciseStatus error: $e');
      return (status: 0, startTime: null);
    }
  }

  /// Command 0x19 subcommand 0x01 — Start an exercise session.
  Future<bool> startExercise(int exerciseType) async {
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x19;
      payload[1] = 0x01;
      payload[2] = exerciseType;
      await _writeCommand(payload);
      debugPrint('[Ring BLE] startExercise: type=$exerciseType');
      return true;
    } catch (e) {
      debugPrint('[Ring BLE] startExercise error: $e');
      return false;
    }
  }

  /// Command 0x19 subcommand 0x06 — Stop the active exercise session.
  Future<bool> stopExercise() async {
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x19;
      payload[1] = 0x06;
      await _writeCommand(payload);
      debugPrint('[Ring BLE] stopExercise');
      return true;
    } catch (e) {
      debugPrint('[Ring BLE] stopExercise error: $e');
      return false;
    }
  }

  /// Command 0x5C subcommand 0x00 — Fetch stored exercise records.
  ///
  /// Each record is 27 bytes with CRC:
  ///   [0]=0x5C [1]=0x00 [2]=ID [3-8]=BCD start time [9]=type [10]=avgHR
  ///   [11-12]=durationSec LE16 [13-14]=steps LE16 [15-16]=pace BCD (min:sec/km)
  ///   [17-20]=calories IEEE754 [21-24]=distKm IEEE754 [25-26]=CRC/pad
  Future<List<RingExerciseRecord>> fetchExerciseData() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchExerciseData: not connected');
      return [];
    }
    debugPrint('[Ring BLE] fetchExerciseData: sending 0x5C 0x00');

    final buffer = <int>[];
    final endMarker = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x5C) return;
      if (data.length >= 2 && data[1] == 0xFF) {
        if (!endMarker.isCompleted) endMarker.complete();
        return;
      }
      buffer.addAll(data);
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x5C;
      payload[1] = 0x00;
      await _writeCommand(payload);
      try {
        await endMarker.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        debugPrint(
          '[Ring BLE] fetchExerciseData timeout, parsing buffered bytes',
        );
      }
    } catch (e) {
      debugPrint('[Ring BLE] fetchExerciseData error: $e');
      return [];
    } finally {
      await sub.cancel();
    }

    final records = <RingExerciseRecord>[];
    var offset = 0;
    while (offset + 27 <= buffer.length) {
      if (buffer[offset] != 0x5C) {
        offset++;
        continue;
      }
      try {
        final startTime = _parseRingTimestamp(buffer, offset + 3);
        if (startTime == null) {
          offset += 27;
          continue;
        }
        final exerciseType = buffer[offset + 9];
        final avgHr = buffer[offset + 10];
        final durationSec = buffer[offset + 11] | (buffer[offset + 12] << 8);
        final steps = buffer[offset + 13] | (buffer[offset + 14] << 8);
        final paceMin = _bcdToDecimal(buffer[offset + 15]);
        final paceSec = _bcdToDecimal(buffer[offset + 16]);
        final paceMinPerKm = paceMin + paceSec / 60.0;
        final calories = _parseFloat32Le(buffer, offset + 17);
        final distKm = _parseFloat32Le(buffer, offset + 21);
        if (avgHr > 0 || durationSec > 0) {
          records.add(
            RingExerciseRecord(
              startTime: startTime,
              exerciseType: exerciseType,
              avgHeartRate: avgHr,
              durationSeconds: durationSec,
              steps: steps,
              paceMinPerKm: paceMinPerKm,
              calories: calories,
              distanceKm: distKm,
            ),
          );
        }
      } catch (_) {}
      offset += 27;
    }
    debugPrint('[Ring BLE] fetchExerciseData: ${records.length} record(s)');
    return records;
  }

  /// Command 0x5C subcommand 0x02 — Continue fetching exercise data (next page).
  Future<void> continueExerciseData() async {
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x5C;
      payload[1] = 0x02;
      await _writeCommand(payload);
    } catch (e) {
      debugPrint('[Ring BLE] continueExerciseData error: $e');
    }
  }

  /// Command 0x5C subcommand 0x99 — Delete all exercise data from ring.
  Future<void> deleteExerciseData() async {
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x5C;
      payload[1] = 0x99;
      await _writeCommand(payload);
      debugPrint('[Ring BLE] deleteExerciseData: sent');
    } catch (e) {
      debugPrint('[Ring BLE] deleteExerciseData error: $e');
    }
  }

  // ─── Measurement intervals ────────────────────────────────────────────────

  /// Command 0x2B — Get automatic measurement interval for [measureType].
  ///
  /// measureType: 1=HR, 2=SpO2, 3=Temperature, 4=HRV/BP
  ///
  /// Response is 10 bytes:
  ///   [0]=0x2B [1]=mode [2-3]=BCD startTime (HH:MM) [4-5]=BCD endTime
  ///   [6]=weekdayBits [7-8]=intervalMinutes BE16 [9]=measureType
  Future<RingMeasurementInterval?> getMeasurementInterval(
    int measureType,
  ) async {
    if (_notifyChar == null) return null;
    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x2B;
      payload[1] = measureType;
      final completer = Completer<List<int>>();
      StreamSubscription<List<int>>? sub;
      sub = _notifyChar!.onValueReceived.listen((data) {
        if (data.isNotEmpty && data[0] == 0x2B && !completer.isCompleted) {
          completer.complete(data);
        }
      });
      try {
        await _writeCommand(payload);
        final response = await completer.future.timeout(_responseTimeout);
        if (response.length < 10) return null;
        final mode = response[1];
        final startH = _bcdToDecimal(response[2]);
        final startM = _bcdToDecimal(response[3]);
        final endH = _bcdToDecimal(response[4]);
        final endM = _bcdToDecimal(response[5]);
        final weekdayBits = response[6];
        final intervalMin = (response[7] << 8) | response[8];
        return RingMeasurementInterval(
          measureType: response[9],
          mode: mode,
          intervalMinutes: intervalMin,
          weekdayBits: weekdayBits,
          startTime:
              '${startH.toString().padLeft(2, '0')}:${startM.toString().padLeft(2, '0')}',
          endTime:
              '${endH.toString().padLeft(2, '0')}:${endM.toString().padLeft(2, '0')}',
        );
      } finally {
        await sub.cancel();
      }
    } catch (e) {
      debugPrint('[Ring BLE] getMeasurementInterval error: $e');
      return null;
    }
  }

  /// Command 0x2A — Set automatic measurement interval.
  ///
  /// [measureType]: 1=HR, 2=SpO2, 3=Temperature, 4=HRV/BP
  /// [mode]: 0=off, 1=manual, 2=auto
  /// [intervalMinutes]: auto-measurement interval
  /// [weekdayBits]: bitmask bit0=Mon … bit6=Sun (0x7F = every day)
  Future<void> setMeasurementInterval({
    required int measureType,
    required int mode,
    required int intervalMinutes,
    int weekdayBits = 0x7F,
    String startTime = '00:00',
    String endTime = '23:59',
  }) async {
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      final startH = int.tryParse(startParts[0]) ?? 0;
      final startM = startParts.length > 1
          ? (int.tryParse(startParts[1]) ?? 0)
          : 0;
      final endH = int.tryParse(endParts[0]) ?? 23;
      final endM = endParts.length > 1 ? (int.tryParse(endParts[1]) ?? 59) : 59;

      final payload = List<int>.filled(15, 0);
      payload[0] = 0x2A;
      payload[1] = mode;
      payload[2] = _decimalToBcd(startH);
      payload[3] = _decimalToBcd(startM);
      payload[4] = _decimalToBcd(endH);
      payload[5] = _decimalToBcd(endM);
      payload[6] = weekdayBits;
      payload[7] = (intervalMinutes >> 8) & 0xFF; // BE16
      payload[8] = intervalMinutes & 0xFF;
      payload[9] = measureType;
      await _writeCommand(payload);
      debugPrint(
        '[Ring BLE] setMeasurementInterval: type=$measureType mode=$mode interval=${intervalMinutes}min',
      );
    } catch (e) {
      debugPrint('[Ring BLE] setMeasurementInterval error: $e');
    }
  }

  /// Initialize ring on reconnect: set time, user info (default), and measurement intervals
  Future<void> initializeRing({
    int gender = 1, // 1=male, 2=female (default male)
    int age = 20,
    int heightCm = 170,
    int weightKg = 70,
  }) async {
    if (!isConnected) {
      debugPrint('[Ring BLE] initializeRing: not connected');
      return;
    }

    try {
      // Set time
      await setTime();

      // Set user info
      await setUserInfo(
        gender: gender,
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
      );

      // Set measurement intervals to 5 minutes for all metrics
      // measureType: 1=HR, 2=SpO2, 3=Temperature, 4=HRV/BP
      // mode: 2=auto
      for (final measureType in [1, 2, 3, 4]) {
        await setMeasurementInterval(
          measureType: measureType,
          mode: 2, // auto
          intervalMinutes: 5,
        );
      }

      debugPrint('[Ring BLE] Ring initialization complete');
    } catch (e) {
      debugPrint('[Ring BLE] initializeRing error: $e');
    }
  }

  // ─── Detailed steps ───────────────────────────────────────────────────────

  /// Command 0x52 — Fetch detailed per-minute step records.
  ///
  /// Each record is 25 bytes:
  ///   [0]=0x52 [1]=ID1 [2]=ID2 [3-5]=BCD date(YY MM DD) [6-7]=BCD time(HH MM)
  ///   [8-9]=steps LE16 [10-11]=calories LE16 [12-13]=distanceCm LE16
  ///   [14-23]=10 per-minute step counts
  Future<List<RingDetailedStepRecord>> fetchDetailedSteps() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchDetailedSteps: not connected');
      return [];
    }
    debugPrint('[Ring BLE] fetchDetailedSteps: sending 0x52');

    final buffer = <int>[];
    final endMarker = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isEmpty || data[0] != 0x52) return;
      if (data.length >= 2 && data[1] == 0xFF) {
        if (!endMarker.isCompleted) endMarker.complete();
        return;
      }
      buffer.addAll(data);
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x52;
      payload[1] = 0x00;
      await _writeCommand(payload);
      try {
        await endMarker.future.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        debugPrint(
          '[Ring BLE] fetchDetailedSteps timeout, parsing buffered bytes',
        );
      }
    } catch (e) {
      debugPrint('[Ring BLE] fetchDetailedSteps error: $e');
      return [];
    } finally {
      await sub.cancel();
    }

    final records = <RingDetailedStepRecord>[];
    var offset = 0;
    while (offset + 25 <= buffer.length) {
      if (buffer[offset] != 0x52) {
        offset++;
        continue;
      }
      try {
        final yy = _bcdToDecimal(buffer[offset + 3]);
        final mm = _bcdToDecimal(buffer[offset + 4]);
        final dd = _bcdToDecimal(buffer[offset + 5]);
        final hh = _bcdToDecimal(buffer[offset + 6]);
        final min = _bcdToDecimal(buffer[offset + 7]);
        if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
          offset += 25;
          continue;
        }
        final ts = DateTime(2000 + yy, mm, dd, hh, min);
        final steps = buffer[offset + 8] | (buffer[offset + 9] << 8);
        final calories = buffer[offset + 10] | (buffer[offset + 11] << 8);
        final distCm = buffer[offset + 12] | (buffer[offset + 13] << 8);
        final perMinute = List<int>.generate(
          10,
          (i) => buffer[offset + 14 + i],
        );
        records.add(
          RingDetailedStepRecord(
            timestamp: ts,
            steps: steps,
            calories: calories,
            distanceKm: distCm / 100000.0,
            perMinuteSteps: perMinute,
          ),
        );
      } catch (_) {}
      offset += 25;
    }
    debugPrint('[Ring BLE] fetchDetailedSteps: ${records.length} record(s)');
    return records;
  }

  // ─── Commands ────────────────────────────────────────────────────────────

  /// Command 0x01 — Set Time
  /// Fields must be BCD-encoded per protocol spec. Sending plain decimal values
  /// may return a success ACK but doesn't reliably update the ring RTC.
  /// Byte[7] carries the weekday (1=Mon, 7=Sun) to keep the ring's day-of-week
  /// counter in sync; the ring uses the same 1–7 convention as Dart's weekday.
  /// Returns true if the ring acknowledged success, false on failure or timeout.
  /// Never throws — errors are logged and the pairing flow continues.
  Future<bool> setTime() async {
    try {
      final now = DateTime.now();
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x01;
      payload[1] = _decimalToBcd(now.year - 2000);
      payload[2] = _decimalToBcd(now.month);
      payload[3] = _decimalToBcd(now.day);
      payload[4] = _decimalToBcd(now.hour);
      payload[5] = _decimalToBcd(now.minute);
      payload[6] = _decimalToBcd(now.second);
      payload[7] = now.weekday; // 1=Mon … 7=Sun (matches ring convention)

      if (_notifyChar == null) {
        await _writeCommand(payload);
        return true;
      }

      final completer = Completer<bool>();
      StreamSubscription<List<int>>? sub;
      sub = _notifyChar!.onValueReceived.listen((data) {
        if (data.isNotEmpty && (data[0] == 0x01 || data[0] == 0x81)) {
          if (!completer.isCompleted) completer.complete(data[0] == 0x01);
        }
      });

      try {
        await _writeCommand(payload);
        final success = await completer.future.timeout(_responseTimeout);
        if (!success)
          debugPrint('[Ring BLE] _setTime: ring returned failure (0x81)');
        return success;
      } on TimeoutException {
        // Ring accepted the write but sent no ACK — treat as non-fatal.
        debugPrint(
          '[Ring BLE] _setTime: no ACK within timeout, assuming success',
        );
        return true;
      } finally {
        await sub.cancel();
      }
    } catch (e) {
      debugPrint('[Ring BLE] _setTime error: $e');
      return false;
    }
  }

  /// Command 0x02 — Set User Info
  Future<void> setUserInfo({
    required int gender,
    required int age,
    required int heightCm,
    required int weightKg,
  }) async {
    final stepLen = _estimateStepLength(heightCm);
    final payload = List<int>.filled(15, 0);
    payload[0] = 0x02;
    payload[1] = gender;
    payload[2] = age;
    payload[3] = heightCm;
    payload[4] = weightKg;
    payload[5] = stepLen;
    for (var i = 6; i <= 11; i++) {
      payload[i] = 0x30; // '0'
    }
    await _writeCommand(payload);
  }

  /// Command 0x22 — Get MAC Address
  Future<String?> _getMacAddress() async {
    try {
      final response = await _sendCommandWithResponse(0x22);
      if (response == null || response.length < 7) return null;
      if (response[0] == 0xA2) return null;
      final mac = response
          .sublist(1, 7)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
      return mac;
    } catch (e) {
      debugPrint('[Ring BLE] getMacAddress error: $e');
      return null;
    }
  }

  /// Command 0x27 — Get Firmware Version
  Future<String?> _getFirmwareVersion() async {
    try {
      final response = await _sendCommandWithResponse(0x27);
      if (response == null || response.length < 8) return null;
      if (response[0] == 0xA7) return null;
      final a = _bcdToDecimal(response[1]);
      final b = _bcdToDecimal(response[2]);
      final c = _bcdToDecimal(response[3]);
      final d = _bcdToDecimal(response[4]);
      return '$a.$b.$c.$d';
    } catch (e) {
      debugPrint('[Ring BLE] getFirmwareVersion error: $e');
      return null;
    }
  }

  /// Command 0x13 — Get Battery Level
  Future<int?> _getBatteryLevel() async {
    try {
      final response = await _sendCommandWithResponse(0x13);
      if (response == null || response.length < 2) return null;
      if (response[0] == 0x93) return null;
      return response[1].clamp(0, 100);
    } catch (e) {
      debugPrint('[Ring BLE] getBatteryLevel error: $e');
      return null;
    }
  }

  // ─── Timestamp parsing ───────────────────────────────────────────────────

  /// Decode a 6-byte BCD timestamp from [data] starting at [offset].
  /// Returns null and logs a warning if any field is out of range or if
  /// decoding throws, so callers can skip corrupt records without crashing.
  ///
  /// Ring timestamps are always local time (the ring clock is set to local
  /// time via 0x01 SetTime), so the returned DateTime is local.
  DateTime? _parseRingTimestamp(List<int> data, int offset) {
    try {
      final yy = _bcdToDecimal(data[offset]);
      final mm = _bcdToDecimal(data[offset + 1]);
      final dd = _bcdToDecimal(data[offset + 2]);
      final hh = _bcdToDecimal(data[offset + 3]);
      final min = _bcdToDecimal(data[offset + 4]);
      final ss = _bcdToDecimal(data[offset + 5]);

      if (mm < 1 ||
          mm > 12 ||
          dd < 1 ||
          dd > 31 ||
          hh > 23 ||
          min > 59 ||
          ss > 59) {
        debugPrint(
          '[Ring BLE] Invalid timestamp at offset $offset: '
          'yy=$yy mm=$mm dd=$dd hh=$hh min=$min ss=$ss',
        );
        return null;
      }

      return DateTime(2000 + yy, mm, dd, hh, min, ss);
    } catch (e) {
      debugPrint('[Ring BLE] Timestamp parse error at offset $offset: $e');
      return null;
    }
  }

  // ─── Low-level helpers ───────────────────────────────────────────────────

  Future<void> _writeCommand(List<int> payload) async {
    if (_writeChar == null) throw Exception('Not connected');
    final packet = List<int>.filled(16, 0);
    for (var i = 0; i < 15; i++) {
      packet[i] = payload[i];
    }
    packet[15] = _computeCrc(packet.sublist(0, 15));
    debugPrint('[Ring TX] ${_hexDump(packet)}');
    await _writeChar!.write(packet, withoutResponse: false);
  }

  Future<List<int>?> _sendCommandWithResponse(int cmd) async {
    if (_notifyChar == null) return null;

    final completer = Completer<List<int>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.onValueReceived.listen((data) {
      if (data.isNotEmpty && (data[0] == cmd || data[0] == (cmd | 0x80))) {
        if (!completer.isCompleted) {
          completer.complete(data);
        }
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = cmd;
      await _writeCommand(payload);
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      debugPrint(
        '[Ring BLE] Timeout waiting for response to cmd 0x${cmd.toRadixString(16).padLeft(2, '0')}',
      );
      return null;
    } finally {
      await sub.cancel();
    }
  }

  void _subscribeRawNotifyLog() {
    _notifySubscription?.cancel();
    _notifySubscription = _notifyChar!.onValueReceived.listen((data) {
      if (data.isNotEmpty) {
        debugPrint('[Ring RX] ${_hexDump(data)}');
      }
    });
  }

  String _hexDump(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  int _computeCrc(List<int> bytes) {
    int sum = 0;
    for (final b in bytes) {
      sum += b;
    }
    return sum & 0xFF;
  }

  int _bcdToDecimal(int bcd) {
    return ((bcd >> 4) * 10) + (bcd & 0x0F);
  }

  int _decimalToBcd(int decimal) {
    return ((decimal ~/ 10) << 4) | (decimal % 10);
  }

  /// Decode a 3-byte BCD date (YY MM DD) from [data] at [offset].
  /// Returns null if any field is out of range.
  DateTime? _parseStepDate(List<int> data, int offset) {
    try {
      final yy = _bcdToDecimal(data[offset]);
      final mm = _bcdToDecimal(data[offset + 1]);
      final dd = _bcdToDecimal(data[offset + 2]);
      if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
      return DateTime(2000 + yy, mm, dd);
    } catch (_) {
      return null;
    }
  }

  /// Encode DateTime as 6-byte BCD timestamp: YY MM DD HH mm SS
  /// YY is relative to year 2000 (BCD)
  List<int> _encodeBcdTimestamp(DateTime dt) {
    final yy = _decimalToBcd(dt.year - 2000);
    final mm = _decimalToBcd(dt.month);
    final dd = _decimalToBcd(dt.day);
    final hh = _decimalToBcd(dt.hour);
    final min = _decimalToBcd(dt.minute);
    final ss = _decimalToBcd(dt.second);
    return [yy, mm, dd, hh, min, ss];
  }

  /// Decode a 4-byte little-endian unsigned integer from [data] at [offset].
  int _leInt32(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Decode a 4-byte little-endian IEEE 754 float from [data] at [offset].
  double _parseFloat32Le(List<int> data, int offset) {
    final bytes = Uint8List(4);
    bytes[0] = data[offset];
    bytes[1] = data[offset + 1];
    bytes[2] = data[offset + 2];
    bytes[3] = data[offset + 3];
    return bytes.buffer.asByteData().getFloat32(0, Endian.little);
  }

  int _estimateStepLength(int heightCm) {
    return ((heightCm * 0.415)).round().clamp(50, 100);
  }

  // ─── Bluetooth state helpers ─────────────────────────────────────────────

  static Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  static Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  static Future<bool> get isSupported async =>
      await FlutterBluePlus.isSupported;
}

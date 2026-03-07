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

class RingBleService {
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

  bool get isConnected => _connectedDevice != null && _writeChar != null;

  // ─── Scanning ────────────────────────────────────────────────────────────

  /// Scan for nearby Lumie Rings (filtered by device name prefix "X6B").
  Future<void> startScan({
    required void Function(DiscoveredRing ring) onFound,
    required void Function() onTimeout,
  }) async {
    debugPrint('[Ring BLE] startScan: stopping any existing scan');
    await FlutterBluePlus.stopScan();

    final found = <String>{};

    await FlutterBluePlus.startScan(
      timeout: _scanTimeout,
    );

    FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        if (!name.toUpperCase().startsWith('X6B')) continue;

        final id = result.device.remoteId.str;
        if (found.contains(id)) continue;
        found.add(id);

        debugPrint('[Ring BLE] Found ring: $name ($id) RSSI=${result.rssi}');
        onFound(DiscoveredRing(
          deviceId: id,
          displayName: name,
          rssi: result.rssi,
        ));
      }
    });

    await FlutterBluePlus.isScanning.where((s) => !s).first.timeout(
      _scanTimeout + const Duration(seconds: 2),
      onTimeout: () => false,
    );
    debugPrint('[Ring BLE] Scan complete, found ${found.length} ring(s)');
    onTimeout();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
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
    debugPrint('[Ring BLE] connectAndPair: ${ring.deviceId} (${ring.displayName})');
    final device = BluetoothDevice.fromId(ring.deviceId);

    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
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

    await _setTime();
    debugPrint('[Ring BLE] Time synced (0x01)');

    final mac = await _getMacAddress();
    debugPrint('[Ring BLE] MAC address: $mac');

    await _setUserInfo(gender: gender, age: age, heightCm: heightCm, weightKg: weightKg);
    debugPrint('[Ring BLE] User info set (0x02): gender=$gender age=$age h=${heightCm}cm w=${weightKg}kg');

    final firmwareVersion = await _getFirmwareVersion();
    debugPrint('[Ring BLE] Firmware: $firmwareVersion');

    final batteryLevel = await _getBatteryLevel();
    debugPrint('[Ring BLE] Battery: $batteryLevel%');

    final macFormatted = mac ?? ring.deviceId;
    final ringName = 'Lumie Ring ${macFormatted.length >= 5 ? macFormatted.substring(macFormatted.length - 5).replaceAll(':', '') : macFormatted}';

    _subscribeToConnectionState(device);
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

  /// Reconnect to a previously paired ring by device ID (no full handshake).
  /// Discovers GATT, enables notifications, and re-syncs time.
  Future<void> reconnect(String deviceId) async {
    debugPrint('[Ring BLE] reconnect: $deviceId');
    final device = BluetoothDevice.fromId(deviceId);

    // Cancel stale connection state sub before connecting
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;

    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
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
      debugPrint('[Ring BLE] ERROR: characteristics not found during reconnect');
      await disconnect();
      throw Exception('Characteristics not found during reconnect');
    }

    await _notifyChar!.setNotifyValue(true);
    _subscribeRawNotifyLog();
    await _setTime();
    debugPrint('[Ring BLE] Reconnect complete, time synced');
    _subscribeToConnectionState(device);
  }

  // ─── Heart Rate ───────────────────────────────────────────────────────────

  /// Command 0x55 — Fetch today's stored HR history from the ring.
  Future<List<HrDataPoint>> fetchHrHistory() async {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] fetchHrHistory: not connected');
      return [];
    }
    debugPrint('[Ring BLE] fetchHrHistory: sending 0x55');

    final today = DateTime.now();
    final results = <HrDataPoint>[];
    final completer = Completer<List<HrDataPoint>>();
    StreamSubscription<List<int>>? sub;

    sub = _notifyChar!.lastValueStream.listen((data) {
      if (data.isEmpty || data[0] != 0x55) return;

      if (data.length >= 2 && data[1] == 0xFF) {
        debugPrint('[Ring BLE] HR history end marker received, ${results.length} records today');
        if (!completer.isCompleted) completer.complete(results);
        return;
      }

      if (data.length < 10) return;

      final yy = _bcdToDecimal(data[3]);
      final mm = _bcdToDecimal(data[4]);
      final dd = _bcdToDecimal(data[5]);
      final hh = _bcdToDecimal(data[6]);
      final min = _bcdToDecimal(data[7]);
      final ss = _bcdToDecimal(data[8]);
      final hr = data[9];

      if (hr == 0 || hr >= 250) return;

      final recordTime = DateTime(2000 + yy, mm, dd, hh, min, ss);
      if (recordTime.year == today.year &&
          recordTime.month == today.month &&
          recordTime.day == today.day) {
        results.add(HrDataPoint(time: recordTime, bpm: hr));
      }
    });

    try {
      final payload = List<int>.filled(15, 0);
      payload[0] = 0x55;
      payload[1] = 0x00;
      await _writeCommand(payload);
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('[Ring BLE] HR history timeout, got ${results.length} records');
          return results;
        },
      );
    } catch (e) {
      debugPrint('[Ring BLE] fetchHrHistory error: $e');
      return results;
    } finally {
      await sub.cancel();
    }
  }

  /// Start an on-demand HR measurement.
  /// Sends 0x28 (HR mode) then enables 0x09 streaming.
  Stream<int> startHrStreaming() {
    if (_notifyChar == null) {
      debugPrint('[Ring BLE] startHrStreaming: not connected');
      return const Stream.empty();
    }
    debugPrint('[Ring BLE] startHrStreaming: starting 0x28 + 0x09');

    _hrStreamController?.close();
    _hrStreamController = StreamController<int>.broadcast();

    // Capture the notify char reference at subscription time.
    // If reconnect happens, old sub is cancelled and a new one is created.
    final notifyChar = _notifyChar!;

    _hrStreamSub?.cancel();
    _hrStreamSub = notifyChar.lastValueStream.listen((data) {
      if (data.isEmpty || data[0] != 0x09) return;

      int hr = 0;
      if (data.length == 16) {
        hr = data[13];
      } else if (data.length >= 26) {
        hr = data[21];
      }

      if (hr > 0 && hr < 250 && _hrStreamController?.isClosed == false) {
        debugPrint('[Ring BLE] HR reading: $hr BPM (packet len=${data.length})');
        _hrStreamController!.add(hr);
      }
    });

    // 0x28: Start dedicated HR measurement (green LED), 60s duration
    final measurePayload = List<int>.filled(15, 0);
    measurePayload[0] = 0x28;
    measurePayload[1] = 0x02; // HR mode
    measurePayload[2] = 0x01; // start
    measurePayload[5] = 60;   // duration_lo
    measurePayload[6] = 0x00; // duration_hi
    _writeCommand(measurePayload).catchError((e) {
      debugPrint('[Ring BLE] 0x28 write error: $e');
    });

    // 0x09: Enable realtime streaming
    final streamPayload = List<int>.filled(15, 0);
    streamPayload[0] = 0x09;
    streamPayload[1] = 0x01; // start
    streamPayload[2] = 0x01; // enable temperature
    _writeCommand(streamPayload).catchError((e) {
      debugPrint('[Ring BLE] 0x09 write error: $e');
    });

    return _hrStreamController!.stream;
  }

  /// Stop the on-demand HR measurement and streaming.
  Future<void> stopHrStreaming() async {
    debugPrint('[Ring BLE] stopHrStreaming');
    try {
      final measurePayload = List<int>.filled(15, 0);
      measurePayload[0] = 0x28;
      measurePayload[1] = 0x02;
      measurePayload[2] = 0x00; // stop
      await _writeCommand(measurePayload);
    } catch (e) {
      debugPrint('[Ring BLE] 0x28 stop error: $e');
    }

    try {
      final streamPayload = List<int>.filled(15, 0);
      streamPayload[0] = 0x09;
      streamPayload[1] = 0x00; // stop
      await _writeCommand(streamPayload);
    } catch (e) {
      debugPrint('[Ring BLE] 0x09 stop error: $e');
    }

    await _hrStreamSub?.cancel();
    _hrStreamSub = null;
    await _hrStreamController?.close();
    _hrStreamController = null;
    debugPrint('[Ring BLE] HR streaming stopped');
  }

  // ─── Commands ────────────────────────────────────────────────────────────

  /// Command 0x01 — Set Time
  Future<void> _setTime() async {
    final now = DateTime.now();
    final payload = List<int>.filled(15, 0);
    payload[0] = 0x01;
    payload[1] = now.year - 2000;
    payload[2] = now.month;
    payload[3] = now.day;
    payload[4] = now.hour;
    payload[5] = now.minute;
    payload[6] = now.second;
    await _writeCommand(payload);
  }

  /// Command 0x02 — Set User Info
  Future<void> _setUserInfo({
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
      final mac = response.sublist(1, 7)
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

    sub = _notifyChar!.lastValueStream.listen((data) {
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
      debugPrint('[Ring BLE] Timeout waiting for response to cmd 0x${cmd.toRadixString(16).padLeft(2, '0')}');
      return null;
    } finally {
      await sub.cancel();
    }
  }

  void _subscribeRawNotifyLog() {
    _notifySubscription?.cancel();
    _notifySubscription = _notifyChar!.lastValueStream.listen((data) {
      if (data.isNotEmpty) {
        debugPrint('[Ring RX] ${_hexDump(data)}');
      }
    });
  }

  String _hexDump(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

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

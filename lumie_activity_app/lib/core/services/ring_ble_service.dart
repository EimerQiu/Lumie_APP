// BLE communication service for the Lumie Smart Ring (X6B)
// Protocol details: see docs/SMART_RING_PROTOCOL.md
//
// GATT Service:    0000fff0-0000-1000-8000-00805f9b34fb
// Write char:      0000fff6-0000-1000-8000-00805f9b34fb
// Notify char:     0000fff7-0000-1000-8000-00805f9b34fb

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../shared/models/ring_models.dart';

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

  bool get isConnected => _connectedDevice != null && _writeChar != null;

  // ─── Scanning ────────────────────────────────────────────────────────────

  /// Scan for nearby Lumie Rings (filtered by device name prefix "X6B").
  /// Rings do not advertise their service UUID during scanning, so we scan
  /// all devices and filter by the name prefix used by the X6B hardware.
  /// Calls [onFound] for each discovered ring. Stops after [_scanTimeout].
  Future<void> startScan({
    required void Function(DiscoveredRing ring) onFound,
    required void Function() onTimeout,
  }) async {
    await FlutterBluePlus.stopScan();

    final found = <String>{};

    await FlutterBluePlus.startScan(
      timeout: _scanTimeout,
    );

    FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        // Only surface X6B devices (Lumie Ring hardware)
        if (!name.toUpperCase().startsWith('X6B')) continue;

        final id = result.device.remoteId.str;
        if (found.contains(id)) continue;
        found.add(id);

        onFound(DiscoveredRing(
          deviceId: id,
          displayName: name,
          rssi: result.rssi,
        ));
      }
    });

    // Wait for scan to complete then fire timeout callback
    await FlutterBluePlus.isScanning.where((s) => !s).first.timeout(
      _scanTimeout + const Duration(seconds: 2),
      onTimeout: () => false,
    );
    onTimeout();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ─── Connection ──────────────────────────────────────────────────────────

  /// Connect to a discovered ring device and perform handshake.
  /// Returns [RingInfo] on success, throws on failure.
  Future<RingInfo> connectAndPair({
    required DiscoveredRing ring,
    required int gender,    // 0=female, 1=male
    required int age,
    required int heightCm,
    required int weightKg,
  }) async {
    final device = BluetoothDevice.fromId(ring.deviceId);

    // Connect with auto-reconnect disabled (we manage this ourselves)
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    _connectedDevice = device;

    // Discover GATT services
    final services = await device.discoverServices();
    BluetoothService? lumieService;
    for (final s in services) {
      if (s.serviceUuid.str.toLowerCase().contains('fff0')) {
        lumieService = s;
        break;
      }
    }
    if (lumieService == null) {
      await disconnect();
      throw Exception('Not a Lumie Ring: required service not found.');
    }

    for (final c in lumieService.characteristics) {
      final uuid = c.characteristicUuid.str.toLowerCase();
      if (uuid.contains(_writeCharFragment)) _writeChar = c;
      if (uuid.contains(_notifyCharFragment)) _notifyChar = c;
    }

    if (_writeChar == null || _notifyChar == null) {
      await disconnect();
      throw Exception('Not a Lumie Ring: required characteristics not found.');
    }

    // Enable BLE notifications
    await _notifyChar!.setNotifyValue(true);

    // Step 1: Set current time on ring (command 0x01)
    await _setTime();

    // Step 2: Set user info (command 0x02)
    final mac = await _getMacAddress();
    await _setUserInfo(
      gender: gender,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
    );

    // Step 3: Get firmware version (command 0x27)
    final firmwareVersion = await _getFirmwareVersion();

    // Step 4: Get battery level (command 0x13)
    final batteryLevel = await _getBatteryLevel();

    final macFormatted = mac ?? ring.deviceId;
    final ringName = 'Lumie Ring ${macFormatted.length >= 5 ? macFormatted.substring(macFormatted.length - 5).replaceAll(':', '') : macFormatted}';

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
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _writeChar = null;
    _notifyChar = null;
  }

  // ─── Commands ────────────────────────────────────────────────────────────

  /// Command 0x01 — Set Time (plain decimal, NOT BCD)
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
    // ring_id bytes 6–11: "000000" in ASCII
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
      if (response[0] == 0xA2) return null; // error
      final mac = response.sublist(1, 7)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
      return mac;
    } catch (_) {
      return null;
    }
  }

  /// Command 0x27 — Get Firmware Version
  Future<String?> _getFirmwareVersion() async {
    try {
      final response = await _sendCommandWithResponse(0x27);
      if (response == null || response.length < 8) return null;
      if (response[0] == 0xA7) return null; // error
      final a = _bcdToDecimal(response[1]);
      final b = _bcdToDecimal(response[2]);
      final c = _bcdToDecimal(response[3]);
      final d = _bcdToDecimal(response[4]);
      return '$a.$b.$c.$d';
    } catch (_) {
      return null;
    }
  }

  /// Command 0x13 — Get Battery Level
  Future<int?> _getBatteryLevel() async {
    try {
      final response = await _sendCommandWithResponse(0x13);
      if (response == null || response.length < 2) return null;
      if (response[0] == 0x93) return null; // error
      return response[1].clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  // ─── Low-level helpers ───────────────────────────────────────────────────

  /// Write a 15-byte payload, appending the CRC byte at position 15.
  Future<void> _writeCommand(List<int> payload) async {
    if (_writeChar == null) throw Exception('Not connected');
    final packet = List<int>.filled(16, 0);
    for (var i = 0; i < 15; i++) {
      packet[i] = payload[i];
    }
    packet[15] = _computeCrc(packet.sublist(0, 15));
    await _writeChar!.write(packet, withoutResponse: false);
  }

  /// Send a single-byte command and wait for the first matching notify response.
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
      return null;
    } finally {
      await sub.cancel();
    }
  }

  /// CRC: sum of bytes[0..14] & 0xFF
  int _computeCrc(List<int> bytes) {
    int sum = 0;
    for (final b in bytes) {
      sum += b;
    }
    return sum & 0xFF;
  }

  /// BCD byte to decimal: ((byte >> 4) * 10) + (byte & 0x0F)
  int _bcdToDecimal(int bcd) {
    return ((bcd >> 4) * 10) + (bcd & 0x0F);
  }

  /// Estimate step length from height (rough heuristic: height * 0.415)
  int _estimateStepLength(int heightCm) {
    return ((heightCm * 0.415)).round().clamp(50, 100);
  }

  // ─── Bluetooth state helpers ─────────────────────────────────────────────

  /// Check if Bluetooth adapter is on
  static Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Stream of Bluetooth adapter state changes
  static Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  /// Whether the device supports BLE
  static Future<bool> get isSupported async =>
      await FlutterBluePlus.isSupported;
}

// Ring state management provider
// Handles BLE scanning, connection, pairing, and persistent ring info

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/services/ring_ble_service.dart';
import '../../../core/services/ring_service.dart';
import '../../../shared/models/ring_models.dart';

enum RingProviderState {
  idle,
  checkingBluetooth,
  scanning,
  connecting,
  paired,
  unpaired,
  error,
}

class RingProvider extends ChangeNotifier {
  final RingBleService _bleService = RingBleService();
  final RingService _ringService = RingService();

  RingProviderState _state = RingProviderState.idle;
  RingInfo? _ringInfo;
  List<DiscoveredRing> _discoveredRings = [];
  String? _errorMessage;
  bool _isBluetoothOn = false;
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription;

  RingProviderState get state => _state;
  RingInfo? get ringInfo => _ringInfo;
  List<DiscoveredRing> get discoveredRings => List.unmodifiable(_discoveredRings);
  String? get errorMessage => _errorMessage;
  bool get isBluetoothOn => _isBluetoothOn;
  bool get isPaired => _ringInfo?.isPaired ?? false;

  void setToken(String token) => _ringService.setToken(token);
  void clearToken() => _ringService.clearToken();

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> init() async {
    // Load cached ring info
    _ringInfo = await _ringService.loadLocalRingInfo();
    _state = (_ringInfo?.isPaired == true)
        ? RingProviderState.paired
        : RingProviderState.unpaired;

    // Monitor Bluetooth state
    _isBluetoothOn = await RingBleService.isBluetoothOn();
    _btStateSubscription = RingBleService.adapterStateStream.listen((state) {
      _isBluetoothOn = state == BluetoothAdapterState.on;
      notifyListeners();
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _btStateSubscription?.cancel();
    _bleService.disconnect();
    super.dispose();
  }

  // ─── Scanning ─────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    _errorMessage = null;
    _discoveredRings = [];
    _state = RingProviderState.scanning;
    notifyListeners();

    try {
      await _bleService.startScan(
        onFound: (ring) {
          if (!_discoveredRings.any((r) => r.deviceId == ring.deviceId)) {
            _discoveredRings = [..._discoveredRings, ring];
            notifyListeners();
          }
        },
        onTimeout: () {
          if (_state == RingProviderState.scanning) {
            _state = _discoveredRings.isEmpty
                ? RingProviderState.idle
                : RingProviderState.scanning;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      _errorMessage = 'Scan failed: ${e.toString()}';
      _state = RingProviderState.idle;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _bleService.stopScan();
    if (_state == RingProviderState.scanning) {
      _state = RingProviderState.idle;
      notifyListeners();
    }
  }

  // ─── Connection & Pairing ─────────────────────────────────────────────────

  /// Connect to a ring and pair it with the user's account.
  /// [gender]: 0=female, 1=male. [age], [heightCm], [weightKg] from user profile.
  Future<bool> connectAndPair({
    required DiscoveredRing ring,
    required int gender,
    required int age,
    required int heightCm,
    required int weightKg,
  }) async {
    _errorMessage = null;
    _state = RingProviderState.connecting;
    notifyListeners();

    try {
      // 1. Establish BLE connection and run handshake
      final bleInfo = await _bleService.connectAndPair(
        ring: ring,
        gender: gender,
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
      );

      // 2. Register with backend
      final savedInfo = await _ringService.pairRing(
        ringDeviceId: bleInfo.ringDeviceId!,
        ringName: bleInfo.ringName!,
        firmwareVersion: bleInfo.firmwareVersion,
      );

      _ringInfo = savedInfo.copyWith(
        batteryLevel: bleInfo.batteryLevel,
        connectionStatus: RingConnectionStatus.connected,
      );
      _state = RingProviderState.paired;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _state = _ringInfo?.isPaired == true
          ? RingProviderState.paired
          : RingProviderState.unpaired;
      notifyListeners();
      return false;
    }
  }

  // ─── Unpairing ────────────────────────────────────────────────────────────

  Future<void> unpairRing() async {
    await _bleService.disconnect();
    await _ringService.unpairRing();
    _ringInfo = null;
    _state = RingProviderState.unpaired;
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Ring prompt tracking ─────────────────────────────────────────────────

  Future<bool> hasShownRingPrompt() => _ringService.hasShownRingPrompt();
  Future<void> markRingPromptShown() => _ringService.markRingPromptShown();

  // ─── Logout cleanup ───────────────────────────────────────────────────────

  Future<void> clearOnLogout() async {
    await _bleService.disconnect();
    await _ringService.clearOnLogout();
    _ringInfo = null;
    _state = RingProviderState.unpaired;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

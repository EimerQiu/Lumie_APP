// Ring state management provider
// Handles BLE scanning, connection, pairing, and persistent ring info

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/services/ring_ble_service.dart';
import '../../../core/services/ring_service.dart';
import '../../../core/services/ring_sync_service.dart';
import '../../../core/services/ring_command_service.dart';
import '../../../shared/models/ring_models.dart';
import '../../../shared/models/heart_rate_models.dart';

enum RingProviderState {
  idle,
  checkingBluetooth,
  scanning,
  connecting,
  paired,
  disconnected, // paired ring exists but BLE is not currently connected
  reconnecting, // actively attempting background reconnect (direct or scan)
  unpaired,
  error,
}

class RingProvider extends ChangeNotifier with WidgetsBindingObserver {
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
  List<DiscoveredRing> get discoveredRings =>
      List.unmodifiable(_discoveredRings);
  String? get errorMessage => _errorMessage;
  bool get isBluetoothOn => _isBluetoothOn;
  bool get isPaired => _ringInfo?.isPaired ?? false;
  bool get isConnected => _bleService.isConnected;

  void setToken(String token) => _ringService.setToken(token);
  void clearToken() => _ringService.clearToken();

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    // Load cached ring info
    _ringInfo = await _ringService.loadLocalRingInfo();

    // Wire up disconnection callback so we get notified if the ring drops
    _bleService.onDisconnected = _handleDisconnected;

    if (_ringInfo?.isPaired == true) {
      // Start disconnected; attempt BLE reconnect in the background
      _state = RingProviderState.disconnected;
      _tryReconnect();
    } else {
      _state = RingProviderState.unpaired;
    }

    // Monitor Bluetooth adapter state
    _isBluetoothOn = await RingBleService.isBluetoothOn();
    _btStateSubscription = RingBleService.adapterStateStream.listen((state) {
      _isBluetoothOn = state == BluetoothAdapterState.on;
      notifyListeners();
    });

    notifyListeners();
  }

  void _handleDisconnected() {
    if (_ringInfo?.isPaired == true) {
      debugPrint('[Ring] Disconnected — scheduling auto-reconnect');
      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.disconnected,
      );
      _state = RingProviderState.disconnected;
      notifyListeners();
      // Auto-reconnect with retry after a short delay
      _autoReconnectWithRetry();
    }
  }

  /// Attempt to reconnect to the cached ring. Safe to call at any time.
  Future<void> tryReconnect() => _tryReconnect();

  Future<void> _tryReconnect() async {
    if (_bleService.isConnected) {
      // Already connected at the BLE layer — ensure provider state matches.
      if (_state != RingProviderState.paired) {
        _state = RingProviderState.paired;
        notifyListeners();
      }
      return;
    }
    final deviceId = _ringInfo?.ringDeviceId;
    if (deviceId == null) return;
    debugPrint('[Ring] tryReconnect: $deviceId');

    _state = RingProviderState.reconnecting;
    notifyListeners();

    try {
      // Fast path: direct connect by stored device ID (works on Android and
      // when the ring has been seen recently on iOS).
      try {
        await _bleService.reconnect(deviceId);
      } catch (directError) {
        // Slow path: scan for X6B rings and connect to the one that matches.
        // Required on iOS cold-start where CoreBluetooth needs to re-discover.
        debugPrint(
          '[Ring] Direct reconnect failed ($directError) — trying scan fallback',
        );
        await _bleService.scanAndReconnect(deviceId);
      }
      final battery = await _bleService.fetchBatteryLevel();
      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.connected,
        batteryLevel: battery ?? _ringInfo?.batteryLevel,
      );
      _state = RingProviderState.paired;
      debugPrint('[Ring] Reconnect succeeded');
      notifyListeners();
      _syncSleepInBackground();
    } catch (e) {
      debugPrint('[Ring] Reconnect failed: $e');
      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.disconnected,
      );
      _state = RingProviderState.disconnected;
      notifyListeners();
    }
  }

  /// Auto-reconnect on unexpected disconnect — retries every 30 s for up to
  /// 5 minutes (10 attempts) before giving up and showing "disconnected".
  /// First attempt fires after a 5 s stabilisation delay so the BLE stack
  /// has time to notice the disconnect before we try again.
  Future<void> _autoReconnectWithRetry() async {
    const maxAttempts = 10;
    const firstDelay = Duration(seconds: 5);
    const retryInterval = Duration(seconds: 30);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final deviceId = _ringInfo?.ringDeviceId;
      if (deviceId == null) return; // Ring unpaired while retrying
      if (_bleService.isConnected) return; // Already reconnected

      final delay = attempt == 1 ? firstDelay : retryInterval;
      debugPrint(
        '[Ring] Auto-reconnect attempt $attempt/$maxAttempts in ${delay.inSeconds}s',
      );
      await Future.delayed(delay);

      // Re-check after delay
      if (_bleService.isConnected || _ringInfo?.ringDeviceId == null) return;

      try {
        try {
          await _bleService.reconnect(deviceId);
        } catch (directError) {
          debugPrint(
            '[Ring] Auto-reconnect direct failed ($directError) — trying scan',
          );
          await _bleService.scanAndReconnect(deviceId);
        }
        final battery = await _bleService.fetchBatteryLevel();
        _ringInfo = _ringInfo?.copyWith(
          connectionStatus: RingConnectionStatus.connected,
          batteryLevel: battery ?? _ringInfo?.batteryLevel,
        );
        _state = RingProviderState.paired;
        debugPrint('[Ring] Auto-reconnect succeeded on attempt $attempt');
        notifyListeners();
        _syncSleepInBackground();
        return;
      } catch (e) {
        debugPrint('[Ring] Auto-reconnect attempt $attempt failed: $e');
        if (attempt == maxAttempts) {
          debugPrint('[Ring] All reconnect attempts exhausted after 5 min');
          _ringInfo = _ringInfo?.copyWith(
            connectionStatus: RingConnectionStatus.disconnected,
          );
          _state = RingProviderState.disconnected;
          notifyListeners();
        }
      }
    }
  }

  // ─── Background sleep sync ────────────────────────────────────────────────

  /// Triggered automatically after every successful connect / reconnect.
  /// Fetches sleep records (0x53) and HR history (0x55) from the ring, then
  /// uploads to the backend.  Retries the sleep fetch once if the first
  /// attempt times out before the end-of-data marker is received.
  /// All errors are caught — this must never disrupt the connection flow.
  void _syncSleepInBackground() {
    if (!isConnected) return;
    RingSyncService().triggerSync(
      fetchSleep: () => _bleService.fetchSleepHistory(),
      fetchHr: () => _bleService.fetchHrHistory(),
      fetchSteps: () => _bleService.fetchStepHistory(),
      fetchHrv: () => _bleService.fetchHrvHistory(),
      fetchHrDetails: () => _bleService.fetchHrDetails(),
      fetchTemperature: () => _bleService.fetchTemperatureHistory(),
      fetchSpo2: () => _bleService.fetchSpo2History(),
    );
    RingCommandService().checkAndExecute(_bleService);
  }

  /// Handle a remote ring command notification while the app is already open.
  /// If we are connected, execute immediately. If paired but disconnected,
  /// reconnect first; successful reconnect will poll pending commands.
  Future<void> handleRemoteRingCommand() async {
    if (isConnected) {
      _syncSleepInBackground();
      return;
    }

    if (isPaired) {
      await _tryReconnect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSleepInBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  // ─── Heart Rate BLE delegation ────────────────────────────────────────────

  Future<List<HrDataPoint>> fetchHrHistory() =>
      isPaired ? _bleService.fetchHrHistory() : Future.value([]);

  Stream<int> startHrStreaming() =>
      isPaired ? _bleService.startHrStreaming() : const Stream.empty();

  Future<void> stopHrStreaming() =>
      isPaired ? _bleService.stopHrStreaming() : Future.value();

  // ─── Sleep BLE delegation ─────────────────────────────────────────────────

  Future<({List<RingRawSleepRecord> records, bool isComplete})>
  fetchSleepHistory() => isPaired
      ? _bleService.fetchSleepHistory()
      : Future.value((records: <RingRawSleepRecord>[], isComplete: false));

  // ─── Step BLE delegation ──────────────────────────────────────────────────

  Future<List<RingRawDailySteps>> fetchStepHistory() =>
      isPaired ? _bleService.fetchStepHistory() : Future.value([]);

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

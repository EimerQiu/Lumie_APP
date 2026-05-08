// Ring state management provider
// Handles BLE scanning, connection, pairing, and persistent ring info

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/services/debug_log_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/ring_ble_service.dart';
import '../../../core/services/ring_service.dart';
import '../../../core/services/ring_sync_service.dart';
import '../../../core/services/ring_command_service.dart';
import '../../../shared/models/ring_models.dart';
import '../../../shared/models/heart_rate_models.dart';
import '../../../shared/models/user_models.dart';

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
  final ProfileService _profileService = ProfileService();

  RingProviderState _state = RingProviderState.idle;
  RingInfo? _ringInfo;
  List<DiscoveredRing> _discoveredRings = [];
  String? _errorMessage;
  bool _isBluetoothOn = false;
  bool _heartRateMeasurementInProgress = false;
  Future<void>? _reconnectInFlight;
  bool _autoReconnectLoopRunning = false;
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription;
  Timer? _commandPollTimer;

  RingProviderState get state => _state;
  RingInfo? get ringInfo => _ringInfo;
  List<DiscoveredRing> get discoveredRings =>
      List.unmodifiable(_discoveredRings);
  String? get errorMessage => _errorMessage;
  bool get isBluetoothOn => _isBluetoothOn;
  bool get isPaired => _ringInfo?.isPaired ?? false;
  bool get isConnected => _bleService.isConnected;
  bool get isHeartRateMeasurementInProgress => _heartRateMeasurementInProgress;

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
      _state = RingProviderState.disconnected;
    } else {
      _state = RingProviderState.unpaired;
    }

    // Monitor Bluetooth adapter state and attempt reconnect when BT is ready
    _isBluetoothOn = await RingBleService.isBluetoothOn();
    _btStateSubscription = RingBleService.adapterStateStream.listen((state) {
      _isBluetoothOn = state == BluetoothAdapterState.on;
      notifyListeners();

      // Auto-reconnect when BT becomes available
      if (_isBluetoothOn &&
          _ringInfo?.isPaired == true &&
          _state == RingProviderState.disconnected) {
        debugPrint('[Ring] Bluetooth is now on, attempting auto-reconnect');
        _tryReconnect();
      }
    });

    // If BT is already on, try reconnect immediately
    if (_isBluetoothOn && _ringInfo?.isPaired == true) {
      debugPrint(
        '[Ring] Bluetooth is on at init, attempting initial reconnect',
      );
      _tryReconnect();
    } else if (!_isBluetoothOn && _ringInfo?.isPaired == true) {
      debugPrint(
        '[Ring] Bluetooth not ready at init, will reconnect when ready',
      );
    }

    notifyListeners();
  }

  void _handleDisconnected() {
    if (_ringInfo?.isPaired == true) {
      debugPrint('[Ring] Disconnected — scheduling auto-reconnect');
      dlog('RING', 'handleDisconnected → scheduling auto-reconnect');
      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.disconnected,
      );
      _state = RingProviderState.disconnected;
      notifyListeners();
      // Auto-reconnect with retry after a short delay
      unawaited(_autoReconnectWithRetry());
    }
  }

  /// Attempt to reconnect to the cached ring. Safe to call at any time.
  Future<void> tryReconnect() => _tryReconnect();

  Future<void> _tryReconnect() async {
    if (_reconnectInFlight != null) {
      dlog('RING', 'reconnect skipped: in-flight reconnect already running');
      return _reconnectInFlight;
    }
    final future = _tryReconnectInternal(runBackgroundSyncAfterConnect: true);
    _reconnectInFlight = future.whenComplete(() {
      _reconnectInFlight = null;
    });
    return _reconnectInFlight;
  }

  Future<void> _tryReconnectInternal({
    required bool runBackgroundSyncAfterConnect,
  }) async {
    if (_bleService.isConnected) {
      // Already connected at the BLE layer — ensure provider state matches.
      if (_state != RingProviderState.paired) {
        _state = RingProviderState.paired;
        notifyListeners();
      }
      return;
    }
    final bleDeviceName = await _ringService.loadLastBleDeviceName();
    final bleDeviceId =
        await _ringService.loadLastBleDeviceId() ?? _ringInfo?.ringDeviceId;
    if (bleDeviceName == null && bleDeviceId == null) return;
    debugPrint('[Ring] tryReconnect: name=$bleDeviceName id=$bleDeviceId');

    _state = RingProviderState.reconnecting;
    notifyListeners();
    dlog('RING', 'reconnect attempt name=$bleDeviceName id=$bleDeviceId');

    try {
      try {
        if (bleDeviceName != null && bleDeviceName.isNotEmpty) {
          await _bleService.scanAndReconnectByName(bleDeviceName);
        } else if (bleDeviceId != null) {
          await _bleService.reconnect(bleDeviceId);
        } else {
          throw Exception('No cached ring identifier available');
        }
      } catch (directError) {
        debugPrint(
          '[Ring] Preferred reconnect failed ($directError) — trying scan fallback',
        );
        dlog('RING', 'preferred reconnect failed: $directError → scan fallback');
        if (bleDeviceId != null) {
          await _bleService.scanAndReconnect(bleDeviceId);
        } else if (bleDeviceName != null && bleDeviceName.isNotEmpty) {
          await _bleService.scanAndReconnectByName(bleDeviceName);
        } else {
          throw Exception('No cached ring identifier available');
        }
      }
      final battery = await _bleService.fetchBatteryLevel();
      final connectedBleId = _bleService.connectedBleDeviceId;
      if (connectedBleId != null) {
        await _ringService.saveLastBleDeviceId(connectedBleId);
      }
      final connectedBleName = _bleService.connectedBleDeviceName;
      if (connectedBleName != null && connectedBleName.isNotEmpty) {
        await _ringService.saveLastBleDeviceName(connectedBleName);
      }

      // Initialize ring: set time, user info, and measurement intervals
      final ringUser = await _resolveRingUserInfoFromProfile();
      await _bleService.initializeRing(
        gender: ringUser.gender,
        age: ringUser.age,
        heightCm: ringUser.heightCm,
        weightKg: ringUser.weightKg,
      );

      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.connected,
        batteryLevel: battery ?? _ringInfo?.batteryLevel,
      );
      if (_ringInfo != null) {
        await _ringService.saveLocalRingInfo(_ringInfo!);
      }
      _state = RingProviderState.paired;
      debugPrint('[Ring] Reconnect succeeded');
      dlog('RING', 'reconnect succeeded — battery=$battery');
      notifyListeners();
      if (runBackgroundSyncAfterConnect) {
        _syncSleepInBackground();
      }
    } catch (e) {
      debugPrint('[Ring] Reconnect failed: $e');
      dlog('RING', 'reconnect failed: $e');
      _ringInfo = _ringInfo?.copyWith(
        connectionStatus: RingConnectionStatus.disconnected,
      );
      _state = RingProviderState.disconnected;
      notifyListeners();
    }
  }

  /// Auto-reconnect on unexpected disconnect — uses exponential backoff so we
  /// don't hammer the BLE scanner when the ring is genuinely unreachable
  /// (out of range, rebooting, battery dead). Total wait across all attempts
  /// is roughly 28 minutes before we give up and show "disconnected".
  ///
  /// Schedule (seconds): 5, 10, 30, 60, 120, 300, 300, 300, 300, 300.
  static const List<int> _reconnectBackoffSeconds = [
    5, 10, 30, 60, 120, 300, 300, 300, 300, 300,
  ];

  Future<void> _autoReconnectWithRetry() async {
    if (_autoReconnectLoopRunning) {
      dlog('RING', 'auto-reconnect loop skipped: already running');
      return;
    }
    _autoReconnectLoopRunning = true;
    final maxAttempts = _reconnectBackoffSeconds.length;

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final bleDeviceName = await _ringService.loadLastBleDeviceName();
        final bleDeviceId =
            await _ringService.loadLastBleDeviceId() ?? _ringInfo?.ringDeviceId;
        if (bleDeviceName == null && bleDeviceId == null) return;
        if (_bleService.isConnected) return; // Already reconnected

        final delay = Duration(
          seconds: _reconnectBackoffSeconds[attempt - 1],
        );
        debugPrint(
          '[Ring] Auto-reconnect attempt $attempt/$maxAttempts in ${delay.inSeconds}s',
        );
        dlog(
          'RING',
          'auto-reconnect attempt $attempt/$maxAttempts — waiting ${delay.inSeconds}s',
        );
        await Future.delayed(delay);

        // Re-check after delay
        if (_bleService.isConnected || _ringInfo?.ringDeviceId == null) return;

        await _tryReconnect();
        if (_bleService.isConnected) {
          debugPrint('[Ring] Auto-reconnect succeeded on attempt $attempt');
          return;
        }
        if (attempt == maxAttempts) {
          debugPrint('[Ring] All reconnect attempts exhausted');
          dlog('RING', 'auto-reconnect exhausted after $maxAttempts attempts');
          _ringInfo = _ringInfo?.copyWith(
            connectionStatus: RingConnectionStatus.disconnected,
          );
          _state = RingProviderState.disconnected;
          notifyListeners();
        }
      }
    } finally {
      _autoReconnectLoopRunning = false;
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
    if (_heartRateMeasurementInProgress) {
      debugPrint('[RCMD] Sync skipped: heart-rate measurement in progress');
      return;
    }
    unawaited(_writeUserInfoToRing());
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

  Future<void> _writeUserInfoToRing() async {
    if (!isConnected) return;
    try {
      final ringUser = await _resolveRingUserInfoFromProfile();
      await _bleService.setUserInfo(
        gender: ringUser.gender,
        age: ringUser.age,
        heightCm: ringUser.heightCm,
        weightKg: ringUser.weightKg,
      );
      debugPrint(
        '[Ring] User info synced to ring: gender=${ringUser.gender} age=${ringUser.age} h=${ringUser.heightCm} w=${ringUser.weightKg}',
      );
    } catch (e) {
      debugPrint('[Ring] Failed to sync user info to ring: $e');
    }
  }

  Future<({int gender, int age, int heightCm, int weightKg})>
  _resolveRingUserInfoFromProfile() async {
    // Defaults kept conservative; values are clamped before writing to ring.
    var gender = 1; // 1=male, 2=female (protocol)
    var age = 20;
    var heightCm = 170;
    var weightKg = 70;

    try {
      final profile = await _profileService.getProfile();
      if (profile.age != null) {
        age = profile.age!.clamp(5, 100);
      }
      if (profile.height != null) {
        heightCm = _toHeightCm(profile.height!).clamp(80, 240);
      }
      if (profile.weight != null) {
        weightKg = _toWeightKg(profile.weight!).clamp(25, 250);
      }
      // No explicit gender in current profile model; keep default.
    } catch (_) {
      // Keep defaults if profile read fails.
    }

    return (gender: gender, age: age, heightCm: heightCm, weightKg: weightKg);
  }

  int _toHeightCm(HeightData height) {
    if (height.unit == HeightUnit.cm) return height.value.round();
    // ft/in mode stores total inches in value.
    return (height.value * 2.54).round();
  }

  int _toWeightKg(WeightData weight) {
    if (weight.unit == WeightUnit.kg) return weight.value.round();
    return (weight.value / 2.20462).round();
  }

  Future<void> _checkPendingRingCommandsOnly() async {
    if (!isConnected) return;
    await RingCommandService().checkAndExecute(_bleService);
  }

  Future<RingHrMeasurementResult?> measureHeartRate({
    int durationSeconds = 30,
  }) async {
    if (!isPaired || !isConnected) {
      debugPrint('[RCMD] measureHeartRate skipped: ring not connected');
      return null;
    }
    if (_heartRateMeasurementInProgress) {
      debugPrint(
        '[RCMD] measureHeartRate skipped: measurement already in progress',
      );
      return null;
    }

    _heartRateMeasurementInProgress = true;
    try {
      return await _bleService.measureHeartRate(
        durationSeconds: durationSeconds,
      );
    } finally {
      _heartRateMeasurementInProgress = false;
    }
  }

  /// Handle a remote ring command notification while the app is already open.
  /// If we are connected, execute immediately. If paired but disconnected,
  /// reconnect first; successful reconnect will poll pending commands.
  Future<void> handleRemoteRingCommand() async {
    debugPrint(
      '[RingCommand] 🔄 Handler called: isConnected=$isConnected isPaired=$isPaired state=$_state',
    );
    if (isConnected) {
      debugPrint(
        '[RingCommand] ✓ Already connected, checking pending commands...',
      );
      await _checkPendingRingCommandsOnly();
      return;
    }

    if (isPaired) {
      debugPrint(
        '[RingCommand] ⟳ Paired but disconnected, attempting reconnect...',
      );
      await _tryReconnectInternal(runBackgroundSyncAfterConnect: false);
      await _checkPendingRingCommandsOnly();
      return;
    }

    debugPrint('[RingCommand] ❌ Ring not paired, ignoring command');
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
            _state = RingProviderState.idle;
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
      await _ringService.saveLastBleDeviceId(ring.deviceId);
      await _ringService.saveLastBleDeviceName(ring.displayName);

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

  Future<List<HrDataPoint>> fetchHrHistoryRange({
    required DateTime start,
    DateTime? end,
  }) => isPaired
      ? _bleService.fetchHrHistoryRange(start: start, end: end)
      : Future.value([]);

  Future<List<HrDataPoint>> fetchHrDetailsRange({
    required DateTime start,
    DateTime? end,
  }) => isPaired
      ? _bleService.fetchHrDetailsRange(start: start, end: end)
      : Future.value([]);

  // ─── Heart Rate Streaming ─────────────────────────────────────────────────

  /// Start streaming real-time heart rate from the ring.
  /// Returns a Stream<int> of BPM values.
  Stream<int> startHrStreaming() {
    if (!isPaired || !isConnected) return Stream.empty();
    return _bleService.startHrStreaming();
  }

  /// Stop streaming heart rate data from the ring.
  Future<void> stopHrStreaming() async {
    await _bleService.stopHrStreaming();
  }

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

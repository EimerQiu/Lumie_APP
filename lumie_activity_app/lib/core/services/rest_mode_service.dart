import 'package:shared_preferences/shared_preferences.dart';

/// Tracks manually-activated Rest Mode with a 24-hour auto-expiry.
///
/// Activation is triggered when the user accepts a rest day suggestion.
/// The activation timestamp is persisted so the timer survives app restarts.
class RestModeService {
  static final RestModeService _instance = RestModeService._internal();
  factory RestModeService() => _instance;
  RestModeService._internal();

  static const _kActivatedAt = 'rest_mode_activated_at';
  static const _kExpiry = Duration(hours: 24);

  SharedPreferences? _prefs;

  /// Call once at app startup before [runApp] to load persisted state
  /// and immediately expire any stale activation.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await checkAndExpire();
  }

  /// True if Rest Mode was manually activated and the 24-hour window has not
  /// yet elapsed.
  bool get isActive {
    final raw = _prefs?.getString(_kActivatedAt);
    if (raw == null) return false;
    final activatedAt = DateTime.tryParse(raw);
    if (activatedAt == null) return false;
    return DateTime.now().difference(activatedAt) < _kExpiry;
  }

  /// When Rest Mode was activated, or null if it is not currently active.
  DateTime? get activatedAt {
    if (!isActive) return null;
    final raw = _prefs?.getString(_kActivatedAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// How long until Rest Mode auto-expires, or null if it is not active.
  Duration? get timeRemaining {
    final at = activatedAt;
    if (at == null) return null;
    final remaining = _kExpiry - DateTime.now().difference(at);
    return remaining.isNegative ? null : remaining;
  }

  /// Start Rest Mode now. Overwrites any previous activation timestamp.
  Future<void> activate() async {
    final prefs = await _ensurePrefs();
    await prefs.setString(_kActivatedAt, DateTime.now().toIso8601String());
  }

  /// Manually deactivate Rest Mode before the 24-hour window expires.
  Future<void> deactivate() async {
    final prefs = await _ensurePrefs();
    await prefs.remove(_kActivatedAt);
  }

  /// Remove the stored key if 24 h have elapsed since activation.
  /// Call this on app launch and on app resume so the Today page reflects
  /// the correct state without needing a live timer.
  Future<void> checkAndExpire() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(_kActivatedAt);
    if (raw == null) return;
    final activatedAt = DateTime.tryParse(raw);
    if (activatedAt == null ||
        DateTime.now().difference(activatedAt) >= _kExpiry) {
      await prefs.remove(_kActivatedAt);
    }
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }
}

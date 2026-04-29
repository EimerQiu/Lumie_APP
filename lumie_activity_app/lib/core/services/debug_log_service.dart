import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// File-based diagnostic log for the HR/BLE pipeline.
///
/// When enabled, every `log(tag, msg)` call appends a line like
/// `2026-04-28T13:55:02.341Z [HR_BLE] 0x18 → 78 BPM (t=312s)` to
/// `${ApplicationDocumentsDirectory}/lumie_diag.log`. The file rolls over to
/// `lumie_diag.log.1` once it exceeds [_maxBytes].
///
/// Calls are non-blocking — they enqueue onto a single Future chain so writes
/// stay ordered and never overlap. If file IO fails the error is swallowed so
/// the BLE/HR pipeline is never affected by logging.
///
/// The toggle is persisted in SharedPreferences under [_kEnabledKey] so the
/// switch survives app restarts.
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  static const String _kEnabledKey = 'debug_log_enabled';
  static const String _logFileName = 'lumie_diag.log';
  static const String _logRotationName = 'lumie_diag.log.1';
  static const int _maxBytes = 20 * 1024 * 1024; // 20 MB

  bool _enabled = false;
  bool _initialized = false;
  File? _logFile;
  Future<void> _writeChain = Future.value();

  bool get isEnabled => _enabled;

  /// Load the persisted enable flag and resolve the log file path.
  /// Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabledKey) ?? false;
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');
    } catch (e) {
      debugPrint('[DebugLog] init error: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    await init();
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, value);
    } catch (e) {
      debugPrint('[DebugLog] persist error: $e');
    }
    if (value) {
      log('DEBUG_LOG', 'Logging enabled');
    }
  }

  /// Append a single line. No-op when disabled. Never throws.
  void log(String tag, String message) {
    if (!_enabled) return;
    final ts = DateTime.now().toUtc().toIso8601String();
    final line = '$ts [$tag] $message\n';
    _enqueueWrite(line);
  }

  void _enqueueWrite(String line) {
    _writeChain = _writeChain.then((_) async {
      final file = _logFile;
      if (file == null) return;
      try {
        // Best-effort rotation when the file exceeds the cap.
        if (await file.exists()) {
          final size = await file.length();
          if (size > _maxBytes) {
            try {
              final dir = file.parent;
              final rotated = File('${dir.path}/$_logRotationName');
              if (await rotated.exists()) {
                await rotated.delete();
              }
              await file.rename(rotated.path);
              // After rename `file` no longer exists at its path; the next
              // write below will create it fresh.
            } catch (e) {
              debugPrint('[DebugLog] rotation error: $e');
            }
          }
        }
        await file.writeAsString(
          line,
          mode: FileMode.append,
          flush: false,
        );
      } catch (e) {
        debugPrint('[DebugLog] write error: $e');
      }
    });
  }

  /// Wait for all queued writes to land on disk. Useful before exporting.
  Future<void> flush() async {
    await _writeChain;
  }

  Future<File?> getLogFile() async {
    await init();
    return _logFile;
  }

  /// Returns (current_size, rotated_size). Either may be 0 if the file
  /// doesn't exist yet.
  Future<({int current, int rotated})> getSizes() async {
    await init();
    int current = 0;
    int rotated = 0;
    try {
      final file = _logFile;
      if (file != null && await file.exists()) {
        current = await file.length();
      }
      final dir = await getApplicationDocumentsDirectory();
      final rot = File('${dir.path}/$_logRotationName');
      if (await rot.exists()) {
        rotated = await rot.length();
      }
    } catch (e) {
      debugPrint('[DebugLog] size error: $e');
    }
    return (current: current, rotated: rotated);
  }

  /// Delete both the active log and the rotated copy.
  Future<void> clear() async {
    await init();
    await flush();
    try {
      final file = _logFile;
      if (file != null && await file.exists()) {
        await file.delete();
      }
      final dir = await getApplicationDocumentsDirectory();
      final rot = File('${dir.path}/$_logRotationName');
      if (await rot.exists()) {
        await rot.delete();
      }
    } catch (e) {
      debugPrint('[DebugLog] clear error: $e');
    }
  }
}

/// Convenience top-level shorthand: `dlog('HR_BLE', '...')`.
void dlog(String tag, String message) => DebugLogService().log(tag, message);

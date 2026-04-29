import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/debug_log_service.dart';
import '../../../core/theme/app_colors.dart';

/// Diagnostics & detailed logging.
///
/// When the toggle is on, the app appends one line to a log file for every
/// BLE notify packet, HR provider state change, gap, backfill round, and
/// reconnect. The file lives in the app's documents directory; on iOS it can
/// be pulled via the Files app (Lumie folder) since UIFileSharingEnabled +
/// LSSupportsOpeningDocumentsInPlace are set in Info.plist. On a tethered
/// Mac, Xcode → Devices → Lumie → Documents also works.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final DebugLogService _logService = DebugLogService();
  bool _enabled = false;
  bool _loading = true;
  String? _logPath;
  int _currentBytes = 0;
  int _rotatedBytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await _logService.init();
    final file = await _logService.getLogFile();
    final sizes = await _logService.getSizes();
    if (!mounted) return;
    setState(() {
      _enabled = _logService.isEnabled;
      _logPath = file?.path;
      _currentBytes = sizes.current;
      _rotatedBytes = sizes.rotated;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await _logService.setEnabled(value);
    await _refresh();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear logs?'),
        content: const Text(
          'This deletes the active log file and any rotated backups.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _logService.clear();
      await _refresh();
    }
  }

  Future<void> _copyPath() async {
    final path = _logPath;
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log path copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Diagnostics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildToggleCard(),
                const SizedBox(height: 16),
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildHelpCard(),
              ],
            ),
    );
  }

  Widget _buildToggleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLemon.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bug_report_outlined,
              size: 22,
              color: AppColors.textOnYellow,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detailed BLE/HR Logging',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Captures every ring packet, HR reading, gap and reconnect.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _enabled,
            activeColor: AppColors.primaryLemonDark,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final totalBytes = _currentBytes + _rotatedBytes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Log Files',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _kvRow('Active file', _fmtBytes(_currentBytes)),
          if (_rotatedBytes > 0) ...[
            const SizedBox(height: 8),
            _kvRow('Rotated backup', _fmtBytes(_rotatedBytes)),
          ],
          const SizedBox(height: 8),
          _kvRow('Total on disk', _fmtBytes(totalBytes)),
          const SizedBox(height: 12),
          if (_logPath != null) ...[
            Text(
              'File path',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _logPath!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textPrimary,
                fontFamily: 'Menlo',
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _logPath == null ? null : _copyPath,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy path'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.textLight),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: totalBytes == 0 ? null : _clear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundPaper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to download the log',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'iOS — Files app:\n'
            '• Open the Files app on this iPhone\n'
            '• On My iPhone, find the Lumie folder\n'
            '• lumie_diag.log appears there. Long-press to share.\n\n'
            'iOS — Mac (tethered):\n'
            '• Open Xcode → Window → Devices and Simulators\n'
            '• Select this device, find Lumie under Installed Apps\n'
            '• Click the gear → Download Container — the log file is\n'
            '  inside AppData/Documents/lumie_diag.log',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

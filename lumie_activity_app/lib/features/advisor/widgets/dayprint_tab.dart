import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/dayprint_service.dart';
import '../../../shared/models/dayprint_models.dart';

class DayprintTab extends StatefulWidget {
  const DayprintTab({super.key});

  @override
  State<DayprintTab> createState() => _DayprintTabState();
}

class _DayprintTabState extends State<DayprintTab>
    with AutomaticKeepAliveClientMixin {
  final DayprintService _service = DayprintService();
  Dayprint? _dayprint;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => false; // Reload when tab is revisited

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dp = await _service.getTodayDayprint();
      if (mounted) setState(() => _dayprint = dp);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load Dayprint.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLemonDark),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_dayprint == null || _dayprint!.events.isEmpty) {
      return _EmptyDayprint(onRefresh: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryLemonDark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SectionHeader(
            title: "Today's Log",
            subtitle: '${_dayprint!.events.length} entries',
          ),
          const SizedBox(height: 12),
          ..._dayprint!.events.reversed.map((e) => _EventTile(event: e)),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyDayprint extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyDayprint({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primaryLemon,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('✦', style: TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your Dayprint is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Complete tasks or chat with your advisor to\nbuild today\'s log.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryLemonDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textLight),
        ),
      ],
    );
  }
}

// ── Event tile ────────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final DayprintEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isTask = event.type == 'task_completed';
    final isChat = event.type == 'advisor_chat';

    final icon = isTask
        ? Icons.check_circle_outline_rounded
        : Icons.chat_bubble_outline_rounded;
    final iconColor =
        isTask ? AppColors.success : AppColors.primaryLemonDark;
    final iconBg = isTask
        ? const Color(0xFFDCFCE7)
        : AppColors.primaryLemon;

    String title;
    String? subtitle;
    if (isTask) {
      title = event.data['task_name'] as String? ?? 'Task';
      final type = event.data['task_type'] as String? ?? '';
      subtitle = type.isNotEmpty ? type : null;
    } else if (isChat) {
      title = event.data['summary'] as String? ?? 'Advisor chat';
      subtitle = null;
    } else {
      title = event.type;
    }

    final timeStr = _formatTime(event.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      String s = iso;
      if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
      final dt = DateTime.parse(s).toLocal();
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final hour12 = h % 12 == 0 ? 12 : h % 12;
      return '$hour12:$m $period';
    } catch (_) {
      return '';
    }
  }
}

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
  static const int _pageSize = 14;

  final DayprintService _service = DayprintService();
  final ScrollController _scrollController = ScrollController();

  final List<_TimelineEntry> _entries = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _nextBeforeDate;
  String? _error;

  @override
  bool get wantKeepAlive => false; // Reload when tab is revisited

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _entries.clear();
      _hasMore = true;
      _nextBeforeDate = null;
    });

    try {
      final page = await _service.getDayprintHistory(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _entries.addAll(_flattenDayprints(page.dayprints));
        _hasMore = page.hasMore;
        _nextBeforeDate = page.nextBeforeDate;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load Dayprint.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);
    try {
      final page = await _service.getDayprintHistory(
        limit: _pageSize,
        beforeDate: _nextBeforeDate,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(_flattenDayprints(page.dayprints));
        _hasMore = page.hasMore;
        _nextBeforeDate = page.nextBeforeDate;
      });
    } catch (_) {
      // Keep existing list when load-more fails.
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  List<_TimelineEntry> _flattenDayprints(List<Dayprint> dayprints) {
    final result = <_TimelineEntry>[];
    for (final day in dayprints) {
      for (final event in day.events.reversed) {
        result.add(_TimelineEntry(date: day.date, event: event));
      }
    }
    return result;
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
            Text(
              _error!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return _EmptyDayprint(onRefresh: _load);
    }

    final totalLabel = _hasMore
        ? '${_entries.length}+ entries'
        : '${_entries.length} entries';

    return SelectionArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primaryLemonDark,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: _entries.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'All Logs', subtitle: totalLabel),
                  const SizedBox(height: 12),
                ],
              );
            }

            if (index == _entries.length + 1) {
              if (_loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryLemonDark,
                      ),
                    ),
                  ),
                );
              }
              if (!_hasMore) {
                return const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 2),
                  child: Center(
                    child: Text(
                      'No more logs',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            final entry = _entries[index - 1];
            return _EventTile(event: entry.event, dayDate: entry.date);
          },
        ),
      ),
    );
  }
}

class _TimelineEntry {
  final String date;
  final DayprintEvent event;

  const _TimelineEntry({required this.date, required this.event});
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
              'No Dayprint logs yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Complete tasks or chat with your advisor to\nbuild your Dayprint timeline.',
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
  final String dayDate;
  const _EventTile({required this.event, required this.dayDate});

  @override
  Widget build(BuildContext context) {
    final isTask = event.type == 'task_completed';
    final isChat = event.type == 'advisor_chat';
    final isInsight = event.type == 'important_insight';

    final icon = isTask
        ? Icons.check_circle_outline_rounded
        : isInsight
        ? Icons.flag_rounded
        : Icons.chat_bubble_outline_rounded;
    final iconColor = isTask
        ? AppColors.success
        : isInsight
        ? AppColors.accentOrange
        : AppColors.primaryLemonDark;
    final iconBg = isTask
        ? const Color(0xFFDCFCE7)
        : isInsight
        ? const Color(0xFFFFF7ED)
        : AppColors.primaryLemon;

    String title;
    String? subtitle;
    if (isTask) {
      title = event.data['task_name'] as String? ?? 'Task';
      final type = event.data['task_type'] as String? ?? '';
      subtitle = type.isNotEmpty ? type : null;
    } else if (isInsight) {
      title = event.data['summary'] as String? ?? 'Important insight';
      final cat = event.data['category'] as String? ?? '';
      subtitle = cat.isNotEmpty ? _formatCategory(cat) : null;
    } else if (isChat) {
      title = event.data['summary'] as String? ?? 'Advisor chat';
      subtitle = null;
    } else {
      title = event.type;
    }

    final timeStr = _formatTimestamp(event.timestamp, dayDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isInsight
              ? const Color(0xFFFFFBF5)
              : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.cardShadow,
          border: isInsight
              ? Border(
                  left: BorderSide(color: AppColors.accentOrange, width: 3),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
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
              style: const TextStyle(fontSize: 12, color: AppColors.textLight),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCategory(String cat) {
    const labels = {
      'symptom': 'Symptom',
      'medication': 'Medication',
      'emotional': 'Emotional',
      'health_concern': 'Health concern',
      'urgent': 'Urgent',
      'other': 'Note',
    };
    return labels[cat] ?? cat;
  }

  String _formatTimestamp(String iso, String fallbackDate) {
    try {
      String s = iso;
      if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
      final dt = DateTime.parse(s).toLocal();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final hour12 = h % 12 == 0 ? 12 : h % 12;
      return '$month/$day $hour12:$m $period';
    } catch (_) {
      return fallbackDate;
    }
  }
}

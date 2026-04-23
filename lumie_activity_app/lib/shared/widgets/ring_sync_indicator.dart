import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/ring_sync_service.dart';

/// Compact sync-status row that reads from [RingSyncService].
///
/// Shows a spinner while syncing, a checkmark with elapsed time after success,
/// or a warning badge if the last sync was incomplete.
/// Returns [SizedBox.shrink] when no sync has ever occurred.
class RingSyncIndicator extends StatelessWidget {
  /// Override the text/icon colour for use on coloured backgrounds.
  final Color? color;

  const RingSyncIndicator({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Consumer<RingSyncService>(
      builder: (context, sync, _) {
        final status = sync.status;
        final c = color ?? AppColors.textLight;

        if (status.isSyncing) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(c),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Syncing…',
                style: TextStyle(fontSize: 11, color: c),
              ),
            ],
          );
        }

        if (status.lastSyncAt != null) {
          final mins =
              DateTime.now().difference(status.lastSyncAt!).inMinutes;
          final timeAgo = mins < 1 ? 'just now' : '${mins}m ago';
          final incomplete = status.lastWasIncomplete;
          final label =
              incomplete ? 'Sync incomplete · $timeAgo' : 'Synced $timeAgo';
          final iconColor =
              incomplete ? AppColors.warning : c;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                incomplete
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 12,
                color: iconColor,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: incomplete ? AppColors.warning : c,
                ),
              ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

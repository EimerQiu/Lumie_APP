import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/tasks_provider.dart';
import '../../../shared/models/task_models.dart';
import '../../auth/providers/auth_provider.dart';
import 'edit_task_screen.dart';

// ─── Unified data class ───────────────────────────────────────────────────────

class _Detail {
  final String taskId;
  final String taskName;
  final String taskType;
  final String openDatetime;
  final String closeDatetime;
  final String status;
  final String? taskInfo;
  final String? note;
  final List<TaskAttachment> attachments;
  final String? teamId;
  final String? teamName;
  final String? userId;
  final String? username;
  final String? createdBy;
  final String? rpttaskId;
  final DateTime? completedAt;
  final int extensionCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double progress;
  final String progressText;

  const _Detail({
    required this.taskId,
    required this.taskName,
    required this.taskType,
    required this.openDatetime,
    required this.closeDatetime,
    required this.status,
    this.taskInfo,
    this.note,
    required this.attachments,
    this.teamId,
    this.teamName,
    this.userId,
    this.username,
    this.createdBy,
    this.rpttaskId,
    this.completedAt,
    this.extensionCount = 0,
    this.createdAt,
    this.updatedAt,
    this.progress = 0,
    this.progressText = '',
  });

  factory _Detail.fromTask(Task t) => _Detail(
        taskId: t.taskId,
        taskName: t.taskName,
        taskType: t.taskType.displayName,
        openDatetime: t.openDatetime,
        closeDatetime: t.closeDatetime,
        status: _capitalise(t.status),
        taskInfo: t.taskInfo,
        note: t.note,
        attachments: t.attachments,
        teamId: t.teamId,
        userId: t.userId,
        createdBy: t.createdBy,
        rpttaskId: t.rpttaskId,
        completedAt: t.completedAt,
        extensionCount: t.extensionCount,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        progress: t.progress,
        progressText: t.progressText,
      );

  factory _Detail.fromAdminTask(AdminTaskData t) => _Detail(
        taskId: t.taskId,
        taskName: t.rpttaskName,
        taskType: t.rpttaskType.isNotEmpty ? t.rpttaskType : t.taskType,
        openDatetime: t.openDatetime,
        closeDatetime: t.closeDatetime,
        status: _capitalise(t.status),
        taskInfo: t.rpttaskInfo,
        note: t.note,
        attachments: t.attachments,
        teamId: t.familyId,
        teamName: t.familyName,
        userId: t.userId,
        username: t.username,
        rpttaskId: t.rpttaskId,
      );

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  bool get isPending => status.toLowerCase() == 'pending';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TaskDetailScreen extends StatelessWidget {
  final _Detail _data;
  // Original model kept so the edit screen can be pre-populated
  final EditTaskArgs _editArgs;

  TaskDetailScreen.fromTask({super.key, required Task task})
      : _data = _Detail.fromTask(task),
        _editArgs = EditTaskArgs.fromTask(task);

  TaskDetailScreen.fromAdminTask({super.key, required AdminTaskData task})
      : _data = _Detail.fromAdminTask(task),
        _editArgs = EditTaskArgs.fromAdminTask(task);

  // ─── Gradient pairs ───────────────────────────────────────────────────────
  static const List<List<Color>> _gradientPairs = [
    [Color(0xFFFF3B30), Color(0xFFFF2D55)],
    [Color(0xFF007AFF), Color(0xFF5AC8FA)],
    [Color(0xFFFF3B30), Color(0xFFFF9500)],
    [Color(0xFF34C759), Color(0xFFFFCC00)],
    [Color(0xFFFF2D55), Color(0xFF5856D6)],
    [Color(0xFF5AC8FA), Color(0xFF34C759)],
    [Color(0xFF007AFF), Color(0xFF5856D6)],
    [Color(0xFFFF9500), Color(0xFFFFCC00)],
    [Color(0xFFFF2D55), Color(0xFFFF3B30)],
    [Color(0xFF5AC8FA), Color(0xFF007AFF)],
    [Color(0xFFFF9500), Color(0xFFFF3B30)],
    [Color(0xFFFFCC00), Color(0xFF34C759)],
    [Color(0xFF5856D6), Color(0xFFFF2D55)],
    [Color(0xFF34C759), Color(0xFF5AC8FA)],
    [Color(0xFF5856D6), Color(0xFF007AFF)],
    [Color(0xFFFFCC00), Color(0xFFFF9500)],
    [Color(0xFF007AFF), Color(0xFFFF3B30)],
    [Color(0xFF34C759), Color(0xFFFF2D55)],
    [Color(0xFFFF9500), Color(0xFF5856D6)],
    [Color(0xFF5AC8FA), Color(0xFFFF2D55)],
    [Color(0xFFFFCC00), Color(0xFF5856D6)],
    [Color(0xFF34C759), Color(0xFFFF3B30)],
    [Color(0xFFFF2D55), Color(0xFF007AFF)],
    [Color(0xFF5AC8FA), Color(0xFFFF9500)],
  ];

  List<Color> get _colors =>
      _gradientPairs[_data.taskId.hashCode.abs() % _gradientPairs.length];

  Color get _statusColor {
    switch (_data.status.toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'expired':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  String _formatRaw(String raw) {
    try {
      final dt = DateTime.parse('${raw.replaceAll(' ', 'T')}Z').toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}  ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  String _formatDt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${_p(l.month)}-${_p(l.day)}  ${_p(l.hour)}:${_p(l.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  List<String> _thumbUrls(TaskAttachment a) =>
      _resolveUrls((a.thumbnailUrl?.isNotEmpty == true) ? a.thumbnailUrl! : a.url);

  List<String> _fullUrls(TaskAttachment a) => _resolveUrls(a.url);

  List<String> _videoUrls(TaskAttachment a) {
    final urls = <String>[];
    if (a.playbackUrl?.isNotEmpty == true) urls.addAll(_resolveUrls(a.playbackUrl!));
    urls.addAll(_resolveUrls(a.url));
    return urls.toSet().toList();
  }

  List<String> _resolveUrls(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return [raw];
    final base = Uri.parse(ApiConstants.baseUrl);
    final scheme = base.scheme;
    final host = base.host;
    final path = raw.startsWith('/') ? raw : '/$raw';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final c = <String>[
      '$scheme://$host$path',
      '$scheme://$host$basePath$path',
      '${ApiConstants.baseUrl}$path',
    ];
    if (host == 'yumo.org') c.add('$scheme://api.yumo.org$path');
    return c.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final currentUserId = context.read<AuthProvider>().user?.userId;
    final canEdit = currentUserId != null &&
        (currentUserId == _data.userId || currentUserId == _data.createdBy);

    // Use the first attachment as a parallax hero when it's an image.
    // Videos stay in the media strip below (can't live in a SliverAppBar bg).
    final hasAttachments = _data.attachments.isNotEmpty;
    final firstIsImage =
        hasAttachments && !_data.attachments[0].isVideo;

    // Attachments shown in the media strip (everything except the hero image)
    final stripAttachments = firstIsImage
        ? _data.attachments.sublist(1)
        : _data.attachments;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFEF3C7), Color(0xFFFFFFFF)],
              ),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            // BouncingScrollPhysics lets the SliverAppBar stretch past its
            // expanded height on over-scroll (required for the zoom effect).
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                expandedHeight: firstIsImage ? 350 : 220,
                pinned: true,
                stretch: firstIsImage,
                backgroundColor: firstIsImage ? Colors.black : colors[0],
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit task',
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/tasks/edit',
                        arguments: _editArgs,
                      ),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: firstIsImage
                      ? const [StretchMode.zoomBackground]
                      : const [],
                  background: firstIsImage
                      ? _buildImageHeader(context, colors)
                      : _buildHeader(colors),
                ),
              ),
              // ── Media strip (remaining attachments, or all if no hero) ──
              if (stripAttachments.isNotEmpty)
                SliverToBoxAdapter(
                  child: _AttachmentsGrid(
                    attachments: stripAttachments,
                    thumbUrls: _thumbUrls,
                    fullUrls: _fullUrls,
                    videoUrls: _videoUrls,
                    fullWidth: true,
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status + type chips
                      Wrap(
                        spacing: 8,
                        children: [
                          _StatusBadge(label: _data.status, color: _statusColor),
                          _TypeChip(label: _data.taskType),
                          if (_data.teamId != null)
                            _TypeChip(
                              label: _data.teamName ?? 'Team',
                              icon: Icons.group_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Time window
                      _SectionCard(children: [
                        _InfoRow(
                          icon: Icons.schedule_outlined,
                          label: 'Opens',
                          value: _formatRaw(_data.openDatetime),
                        ),
                        const Divider(height: 1),
                        _InfoRow(
                          icon: Icons.timer_off_outlined,
                          label: 'Closes',
                          value: _formatRaw(_data.closeDatetime),
                        ),
                        if (_data.completedAt != null) ...[
                          const Divider(height: 1),
                          _InfoRow(
                            icon: Icons.check_circle_outline,
                            label: 'Completed',
                            value: _formatDt(_data.completedAt!),
                            valueColor: AppColors.success,
                          ),
                        ],
                      ]),
                      const SizedBox(height: 12),

                      // Progress bar (pending only)
                      if (_data.isPending && _data.progress > 0) ...[
                        _SectionCard(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.timelapse_outlined,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Progress',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _data.progressText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colors[0],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _data.progress,
                                    minHeight: 6,
                                    backgroundColor: AppColors.surfaceLight,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colors[0],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                      ],

                      // Description
                      if (_data.taskInfo?.isNotEmpty == true) ...[
                        _SectionLabel(label: 'Description'),
                        const SizedBox(height: 6),
                        _SectionCard(children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _data.taskInfo!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                      ],

                      // Note
                      if (_data.note?.isNotEmpty == true) ...[
                        _SectionLabel(label: 'Note'),
                        const SizedBox(height: 6),
                        _SectionCard(children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.notes_outlined,
                                  size: 16,
                                  color: AppColors.textLight,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _data.note!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                      height: 1.55,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                      ],

                      if (canEdit) ...[
                        const SizedBox(height: 24),

                        // Edit button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit Task'),
                            onPressed: () async {
                              final result = await Navigator.pushNamed(
                                context,
                                '/tasks/edit',
                                arguments: _editArgs,
                              );
                              // Pop detail screen with true so the parent list refreshes
                              if (result != null && context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.surfaceLight),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Delete button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Delete Task'),
                            onPressed: () => _confirmDelete(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(
                                color: AppColors.error.withValues(alpha: 0.4),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Delete "${_data.taskName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<TasksProvider>().deleteTask(_data.taskId);
      if (context.mounted) {
        Navigator.of(context).pop(true); // signal parent list to refresh
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  Widget _buildHeader(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors[0], colors[1]],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '❝',
                style: TextStyle(
                  fontSize: 32,
                  color: Colors.white.withValues(alpha: 0.5),
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _data.taskName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Header used when the first attachment is an image.
  /// The image fills the SliverAppBar background; a dark gradient overlay
  /// keeps the task-name text legible; StretchMode.zoomBackground makes the
  /// image zoom out on over-scroll for a parallax feel.
  Widget _buildImageHeader(BuildContext context, List<Color> colors) {
    final a = _data.attachments[0];
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-res image, covers the entire hero area — tap opens full preview
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => a.isVideo
                ? _VideoPreviewDialog(urlCandidates: _videoUrls(a))
                : _ImagePreviewDialog(urlCandidates: _fullUrls(a)),
          ),
          child: _ImageThumbCell(urlCandidates: _fullUrls(a)),
        ),
        // Dark gradient so white text stays readable
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.55, 1.0],
              colors: [
                Color(0x26000000), // 15 % black at top
                Color(0x40000000), // 25 % in the middle
                Color(0xB3000000), // 70 % at the bottom
              ],
            ),
          ),
        ),
        // Task name pinned to the bottom of the expanded space
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '❝',
                  style: TextStyle(
                    fontSize: 32,
                    color: Colors.white.withValues(alpha: 0.6),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _data.taskName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textLight,
          letterSpacing: 0.8,
        ),
      );
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.cardShadow,
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: valueColor ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontFamily: null,
                ),
                softWrap: true,
              ),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _TypeChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryLemon,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: AppColors.textOnYellow),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnYellow,
              ),
            ),
          ],
        ),
      );
}

// ─── Attachments grid ─────────────────────────────────────────────────────────

class _AttachmentsGrid extends StatelessWidget {
  final List<TaskAttachment> attachments;
  final List<String> Function(TaskAttachment) thumbUrls;
  final List<String> Function(TaskAttachment) fullUrls;
  final List<String> Function(TaskAttachment) videoUrls;
  final bool fullWidth;

  const _AttachmentsGrid({
    required this.attachments,
    required this.thumbUrls,
    required this.fullUrls,
    required this.videoUrls,
    this.fullWidth = false,
  });

  Widget _cell(BuildContext context, int i, {double? fixedHeight}) {
    final a = attachments[i];
    // Full-width cells use full-res URLs for images; thumbnails only for grid previews
    final imageUrls = fullWidth ? fullUrls(a) : thumbUrls(a);
    Widget child = Container(
      color: AppColors.surfaceLight,
      child: a.isVideo
          ? _VideoThumbCell(urlCandidates: thumbUrls(a))
          : _ImageThumbCell(urlCandidates: imageUrls),
    );
    if (fixedHeight != null) {
      child = SizedBox(height: fixedHeight, child: child);
    }
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => a.isVideo
            ? _VideoPreviewDialog(urlCandidates: videoUrls(a))
            : _ImagePreviewDialog(urlCandidates: fullUrls(a)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(fullWidth ? 0 : 10),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (fullWidth) {
      const gap = 2.0;
      const cellH = 260.0;

      if (attachments.length == 1) {
        // Single image: full screen width
        return SizedBox(
          height: cellH,
          child: _cell(context, 0),
        );
      }

      if (attachments.length == 2) {
        // Two side-by-side
        return SizedBox(
          height: cellH,
          child: Row(
            children: [
              Expanded(child: _cell(context, 0)),
              const SizedBox(width: gap),
              Expanded(child: _cell(context, 1)),
            ],
          ),
        );
      }

      // 3 or more: featured top row + 2-column strip below
      return Column(
        children: [
          SizedBox(
            height: cellH,
            child: Row(
              children: [
                Expanded(child: _cell(context, 0)),
                if (attachments.length > 1) ...[
                  const SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _cell(context, 1)),
                        if (attachments.length > 2) ...[
                          const SizedBox(height: gap),
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _cell(context, 2),
                                if (attachments.length > 3)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black45,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '+${attachments.length - 3}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    // Non-full-width: regular 3-column grid
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, i) => _cell(context, i),
    );
  }
}

class _ImageThumbCell extends StatefulWidget {
  final List<String> urlCandidates;
  const _ImageThumbCell({required this.urlCandidates});

  @override
  State<_ImageThumbCell> createState() => _ImageThumbCellState();
}

class _ImageThumbCellState extends State<_ImageThumbCell> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urlCandidates.isEmpty) {
      return const Icon(Icons.broken_image_outlined, color: AppColors.textLight);
    }
    return Image.network(
      widget.urlCandidates[_idx],
      fit: BoxFit.cover,
      errorBuilder: (_, e, st) {
        if (_idx < widget.urlCandidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _idx++);
          });
        }
        return const Icon(Icons.broken_image_outlined, color: AppColors.textLight);
      },
    );
  }
}

class _VideoThumbCell extends StatelessWidget {
  final List<String> urlCandidates;
  const _VideoThumbCell({required this.urlCandidates});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          _ImageThumbCell(urlCandidates: urlCandidates),
          Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white.withValues(alpha: 0.92),
              size: 28,
            ),
          ),
        ],
      );
}

class _ImagePreviewDialog extends StatefulWidget {
  final List<String> urlCandidates;
  const _ImagePreviewDialog({required this.urlCandidates});

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final url =
        widget.urlCandidates.isNotEmpty ? widget.urlCandidates[_idx] : '';
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, e, st) {
                      if (_idx < widget.urlCandidates.length - 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _idx++);
                        });
                      }
                      return const Center(child: Text('Failed to load image'));
                    },
                  )
                : const Center(child: Text('No image URL')),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black26,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final List<String> urlCandidates;
  const _VideoPreviewDialog({required this.urlCandidates});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tryInit(0);
  }

  Future<void> _tryInit(int idx) async {
    if (idx >= widget.urlCandidates.length) return;
    final ctrl =
        VideoPlayerController.networkUrl(Uri.parse(widget.urlCandidates[idx]));
    try {
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _controller?.dispose();
        _controller = ctrl;
        _initialized = true;
      });
      ctrl.play();
    } catch (_) {
      ctrl.dispose();
      _tryInit(idx + 1);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio:
                  _initialized ? _controller!.value.aspectRatio : 16 / 9,
              child: _initialized
                  ? VideoPlayer(_controller!)
                  : const Center(child: CircularProgressIndicator()),
            ),
            if (_initialized)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _controller!.value.isPlaying
                        ? _controller!.pause()
                        : _controller!.play();
                  }),
                  behavior: HitTestBehavior.translucent,
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Admin Dashboard Screen - Global task view for team admins
///
/// Shows all tasks across teams with email search, member quick-filter chips,
/// previous/upcoming split with pagination, and swipe actions to complete/delete.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/advisor_v2_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/teams/providers/teams_provider.dart';
import '../providers/admin_tasks_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const int _maxImageBytes = 500 * 1024;
  static const int _maxVideoBytes = 5 * 1024 * 1024;

  final _emailController = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final Dio _dio = Dio();
  final AdvisorV2Service _advisorV2 = AdvisorV2Service();
  double _overscrollAccumulation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamsProvider = context.read<TeamsProvider>();
      final tasksProvider = context.read<AdminTasksProvider>();

      // Load teams first (needed to determine admin status for swipe actions)
      teamsProvider.loadTeams().then((_) {
        tasksProvider.loadMemberChips();
        tasksProvider.loadTasks();
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          appBar: AppBar(
            title: const Text('All Tasks'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            actions: [
              IconButton(
                onPressed: () {
                  final adminProvider = context.read<AdminTasksProvider>();
                  final authProvider = context.read<AuthProvider>();

                  // Use selected member email, or default to current user
                  final email =
                      adminProvider.filterEmail ?? authProvider.user?.email;

                  if (email == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to determine user email'),
                      ),
                    );
                    return;
                  }

                  Navigator.pushNamed(
                    context,
                    '/tasks/reward-calc',
                    arguments: email,
                  );
                },
                icon: const Icon(Icons.attach_money),
                tooltip: 'Reward Calculator',
              ),
            ],
          ),
          body: Consumer<AdminTasksProvider>(
            builder: (context, provider, _) {
              return Column(
                children: [
                  // Search bar
                  _buildSearchBar(provider),

                  // Member quick-filter chips
                  if (provider.memberChips.isNotEmpty)
                    _buildMemberChips(provider),

                  // Task list
                  Expanded(child: _buildTaskList(provider)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(AdminTasksProvider provider) {
    // Hide search bar for non-admin users
    if (!provider.isAdmin) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: 'Search by email...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.surfaceLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.surfaceLight),
                ),
                suffixIcon: _emailController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _emailController.clear();
                          provider.loadTasks();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) => _search(provider),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _search(provider),
            icon: const Icon(Icons.search),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _search(AdminTasksProvider provider) {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an email address to search'),
        ),
      );
      return;
    }
    provider.loadTasks(email: email);
  }

  Widget _buildMemberChips(AdminTasksProvider provider) {
    // Chip color palette
    const chipColors = [
      Color(0xFF6366F1), // indigo
      Color(0xFF8B5CF6), // purple
      Color(0xFF3B82F6), // blue
      Color(0xFF14B8A6), // teal
      Color(0xFF06B6D4), // cyan
      Color(0xFFEC4899), // pink
    ];

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: provider.memberChips.length,
        itemBuilder: (context, index) {
          final chip = provider.memberChips[index];
          final color = chipColors[index % chipColors.length];
          final isSelected = provider.filterEmail == chip.email;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(
                chip.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              backgroundColor: isSelected
                  ? color
                  : color.withValues(alpha: 0.1),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
              onPressed: () {
                _emailController.text = chip.email;
                provider.loadTasks(email: chip.email);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTaskList(AdminTasksProvider provider) {
    if (provider.isLoading &&
        provider.previousTasks.isEmpty &&
        provider.upcomingTasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              provider.errorMessage ?? 'Something went wrong',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadTasks(email: provider.filterEmail),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Filter tasks: only show tasks the user can access
    final filteredPreviousTasks = provider.previousTasks
        .where((task) => _canViewTask(context, task))
        .toList();
    final filteredUpcomingTasks = provider.upcomingTasks
        .where((task) => _canViewTask(context, task))
        .toList();

    final allEmpty =
        filteredPreviousTasks.isEmpty && filteredUpcomingTasks.isEmpty;
    if (allEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.admin_panel_settings,
              size: 64,
              color: AppColors.surfaceLight,
            ),
            SizedBox(height: 16),
            Text(
              'No tasks found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try searching by email or selecting a member',
              style: TextStyle(fontSize: 14, color: AppColors.textLight),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;

        if (notification is ScrollUpdateNotification) {
          // iOS overscroll appears as out-of-bounds pixels, not OverscrollNotification
          if (metrics.pixels < 0) {
            // Pulling DOWN past top boundary
            _overscrollAccumulation = metrics.pixels;

            if (_overscrollAccumulation <= -150 &&
                provider.hasMorePrevious &&
                !provider.isLoadingMorePrevious) {
              _overscrollAccumulation = 0;
              provider.loadMorePrevious();
            }
          } else if (metrics.pixels > metrics.maxScrollExtent) {
            // Pulling UP past bottom boundary
            _overscrollAccumulation = metrics.pixels - metrics.maxScrollExtent;

            if (_overscrollAccumulation >= 150 &&
                provider.hasMoreUpcoming &&
                !provider.isLoadingMoreUpcoming) {
              _overscrollAccumulation = 0;
              provider.loadMoreUpcoming();
            }
          }
        } else if (notification is ScrollEndNotification) {
          _overscrollAccumulation = 0;
        }
        return false;
      },
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Loading indicator for previous tasks
          if (provider.isLoadingMorePrevious)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),

          // Previous Tasks section
          if (filteredPreviousTasks.isNotEmpty) ...[
            _SectionHeader(
              title: 'Previous Tasks',
              count: filteredPreviousTasks.length,
            ),
            ...filteredPreviousTasks.map((task) {
              final canManage = _canManageTask(context, task);
              final isTaskOwner = _isTaskOwner(context, task);
              return _AdminTaskCard(
                task: task,
                isAdmin: canManage,
                onTap: () async {
                  final result = await Navigator.pushNamed(
                    context,
                    '/tasks/detail',
                    arguments: task,
                  );
                  if (result == true && context.mounted) {
                    provider.loadTasks();
                  }
                },
                onComplete: () => _completeTask(provider, task),
                onDelete: () => _deleteTask(provider, task),
                canSwipeComplete: true,
                canSwipeDelete: canManage,
                resolveAttachmentUrls: _thumbnailUrlCandidates,
                onAttachmentTap: (attachment) =>
                    _openAttachmentPreview(attachment),
                onAddAttachment: (task.isCompleted && isTaskOwner)
                    ? () => _pickAndUploadAttachments(provider, task)
                    : null,
              );
            }),
          ],

          // Divider
          if (filteredPreviousTasks.isNotEmpty &&
              filteredUpcomingTasks.isNotEmpty)
            const Divider(height: 32),

          // Upcoming Tasks section
          if (filteredUpcomingTasks.isNotEmpty) ...[
            _SectionHeader(
              title: 'Upcoming Tasks',
              count: filteredUpcomingTasks.length,
            ),
            ...filteredUpcomingTasks.map((task) {
              final canManage = _canManageTask(context, task);
              final isTaskOwner = _isTaskOwner(context, task);
              return _AdminTaskCard(
                task: task,
                isAdmin: canManage,
                onTap: () async {
                  final result = await Navigator.pushNamed(
                    context,
                    '/tasks/detail',
                    arguments: task,
                  );
                  if (result == true && context.mounted) {
                    provider.loadTasks();
                  }
                },
                onComplete: () => _completeTask(provider, task),
                onDelete: () => _deleteTask(provider, task),
                canSwipeComplete: true,
                canSwipeDelete: canManage,
                resolveAttachmentUrls: _thumbnailUrlCandidates,
                onAttachmentTap: (attachment) =>
                    _openAttachmentPreview(attachment),
                onAddAttachment: (task.isCompleted && isTaskOwner)
                    ? () => _pickAndUploadAttachments(provider, task)
                    : null,
              );
            }),
          ],

          // Loading indicator for upcoming tasks
          if (provider.isLoadingMoreUpcoming)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _completeTask(
    AdminTasksProvider provider,
    AdminTaskData task,
  ) async {
    final canManage = _canManageTask(context, task);
    if (!canManage) {
      await _requestAdminCompletion(provider, task);
      return;
    }

    try {
      await provider.completeTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.rpttaskName}" completed')),
        );
      }
    } catch (e) {
      if (mounted) {
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

  Future<void> _requestAdminCompletion(
    AdminTasksProvider provider,
    AdminTaskData task,
  ) async {
    final adminContact = await _resolveTeamAdminContact(task);
    if (!mounted) return;
    final adminDisplay = adminContact?.name ?? 'team admin';
    final reasonController = TextEditingController();
    String? validationError;
    bool submitting = false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Request Admin Completion'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send a completion request to $adminDisplay?'),
                  const SizedBox(height: 8),
                  Text(
                    'Task: ${task.rpttaskName}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    enabled: !submitting,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Why should this task be marked completed?',
                      errorText: validationError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            setStateDialog(() {
                              validationError = 'Reason is required';
                            });
                            return;
                          }
                          setStateDialog(() {
                            validationError = null;
                            submitting = true;
                          });
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: const Text('Send Request'),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) {
      reasonController.dispose();
      return;
    }

    final reason = reasonController.text.trim();
    reasonController.dispose();

    try {
      final targetEmail = adminContact?.email;
      if (targetEmail == null || targetEmail.isEmpty) {
        throw Exception('Could not resolve admin email for this team');
      }

      final prompt =
          '''
Send a cross-advisor completion request.
target_email: $targetEmail
cross_advisor_action_type: tasks_complete
task_id: ${task.taskId}
task_name: ${task.rpttaskName}
open_datetime: ${task.openDatetime}
close_datetime: ${task.closeDatetime}
reason: $reason
''';

      final response = await _advisorV2.sendMessage(
        prompt,
        history: const [],
        sessionId: 'tasks-request-${DateTime.now().millisecondsSinceEpoch}',
        teamId: task.familyId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.reply.isNotEmpty
                ? response.reply
                : 'Request sent to $adminDisplay',
          ),
        ),
      );
      await provider.loadTasks(email: provider.filterEmail);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send request: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<_AdminContact?> _resolveTeamAdminContact(AdminTaskData task) async {
    final teamId = task.familyId;
    if (teamId == null || teamId.isEmpty) return null;
    try {
      final teamsProvider = context.read<TeamsProvider>();
      final authProvider = context.read<AuthProvider>();
      final me = authProvider.user?.userId;
      final membersResp = await teamsProvider.getTeamMembers(teamId);
      final admins = membersResp.members
          .where((m) => m.role.name == 'admin')
          .toList();
      if (admins.isEmpty) return null;
      final preferred = admins.firstWhere(
        (m) => m.userId != me,
        orElse: () => admins.first,
      );
      return _AdminContact(name: preferred.name, email: preferred.email);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteTask(
    AdminTasksProvider provider,
    AdminTaskData task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Permanently delete "${task.rpttaskName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await provider.deleteTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.rpttaskName}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
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

  List<String> _attachmentUrlCandidates(
    TaskAttachment attachment, {
    bool preferThumbnail = false,
  }) {
    final raw = preferThumbnail
        ? (attachment.thumbnailUrl ?? attachment.url)
        : attachment.url;

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return [raw];
    }
    final base = Uri.parse(ApiConstants.baseUrl);
    final scheme = base.scheme;
    final host = base.host;
    final path = raw.startsWith('/') ? raw : '/$raw';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    final candidates = <String>[
      '$scheme://$host$path',
      '$scheme://$host$basePath$path',
      '${ApiConstants.baseUrl}$path',
    ];

    if (host == 'yumo.org') {
      candidates.add('$scheme://api.yumo.org$path');
      candidates.add('$scheme://api.yumo.org$basePath$path');
    } else if (host == 'api.yumo.org') {
      candidates.add('$scheme://yumo.org$path');
      candidates.add('$scheme://yumo.org$basePath$path');
    }
    return candidates.toSet().toList();
  }

  List<String> _thumbnailUrlCandidates(TaskAttachment attachment) =>
      _attachmentUrlCandidates(attachment, preferThumbnail: true);

  List<String> _videoPreviewUrlCandidates(TaskAttachment attachment) {
    final preferred = <String>[];
    if ((attachment.playbackUrl ?? '').isNotEmpty) {
      preferred.addAll(
        _attachmentUrlCandidatesFromRaw(attachment.playbackUrl!),
      );
    }
    preferred.addAll(_attachmentUrlCandidates(attachment));
    return preferred.toSet().toList();
  }

  List<String> _attachmentUrlCandidatesFromRaw(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return [raw];
    }
    final base = Uri.parse(ApiConstants.baseUrl);
    final scheme = base.scheme;
    final host = base.host;
    final path = raw.startsWith('/') ? raw : '/$raw';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    final candidates = <String>[
      '$scheme://$host$path',
      '$scheme://$host$basePath$path',
      '${ApiConstants.baseUrl}$path',
    ];

    if (host == 'yumo.org') {
      candidates.add('$scheme://api.yumo.org$path');
      candidates.add('$scheme://api.yumo.org$basePath$path');
    } else if (host == 'api.yumo.org') {
      candidates.add('$scheme://yumo.org$path');
      candidates.add('$scheme://yumo.org$basePath$path');
    }
    return candidates.toSet().toList();
  }

  Future<void> _openAttachmentPreview(TaskAttachment attachment) async {
    final urlCandidates = attachment.isVideo
        ? _videoPreviewUrlCandidates(attachment)
        : _attachmentUrlCandidates(attachment);
    if (!mounted) return;
    if (attachment.isVideo) {
      await showDialog(
        context: context,
        builder: (_) => _VideoPreviewDialog(
          urlCandidates: urlCandidates,
          onDownload: (resolvedUrl) =>
              _downloadAttachment(attachment, directUrl: resolvedUrl),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => _ImagePreviewDialog(
        urlCandidates: urlCandidates,
        onDownload: (resolvedUrl) =>
            _downloadAttachment(attachment, directUrl: resolvedUrl),
      ),
    );
  }

  Future<File> _compressImageToLimit(File source) async {
    if (source.lengthSync() <= _maxImageBytes) return source;
    final tempDir = await getTemporaryDirectory();
    File? lastCompressed;
    final qualities = [85, 75, 65, 55, 45, 35, 25];
    for (final quality in qualities) {
      final targetPath =
          '${tempDir.path}/admin_img_${DateTime.now().microsecondsSinceEpoch}_$quality.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) continue;
      final file = File(compressed.path);
      if (!file.existsSync()) continue;
      lastCompressed = file;
      if (file.lengthSync() <= _maxImageBytes) return file;
    }
    if (lastCompressed != null &&
        lastCompressed.lengthSync() <= _maxImageBytes) {
      return lastCompressed;
    }
    throw Exception('Image is still larger than 500KB after compression.');
  }

  Future<File> _compressVideoToLimit(File source) async {
    final lowerPath = source.path.toLowerCase();
    final isMp4 = lowerPath.endsWith('.mp4');
    if (source.lengthSync() <= _maxVideoBytes && isMp4) return source;
    File? lastCompressed;
    final qualities = [
      VideoQuality.MediumQuality,
      VideoQuality.LowQuality,
      VideoQuality.Res640x480Quality,
    ];
    for (final quality in qualities) {
      final info = await VideoCompress.compressVideo(
        source.path,
        quality: quality,
        includeAudio: true,
        deleteOrigin: false,
      );
      final file = info?.file;
      if (file == null || !file.existsSync()) continue;
      lastCompressed = file;
      if (file.lengthSync() <= _maxVideoBytes) return file;
    }
    if (lastCompressed != null &&
        lastCompressed.lengthSync() <= _maxVideoBytes) {
      return lastCompressed;
    }
    if (source.lengthSync() <= _maxVideoBytes) {
      return source;
    }
    throw Exception('Video is still larger than 5MB after compression.');
  }

  Future<void> _pickAndUploadAttachments(
    AdminTasksProvider provider,
    AdminTaskData task,
  ) async {
    final available = 99 - task.attachments.length;
    if (available <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This task already has 99 attachments.')),
      );
      return;
    }
    final picked = await _imagePicker.pickMultipleMedia();
    if (picked.isEmpty) return;
    final selected = picked.take(available).toList();
    if (selected.isEmpty) return;
    if (!mounted) return;

    final progress = ValueNotifier<double>(0);
    final stage = ValueNotifier<String>('Compression...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Uploading media'),
          content: SizedBox(
            height: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: stage,
                  builder: (context, value, child) => Text(value),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, child) =>
                      LinearProgressIndicator(value: value > 0 ? value : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final files = <File>[];
      for (var i = 0; i < selected.length; i++) {
        final x = selected[i];
        final src = File(x.path);
        if (!src.existsSync()) continue;
        final lower = src.path.toLowerCase();
        final isVideo =
            lower.endsWith('.mp4') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.3gp') ||
            lower.endsWith('.avi') ||
            lower.endsWith('.mkv') ||
            lower.endsWith('.webm');
        final out = isVideo
            ? await _compressVideoToLimit(src)
            : await _compressImageToLimit(src);
        files.add(out);
        progress.value = ((i + 1) / selected.length) * 0.7;
      }

      stage.value = 'Upload...';
      await provider.uploadTaskAttachments(
        taskId: task.taskId,
        files: files,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          progress.value = 0.7 + ((sent / total) * 0.3);
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Media uploaded')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      progress.dispose();
      stage.dispose();
      await VideoCompress.cancelCompression();
    }
  }

  Future<void> _downloadAttachment(
    TaskAttachment attachment, {
    String? directUrl,
  }) async {
    final candidates = directUrl != null
        ? [directUrl, ..._attachmentUrlCandidates(attachment)]
        : _attachmentUrlCandidates(attachment);
    var downloaded = false;
    for (final url in candidates.toSet()) {
      try {
        final tempDir = await getTemporaryDirectory();
        final localPath = '${tempDir.path}/${attachment.filename}';
        await _dio.download(url, localPath);
        final result = await ImageGallerySaverPlus.saveFile(
          localPath,
          isReturnPathOfIOS: true,
        );
        final ok =
            (result['isSuccess'] == true) || (result['filePath'] != null);
        if (ok) {
          downloaded = true;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(downloaded ? 'Saved to Photos' : 'Download failed'),
      ),
    );
  }

  /// Check if current user can view a task (access control filter)
  /// Can view if: team admin, task assigned to user, or personal task owner
  bool _canViewTask(BuildContext context, AdminTaskData task) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.userId;

    // Personal task (no team) - only visible to task owner
    if (task.familyId == null || task.familyId!.isEmpty) {
      return currentUserId == task.userId;
    }

    // Team task - visible if admin of the team OR task is assigned to user
    final teamsProvider = context.read<TeamsProvider>();

    try {
      final team = teamsProvider.teams.firstWhere(
        (t) => t.teamId == task.familyId,
      );
      if (team.role.name == 'admin') return true;
      return currentUserId == task.userId;
    } catch (e) {
      // If team not found, don't show the task
      return false;
    }
  }

  /// Check if current user is the task owner
  bool _isTaskOwner(BuildContext context, AdminTaskData task) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.userId;
    return currentUserId == task.userId;
  }

  /// Check if current user can manage a task
  /// Can manage if: team admin OR personal task (no team) and task owner
  bool _canManageTask(BuildContext context, AdminTaskData task) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.userId;

    // Personal task (no team) - user can manage if they own it
    if (task.familyId == null || task.familyId!.isEmpty) {
      return currentUserId == task.userId;
    }

    // Team task - user can manage if they're admin of the team
    final teamsProvider = context.read<TeamsProvider>();

    try {
      final team = teamsProvider.teams.firstWhere(
        (t) => t.teamId == task.familyId,
      );
      final isAdmin = team.role.name == 'admin';
      return isAdmin;
    } catch (e) {
      // If team not found, default to true (assume admin can view all)
      return true;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLemon,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnYellow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTaskCard extends StatelessWidget {
  final AdminTaskData task;
  final bool isAdmin;
  final bool canSwipeComplete;
  final bool canSwipeDelete;
  final VoidCallback onComplete;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final List<String> Function(TaskAttachment) resolveAttachmentUrls;
  final ValueChanged<TaskAttachment> onAttachmentTap;
  final VoidCallback? onAddAttachment;

  const _AdminTaskCard({
    required this.task,
    required this.isAdmin,
    required this.canSwipeComplete,
    required this.canSwipeDelete,
    required this.onComplete,
    required this.onDelete,
    required this.onTap,
    required this.resolveAttachmentUrls,
    required this.onAttachmentTap,
    this.onAddAttachment,
  });

  Color get _statusColor {
    switch (task.status) {
      case 'completed':
        return AppColors.success;
      case 'pending':
        return AppColors.info;
      case 'expired':
        return AppColors.error;
      default:
        return AppColors.textLight;
    }
  }

  Color get _cardBackgroundColor {
    return _statusColor.withValues(alpha: 0.1);
  }

  String get _statusLabel {
    switch (task.status) {
      case 'completed':
        return 'Completed';
      case 'pending':
        return 'Pending';
      case 'expired':
        return 'Expired';
      default:
        return task.status;
    }
  }

  String _getViewOnlyMessage(AdminTaskData task) {
    // If task has a team, user must be team admin to edit
    if (task.familyId != null && task.familyId!.isNotEmpty) {
      return 'View only - you must be a ${task.familyName ?? "team"} admin to edit';
    }
    // If task is personal, it belongs to another user
    return 'View only - this is another user\'s personal task';
  }

  String _formatCompletedAt(String completedAtStr) {
    try {
      final dt = DateTime.parse(completedAtStr).toLocal();
      final date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (_) {
      return completedAtStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canSwipeComplete && !canSwipeDelete) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        color: _cardBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.surfaceLight),
        ),
        clipBehavior: Clip.hardEdge,
        child: InkWell(onTap: onTap, child: _buildTaskContent(context)),
      );
    }

    return Dismissible(
      key: Key(task.taskId),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: AppColors.success,
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (!canSwipeComplete) return false;
          onComplete();
          return false;
        } else {
          if (!canSwipeDelete) return false;
          onDelete();
          return false;
        }
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        color: _cardBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.surfaceLight),
        ),
        clipBehavior: Clip.hardEdge,
        child: InkWell(onTap: onTap, child: _buildTaskContent(context)),
      ),
    );
  }

  Widget _buildTaskContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time window (moved to top)
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: AppColors.textLight),
              const SizedBox(width: 4),
              Text(
                task.timeWindowText,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Header: name + status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  task.rpttaskName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),

          // Completed at (for completed tasks)
          if (task.isCompleted && task.completedAt != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  'Completed: ${_formatCompletedAt(task.completedAt!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],

          // Description
          if (task.rpttaskInfo != null && task.rpttaskInfo!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.rpttaskInfo!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Note
          if (task.note != null && task.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 14,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          // User + team info
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.textLight,
              ),
              const SizedBox(width: 4),
              Text(
                'User: ${task.username}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (task.familyName != null) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.group_outlined,
                  size: 14,
                  color: AppColors.textLight,
                ),
                const SizedBox(width: 4),
                Text(
                  'Team: ${task.familyName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),

          // Task type
          if (task.rpttaskType.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.rpttaskType,
              style: const TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],

          // Attachments (completed tasks with media or upload capability)
          if (task.isCompleted &&
              (task.attachments.isNotEmpty || onAddAttachment != null)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.perm_media_outlined,
                  size: 14,
                  color: AppColors.textLight,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Media',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...task.attachments.map((a) {
                    final urls = resolveAttachmentUrls(a);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => onAttachmentTap(a),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 52,
                            height: 52,
                            color: Colors.grey.shade200,
                            child: a.isVideo
                                ? _VideoThumb(urlCandidates: urls)
                                : _AttachmentThumb(urlCandidates: urls),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (onAddAttachment != null)
                    GestureDetector(
                      onTap: onAddAttachment,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.surfaceLight),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Admin-only notice
          if (!isAdmin) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getViewOnlyMessage(task),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.info,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminContact {
  final String name;
  final String email;

  const _AdminContact({required this.name, required this.email});
}

class _AttachmentThumb extends StatefulWidget {
  final List<String> urlCandidates;

  const _AttachmentThumb({required this.urlCandidates});

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urlCandidates.isEmpty) {
      return const Icon(
        Icons.broken_image_outlined,
        color: AppColors.textLight,
      );
    }
    final url = widget.urlCandidates[_index];
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (_index < widget.urlCandidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _index += 1);
          });
        }
        return const Icon(
          Icons.broken_image_outlined,
          color: AppColors.textLight,
        );
      },
    );
  }
}

class _VideoThumb extends StatelessWidget {
  final List<String> urlCandidates;

  const _VideoThumb({required this.urlCandidates});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _AttachmentThumb(urlCandidates: urlCandidates),
        Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white.withValues(alpha: 0.92),
            size: 20,
          ),
        ),
      ],
    );
  }
}

class _ImagePreviewDialog extends StatefulWidget {
  final List<String> urlCandidates;
  final ValueChanged<String> onDownload;

  const _ImagePreviewDialog({
    required this.urlCandidates,
    required this.onDownload,
  });

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final hasUrl = widget.urlCandidates.isNotEmpty;
    final url = hasUrl ? widget.urlCandidates[_index] : '';
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: GestureDetector(
        onLongPress: hasUrl ? () => widget.onDownload(url) : null,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: hasUrl
                  ? Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        if (_index < widget.urlCandidates.length - 1) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _index += 1);
                          });
                        }
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Failed to load image'),
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No image URL'),
                      ),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final List<String> urlCandidates;
  final ValueChanged<String> onDownload;

  const _VideoPreviewDialog({
    required this.urlCandidates,
    required this.onDownload,
  });

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;
  int _index = 0;
  bool _ready = false;
  String? _error;
  String? _tempVideoPath;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    // First pass: try direct network playback.
    while (_index < widget.urlCandidates.length) {
      final url = widget.urlCandidates[_index];
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize();
        if (!mounted) return;
        setState(() {
          _controller = c;
          _ready = true;
          _error = null;
        });
        return;
      } catch (_) {
        await c.dispose();
        _index += 1;
      }
    }

    // Fallback: download and play from local temp file (robust on iOS when
    // server-side byte-range streaming is not available).
    for (var i = 0; i < widget.urlCandidates.length; i++) {
      final localPath = await _downloadVideoToTemp(widget.urlCandidates[i]);
      if (localPath == null) continue;
      final c = VideoPlayerController.file(File(localPath));
      try {
        await c.initialize();
        if (!mounted) return;
        setState(() {
          _controller = c;
          _ready = true;
          _error = null;
          _index = i;
          _tempVideoPath = localPath;
        });
        return;
      } catch (_) {
        await c.dispose();
      }
    }

    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = 'Failed to load video';
    });
  }

  Future<String?> _downloadVideoToTemp(String url) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/preview_${DateTime.now().microsecondsSinceEpoch}.mp4';
      await Dio().download(url, tempPath);
      final file = File(tempPath);
      if (!file.existsSync() || file.lengthSync() <= 0) return null;
      return tempPath;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    final tempPath = _tempVideoPath;
    if (tempPath != null) {
      final f = File(tempPath);
      if (f.existsSync()) {
        f.deleteSync();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: GestureDetector(
        onLongPress: _ready && _controller != null
            ? () => widget.onDownload(widget.urlCandidates[_index])
            : null,
        child: AspectRatio(
          aspectRatio: (_ready && _controller != null)
              ? _controller!.value.aspectRatio
              : 16 / 9,
          child: Stack(
            children: [
              Positioned.fill(
                child: _error != null
                    ? Center(child: Text(_error!))
                    : _ready && _controller != null
                    ? VideoPlayer(_controller!)
                    : const Center(child: CircularProgressIndicator()),
              ),
              if (_ready && _controller != null)
                Positioned.fill(
                  child: Center(
                    child: IconButton(
                      iconSize: 52,
                      color: Colors.white,
                      onPressed: () {
                        setState(() {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                          } else {
                            _controller!.play();
                          }
                        });
                      },
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

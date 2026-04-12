// Tasks List Screen - Main task list with pull-to-refresh and swipe actions

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:video_compress/video_compress.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/task_service.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/widgets/animated_fab.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_card.dart';
import '../../advisor/screens/advisor_screen.dart';

class TasksListScreen extends StatefulWidget {
  const TasksListScreen({super.key});

  @override
  State<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends State<TasksListScreen> {
  AiTip? _aiTip;
  bool _aiTipLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TasksProvider>();
      provider.loadTasks();
      provider.startPolling();
      _loadAiTip();
    });
  }

  String _deviceTimezone() {
    try {
      final name = tz.local.name;
      return (name.isNotEmpty && name != 'UTC') ? name : 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }

  static const _tipCacheKey = 'ai_tip_cache';
  static const _tipTimestampKey = 'ai_tip_timestamp';
  static const _tipTtl = Duration(hours: 1);

  Future<void> _loadAiTip({bool forceRefresh = false}) async {
    if (_aiTipLoading) return;
    setState(() => _aiTipLoading = true);
    try {
      if (!forceRefresh) {
        final cached = await _loadCachedTip();
        if (cached != null) {
          if (mounted) setState(() => _aiTip = cached);
          return;
        }
      }
      final tip = await TaskService().getAiTips(
        daysBack: 30,
        timeZone: _deviceTimezone(),
      );
      if (mounted) setState(() => _aiTip = tip);
      await _saveTipToCache(tip);
    } catch (_) {
      // Non-fatal: tip card stays hidden on error
    } finally {
      if (mounted) setState(() => _aiTipLoading = false);
    }
  }

  Future<AiTip?> _loadCachedTip() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_tipTimestampKey);
    if (timestamp == null) return null;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedAt) > _tipTtl) return null;
    final raw = prefs.getString(_tipCacheKey);
    if (raw == null) return null;
    try {
      return AiTip.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTipToCache(AiTip tip) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'tip': tip.tip,
      'task_stats': {
        'total_tasks': tip.taskStats.totalTasks,
        'completed_tasks': tip.taskStats.completedTasks,
        'expired_tasks': tip.taskStats.expiredTasks,
        'pending_tasks': tip.taskStats.pendingTasks,
        'completion_rate': tip.taskStats.completionRate,
      },
    };
    await prefs.setString(_tipCacheKey, json.encode(data));
    await prefs.setInt(_tipTimestampKey, DateTime.now().millisecondsSinceEpoch);
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
            title: const Text('Med-Reminder'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            actions: [
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/tasks/admin'),
                icon: const Icon(Icons.checklist),
                tooltip: 'All Tasks',
              ),
            ],
          ),
          body: Consumer<TasksProvider>(
            builder: (context, provider, _) {
              return Column(
                children: [
                  // Subscription banner
                  if (provider.subscriptionBannerMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLemon,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppColors.textOnYellow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.subscriptionBannerMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textOnYellow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Task limit indicator
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          provider.taskLimitText,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Task list (AI tip card is appended inside as last item)
                  Expanded(child: _buildTaskList(provider)),
                ],
              );
            },
          ),
          floatingActionButton: AnimatedFAB(
            items: [
              FABMenuItem(
                icon: Icons.add,
                label: 'Create a New Task',
                onTap: () => Navigator.pushNamed(context, '/tasks/create'),
              ),
              FABMenuItem(
                icon: Icons.view_list_outlined,
                label: 'Create Tasks from Template',
                onTap: () => Navigator.pushNamed(context, '/tasks/templates'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiTipCard() {
    if (!_aiTipLoading && _aiTip == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdvisorScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryLemon.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryLemon.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Sparkle icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppColors.textOnYellow,
              ),
            ),
            const SizedBox(width: 10),
            if (_aiTipLoading)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Expanded(
                child: MarkdownBody(
                  data: _aiTip!.tip,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                    listBullet: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                    strong: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _loadAiTip(forceRefresh: true),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.refresh,
                    size: 18,
                    color: AppColors.textLight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(TasksProvider provider) {
    if (provider.isLoading && provider.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              provider.errorMessage ?? 'Something went wrong',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadTasks(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final activeTasks = provider.activeTasks;

    if (activeTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: AppColors.surfaceLight),
            const SizedBox(height: 16),
            Text(
              'No Tasks Available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check All Tasks for all previous\nand upcoming tasks, or tap + to create one.',
              style: TextStyle(fontSize: 14, color: AppColors.textLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/tasks/admin'),
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('Open All Tasks'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadTasks(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: activeTasks.length + 1,
        itemBuilder: (context, index) {
          if (index == activeTasks.length) return _buildAiTipCard();
          final task = activeTasks[index];
          return TaskCard(
            task: task,
            onTap: () => _showCompleteDialog(task),
            onComplete: () => _showCompleteDialog(task),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
    );
  }

  void _showCompleteDialog(Task task) {
    showDialog<String>(
      context: context,
      builder: (context) => _TaskCompleteDialog(task: task),
    ).then((message) {
      if (!mounted || message == null || message.isEmpty) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _deleteTask(Task task) async {
    try {
      await context.read<TasksProvider>().deleteTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${task.taskName}" deleted')));
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
}

class _TaskCompleteDialog extends StatefulWidget {
  final Task task;

  const _TaskCompleteDialog({required this.task});

  @override
  State<_TaskCompleteDialog> createState() => _TaskCompleteDialogState();
}

class _TaskCompleteDialogState extends State<_TaskCompleteDialog> {
  static const int _maxFiles = 99;
  static const int _maxImageBytes = 500 * 1024;
  static const int _maxVideoBytes = 5 * 1024 * 1024;

  final TextEditingController _noteController = TextEditingController();
  final List<_TaskMediaItem> _media = [];
  final ImagePicker _imagePicker = ImagePicker();

  bool _isWorking = false;
  bool _isAnalyzingNutrition = false;
  String _stageLabel = '';
  double _progress = 0;
  String? _lastAutoNutritionNote;

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.task.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  Future<void> _pickMedia() async {
    if (_isWorking) return;
    final available = _maxFiles - _media.length;
    if (available <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can upload up to 99 files.')),
      );
      return;
    }

    final picked = await _imagePicker.pickMultipleMedia();
    if (picked.isEmpty) return;

    final existingPaths = _media.map((m) => m.file.path).toSet();
    final additions = <_TaskMediaItem>[];
    for (final item in picked) {
      final path = item.path;
      if (existingPaths.contains(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      additions.add(
        _TaskMediaItem(
          file: file,
          isVideo: _isVideoPath(path),
          originalBytes: file.lengthSync(),
        ),
      );
      existingPaths.add(path);
    }

    if (additions.isEmpty) return;
    final trimmed = additions.take(available).toList();
    setState(() => _media.addAll(trimmed));

    if (additions.length > trimmed.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the first 99 files were kept.')),
      );
    }

    await _analyzeNutritionFromSelectedImages();
  }

  Future<void> _analyzeNutritionFromSelectedImages() async {
    if (_isWorking || _isAnalyzingNutrition) return;
    if (widget.task.taskType != TaskType.nutrition) return;

    final imageItems = _media.where((m) => !m.isVideo).toList();
    if (imageItems.isEmpty) return;

    setState(() => _isAnalyzingNutrition = true);
    try {
      final provider = context.read<TasksProvider>();
      final compressedImages = <File>[];
      for (final item in imageItems) {
        final compressed = await _compressImageToLimit(item.file);
        compressedImages.add(compressed);
      }
      final summary = await provider.analyzeNutritionImages(
        files: compressedImages,
      );
      final normalized = summary.trim();
      if (normalized.isEmpty || !mounted) return;

      final current = _noteController.text.trim();
      String nextText;
      if (current.isEmpty ||
          (_lastAutoNutritionNote != null &&
              current == _lastAutoNutritionNote)) {
        nextText = normalized;
      } else if (current.contains(normalized)) {
        nextText = current;
      } else {
        nextText = '$current\n$normalized';
      }

      _noteController.value = _noteController.value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
      _lastAutoNutritionNote = normalized;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nutrition analysis failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAnalyzingNutrition = false);
    }
  }

  Future<File> _compressImageToLimit(File source) async {
    if (source.lengthSync() <= _maxImageBytes) return source;

    final tempDir = await getTemporaryDirectory();
    File? lastCompressed;
    final qualities = [85, 75, 65, 55, 45, 35, 25];
    for (final quality in qualities) {
      final targetPath =
          '${tempDir.path}/img_${DateTime.now().microsecondsSinceEpoch}_$quality.jpg';
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
    throw Exception(
      'Image is still larger than 500KB after compression. Please choose another image.',
    );
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
    throw Exception(
      'Video is still larger than 5MB after compression. Please choose a shorter video.',
    );
  }

  Future<List<File>> _compressAll() async {
    if (_media.isEmpty) return const [];
    final result = <File>[];
    for (var i = 0; i < _media.length; i++) {
      final item = _media[i];
      setState(() {
        _stageLabel = 'Compression ${i + 1}/${_media.length}';
      });
      final compressed = item.isVideo
          ? await _compressVideoToLimit(item.file)
          : await _compressImageToLimit(item.file);
      result.add(compressed);
      setState(() {
        _progress = ((i + 1) / _media.length) * 0.7;
      });
    }
    return result;
  }

  Future<void> _onComplete() async {
    if (_isWorking) return;
    final hasMedia = _media.isNotEmpty;
    setState(() {
      _isWorking = true;
      _stageLabel = hasMedia ? 'Preparing...' : '';
      _progress = 0;
    });

    try {
      final provider = context.read<TasksProvider>();
      final note = _noteController.text.trim();
      if (note.isNotEmpty) {
        await provider.updateNote(widget.task.taskId, note);
      }

      final compressedFiles = await _compressAll();
      if (compressedFiles.isNotEmpty) {
        setState(() => _stageLabel = 'Upload...');
        await provider.uploadTaskAttachments(
          taskId: widget.task.taskId,
          files: compressedFiles,
          onSendProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() {
              _progress = 0.7 + ((sent / total) * 0.3);
            });
          },
        );
      }

      await provider.completeTask(widget.task.taskId);
      if (mounted) {
        Navigator.of(context).pop('"${widget.task.taskName}" completed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      await VideoCompress.cancelCompression();
    }
  }

  Future<void> _onExtend() async {
    if (_isWorking || widget.task.extensionCount >= 1) return;
    setState(() => _isWorking = true);
    try {
      final provider = context.read<TasksProvider>();
      final note = _noteController.text.trim();
      if (note.isNotEmpty) {
        await provider.updateNote(widget.task.taskId, note);
      }
      await provider.extendTask(widget.task.taskId);
      if (mounted) {
        Navigator.of(context).pop('"${widget.task.taskName}" extended by 10%');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Complete Task',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isWorking
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Mark "${widget.task.taskName}" as completed?'),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_media.isNotEmpty) ...[
                      SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _media.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final item = _media[index];
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    color: Colors.grey.shade200,
                                    child: item.isVideo
                                        ? const Icon(
                                            Icons.videocam,
                                            color: AppColors.textSecondary,
                                          )
                                        : Image.file(
                                            item.file,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: InkWell(
                                    onTap: _isWorking
                                        ? null
                                        : () => setState(
                                            () => _media.removeAt(index),
                                          ),
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 180),
                      child: TextField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: widget.task.taskType == TaskType.nutrition
                              ? 'Add a note (nutrition analysis will auto-fill)'
                              : 'Add a note (optional)',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 8,
                          ),
                          counterText: '',
                        ),
                        style: const TextStyle(fontSize: 13),
                        enabled: !_isWorking,
                        minLines: 6,
                        maxLines: 9,
                        maxLength: 1000,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isWorking ? null : _pickMedia,
                  icon: const Icon(
                    Icons.photo_library_outlined,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  label: const Text(
                    'Select photos and videos',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_media.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_media.length}/99 selected',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_isAnalyzingNutrition &&
                  widget.task.taskType == TaskType.nutrition)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Analyzing selected food photos...',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isWorking && _media.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _stageLabel,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
                const SizedBox(height: 6),
                Text('${(100 * _progress).round()}%'),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (_isWorking || widget.task.extensionCount >= 1)
                        ? null
                        : _onExtend,
                    child: const Text('Extend'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isWorking ? null : _onComplete,
                    child: Text(_isWorking ? 'Processing...' : 'Complete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMediaItem {
  final File file;
  final bool isVideo;
  final int originalBytes;

  const _TaskMediaItem({
    required this.file,
    required this.isVideo,
    required this.originalBytes,
  });
}

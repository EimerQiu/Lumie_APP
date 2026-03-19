// Tasks List Screen - Main task list with pull-to-refresh and swipe actions

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
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

  Future<void> _loadAiTip() async {
    if (_aiTipLoading) return;
    setState(() => _aiTipLoading = true);
    try {
      final tip = await TaskService().getAiTips(
        daysBack: 30,
        timeZone: _deviceTimezone(),
      );
      if (mounted) setState(() => _aiTip = tip);
    } catch (_) {
      // Non-fatal: tip card stays hidden on error
    } finally {
      if (mounted) setState(() => _aiTipLoading = false);
    }
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
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLemon,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: AppColors.textOnYellow),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.subscriptionBannerMessage!,
                              style: TextStyle(fontSize: 13, color: AppColors.textOnYellow),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Task limit indicator
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        border: Border.all(color: AppColors.primaryLemon.withValues(alpha: 0.6)),
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
            child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.textOnYellow),
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
              child: Text(
                _aiTip!.tip,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
            GestureDetector(
              onTap: _loadAiTip,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.refresh, size: 18, color: AppColors.textLight),
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
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 20),
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Mark "${task.taskName}" as completed?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: task.extensionCount >= 1
                        ? null
                        : () async {
                            final newEndTime = _calcExtendedEndTime(task);
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => Dialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 20),
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
                                                'Extend Task?',
                                                style: Theme.of(ctx).textTheme.titleLarge,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            icon: const Icon(Icons.close),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      RichText(
                                        text: TextSpan(
                                          style: Theme.of(ctx).textTheme.bodyMedium,
                                          children: [
                                            const TextSpan(text: 'The end time will be extended to '),
                                            TextSpan(
                                              text: newEndTime,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            const TextSpan(text: '.\n\nThis task can only be extended once.'),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          FilledButton(
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('Extend'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              Navigator.of(context).pop();
                              _extendTask(task);
                            }
                          },
                    child: const Text('Extend'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _completeTask(task);
                    },
                    child: const Text('Complete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Calculates the new end time after a 10% extension, formatted for display.
  /// Returns "HH:mm" if same day as original close, or "yyyy-MM-dd HH:mm" if it crosses to another day.
  String _calcExtendedEndTime(Task task) {
    try {
      final open = DateTime.parse('${task.openDatetime.replaceAll(' ', 'T')}Z').toLocal();
      final close = DateTime.parse('${task.closeDatetime.replaceAll(' ', 'T')}Z').toLocal();
      final extension = Duration(microseconds: (close.difference(open).inMicroseconds * 0.1).round());
      final newClose = close.add(extension);
      final timeStr = '${newClose.hour.toString().padLeft(2, '0')}:${newClose.minute.toString().padLeft(2, '0')}';
      if (newClose.day != close.day || newClose.month != close.month || newClose.year != close.year) {
        return '${newClose.year}-${newClose.month.toString().padLeft(2, '0')}-${newClose.day.toString().padLeft(2, '0')} $timeStr';
      }
      return timeStr;
    } catch (_) {
      return task.closeDatetime;
    }
  }

  Future<void> _extendTask(Task task) async {
    try {
      await context.read<TasksProvider>().extendTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.taskName}" extended by 10%')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _completeTask(Task task) async {
    try {
      await context.read<TasksProvider>().completeTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.taskName}" completed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    try {
      await context.read<TasksProvider>().deleteTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.taskName}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }
}

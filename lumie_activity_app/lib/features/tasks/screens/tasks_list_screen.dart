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
      builder: (context) => AlertDialog(
        title: const Text('Complete Task'),
        content: Text('Are you sure you want to mark "${task.taskName}" as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _completeTask(task);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
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

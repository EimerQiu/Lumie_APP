/// Tasks List Screen - Main task list with pull-to-refresh and swipe actions

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_card.dart';

class TasksListScreen extends StatefulWidget {
  const TasksListScreen({super.key});

  @override
  State<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends State<TasksListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TasksProvider>();
      provider.loadTasks();
      provider.startPolling();
    });
  }

  @override
  void dispose() {
    // Stop polling when leaving screen
    // Note: provider persists, polling continues if user comes back
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Med-Reminder'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Templates button
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/tasks/templates'),
            icon: const Icon(Icons.view_list_outlined),
            tooltip: 'Templates',
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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: AppColors.textOnYellow),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

              // Task list
              Expanded(
                child: _buildTaskList(provider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<TasksProvider>(
        builder: (context, provider, _) {
          return FloatingActionButton.extended(
            onPressed: () => _onAddTask(provider),
            backgroundColor: AppColors.primaryLemonDark,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Task'),
          );
        },
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
            Icon(Icons.task_alt, size: 64, color: AppColors.surfaceLight),
            const SizedBox(height: 16),
            Text(
              'No active tasks',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create a new task',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadTasks(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: activeTasks.length,
        itemBuilder: (context, index) {
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

  void _onAddTask(TasksProvider provider) {
    if (provider.hasReachedTaskLimit) {
      UpgradePromptBottomSheet.showCustom(
        context: context,
        title: 'Task Limit Reached',
        message: 'You\'ve reached your task limit (${provider.activeTaskCount}/6 active tasks)',
        detail: 'Upgrade to Pro for unlimited tasks.',
        onUpgrade: () => Navigator.pushNamed(context, '/subscription/upgrade'),
      );
      return;
    }
    Navigator.pushNamed(context, '/tasks/create');
  }

  void _showCompleteDialog(Task task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Task'),
        content: Text(
            'Are you sure you want to mark "${task.taskName}" as completed?'),
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
          SnackBar(
              content:
                  Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
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
          SnackBar(
              content:
                  Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }
}

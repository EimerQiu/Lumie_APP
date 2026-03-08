/// Tasks List Screen - Main task list with pull-to-refresh and swipe actions

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_card.dart';

class TasksListScreen extends StatefulWidget {
  const TasksListScreen({super.key});

  @override
  State<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends State<TasksListScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isMenuExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TasksProvider>();
      provider.loadTasks();
      provider.startPolling();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
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
          // Admin Dashboard button
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/tasks/admin'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: 'Admin Dashboard',
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
      floatingActionButton: _buildAnimatedFAB(),
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
              'Check the Admin Dashboard for all previous\nand upcoming tasks, or tap + to create one.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/tasks/admin'),
              icon: const Icon(Icons.admin_panel_settings, size: 18),
              label: const Text('Open Admin Dashboard'),
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

  Widget _buildAnimatedFAB() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Menu item 1: Create Task (grows from center outward)
        _AnimatedMenuButton(
          animation: _animationController,
          offset: const Offset(0, 70),
          icon: Icons.add,
          label: 'New Task',
          onTap: () {
            _toggleMenu();
            Navigator.pushNamed(context, '/tasks/create');
          },
        ),
        // Menu item 2: Templates (grows from center outward)
        _AnimatedMenuButton(
          animation: _animationController,
          offset: const Offset(0, 130),
          icon: Icons.view_list_outlined,
          label: 'From Template',
          onTap: () {
            _toggleMenu();
            Navigator.pushNamed(context, '/tasks/templates');
          },
        ),
        // Main FAB with rotating icon
        Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: _toggleMenu,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryLemonDark,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _animationController.value * (3.14159 / 2),
                    child: Icon(
                      _isMenuExpanded ? Icons.close : Icons.add,
                      color: Colors.white,
                      size: 24,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _toggleMenu() {
    setState(() {
      _isMenuExpanded = !_isMenuExpanded;
    });
    if (_isMenuExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _onAddTask(TasksProvider provider) {
    // No quantity limit — date-range limit is enforced server-side
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

/// Animated menu button that grows out of the main FAB
class _AnimatedMenuButton extends StatelessWidget {
  final Animation<double> animation;
  final Offset offset;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AnimatedMenuButton({
    required this.animation,
    required this.offset,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Scale from 0 to 1 as menu expands
        final scale = animation.value;
        // Slide from center outward based on offset
        final slideOffset = Offset(offset.dx * scale, offset.dy * scale);

        return Positioned(
          bottom: 16 + slideOffset.dy,
          right: 16 + slideOffset.dx,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Opacity(
              opacity: scale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Text label
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLemonDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Icon button
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLemonDark,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x33000000),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

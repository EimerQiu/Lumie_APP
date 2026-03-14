/// Admin Dashboard Screen - Global task view for team admins
///
/// Shows all tasks across teams with email search, member quick-filter chips,
/// previous/upcoming split with pagination, and swipe actions to complete/delete.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final _emailController = TextEditingController();
  final _scrollController = ScrollController();
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
              final email = adminProvider.filterEmail ?? authProvider.user?.email;

              if (email == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to determine user email')),
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
              if (provider.memberChips.isNotEmpty) _buildMemberChips(provider),

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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        const SnackBar(content: Text('Please enter an email address to search')),
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
              backgroundColor: isSelected ? color : color.withValues(alpha: 0.1),
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
    if (provider.isLoading && provider.previousTasks.isEmpty && provider.upcomingTasks.isEmpty) {
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
    final filteredPreviousTasks = provider.previousTasks.where((task) => _canViewTask(context, task)).toList();
    final filteredUpcomingTasks = provider.upcomingTasks.where((task) => _canViewTask(context, task)).toList();

    final allEmpty = filteredPreviousTasks.isEmpty && filteredUpcomingTasks.isEmpty;
    if (allEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.admin_panel_settings, size: 64, color: AppColors.surfaceLight),
            SizedBox(height: 16),
            Text(
              'No tasks found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
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
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          // Previous Tasks section
          if (filteredPreviousTasks.isNotEmpty) ...[
            _SectionHeader(
              title: 'Previous Tasks',
              count: filteredPreviousTasks.length,
            ),
            ...filteredPreviousTasks.map((task) {
              final canManage = _canManageTask(context, task);
              return _AdminTaskCard(
                task: task,
                isAdmin: canManage,
                onComplete: () => _completeTask(provider, task),
                onDelete: () => _deleteTask(provider, task),
              );
            }),
          ],

          // Divider
          if (filteredPreviousTasks.isNotEmpty && filteredUpcomingTasks.isNotEmpty)
            const Divider(height: 32),

          // Upcoming Tasks section
          if (filteredUpcomingTasks.isNotEmpty) ...[
            _SectionHeader(
              title: 'Upcoming Tasks',
              count: filteredUpcomingTasks.length,
            ),
            ...filteredUpcomingTasks.map((task) {
              final canManage = _canManageTask(context, task);
              return _AdminTaskCard(
                task: task,
                isAdmin: canManage,
                onComplete: () => _completeTask(provider, task),
                onDelete: () => _deleteTask(provider, task),
              );
            }),
          ],

          // Loading indicator for upcoming tasks
          if (provider.isLoadingMoreUpcoming)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _completeTask(AdminTasksProvider provider, AdminTaskData task) async {
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
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _deleteTask(AdminTasksProvider provider, AdminTaskData task) async {
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
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  /// Check if current user can view a task (access control filter)
  /// Can view if: team admin OR personal task (no team) and task owner
  bool _canViewTask(BuildContext context, AdminTaskData task) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.userId;

    // Personal task (no team) - only visible to task owner
    if (task.familyId == null || task.familyId!.isEmpty) {
      return currentUserId == task.userId;
    }

    // Team task - visible if user is admin of the team
    final teamsProvider = context.read<TeamsProvider>();

    try {
      final team = teamsProvider.teams.firstWhere(
        (t) => t.teamId == task.familyId,
      );
      return team.role.name == 'admin';
    } catch (e) {
      // If team not found, don't show the task
      return false;
    }
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textOnYellow),
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
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _AdminTaskCard({
    required this.task,
    required this.isAdmin,
    required this.onComplete,
    required this.onDelete,
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

  @override
  Widget build(BuildContext context) {
    // If user is not admin, disable swipe actions
    if (!isAdmin) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        color: Colors.white.withValues(alpha: 0.70),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.surfaceLight),
        ),
        child: _buildTaskContent(context),
      );
    }

    // If user is admin, enable swipe actions
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
          onComplete();
          return false; // Don't dismiss - task stays visible
        } else {
          onDelete();
          return false; // Handled by delete callback
        }
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.surfaceLight),
        ),
        child: _buildTaskContent(context),
      ),
    );
  }

  Widget _buildTaskContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          // Description
          if (task.rpttaskInfo != null && task.rpttaskInfo!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.rpttaskInfo!,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 8),

          // Time window
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: AppColors.textLight),
              const SizedBox(width: 4),
              Text(
                task.timeWindowText,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // User + team info
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: AppColors.textLight),
              const SizedBox(width: 4),
              Text(
                'User: ${task.username}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (task.familyName != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.group_outlined, size: 14, color: AppColors.textLight),
                const SizedBox(width: 4),
                Text(
                  'Team: ${task.familyName}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

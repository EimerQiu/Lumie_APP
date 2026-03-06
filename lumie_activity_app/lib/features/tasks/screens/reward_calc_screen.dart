/// Reward Calculation Screen - Admin tool for date-range reward/fine calculation
///
/// Admin selects exactly two tasks via checkboxes to define a range.
/// Completed tasks earn rewards, expired tasks incur fines.
/// Calculation is entirely client-side.

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/services/task_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';

class RewardCalcScreen extends StatefulWidget {
  const RewardCalcScreen({super.key});

  @override
  State<RewardCalcScreen> createState() => _RewardCalcScreenState();
}

class _RewardCalcScreenState extends State<RewardCalcScreen> {
  final _emailController = TextEditingController();
  final _rewardController = TextEditingController(text: '1.00');
  final _fineController = TextEditingController(text: '0.50');
  final _taskService = TaskService();

  List<AdminTaskData> _tasks = [];
  final Set<String> _selectedTaskIds = {};
  bool _isLoading = false;
  int _offset = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Get email passed from admin dashboard
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _emailController.text = args;
        _loadTasks();
      }
    });
  }

  String _getDeviceTimezone() {
    try {
      String tzName = tz.local.name;
      if (tzName == 'UTC' || tzName.isEmpty) {
        final now = DateTime.now();
        final offsetHours = now.timeZoneOffset.inHours;
        final Map<int, String> offsetMap = {
          -8: 'America/Los_Angeles',
          -7: 'America/Denver',
          -6: 'America/Chicago',
          -5: 'America/New_York',
          0: 'UTC',
          1: 'Europe/London',
          8: 'Asia/Shanghai',
          9: 'Asia/Tokyo',
        };
        return offsetMap[offsetHours] ?? 'UTC';
      }
      return tzName;
    } catch (e) {
      return 'UTC';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _rewardController.dispose();
    _fineController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks({bool loadMore = false}) async {
    if (_emailController.text.trim().isEmpty) return;

    if (!loadMore) {
      _offset = 0;
      _hasMore = true;
    }

    setState(() => _isLoading = true);

    try {
      final tasks = await _taskService.getRewardCalcTasks(
        email: _emailController.text.trim(),
        timeZone: _getDeviceTimezone(),
        offset: _offset,
      );

      setState(() {
        // Filter out pending tasks - only show completed and expired
        final filteredTasks = tasks.where((t) => t.status != 'pending').toList();

        if (loadMore) {
          final existingIds = _tasks.map((t) => t.taskId).toSet();
          _tasks.addAll(filteredTasks.where((t) => !existingIds.contains(t.taskId)));
        } else {
          _tasks = filteredTasks;
          _selectedTaskIds.clear();
        }

        // Sort all tasks ascending by openDatetime (oldest first)
        _tasks.sort((a, b) => a.openDatetime.compareTo(b.openDatetime));

        _hasMore = tasks.length >= 10;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Range calculation
  int get _startIndex {
    if (_selectedTaskIds.length < 2) return -1;
    return _tasks.indexWhere((t) => _selectedTaskIds.contains(t.taskId));
  }

  int get _endIndex {
    if (_selectedTaskIds.length < 2) return -1;
    return _tasks.lastIndexWhere((t) => _selectedTaskIds.contains(t.taskId));
  }

  List<AdminTaskData> get _tasksInRange {
    final start = _startIndex;
    final end = _endIndex;
    if (start < 0 || end < 0) return [];
    return _tasks.sublist(start, end + 1);
  }

  int get _completedCount => _tasksInRange.where((t) => t.isCompleted).length;
  int get _expiredCount => _tasksInRange.where((t) => t.isExpired).length;
  int get _rangeCount => _tasksInRange.length;

  double get _rewardPerTask => double.tryParse(_rewardController.text) ?? 0;
  double get _finePerTask => double.tryParse(_fineController.text) ?? 0;
  double get _netReward => (_completedCount * _rewardPerTask) - (_expiredCount * _finePerTask);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Reward Calculator'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          // Email search
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Member email',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _loadTasks(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _loadTasks(),
                  icon: const Icon(Icons.search),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLemonDark,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Range info + reward settings
          _buildRewardPanel(),

          // Task list
          Expanded(child: _buildTaskList()),
        ],
      ),
    );
  }

  Widget _buildRewardPanel() {
    final rangeLabel = _selectedTaskIds.length < 2
        ? (_selectedTaskIds.isEmpty ? 'Select 2 tasks to define range' : 'Select end task')
        : '$_rangeCount tasks in range';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rangeLabel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),

          // Reward row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Completed',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                ),
              ),
              const SizedBox(width: 8),
              const Text('reward', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _rewardController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '\u00D7 $_completedCount',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fine row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Expired',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error),
                ),
              ),
              const SizedBox(width: 8),
              const Text('fine', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 24),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _fineController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '\u00D7 $_expiredCount',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Total
          Row(
            children: [
              const Text('Total reward: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text(
                '❤️ ${_netReward.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _netReward >= 0 ? AppColors.info : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    if (_isLoading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tasks.isEmpty) {
      return const Center(
        child: Text('Enter a member email to load tasks', style: TextStyle(color: AppColors.textLight)),
      );
    }

    final startIdx = _startIndex;
    final endIdx = _endIndex;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Load more button at top
        if (_hasMore && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: TextButton(
                onPressed: () {
                  _offset += 10;
                  _loadTasks(loadMore: true);
                },
                child: const Text('Load More Tasks'),
              ),
            ),
          );
        }

        final taskIndex = _hasMore ? index - 1 : index;
        final task = _tasks[taskIndex];
        final isSelected = _selectedTaskIds.contains(task.taskId);
        final inRange = startIdx >= 0 && endIdx >= 0 && taskIndex >= startIdx && taskIndex <= endIdx;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: inRange ? const Color(0xFFEFF6FF) : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? AppColors.info : AppColors.surfaceLight),
          ),
          child: CheckboxListTile(
            value: isSelected,
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selectedTaskIds.add(task.taskId);

                  // If this is the second task, auto-select all tasks in range
                  if (_selectedTaskIds.length == 2) {
                    final startIdx = _startIndex;
                    final endIdx = _endIndex;
                    if (startIdx >= 0 && endIdx >= 0) {
                      // Add all tasks between start and end (inclusive)
                      for (int i = startIdx; i <= endIdx; i++) {
                        _selectedTaskIds.add(_tasks[i].taskId);
                      }
                    }
                  }
                } else {
                  _selectedTaskIds.remove(task.taskId);
                }
              });
            },
            title: Text(
              task.rpttaskName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Row(
              children: [
                _StatusDot(status: task.status),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.closeDatetime,
                    style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'completed':
        color = AppColors.success;
        break;
      case 'expired':
        color = AppColors.error;
        break;
      default:
        color = AppColors.info;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Create Task Screen - Form for creating a single task

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/models/subscription_error.dart';
import '../../../shared/widgets/scroll_datetime_picker.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_type_selector.dart';
import '../widgets/family_member_selector.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _infoController = TextEditingController();

  TaskType _selectedType = TaskType.medicine;
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  bool _isLoading = false;
  FamilyMemberSelection _memberSelection = const FamilyMemberSelection();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDateTime = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _endDateTime = _startDateTime.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  String _formatDatetime(DateTime dt) {
    final d = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  String _getDetectedTimezone() {
    try {
      String tzName = tz.local.name;
      // Use the timezone name directly from the tz package
      // Only fallback to offset detection if name is not available
      if (tzName.isNotEmpty && tzName != 'UTC') {
        return tzName;
      }

      // If local timezone is UTC or unknown, try to detect by offset
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      final offsetHours = offset.inHours;

      // Map common offsets to timezones (this is a fallback)
      final Map<int, String> offsetMap = {
        -12: 'Etc/GMT+12',
        -11: 'Etc/GMT+11',
        -10: 'Etc/GMT+10',
        -9: 'Etc/GMT+9',
        -8: 'Etc/GMT+8',
        -7: 'Etc/GMT+7',
        -6: 'Etc/GMT+6',
        -5: 'Etc/GMT+5',
        -4: 'Etc/GMT+4',
        -3: 'Etc/GMT+3',
        -2: 'Etc/GMT+2',
        -1: 'Etc/GMT+1',
        0: 'UTC',
        1: 'Etc/GMT-1',
        2: 'Etc/GMT-2',
        3: 'Etc/GMT-3',
        4: 'Etc/GMT-4',
        5: 'Etc/GMT-5',
        6: 'Etc/GMT-6',
        7: 'Etc/GMT-7',
        8: 'Etc/GMT-8',
        9: 'Etc/GMT-9',
        10: 'Etc/GMT-10',
        11: 'Etc/GMT-11',
        12: 'Etc/GMT-12',
      };

      return offsetMap[offsetHours] ?? 'UTC';
    } catch (e) {
      return 'UTC (detection failed)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Create Task'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Task name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Task Name',
                hintText: 'e.g. Take medication',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Task name is required';
                }
                if (value.length > 200) {
                  return 'Task name too long (max 200 characters)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Task type
            const Text(
              'Task Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TaskTypeSelector(
              selectedType: _selectedType,
              onChanged: (type) => setState(() => _selectedType = type),
            ),
            const SizedBox(height: 24),

            // Family member selector (for admins)
            FamilyMemberSelector(
              onChanged: (selection) => setState(() => _memberSelection = selection),
            ),

            // Timezone info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primaryLemon.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, size: 20, color: AppColors.textOnYellow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Timezone',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getDetectedTimezone(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textOnYellow),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Start time
            const Text(
              'Start Time',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            ScrollDateTimePicker(
              value: _startDateTime,
              minimumDate: DateTime(2000),
              maximumDate: DateTime.now().add(const Duration(days: 365)),
              onChanged: (dt) {
                setState(() {
                  _startDateTime = dt;
                  if (!_startDateTime.isBefore(_endDateTime)) {
                    _endDateTime = _startDateTime.add(const Duration(hours: 1));
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // End time
            const Text(
              'End Time',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            ScrollDateTimePicker(
              value: _endDateTime,
              minimumDate: DateTime.now(),
              maximumDate: DateTime.now().add(const Duration(days: 365)),
              onChanged: (dt) {
                setState(() {
                  final now = DateTime.now();
                  _endDateTime = dt.isBefore(now) ? now : dt;
                });
              },
            ),
            const SizedBox(height: 24),

            // Additional info
            TextFormField(
              controller: _infoController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Additional information about this task',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemonDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Create Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitTask() async {
    if (!_formKey.currentState!.validate()) return;

    final openDatetime = _formatDatetime(_startDateTime);
    final closeDatetime = _formatDatetime(_endDateTime);

    if (closeDatetime.compareTo(openDatetime) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await context.read<TasksProvider>().createTask(
            taskName: _nameController.text.trim(),
            taskType: _selectedType.apiValue,
            openDatetime: openDatetime,
            closeDatetime: closeDatetime,
            taskInfo: _infoController.text.trim().isEmpty ? null : _infoController.text.trim(),
            teamId: _memberSelection.familyId,
            userId: _memberSelection.memberId,
          );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task created successfully')),
        );
      }
    } on SubscriptionLimitException catch (e) {
      if (mounted) {
        UpgradePromptBottomSheet.show(
          context: context,
          error: e.errorResponse,
          onUpgrade: () => Navigator.pushNamed(context, '/subscription/upgrade'),
        );
      }
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
}

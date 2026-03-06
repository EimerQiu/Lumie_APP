/// Batch Generate Screen - Generate tasks from a template

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/subscription_error.dart';
import '../../../shared/widgets/scroll_datetime_picker.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../providers/tasks_provider.dart';
import '../widgets/family_member_selector.dart';

class BatchGenerateScreen extends StatefulWidget {
  const BatchGenerateScreen({super.key});

  @override
  State<BatchGenerateScreen> createState() => _BatchGenerateScreenState();
}

class _BatchGenerateScreenState extends State<BatchGenerateScreen> {
  final _nameController = TextEditingController();
  final _infoController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 6));
  Map<String, dynamic>? _preview;
  bool _isLoading = false;
  bool _isPreviewing = false;
  String? _templateId;
  FamilyMemberSelection _memberSelection = const FamilyMemberSelection();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get template ID from route arguments
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && _templateId == null) {
      _templateId = args;
      // Load template name as default task name
      final provider = context.read<TasksProvider>();
      final template = provider.templates.where((t) => t.id == args).firstOrNull;
      if (template != null && _nameController.text.isEmpty) {
        _nameController.text = template.templateName;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Generate Tasks'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Task name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Task Name',
              hintText: 'Base name for generated tasks',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Family member selector (for admins)
          FamilyMemberSelector(
            onChanged: (selection) => setState(() => _memberSelection = selection),
          ),

          // Start date
          const Text(
            'Start Date',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ScrollDateTimePicker(
            value: _startDate,
            minimumDate: DateTime.now(),
            maximumDate: DateTime.now().add(const Duration(days: 365)),
            mode: PickerMode.dateOnly,
            onChanged: (dt) {
              setState(() {
                _startDate = dt;
                if (_startDate.isAfter(_endDate)) {
                  _endDate = _startDate.add(const Duration(days: 6));
                }
                _preview = null;
              });
            },
          ),
          const SizedBox(height: 16),

          // End date
          const Text(
            'End Date',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ScrollDateTimePicker(
            value: _endDate,
            minimumDate: _startDate,
            maximumDate: DateTime.now().add(const Duration(days: 365)),
            mode: PickerMode.dateOnly,
            onChanged: (dt) {
              setState(() {
                _endDate = dt;
                _preview = null;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            '${_endDate.difference(_startDate).inDays + 1} day(s)',
            style: TextStyle(fontSize: 13, color: AppColors.textLight),
          ),
          const SizedBox(height: 16),

          // Notes
          TextFormField(
            controller: _infoController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // Preview button
          OutlinedButton.icon(
            onPressed: _isPreviewing ? null : _loadPreview,
            icon: _isPreviewing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview),
            label: const Text('Preview Tasks'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryLemonDark,
              side: BorderSide(color: AppColors.primaryLemonDark),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Preview results
          if (_preview != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLemonLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryLemon),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will create ${_preview!['task_count']} tasks',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...(_preview!['tasks_preview'] as List).take(5).map((task) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${task['task_name']} (${task['open_datetime']} - ${task['close_datetime']})',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }),
                  if ((_preview!['tasks_preview'] as List).length > 5)
                    Text(
                      '...and ${(_preview!['tasks_preview'] as List).length - 5} more',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textLight,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _generateTasks,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemonDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Generate Tasks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreview() async {
    if (_templateId == null || _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }

    setState(() => _isPreviewing = true);

    try {
      final preview = await context.read<TasksProvider>().batchPreview(
            templateId: _templateId!,
            taskName: _nameController.text.trim(),
            startDate: _formatDate(_startDate),
            endDate: _formatDate(_endDate),
            taskInfo: _infoController.text.trim().isEmpty
                ? null
                : _infoController.text.trim(),
            teamId: _memberSelection.familyId,
            userId: _memberSelection.memberId,
          );
      setState(() => _preview = preview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  Future<void> _generateTasks() async {
    if (_templateId == null || _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await context.read<TasksProvider>().batchGenerate(
            templateId: _templateId!,
            taskName: _nameController.text.trim(),
            startDate: _formatDate(_startDate),
            endDate: _formatDate(_endDate),
            taskInfo: _infoController.text.trim().isEmpty
                ? null
                : _infoController.text.trim(),
            teamId: _memberSelection.familyId,
            userId: _memberSelection.memberId,
          );

      if (mounted) {
        // Pop back to templates, then tasks will be refreshed
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${_preview?['task_count'] ?? 'Tasks'} tasks created successfully')),
        );
      }
    } on SubscriptionLimitException catch (e) {
      if (mounted) {
        UpgradePromptBottomSheet.show(
          context: context,
          error: e.errorResponse,
          onUpgrade: () =>
              Navigator.pushNamed(context, '/subscription/upgrade'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

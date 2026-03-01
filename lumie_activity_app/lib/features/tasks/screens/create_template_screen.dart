/// Create Template Screen - Form for creating/editing task templates

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_type_selector.dart';
import '../widgets/time_window_editor.dart';

class CreateTemplateScreen extends StatefulWidget {
  final String? templateId;

  const CreateTemplateScreen({super.key, this.templateId});

  @override
  State<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _intervalController = TextEditingController(text: '0');

  TaskType _selectedType = TaskType.medicine;
  List<TimeWindowEditorData> _windows = [TimeWindowEditorData(name: 'Morning')];
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: Text(widget.templateId != null ? 'Edit Template' : 'Create Template'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Template name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Template Name',
                hintText: 'e.g. Daily Medication Schedule',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Template name is required';
                }
                if (value.length > 200) {
                  return 'Name too long (max 200 characters)';
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
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Brief description of this template',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 500,
            ),
            const SizedBox(height: 16),

            // Min interval
            TextFormField(
              controller: _intervalController,
              decoration: const InputDecoration(
                labelText: 'Minimum Interval (minutes)',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final num = int.tryParse(value);
                  if (num == null || num < 0) {
                    return 'Must be 0 or positive';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Time windows header
            Row(
              children: [
                const Text(
                  'Time Windows',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addWindow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Window'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryLemonDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Time window editors
            ...List.generate(_windows.length, (index) {
              return TimeWindowEditor(
                index: index,
                data: _windows[index],
                onChanged: (data) {
                  setState(() => _windows[index] = data);
                },
                onDelete: _windows.length > 1
                    ? () => setState(() => _windows.removeAt(index))
                    : null,
              );
            }),

            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitTemplate,
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
                        'Create Template',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addWindow() {
    final names = ['Morning', 'Afternoon', 'Evening', 'Night'];
    final name = _windows.length < names.length
        ? names[_windows.length]
        : 'Window ${_windows.length + 1}';

    setState(() {
      _windows.add(TimeWindowEditorData(name: name));
    });
  }

  Future<void> _submitTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate windows have names
    for (var i = 0; i < _windows.length; i++) {
      if (_windows[i].name.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Window ${i + 1} needs a name')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final timeWindowList = List.generate(
        _windows.length,
        (i) => _windows[i].toJson(i),
      );

      await context.read<TasksProvider>().createTemplate(
            templateName: _nameController.text.trim(),
            templateType: _selectedType.apiValue,
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
            minInterval: int.tryParse(_intervalController.text) ?? 0,
            timeWindowList: timeWindowList,
          );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template created successfully')),
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

/// Create Template Screen - Form for creating/editing task templates

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/services/task_service.dart';
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
  final _intervalController = TextEditingController(text: '60');

  TaskType _selectedType = TaskType.medicine;
  List<TimeWindowEditorData> _windows = [TimeWindowEditorData(name: 'Morning')];
  bool _isLoading = false;
  bool _isLoadingTemplate = false;
  bool _isAnalyzingPrescription = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _prescriptionPhotos = [];
  static const int _maxPrescriptionPhotos = 12;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTemplate());
    }
  }

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
        title: Text(
          widget.templateId != null ? 'Edit Template' : 'Create Template',
        ),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _isLoadingTemplate
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Template name
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Template Name e.g. Daily Medication',
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      floatingLabelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      border: const OutlineInputBorder(),
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

                  if (_selectedType == TaskType.medicine) ...[
                    _buildPrescriptionSection(),
                    const SizedBox(height: 16),
                  ],

                  // Description
                  TextFormField(
                    controller: _descController,
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      floatingLabelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      hintText: 'Brief description of this template',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 16),

                  // Min interval
                  TextFormField(
                    controller: _intervalController,
                    decoration: InputDecoration(
                      labelText: 'Minimum Interval (minutes)',
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      floatingLabelStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w400,
                      ),
                      hintText: '0',
                      border: const OutlineInputBorder(),
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

                  // Add window button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _addWindow,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Window'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryLemonDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

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
                          : Text(
                              widget.templateId != null
                                  ? 'Save Changes'
                                  : 'Create Template',
                              style: const TextStyle(
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

  Future<void> _loadTemplate() async {
    setState(() => _isLoadingTemplate = true);
    try {
      final template = await context.read<TasksProvider>().getTemplate(
        widget.templateId!,
      );
      _nameController.text = template.templateName;
      _descController.text = template.description ?? '';
      _intervalController.text = template.minInterval.toString();
      _selectedType = template.templateType;

      // Convert TimeWindow list to TimeWindowEditorData
      _windows = template.timeWindowList.map((tw) {
        final openParts = tw.openTime.split(':');
        final closeParts = tw.closeTime.split(':');
        return TimeWindowEditorData(
          name: tw.name,
          openTime: TimeOfDay(
            hour: int.parse(openParts[0]),
            minute: int.parse(openParts[1]),
          ),
          closeTime: TimeOfDay(
            hour: int.parse(closeParts[0]),
            minute: int.parse(closeParts[1]),
          ),
          isNextDay: tw.isNextDay,
        );
      }).toList();

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load template: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isLoadingTemplate = false);
    }
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

  Widget _buildPrescriptionSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prescription Photos',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_prescriptionPhotos.length}/$_maxPrescriptionPhotos selected',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (_prescriptionPhotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _prescriptionPhotos.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final file = _prescriptionPhotos[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          file,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IconButton(
                          onPressed: _isAnalyzingPrescription
                              ? null
                              : () {
                                  setState(() {
                                    _prescriptionPhotos.removeAt(index);
                                  });
                                },
                          icon: const Icon(Icons.close, size: 16),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(22, 22),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isAnalyzingPrescription
                    ? null
                    : _pickPrescriptionPhotos,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Upload Photos'),
              ),
              ElevatedButton.icon(
                onPressed:
                    _isAnalyzingPrescription || _prescriptionPhotos.isEmpty
                    ? null
                    : _analyzePrescriptionPhotos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemonDark,
                  foregroundColor: Colors.white,
                ),
                icon: _isAnalyzingPrescription
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _isAnalyzingPrescription
                      ? 'Recognizing...'
                      : 'Auto Fill Windows',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickPrescriptionPhotos() async {
    final available = _maxPrescriptionPhotos - _prescriptionPhotos.length;
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can upload up to 12 photos')),
      );
      return;
    }

    final picked = await _imagePicker.pickMultiImage();
    if (picked.isEmpty) return;

    final existing = _prescriptionPhotos.map((e) => e.path).toSet();
    final additions = <File>[];
    for (final item in picked) {
      if (existing.contains(item.path)) continue;
      additions.add(File(item.path));
      existing.add(item.path);
    }

    if (additions.isEmpty) return;
    setState(() {
      _prescriptionPhotos.addAll(additions.take(available));
    });
  }

  Future<void> _analyzePrescriptionPhotos() async {
    if (_prescriptionPhotos.isEmpty) return;
    setState(() => _isAnalyzingPrescription = true);
    try {
      final rows = await context
          .read<TasksProvider>()
          .analyzeMedicinePrescriptionImages(files: _prescriptionPhotos);
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No medicine info was extracted')),
        );
        return;
      }
      final nextWindows = _buildWindowsFromPrescription(rows);
      setState(() {
        _windows = nextWindows;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generated ${nextWindows.length} windows from prescription',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Prescription analysis failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAnalyzingPrescription = false);
    }
  }

  List<TimeWindowEditorData> _buildWindowsFromPrescription(
    List<PrescriptionMedicineItem> rows,
  ) {
    final deduped = <PrescriptionMedicineItem>[];
    final seen = <String>{};
    for (final row in rows) {
      final key =
          '${row.medicineName.trim().toLowerCase()}|${row.frequency.trim().toLowerCase()}';
      if (row.medicineName.trim().isEmpty || seen.contains(key)) continue;
      deduped.add(row);
      seen.add(key);
    }

    if (deduped.isEmpty) return [TimeWindowEditorData(name: 'Morning')];

    final windows = <TimeWindowEditorData>[];
    for (final row in deduped.take(12)) {
      final times = _timesForFrequency(row.frequency);
      for (var i = 0; i < times.length; i++) {
        final slot = times[i];
        windows.add(
          TimeWindowEditorData(
            name: times.length == 1
                ? row.medicineName
                : '${row.medicineName} (${i + 1}/${times.length})',
            openTime: slot,
            closeTime: _plusOneHour(slot),
          ),
        );
      }
    }
    return windows.take(12).toList();
  }

  List<TimeOfDay> _timesForFrequency(String frequency) {
    final f = frequency.toLowerCase();
    if (f.contains('4') || f.contains('q6h') || f.contains('6h')) {
      return const [
        TimeOfDay(hour: 6, minute: 0),
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 22, minute: 0),
      ];
    }
    if (f.contains('3') ||
        f.contains('tid') ||
        f.contains('q8h') ||
        f.contains('8h')) {
      return const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 14, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ];
    }
    if (f.contains('2') ||
        f.contains('bid') ||
        f.contains('q12h') ||
        f.contains('12h')) {
      return const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ];
    }
    return const [TimeOfDay(hour: 8, minute: 0)];
  }

  TimeOfDay _plusOneHour(TimeOfDay input) {
    final nextHour = (input.hour + 1) % 24;
    return TimeOfDay(hour: nextHour, minute: input.minute);
  }

  Future<void> _submitTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate windows have names
    for (var i = 0; i < _windows.length; i++) {
      if (_windows[i].name.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Window ${i + 1} needs a name')));
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final timeWindowList = List.generate(
        _windows.length,
        (i) => _windows[i].toJson(i),
      );

      if (widget.templateId != null) {
        // Edit mode
        await context.read<TasksProvider>().updateTemplate(
          templateId: widget.templateId!,
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
            const SnackBar(content: Text('Template updated successfully')),
          );
        }
      } else {
        // Create mode
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

/// Batch Generate Screen - Generate tasks from a template

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/subscription_error.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/widgets/scroll_datetime_picker.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../providers/tasks_provider.dart';
import '../widgets/family_member_selector.dart';

// ---------------------------------------------------------------------------
// Frequency helpers
// ---------------------------------------------------------------------------

enum FrequencyUnit { hour, day, week, month }

extension FrequencyUnitLabel on FrequencyUnit {
  String get label {
    switch (this) {
      case FrequencyUnit.hour:
        return 'Hour(s)';
      case FrequencyUnit.day:
        return 'Day(s)';
      case FrequencyUnit.week:
        return 'Week(s)';
      case FrequencyUnit.month:
        return 'Month(s)';
    }
  }
}

int _frequencyToMinutes(int value, FrequencyUnit unit) {
  switch (unit) {
    case FrequencyUnit.hour:
      return value * 60;
    case FrequencyUnit.day:
      return value * 1440;
    case FrequencyUnit.week:
      return value * 7 * 1440;
    case FrequencyUnit.month:
      return value * 30 * 1440;
  }
}

/// Returns the minimum valid frequency VALUE for the given unit so that
/// frequencyMinutes > templateSpanMinutes.
int _minValueForUnit(FrequencyUnit unit, int spanMinutes) {
  final unitMinutes = _frequencyToMinutes(1, unit);
  // smallest N such that N * unitMinutes > spanMinutes
  return (spanMinutes ~/ unitMinutes) + 1;
}

int _computeTemplateSpanMinutes(RepeatTaskTemplate template) {
  if (template.timeWindowList.isEmpty) return 0;
  int timeToMin(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final opens = template.timeWindowList
      .map((w) => timeToMin(w.openTime))
      .toList();
  final closes = template.timeWindowList.map((w) {
    return timeToMin(w.closeTime) + (w.isNextDay ? 1440 : 0);
  }).toList();
  return closes.reduce((a, b) => a > b ? a : b) -
      opens.reduce((a, b) => a < b ? a : b);
}

String _spanLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes < 1440) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }
  final d = minutes ~/ 1440;
  final rem = minutes % 1440;
  return rem == 0 ? '${d}d' : '${d}d ${rem ~/ 60}h';
}

// ---------------------------------------------------------------------------

class BatchGenerateScreen extends StatefulWidget {
  const BatchGenerateScreen({super.key});

  @override
  State<BatchGenerateScreen> createState() => _BatchGenerateScreenState();
}

class _BatchGenerateScreenState extends State<BatchGenerateScreen> {
  final _nameController = TextEditingController();
  final _infoController = TextEditingController();
  final _freqValueController = TextEditingController(text: '1');

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 6));
  Map<String, dynamic>? _preview;
  bool _previewExpanded = true;
  bool _isLoading = false;
  String? _templateId;
  RepeatTaskTemplate? _template;
  FamilyMemberSelection _memberSelection = const FamilyMemberSelection();

  FrequencyUnit _frequencyUnit = FrequencyUnit.day;
  int _frequencyValue = 1; // kept in sync with _freqValueController
  int _previewRequestVersion = 0;

  // ---------------------------------------------------------------------------
  // Computed helpers
  // ---------------------------------------------------------------------------

  int get _spanMinutes =>
      _template != null ? _computeTemplateSpanMinutes(_template!) : 0;

  int get _effectiveFrequencyValue {
    final live = int.tryParse(_freqValueController.text);
    if (live != null && live >= 1) return live;
    return _frequencyValue;
  }

  int get _frequencyMinutes =>
      _frequencyToMinutes(_effectiveFrequencyValue, _frequencyUnit);

  bool get _hasValidFrequencyValue => _effectiveFrequencyValue >= 1;

  bool get _isFrequencyValid =>
      _hasValidFrequencyValue &&
      (_spanMinutes == 0 || _frequencyMinutes > _spanMinutes);

  String? get _frequencyError {
    if (!_hasValidFrequencyValue) {
      return 'Please enter a repeat frequency of at least 1.';
    }
    if (_spanMinutes == 0 || _isFrequencyValid) return null;
    final minVal = _minValueForUnit(_frequencyUnit, _spanMinutes);
    return 'Template spans ${_spanLabel(_spanMinutes)}. '
        'Minimum is $minVal ${_frequencyUnit.label.toLowerCase()}.';
  }

  // ---------------------------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && _templateId == null) {
      _templateId = args;
      final provider = context.read<TasksProvider>();
      final template = provider.templates
          .where((t) => t.id == args)
          .firstOrNull;
      if (template != null) {
        _template = template;
        if (_nameController.text.isEmpty) {
          _nameController.text = template.templateName;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _infoController.dispose();
    _freqValueController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          FocusScope.of(context).unfocus();
          _loadPreview();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Task name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Task Name',
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
                hintText: 'Base name for generated tasks',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Family member selector (for admins)
            FamilyMemberSelector(
              initialSelection: _memberSelection,
              onChanged: (selection) =>
                  setState(() => _memberSelection = selection),
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
                });
                _loadPreview();
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
                setState(() => _endDate = dt);
                _loadPreview();
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${_endDate.difference(_startDate).inDays + 1} day(s)',
              style: TextStyle(fontSize: 13, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            // ── Repeat Frequency ──────────────────────────────────────────────
            const Text(
              'Repeat Frequency',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (_spanMinutes > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Template span: ${_spanLabel(_spanMinutes)}  •  frequency must be longer',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                ),
              ),
            Row(
              children: [
                // Numeric input
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _freqValueController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      setState(
                        () => _frequencyValue = (parsed != null && parsed >= 1)
                            ? parsed
                            : 0,
                      );
                      _loadPreview();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Unit dropdown
                Expanded(
                  child: DropdownButtonFormField<FrequencyUnit>(
                    initialValue: _frequencyUnit,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: FrequencyUnit.values.map((u) {
                      return DropdownMenuItem<FrequencyUnit>(
                        value: u,
                        child: Text(u.label),
                      );
                    }).toList(),
                    onChanged: (u) {
                      if (u == null) return;
                      setState(() {
                        _frequencyUnit = u;
                        // Auto-correct value to minimum valid for new unit
                        final minVal = _minValueForUnit(u, _spanMinutes);
                        if (_frequencyValue < minVal) {
                          _frequencyValue = minVal;
                          _freqValueController.text = minVal.toString();
                        }
                      });
                      _loadPreview();
                    },
                  ),
                ),
              ],
            ),
            if (_frequencyError != null) ...[
              const SizedBox(height: 6),
              Text(
                _frequencyError!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
            const SizedBox(height: 20),

            // Notes
            TextFormField(
              controller: _infoController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
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
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Preview results
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryLemonLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryLemon),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () =>
                          setState(() => _previewExpanded = !_previewExpanded),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'This will create ${_preview!['task_count']} tasks',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _previewExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_previewExpanded) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildGroupedPreview(
                            _preview!['tasks_preview'] as List,
                          ),
                        ),
                      ),
                    ],
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
                onPressed: (_isLoading || !_isFrequencyValid)
                    ? null
                    : _generateTasks,
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview helpers

  /// Groups tasks_preview by their cycle date and renders date headers
  /// with window rows beneath each one.
  List<Widget> _buildGroupedPreview(List tasks) {
    // Group by the date portion of open_datetime ("yyyy-MM-dd HH:mm" → "yyyy-MM-dd")
    final Map<String, List<dynamic>> byDate = {};
    for (final task in tasks) {
      final open = task['open_datetime'] as String;
      final date = open.length >= 10 ? open.substring(0, 10) : open;
      byDate.putIfAbsent(date, () => []).add(task);
    }

    final widgets = <Widget>[];
    bool first = true;
    for (final entry in byDate.entries) {
      if (!first) widgets.add(const SizedBox(height: 8));
      first = false;

      // Date header
      widgets.add(
        Text(
          entry.key,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );

      // Window rows under this date
      for (final task in entry.value) {
        final open = task['open_datetime'] as String;
        final close = task['close_datetime'] as String;
        // Show only the time part (chars 11-15) for a compact display
        final openTime = open.length >= 16 ? open.substring(11, 16) : open;
        final closeTime = close.length >= 16 ? close.substring(11, 16) : close;
        // Extract just the window name by stripping the base task name prefix
        final fullName = task['task_name'] as String;
        final baseName = _nameController.text.trim();
        final windowName = fullName.startsWith('$baseName - ')
            ? fullName.substring(baseName.length + 3)
            : fullName;

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              '$windowName  $openTime – $closeTime',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _loadPreview() async {
    if (_templateId == null || _nameController.text.trim().isEmpty) return;
    if (!_isFrequencyValid) {
      // Clear stale preview so a wrong-frequency count isn't shown
      if (mounted) setState(() => _preview = null);
      return;
    }

    final requestVersion = ++_previewRequestVersion;
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
        frequencyMinutes: _frequencyMinutes,
      );
      if (!mounted || requestVersion != _previewRequestVersion) return;
      setState(() {
        _preview = preview;
        _previewExpanded = true;
      });
    } catch (e) {
      if (mounted && requestVersion == _previewRequestVersion) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _generateTasks() async {
    if (_templateId == null || _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a task name')));
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
        frequencyMinutes: _frequencyMinutes,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_preview?['task_count'] ?? 'Tasks'} tasks created successfully',
            ),
          ),
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

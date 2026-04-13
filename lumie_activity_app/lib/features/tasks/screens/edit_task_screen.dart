// Edit Task Screen — pre-populated form sharing widgets with CreateTaskScreen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/widgets/scroll_datetime_picker.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_type_selector.dart';
import '../widgets/family_member_selector.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Route argument ───────────────────────────────────────────────────────────

/// Normalised data passed to EditTaskScreen regardless of source model.
class EditTaskArgs {
  final String taskId;
  final String taskName;
  final TaskType taskType;

  /// UTC datetime strings stored by the backend ("yyyy-MM-dd HH:mm")
  final String openDatetimeUtc;
  final String closeDatetimeUtc;
  final String? taskInfo;
  final String? note;

  /// Current team assignment (null = private task)
  final String? teamId;
  final String? teamName;

  /// Currently assigned user (null = self / creator)
  final String? userId;

  const EditTaskArgs({
    required this.taskId,
    required this.taskName,
    required this.taskType,
    required this.openDatetimeUtc,
    required this.closeDatetimeUtc,
    this.taskInfo,
    this.note,
    this.teamId,
    this.teamName,
    this.userId,
  });

  factory EditTaskArgs.fromTask(Task t) => EditTaskArgs(
        taskId: t.taskId,
        taskName: t.taskName,
        taskType: t.taskType,
        openDatetimeUtc: t.openDatetime,
        closeDatetimeUtc: t.closeDatetime,
        taskInfo: t.taskInfo,
        note: t.note,
        teamId: t.teamId,
        userId: t.userId,
      );

  factory EditTaskArgs.fromAdminTask(AdminTaskData t) => EditTaskArgs(
        taskId: t.taskId,
        taskName: t.rpttaskName,
        taskType: TaskType.fromString(
          t.rpttaskType.isNotEmpty ? t.rpttaskType : t.taskType,
        ),
        openDatetimeUtc: t.openDatetime,
        closeDatetimeUtc: t.closeDatetime,
        taskInfo: t.rpttaskInfo,
        note: t.note,
        teamId: t.familyId,
        teamName: t.familyName,
        userId: t.userId,
      );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class EditTaskScreen extends StatefulWidget {
  final EditTaskArgs args;

  const EditTaskScreen({super.key, required this.args});

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _infoController;
  late final TextEditingController _noteController;

  late TaskType _selectedType;
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  bool _isLoading = false;

  // Team / member assignment — tracks the current selection and whether it
  // changed from the original so we know to send it to the backend.
  late FamilyMemberSelection _memberSelection;
  late FamilyMemberSelection _originalMemberSelection;

  @override
  void initState() {
    super.initState();
    final a = widget.args;
    _nameController = TextEditingController(text: a.taskName);
    _infoController = TextEditingController(text: a.taskInfo ?? '');
    _noteController = TextEditingController(text: a.note ?? '');
    _selectedType = a.taskType;

    // Stored datetimes are UTC — convert to local for the pickers
    _startDateTime = _utcStringToLocal(a.openDatetimeUtc);
    _endDateTime = _utcStringToLocal(a.closeDatetimeUtc);

    // Pre-populate team selection from existing assignment
    _originalMemberSelection = FamilyMemberSelection(
      familyId: a.teamId,
      memberId: a.userId,
      teamName: a.teamName,
    );
    _memberSelection = _originalMemberSelection;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _infoController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Parse a "yyyy-MM-dd HH:mm" UTC string and return local DateTime.
  DateTime _utcStringToLocal(String s) {
    try {
      // Append 'Z' so Dart parses as UTC, then convert to local.
      return DateTime.parse('${s.replaceAll(' ', 'T')}Z').toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatDatetime(DateTime dt) {
    final d =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  String _getDeviceTimezone() {
    try {
      final name = tz.local.name;
      return name.isNotEmpty ? name : 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final openStr = _formatDatetime(_startDateTime);
    final closeStr = _formatDatetime(_endDateTime);

    if (closeStr.compareTo(openStr) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<TasksProvider>();

      // Detect whether the team/member selection changed
      final teamChanged =
          _memberSelection.familyId != _originalMemberSelection.familyId;
      final memberChanged =
          _memberSelection.memberId != _originalMemberSelection.memberId;

      // Save core task fields (+ team/user if changed)
      final updated = await provider.updateTask(
        taskId: widget.args.taskId,
        taskName: _nameController.text.trim(),
        taskType: _selectedType.apiValue,
        openDatetime: openStr,
        closeDatetime: closeStr,
        taskInfo: _infoController.text.trim().isEmpty
            ? null
            : _infoController.text.trim(),
        sendTeamId: teamChanged,
        teamId: teamChanged ? _memberSelection.familyId : null,
        sendUserId: memberChanged,
        userId: memberChanged ? _memberSelection.memberId : null,
      );

      // Save note separately (own endpoint) only if it changed
      final newNote = _noteController.text.trim();
      final oldNote = (widget.args.note ?? '').trim();
      if (newNote != oldNote) {
        await provider.updateNote(widget.args.taskId, newNote);
      }

      if (mounted) {
        Navigator.of(context).pop(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task updated')),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tz = _getDeviceTimezone();

    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Edit Task'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLemonDark,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
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
                hintText: 'e.g. Take medication',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Task name is required';
                }
                if (v.length > 200) return 'Max 200 characters';
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
              onChanged: (t) => setState(() => _selectedType = t),
            ),
            const SizedBox(height: 24),

            // Team / privacy assignment (member picker hidden — team only)
            FamilyMemberSelector(
              initialSelection: _originalMemberSelection,
              onChanged: (selection) {
                // When the user picks a team, default the assigned member to
                // themselves so the backend receives a concrete user_id.
                final selfId =
                    context.read<AuthProvider>().user?.userId;
                final resolved = selection.familyId != null &&
                        selection.memberId == null &&
                        selfId != null
                    ? FamilyMemberSelection(
                        familyId: selection.familyId,
                        memberId: selfId,
                        teamName: selection.teamName,
                      )
                    : selection;
                setState(() => _memberSelection = resolved);
              },
              showMemberSelector: false,
            ),

            // Timezone banner (read-only, same as CreateTaskScreen)
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
                  const Icon(
                    Icons.public,
                    size: 20,
                    color: AppColors.textOnYellow,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Timezone',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tz,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textOnYellow,
                          ),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ScrollDateTimePicker(
              value: _endDateTime,
              minimumDate: DateTime(2000),
              maximumDate: DateTime.now().add(const Duration(days: 365)),
              onChanged: (dt) => setState(() => _endDateTime = dt),
            ),
            const SizedBox(height: 24),

            // Description / task info
            TextFormField(
              controller: _infoController,
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
                hintText: 'Additional information about this task',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 16),

            // Note (user personal note on the task)
            TextFormField(
              controller: _noteController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Note (optional)',
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
                hintText: 'Your personal note on this task',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Icon(
                  Icons.notes_outlined,
                  size: 18,
                  color: AppColors.textLight,
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 8,
              maxLength: 1000,
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
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
                        'Save Changes',
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
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/habit_service.dart';

/// Lightweight habit-logging bottom sheet.
/// Call [HabitTrackerSheet.show] to open it.
class HabitTrackerSheet extends StatefulWidget {
  final bool hasConditionMetric;

  const HabitTrackerSheet({super.key, required this.hasConditionMetric});

  static Future<void> show(
    BuildContext context, {
    bool hasConditionMetric = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HabitTrackerSheet(hasConditionMetric: hasConditionMetric),
    );
  }

  @override
  State<HabitTrackerSheet> createState() => _HabitTrackerSheetState();
}

class _HabitTrackerSheetState extends State<HabitTrackerSheet> {
  final HabitService _service = HabitService();

  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  // Working state — null means "not yet selected"
  int? _mood;
  String? _energy;
  String? _hunger;
  String? _workload;
  String? _fatigue;
  final TextEditingController _metricCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _metricCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final entry = await _service.getTodayEntry();
      if (mounted && entry != null) {
        setState(() {
          _mood = entry.mood;
          _energy = entry.energy;
          _hunger = entry.hunger;
          _workload = entry.workload;
          _fatigue = entry.fatigue;
          if (entry.conditionMetric != null) {
            _metricCtrl.text = entry.conditionMetric!.toStringAsFixed(0);
          }
        });
      }
    } catch (_) {
      // Non-critical — start fresh
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveEntry(
        mood: _mood,
        energy: _energy,
        hunger: _hunger,
        workload: _workload,
        fatigue: _fatigue,
        conditionMetric: _metricCtrl.text.isNotEmpty
            ? double.tryParse(_metricCtrl.text)
            : null,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = true;
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: AppColors.backgroundPaper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Row(
              children: [
                const Text(
                  'Habit Tracker',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  'All optional',
                  style: TextStyle(fontSize: 13, color: AppColors.textLight),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 24, endIndent: 24),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            )
          else if (_saved)
            _buildConfirmation()
          else
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MoodCard(value: _mood, onChanged: (v) => setState(() => _mood = v)),
                    const SizedBox(height: 16),
                    _PillCard(
                      label: 'Energy Level',
                      icon: Icons.bolt_outlined,
                      options: const ['Low', 'Moderate', 'High'],
                      values: const ['low', 'moderate', 'high'],
                      selected: _energy,
                      onChanged: (v) => setState(() => _energy = v),
                    ),
                    const SizedBox(height: 12),
                    _PillCard(
                      label: 'Hunger',
                      icon: Icons.restaurant_outlined,
                      options: const ['Low', 'Normal', 'High'],
                      values: const ['low', 'normal', 'high'],
                      selected: _hunger,
                      onChanged: (v) => setState(() => _hunger = v),
                    ),
                    const SizedBox(height: 12),
                    _PillCard(
                      label: 'Workload',
                      icon: Icons.work_outline,
                      options: const ['Light', 'Moderate', 'Heavy'],
                      values: const ['light', 'moderate', 'heavy'],
                      selected: _workload,
                      onChanged: (v) => setState(() => _workload = v),
                    ),
                    const SizedBox(height: 12),
                    _PillCard(
                      label: 'Fatigue',
                      icon: Icons.battery_2_bar_outlined,
                      options: const ['Low', 'Moderate', 'High'],
                      values: const ['low', 'moderate', 'high'],
                      selected: _fatigue,
                      onChanged: (v) => setState(() => _fatigue = v),
                    ),
                    if (widget.hasConditionMetric) ...[
                      const SizedBox(height: 12),
                      _ConditionMetricCard(controller: _metricCtrl),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryLemonDark,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Log for Today',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfirmation() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 36, color: AppColors.success),
          ),
          const SizedBox(height: 16),
          const Text(
            'Logged for today',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your habits have been saved.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _MoodCard extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _MoodCard({required this.value, required this.onChanged});

  static const _emojis = ['😞', '😕', '😐', '🙂', '😄'];

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: 'Mood',
      icon: Icons.mood_outlined,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_emojis.length, (i) {
          final score = i + 1;
          final selected = value == score;
          return GestureDetector(
            onTap: () => onChanged(selected ? null : score),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryLemon
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppColors.primaryLemonDark
                      : AppColors.surfaceLight,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                _emojis[i],
                style: TextStyle(fontSize: selected ? 28 : 24),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PillCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<String> options;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _PillCard({
    required this.label,
    required this.icon,
    required this.options,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: label,
      icon: icon,
      child: Row(
        children: List.generate(options.length, (i) {
          final isSelected = selected == values[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(isSelected ? null : values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: EdgeInsets.only(right: i < options.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryLemon : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryLemonDark
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  options[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ConditionMetricCard extends StatelessWidget {
  final TextEditingController controller;

  const _ConditionMetricCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: 'Condition Metric',
      icon: Icons.monitor_heart_outlined,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: InputDecoration(
          hintText: 'Enter value',
          hintStyle: TextStyle(color: AppColors.textLight, fontSize: 14),
          filled: true,
          fillColor: AppColors.backgroundLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;

  const _CardShell({required this.label, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

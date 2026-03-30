import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/habit/providers/habit_provider.dart';
import '../../../shared/models/habit_models.dart';

/// Bottom sheet for logging daily habits.
class HabitTrackerSheet extends StatefulWidget {
  final String? icd10Code;

  const HabitTrackerSheet({super.key, this.icd10Code});

  /// Open the habit tracker as a modal bottom sheet.
  static void show(BuildContext context, {String? icd10Code}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<HabitProvider>(),
        child: HabitTrackerSheet(icd10Code: icd10Code),
      ),
    );
  }

  @override
  State<HabitTrackerSheet> createState() => _HabitTrackerSheetState();
}

class _HabitTrackerSheetState extends State<HabitTrackerSheet>
    with SingleTickerProviderStateMixin {
  // Local selections (pre-populated from existing entry)
  int? _mood;
  String? _energy;
  String? _hunger;
  String? _workload;
  String? _fatigue;
  final TextEditingController _conditionCtrl = TextEditingController();

  bool _saved = false;
  late AnimationController _checkAnim;
  late Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _checkScale = CurvedAnimation(parent: _checkAnim, curve: Curves.elasticOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<HabitProvider>();
      await provider.loadToday();
      if (mounted) _populateFromEntry(provider.todayEntry);
    });
  }

  void _populateFromEntry(HabitEntry? entry) {
    if (entry == null) return;
    setState(() {
      _mood = entry.mood;
      _energy = entry.energy;
      _hunger = entry.hunger;
      _workload = entry.workload;
      _fatigue = entry.fatigue;
      if (entry.conditionMetric != null) {
        _conditionCtrl.text = entry.conditionMetric!.toStringAsFixed(1);
      }
    });
  }

  @override
  void dispose() {
    _checkAnim.dispose();
    _conditionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<HabitProvider>();
    double? metric;
    final raw = _conditionCtrl.text.trim();
    if (raw.isNotEmpty) metric = double.tryParse(raw);

    await provider.saveEntry(
      mood: _mood,
      energy: _energy,
      hunger: _hunger,
      workload: _workload,
      fatigue: _fatigue,
      conditionMetric: metric,
    );

    if (!mounted) return;
    if (provider.state == HabitProviderState.loaded) {
      setState(() => _saved = true);
      _checkAnim.forward();
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).pop();
    }
  }

  bool get _hasAnySelection =>
      _mood != null ||
      _energy != null ||
      _hunger != null ||
      _workload != null ||
      _fatigue != null ||
      _conditionCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottom),
      child: _saved ? _buildConfirmation() : _buildForm(),
    );
  }

  Widget _buildConfirmation() {
    return SafeArea(
      child: SizedBox(
        height: 280,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 44),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Logged for today ✓',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Consumer<HabitProvider>(
      builder: (context, provider, _) {
        final isLoading = provider.isLoading;
        final isSaving = provider.isSaving;
        final hasExisting = provider.hasEntry;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'How are you feeling?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasExisting ? 'Tap any card to update' : 'All fields are optional',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Cards
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryLemonDark),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.62,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    children: [
                      _MoodCard(
                        selected: _mood,
                        onSelect: (v) => setState(() => _mood = v),
                      ),
                      const SizedBox(height: 10),
                      _PillCard(
                        label: 'Energy Level',
                        icon: Icons.bolt_outlined,
                        options: const ['Low', 'Moderate', 'High'],
                        values: const ['low', 'moderate', 'high'],
                        selected: _energy,
                        onSelect: (v) => setState(() => _energy = v),
                      ),
                      const SizedBox(height: 10),
                      _PillCard(
                        label: 'Hunger',
                        icon: Icons.restaurant_outlined,
                        options: const ['Low', 'Normal', 'High'],
                        values: const ['low', 'normal', 'high'],
                        selected: _hunger,
                        onSelect: (v) => setState(() => _hunger = v),
                      ),
                      const SizedBox(height: 10),
                      _PillCard(
                        label: 'Workload',
                        icon: Icons.work_outline,
                        options: const ['Light', 'Moderate', 'Heavy'],
                        values: const ['light', 'moderate', 'heavy'],
                        selected: _workload,
                        onSelect: (v) => setState(() => _workload = v),
                      ),
                      const SizedBox(height: 10),
                      _PillCard(
                        label: 'Fatigue',
                        icon: Icons.battery_2_bar_outlined,
                        options: const ['Low', 'Moderate', 'High'],
                        values: const ['low', 'moderate', 'high'],
                        selected: _fatigue,
                        onSelect: (v) => setState(() => _fatigue = v),
                      ),
                      if (widget.icd10Code != null) ...[
                        const SizedBox(height: 10),
                        _ConditionMetricCard(
                          controller: _conditionCtrl,
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            // Save button
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (isSaving || !_hasAnySelection) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLemonDark,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            hasExisting ? 'Update' : 'Log for Today',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Mood Card ─────────────────────────────────────────────────────────────

class _MoodCard extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onSelect;

  const _MoodCard({required this.selected, required this.onSelect});

  static const _emojis = ['😞', '😕', '😐', '🙂', '😄'];

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: 'Mood',
      icon: Icons.mood_outlined,
      isSelected: selected != null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(5, (i) {
          final value = i + 1;
          final active = selected == value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(active ? null : value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryLemon
                    : AppColors.backgroundLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? AppColors.primaryLemonDark
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(_emojis[i], style: const TextStyle(fontSize: 26)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Pill Card ─────────────────────────────────────────────────────────────

class _PillCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<String> options;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _PillCard({
    required this.label,
    required this.icon,
    required this.options,
    required this.values,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: label,
      icon: icon,
      isSelected: selected != null,
      child: Row(
        children: List.generate(options.length, (i) {
          final active = selected == values[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < options.length - 1 ? 8 : 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(active ? null : values[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryLemon
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active
                          ? AppColors.primaryLemonDark
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? AppColors.textOnYellow
                            : AppColors.textSecondary,
                      ),
                    ),
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

// ─── Condition Metric Card ──────────────────────────────────────────────────

class _ConditionMetricCard extends StatelessWidget {
  final TextEditingController controller;

  const _ConditionMetricCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      label: 'Condition Reading',
      icon: Icons.monitor_heart_outlined,
      isSelected: controller.text.trim().isNotEmpty,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          hintText: 'Enter value',
          hintStyle: const TextStyle(
            color: AppColors.textLight,
            fontSize: 15,
          ),
          filled: true,
          fillColor: AppColors.backgroundLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ─── Card Shell ────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Widget child;

  const _CardShell({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primaryLemonDark.withValues(alpha: 0.35)
              : AppColors.surfaceLight,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
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
              if (isSelected) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLemonDark,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

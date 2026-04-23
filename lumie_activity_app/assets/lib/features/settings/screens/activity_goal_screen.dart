import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/steps_models.dart';
import '../providers/activity_goal_provider.dart';

class ActivityGoalScreen extends StatefulWidget {
  const ActivityGoalScreen({super.key});

  @override
  State<ActivityGoalScreen> createState() => _ActivityGoalScreenState();
}

class _ActivityGoalScreenState extends State<ActivityGoalScreen> {
  final _customGoalController = TextEditingController();

  // Draft state — not applied until Save is tapped.
  late ActivityGoalType _draftGoalType;
  bool _useCustom = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prov = context.read<ActivityGoalProvider>();
    _draftGoalType = prov.settings.goalType;
    _useCustom = prov.settings.customGoal != null;
    if (_useCustom) {
      _customGoalController.text = prov.settings.customGoal.toString();
    }
  }

  @override
  void dispose() {
    _customGoalController.dispose();
    super.dispose();
  }

  // ─── Draft helpers ────────────────────────────────────────────────────────

  bool _isDirty(ActivityGoalProvider prov) {
    if (_draftGoalType != prov.settings.goalType) return true;
    final draftCustom =
        _useCustom ? int.tryParse(_customGoalController.text.trim()) : null;
    return draftCustom != prov.settings.customGoal;
  }

  void _onGoalTypeTapped(ActivityGoalType newType) {
    if (newType == _draftGoalType) return;
    // Convert any in-progress custom value to the new unit.
    if (_useCustom) {
      final currentVal = int.tryParse(_customGoalController.text.trim());
      if (currentVal != null && currentVal > 0) {
        final converted = newType == ActivityGoalType.steps
            ? (currentVal * 8000 / 60).round()
            : (currentVal * 60 / 8000).round();
        _customGoalController.text = converted.toString();
      }
    }
    setState(() => _draftGoalType = newType);
  }

  Future<void> _save(ActivityGoalProvider prov) async {
    int? customGoal;
    if (_useCustom) {
      final val = int.tryParse(_customGoalController.text.trim());
      if (val == null || val <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid number')),
        );
        return;
      }
      customGoal = val;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    await prov.saveSettings(_draftGoalType, customGoal);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity goal saved ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivityGoalProvider>(
      builder: (context, prov, _) {
        final isDirty = _isDirty(prov);
        return Scaffold(
          backgroundColor: AppColors.backgroundWhite,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundWhite,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: const BackButton(color: AppColors.textPrimary),
            title: const Text(
              'Activity Goal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Fixed Save button at the bottom.
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDirty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit_outlined,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Text(
                            'Preview — tap Save to apply',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (_saving || !isDirty) ? null : () => _save(prov),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.surfaceLight,
                        disabledForegroundColor: AppColors.textLight,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
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
                          : Text(
                              isDirty ? 'Save Goal' : 'Saved',
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
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildGoalTypeCard(),
              const SizedBox(height: 20),
              _buildDefaultCard(prov),
              const SizedBox(height: 20),
              _buildCustomOverrideCard(),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ─── Goal type selector ───────────────────────────────────────────────────

  Widget _buildGoalTypeCard() {
    return _Card(
      title: 'Goal Type',
      child: Column(
        children: [
          _GoalTypeOption(
            label: 'Active Time',
            subtitle: 'Track daily minutes of movement',
            icon: Icons.timer_outlined,
            selected: _draftGoalType == ActivityGoalType.minutes,
            onTap: () => _onGoalTypeTapped(ActivityGoalType.minutes),
          ),
          const Divider(height: 1),
          _GoalTypeOption(
            label: 'Steps',
            subtitle: 'Track daily step count',
            icon: Icons.directions_walk_outlined,
            selected: _draftGoalType == ActivityGoalType.steps,
            onTap: () => _onGoalTypeTapped(ActivityGoalType.steps),
          ),
        ],
      ),
    );
  }

  // ─── Condition-adjusted default info ─────────────────────────────────────

  Widget _buildDefaultCard(ActivityGoalProvider prov) {
    final s = prov.settings;
    // Preview uses _draftGoalType, not the committed type.
    final isSteps = _draftGoalType == ActivityGoalType.steps;
    final defaultVal = isSteps ? s.defaultSteps : s.defaultMinutes;
    final unit = _draftGoalType.unitLabel;

    return _Card(
      title: 'Your Baseline',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$defaultVal $unit/day',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (s.conditionAdjusted) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentMint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Condition-adjusted',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.accentMint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.conditionAdjusted
                  ? 'Automatically reduced based on your health condition. '
                      'You can override this below.'
                  : 'Standard baseline. Reduced automatically on poor-sleep days.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Custom override ──────────────────────────────────────────────────────

  Widget _buildCustomOverrideCard() {
    final unit = _draftGoalType.unitLabel;

    return _Card(
      title: 'Custom Override',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text(
              'Set my own goal',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text(
              'Override the condition-adjusted baseline',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            value: _useCustom,
            activeThumbColor: AppColors.primaryLemonDark,
            onChanged: (val) {
              setState(() {
                _useCustom = val;
                if (!val) _customGoalController.clear();
              });
            },
          ),
          if (_useCustom) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: TextField(
                controller: _customGoalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}), // rebuild to update isDirty
                decoration: InputDecoration(
                  labelText: 'Goal ($unit/day)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GoalTypeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GoalTypeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        icon,
        color: selected ? AppColors.primaryLemonDark : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColors.primaryLemonDark)
          : const Icon(Icons.radio_button_unchecked, color: AppColors.textLight),
      onTap: onTap,
    );
  }
}

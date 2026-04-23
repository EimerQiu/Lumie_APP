import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/workout_template_provider.dart';
import 'template_builder_screen.dart';

/// Screen to choose a split type and create template stubs for each day.
class SplitBuilderScreen extends StatefulWidget {
  const SplitBuilderScreen({super.key});

  @override
  State<SplitBuilderScreen> createState() => _SplitBuilderScreenState();
}

class _SplitBuilderScreenState extends State<SplitBuilderScreen> {
  SplitType _selectedSplit = SplitType.fullBody;
  final _customDays = <String>[];
  final _customDayController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _customDayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Create Workout Split',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose your split type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'This determines how many workout days you train per week and what each day focuses on.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ..._splitOptions.map((opt) => _SplitOptionCard(
                  splitType: opt.type,
                  title: opt.title,
                  subtitle: opt.subtitle,
                  days: opt.days,
                  isSelected: _selectedSplit == opt.type,
                  onTap: () => setState(() {
                    _selectedSplit = opt.type;
                    _customDays.clear();
                  }),
                )),
            // Custom day names
            if (_selectedSplit == SplitType.custom) ...[
              const SizedBox(height: 16),
              const Text('Name your training days',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ..._customDays.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(e.value,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setState(() => _customDays.removeAt(e.key)),
                        ),
                      ],
                    ),
                  )),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customDayController,
                      decoration: InputDecoration(
                        hintText: 'Day name (e.g. "Chest & Triceps")',
                        filled: true,
                        fillColor: AppColors.backgroundLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppColors.primaryLemonDark),
                    onPressed: () {
                      final name = _customDayController.text.trim();
                      if (name.isNotEmpty) {
                        setState(() => _customDays.add(name));
                        _customDayController.clear();
                      }
                    },
                  ),
                ],
              ),
            ],
            // ── Preview of days to create ────────────────────────────
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your split will create ${_dayLabels.length} workout ${_dayLabels.length == 1 ? "template" : "templates"}:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._dayLabels.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLemon,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textOnYellow,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              e.value,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '0 exercises',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 4),
                  Text(
                    'You\'ll add exercises to each day after creating the split.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _creating ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemon,
                  foregroundColor: AppColors.textOnYellow,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _creating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Split',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _dayLabels {
    switch (_selectedSplit) {
      case SplitType.fullBody:
        return ['Full Body'];
      case SplitType.upperLower:
        return ['Upper Body', 'Lower Body'];
      case SplitType.pushPullLegs:
        return ['Push', 'Pull', 'Legs'];
      case SplitType.bodyPart:
        return ['Chest', 'Back', 'Shoulders', 'Legs', 'Arms', 'Core'];
      case SplitType.abBlock:
        return ['Day A', 'Day B'];
      case SplitType.custom:
        return _customDays.isEmpty ? ['Day 1'] : _customDays;
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final provider = context.read<WorkoutTemplateProvider>();
    final groupId = 'split_${DateTime.now().millisecondsSinceEpoch}';
    final labels = _dayLabels;

    WorkoutTemplate? firstTemplate;
    for (int i = 0; i < labels.length; i++) {
      try {
        final t = await provider.createTemplate(
          name: labels[i],
          emoji: _splitEmoji,
          splitType: splitTypeToString(_selectedSplit),
          splitDayLabel: labels[i],
          splitGroupId: groupId,
          blocks: [
            WorkoutBlock(
              blockId: 'block_main_$i',
              name: 'Main Workout',
              order: 0,
            ),
          ],
        );
        firstTemplate ??= t;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
        setState(() => _creating = false);
        return;
      }
    }

    setState(() => _creating = false);

    if (mounted && firstTemplate != null) {
      // Navigate to the first template's builder
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TemplateBuilderScreen(templateId: firstTemplate!.templateId),
        ),
      );
    }
  }

  String get _splitEmoji {
    switch (_selectedSplit) {
      case SplitType.fullBody:
        return '💪';
      case SplitType.upperLower:
        return '🔄';
      case SplitType.pushPullLegs:
        return '🏋️';
      case SplitType.bodyPart:
        return '🎯';
      case SplitType.abBlock:
        return '🅰️';
      case SplitType.custom:
        return '✨';
    }
  }
}

// ── Split option data ─────────────────────────────────────────────────────────

class _SplitOption {
  final SplitType type;
  final String title;
  final String subtitle;
  final List<String> days;
  const _SplitOption(this.type, this.title, this.subtitle, this.days);
}

const _splitOptions = [
  _SplitOption(SplitType.fullBody, 'Full Body',
      'All muscle groups in one session', ['Full Body']),
  _SplitOption(SplitType.upperLower, 'Upper / Lower',
      'Alternate upper and lower body days', ['Upper', 'Lower']),
  _SplitOption(SplitType.pushPullLegs, 'Push / Pull / Legs',
      'Three-way muscle group split', ['Push', 'Pull', 'Legs']),
  _SplitOption(SplitType.bodyPart, 'Body Part Split',
      'Dedicated day per muscle group', ['Chest', 'Back', 'Shoulders', '...']),
  _SplitOption(SplitType.abBlock, 'A/B Block Split',
      'Two alternating workout blocks', ['Day A', 'Day B']),
  _SplitOption(
      SplitType.custom, 'Custom', 'Name each day yourself', ['You decide']),
];

// ── Split option card widget ──────────────────────────────────────────────────

class _SplitOptionCard extends StatelessWidget {
  final SplitType splitType;
  final String title;
  final String subtitle;
  final List<String> days;
  final bool isSelected;
  final VoidCallback onTap;

  const _SplitOptionCard({
    required this.splitType,
    required this.title,
    required this.subtitle,
    required this.days,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLemon.withAlpha(25)
              : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? AppColors.primaryLemonDark : AppColors.surfaceLight,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: days
                        .map((d) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryLemon
                                    : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(d,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.textOnYellow
                                        : AppColors.textSecondary,
                                  )),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: AppColors.primaryLemonDark, size: 24),
          ],
        ),
      ),
    );
  }
}

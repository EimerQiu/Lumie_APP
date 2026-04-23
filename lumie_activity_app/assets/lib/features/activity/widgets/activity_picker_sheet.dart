// Shared "Choose Activity" bottom-sheet widget.
// Updated to show API-fetched workout templates alongside the activity grid.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../../workout/providers/workout_template_provider.dart';
import '../../workout/screens/split_builder_screen.dart';
import '../../workout/screens/active_workout_screen.dart';
import '../../workout/screens/template_builder_screen.dart';

class ActivityPickerSheet extends StatelessWidget {
  final void Function(ActivityType) onSelected;
  final void Function(WorkoutPlan) onWorkoutSelected;
  final bool isPro;
  final VoidCallback onUpgradeTapped;

  const ActivityPickerSheet({
    super.key,
    required this.onSelected,
    required this.onWorkoutSelected,
    required this.isPro,
    required this.onUpgradeTapped,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final templateProvider = context.watch<WorkoutTemplateProvider>();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.87),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle + title ───────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // ── My Workouts ──────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'My Workouts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Builder(builder: (context) {
              // Use API templates if available, fall back to legacy sample plans
              final apiTemplates = templateProvider.templates;
              final hasApiTemplates = apiTemplates.isNotEmpty;

              final visibleTemplates = hasApiTemplates
                  ? (isPro
                      ? apiTemplates
                      : apiTemplates
                          .where((t) => t.isSystemDefault)
                          .toList())
                  : <WorkoutTemplate>[];

              // Legacy fallback only if API hasn't loaded
              final legacyPlans = hasApiTemplates
                  ? <WorkoutPlan>[]
                  : (isPro
                      ? WorkoutPlan.samplePlans
                      : WorkoutPlan.samplePlans
                          .where((p) => p.isFreeDefault)
                          .toList());

              final totalItems =
                  visibleTemplates.length + legacyPlans.length + 1;

              return SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  itemCount: totalItems,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    // ── API template cards ─────────────────────────────────
                    if (i < visibleTemplates.length) {
                      final template = visibleTemplates[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          // For the old-style free template, use legacy session
                          if (template.isSystemDefault) {
                            onWorkoutSelected(
                                WorkoutPlan.fromTemplate(template));
                          } else {
                            // Use new active workout screen
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ActiveWorkoutScreen(
                                    template: template),
                                fullscreenDialog: true,
                              ),
                            );
                          }
                        },
                        onLongPress: template.isSystemDefault
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TemplateBuilderScreen(
                                        templateId: template.templateId),
                                  ),
                                );
                              },
                        child: _TemplatePlanCard(
                          emoji: template.emoji,
                          name: template.name,
                          exerciseCount: template.exerciseCount,
                          isFree: template.isSystemDefault,
                          splitDayLabel: template.splitDayLabel,
                        ),
                      );
                    }

                    // ── Legacy plan cards (fallback) ──────────────────────
                    final legacyIdx = i - visibleTemplates.length;
                    if (legacyIdx < legacyPlans.length) {
                      final plan = legacyPlans[legacyIdx];
                      return GestureDetector(
                        onTap: () => onWorkoutSelected(plan),
                        child: _TemplatePlanCard(
                          emoji: plan.emoji,
                          name: plan.name,
                          exerciseCount: plan.exercises.length,
                          isFree: plan.isFreeDefault,
                        ),
                      );
                    }

                    // ── Create / locked-create card ───────────────────────
                    if (isPro) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SplitBuilderScreen(),
                            ),
                          );
                        },
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.surfaceLight, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 28, color: AppColors.textSecondary),
                              SizedBox(height: 6),
                              Text(
                                'New\nWorkout',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return GestureDetector(
                        onTap: () => UpgradePromptBottomSheet.showCustom(
                          context: ctx,
                          title: 'Custom Workouts',
                          message:
                              'Create and save personalized workout plans with custom exercises, sets, reps, and rest times.',
                          detail:
                              'Available on Monthly and Annual plans. Your free "Full Body Starter" plan is always accessible.',
                          actionLabel: 'Upgrade to Premium',
                          onUpgrade: onUpgradeTapped,
                        ),
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            color: AppColors.backgroundLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.surfaceLight, width: 1.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 24, color: AppColors.textLight),
                              const SizedBox(height: 6),
                              Text(
                                'Create\nWorkout',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLemon,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'PREMIUM',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textOnYellow,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
            // ── Divider ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                      child: Divider(color: AppColors.surfaceLight)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'All Activities',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                  const Expanded(
                      child: Divider(color: AppColors.surfaceLight)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ── Activity type grid ────────────────────────────────────────
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: ActivityType.predefinedTypes.length,
                itemBuilder: (_, i) {
                  final type = ActivityType.predefinedTypes[i];
                  return GestureDetector(
                    onTap: () => onSelected(type),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.warmGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(type.icon,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 6),
                          Text(
                            type.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnYellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable template/plan card for the horizontal scroller.
class _TemplatePlanCard extends StatelessWidget {
  final String emoji;
  final String name;
  final int exerciseCount;
  final bool isFree;
  final String? splitDayLabel;

  const _TemplatePlanCard({
    required this.emoji,
    required this.name,
    required this.exerciseCount,
    required this.isFree,
    this.splitDayLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                  if (splitDayLabel != null && splitDayLabel != name)
                    Text(
                      splitDayLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textOnYellow.withValues(alpha: 0.8),
                      ),
                    ),
                  Text(
                    '$exerciseCount exercises',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textOnYellow.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isFree)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLemonDark,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF78350F),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../../workout/providers/workout_template_provider.dart';
import '../../workout/screens/active_workout_screen.dart';
import '../../workout/screens/exercise_library_screen.dart';
import '../../workout/screens/split_builder_screen.dart';
import '../../workout/screens/template_builder_screen.dart';
import '../providers/workout_history_provider.dart';
import 'quick_log_screen.dart';
import 'strength_progress_screen.dart';
import 'workout_session_detail_screen.dart';

class StrengthHomeScreen extends StatefulWidget {
  const StrengthHomeScreen({super.key});

  @override
  State<StrengthHomeScreen> createState() => _StrengthHomeScreenState();
}

class _StrengthHomeScreenState extends State<StrengthHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkoutTemplateProvider>().loadTemplates();
      context.read<WorkoutHistoryProvider>().loadSessions();
    });
  }

  void _showStartWorkoutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StartWorkoutSheet(
        onFromTemplate: _showTemplatePicker,
        onBuildPlan: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SplitBuilderScreen()),
          );
        },
        onExerciseLibrary: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
          );
        },
      ),
    );
  }

  void _showTemplatePicker() {
    Navigator.pop(context); // close start sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TemplatePickerSheet(
        templates: context.read<WorkoutTemplateProvider>().templates,
        onPick: _launchTemplate,
      ),
    );
  }

  void _launchTemplate(WorkoutTemplate template) {
    Navigator.pop(context); // close picker sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(template: template),
      ),
    ).then((_) {
      if (!mounted) return;
      context.read<WorkoutHistoryProvider>().loadSessions(force: true);
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    return '${m}m';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Strength',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const StrengthProgressScreen()),
            ),
            icon: const Icon(Icons.bar_chart,
                color: AppColors.primaryLemonDark, size: 20),
            label: const Text(
              'Progress',
              style: TextStyle(
                color: AppColors.primaryLemonDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryLemonDark,
        onRefresh: () async {
          final historyProvider = context.read<WorkoutHistoryProvider>();
          final templateProvider = context.read<WorkoutTemplateProvider>();
          await historyProvider.loadSessions(force: true);
          await templateProvider.loadTemplates();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Action buttons ─────────────────────────────────────────
              Row(
                children: [
                  // Log Workout (manual quick-log)
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final provider =
                            context.read<WorkoutHistoryProvider>();
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const QuickLogScreen()),
                        );
                        if (!mounted) return;
                        provider.loadSessions(force: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWhite,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.edit_note,
                                color: AppColors.primaryLemonDark, size: 28),
                            SizedBox(height: 10),
                            Text(
                              'Log Workout',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Manual entry',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Start Workout (template-based)
                  Expanded(
                    child: GestureDetector(
                      onTap: _showStartWorkoutSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.play_arrow_rounded,
                                color: AppColors.textOnYellow, size: 28),
                            SizedBox(height: 10),
                            Text(
                              'Start Workout',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textOnYellow,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'From template',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textOnYellow),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── My Templates ──────────────────────────────────────────
              _SectionHeader(
                title: 'My Templates',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SplitBuilderScreen()),
                ),
                actionLabel: 'New Plan',
              ),
              const SizedBox(height: 12),
              Consumer<WorkoutTemplateProvider>(
                builder: (context, provider, _) {
                  if (provider.loading) {
                    return const _LoadingRow();
                  }
                  final templates = provider.templates;
                  if (templates.isEmpty) {
                    return _EmptyTemplatesCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SplitBuilderScreen()),
                      ),
                    );
                  }
                  return SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: templates.length,
                      separatorBuilder: (_, i) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => _TemplateCard(
                        template: templates[i],
                        onTap: () => _launchTemplate(templates[i]),
                        onEdit: () async {
                          final provider =
                              context.read<WorkoutTemplateProvider>();
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TemplateBuilderScreen(
                                  templateId: templates[i].templateId),
                            ),
                          );
                          if (!mounted) return;
                          provider.loadTemplates();
                        },
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // ── Recent Workouts ──────────────────────────────────────
              const _SectionHeader(title: 'Recent Workouts'),
              const SizedBox(height: 12),
              Consumer<WorkoutHistoryProvider>(
                builder: (context, provider, _) {
                  if (provider.state == WorkoutHistoryState.loading) {
                    return const _LoadingRow();
                  }
                  if (provider.state == WorkoutHistoryState.error) {
                    return _ErrorCard(message: provider.error ?? 'Failed to load');
                  }
                  if (provider.sessions.isEmpty) {
                    return const _EmptySessionsCard();
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.sessions.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final s = provider.sessions[i];
                      return _SessionCard(
                        session: s,
                        dateLabel: _formatDate(s.startedAt),
                        durationLabel: _formatDuration(s.durationSeconds),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                WorkoutSessionDetailScreen(session: s),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 28),

              // ── Secondary actions ─────────────────────────────────────
              _SecondaryActionTile(
                icon: Icons.search,
                title: 'Exercise Library',
                subtitle: 'Browse & search exercises',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExerciseLibraryScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onAction;
  final String? actionLabel;

  const _SectionHeader({
    required this.title,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  actionLabel ?? 'See All',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLemonDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.primaryLemonDark),
              ],
            ),
          ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final WorkoutTemplate template;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _TemplateCard({
    required this.template,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(template.emoji,
                    style: const TextStyle(fontSize: 26)),
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.textLight),
                ),
              ],
            ),
            const Spacer(),
            Text(
              template.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${template.exerciseCount} exercises',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final WorkoutSession session;
  final String dateLabel;
  final String durationLabel;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.dateLabel,
    required this.durationLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final prCount =
        session.exercises.expand((e) => e.sets).where((s) => s.isPr).length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    session.templateName.isNotEmpty
                        ? session.templateName
                        : 'Workout',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (prCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLemon,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🏆 $prCount PR',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnYellow,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatChip(icon: Icons.calendar_today_outlined,
                    label: dateLabel),
                const SizedBox(width: 12),
                _StatChip(icon: Icons.timer_outlined, label: durationLabel),
                const SizedBox(width: 12),
                _StatChip(
                    icon: Icons.fitness_center_outlined,
                    label: '${session.exercises.length} ex'),
                const SizedBox(width: 12),
                _StatChip(
                    icon: Icons.repeat,
                    label: '${session.totalSets} sets'),
              ],
            ),
            const SizedBox(height: 6),
            // Attribution pill
            _AttributionPill(isAdvisorAdded: session.isAdvisorAdded),
            if (session.notes != null && session.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                session.notes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttributionPill extends StatelessWidget {
  final bool isAdvisorAdded;

  const _AttributionPill({required this.isAdvisorAdded});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isAdvisorAdded ? Icons.person_outline : Icons.person,
          size: 12,
          color: AppColors.textLight,
        ),
        const SizedBox(width: 3),
        Text(
          isAdvisorAdded ? 'Added by Advisor' : 'Logged by You',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textLight,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmptyTemplatesCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmptyTemplatesCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.surfaceLight, width: 1.5, style: BorderStyle.solid),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, color: AppColors.textOnYellow),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build your first plan',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('Create a workout split to get started',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _EmptySessionsCard extends StatelessWidget {
  const _EmptySessionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: const Column(
        children: [
          Icon(Icons.fitness_center_outlined,
              size: 40, color: AppColors.textLight),
          SizedBox(height: 12),
          Text(
            'No workouts logged yet',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Tap Start Workout to log your first session',
            style: TextStyle(fontSize: 13, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primaryLemonDark),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      ),
    );
  }
}

class _SecondaryActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SecondaryActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textOnYellow, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Bottom Sheets ────────────────────────────────────────────────────────────

class _StartWorkoutSheet extends StatelessWidget {
  final VoidCallback onFromTemplate;
  final VoidCallback onBuildPlan;
  final VoidCallback onExerciseLibrary;

  const _StartWorkoutSheet({
    required this.onFromTemplate,
    required this.onBuildPlan,
    required this.onExerciseLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start Workout',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose how you want to begin',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _SheetOption(
                icon: Icons.list_alt_outlined,
                color: AppColors.primaryLemon,
                iconColor: AppColors.textOnYellow,
                title: 'From Template',
                subtitle: 'Pick one of your saved workout plans',
                onTap: onFromTemplate,
              ),
              const SizedBox(height: 10),
              _SheetOption(
                icon: Icons.build_outlined,
                color: const Color(0xFFE0F2FE),
                iconColor: const Color(0xFF0369A1),
                title: 'Build a Plan',
                subtitle: 'Create a new split or custom template',
                onTap: onBuildPlan,
              ),
              const SizedBox(height: 10),
              _SheetOption(
                icon: Icons.search,
                color: const Color(0xFFF0FDF4),
                iconColor: const Color(0xFF166534),
                title: 'Exercise Library',
                subtitle: 'Browse exercises and learn movements',
                onTap: onExerciseLibrary,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundPaper,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TemplatePickerSheet extends StatelessWidget {
  final List<WorkoutTemplate> templates;
  final void Function(WorkoutTemplate) onPick;

  const _TemplatePickerSheet({
    required this.templates,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(24),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pick a Template',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No templates yet — build a plan first.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: templates.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = templates[i];
                    return GestureDetector(
                      onTap: () => onPick(t),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundPaper,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Text(t.emoji,
                                style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary)),
                                  Text(
                                    '${t.exerciseCount} exercises',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_arrow_rounded,
                                color: AppColors.primaryLemonDark, size: 28),
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

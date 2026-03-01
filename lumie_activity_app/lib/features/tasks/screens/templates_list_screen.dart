/// Templates List Screen - Template management

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../providers/tasks_provider.dart';

class TemplatesListScreen extends StatefulWidget {
  const TemplatesListScreen({super.key});

  @override
  State<TemplatesListScreen> createState() => _TemplatesListScreenState();
}

class _TemplatesListScreenState extends State<TemplatesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TasksProvider>().loadTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        title: const Text('Templates'),
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Consumer<TasksProvider>(
        builder: (context, provider, _) {
          final templates = provider.templates;

          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.view_list, size: 64, color: AppColors.surfaceLight),
                  const SizedBox(height: 16),
                  Text(
                    'No templates yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a template for recurring tasks',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              return _TemplateCard(
                template: template,
                onGenerateTasks: () => Navigator.pushNamed(
                  context,
                  '/tasks/batch',
                  arguments: template.id,
                ),
                onDelete: () => _deleteTemplate(template),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/tasks/templates/create'),
        backgroundColor: AppColors.primaryLemonDark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
    );
  }

  Future<void> _deleteTemplate(RepeatTaskTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text(
            'Are you sure you want to delete "${template.templateName}"? This does not affect already-created tasks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<TasksProvider>().deleteTemplate(template.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${template.templateName}" deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${e.toString().replaceFirst('Exception: ', '')}')),
          );
        }
      }
    }
  }
}

class _TemplateCard extends StatelessWidget {
  final RepeatTaskTemplate template;
  final VoidCallback onGenerateTasks;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onGenerateTasks,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  template.templateName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLemon,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  template.templateType.displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textOnYellow,
                  ),
                ),
              ),
            ],
          ),
          if (template.description != null) ...[
            const SizedBox(height: 4),
            Text(
              template.description!,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),

          // Info row
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: AppColors.textLight),
              const SizedBox(width: 4),
              Text(
                '${template.timeWindows} window${template.timeWindows > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              if (template.minInterval > 0) ...[
                Icon(Icons.timer, size: 16, color: AppColors.textLight),
                const SizedBox(width: 4),
                Text(
                  '${template.minInterval} min interval',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGenerateTasks,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Create Tasks'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryLemonDark,
                    side: BorderSide(color: AppColors.primaryLemonDark),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 22),
                color: AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/services/advisor_capability_service.dart';
import '../../../core/services/advisor_proactive_checklist_service.dart';
import 'advisor_skill_list_screen.dart';

/// Settings screen for Advisor capabilities and skills.
///
/// Shows capability toggles and links to skill configuration.
class AdvisorSettingsScreen extends StatefulWidget {
  const AdvisorSettingsScreen({super.key});

  @override
  State<AdvisorSettingsScreen> createState() => _AdvisorSettingsScreenState();
}

class _AdvisorSettingsScreenState extends State<AdvisorSettingsScreen> {
  final _capService = AdvisorCapabilityService();
  final _checklistService = AdvisorProactiveChecklistService();
  List<AdvisorCapability> _capabilities = [];
  List<ProactiveChecklistItem> _checklistItems = [];
  bool _loading = true;
  bool _checklistLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final caps = await _capService.getCapabilities();
      final checklist = await _checklistService.getChecklist();
      setState(() {
        _capabilities = caps;
        _checklistItems = checklist.manualItems;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reloadChecklist() async {
    setState(() {
      _checklistLoading = true;
    });
    try {
      final checklist = await _checklistService.getChecklist();
      setState(() {
        _checklistItems = checklist.manualItems;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load checklist: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _checklistLoading = false;
        });
      }
    }
  }

  Future<void> _addChecklistItem() async {
    final text = await _showChecklistInputDialog(title: 'Add Important Item');
    if (text == null) return;
    try {
      final updated = await _checklistService.addItem(text);
      setState(() {
        _checklistItems = updated.manualItems;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add item: $e')));
      }
    }
  }

  Future<void> _editChecklistItem(ProactiveChecklistItem item) async {
    final text = await _showChecklistInputDialog(
      title: 'Edit Important Item',
      initialValue: item.text,
    );
    if (text == null) return;
    try {
      final updated = await _checklistService.updateItem(item.itemId, text);
      setState(() {
        _checklistItems = updated.manualItems;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update item: $e')));
      }
    }
  }

  Future<void> _deleteChecklistItem(ProactiveChecklistItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Remove "${item.text}" from important checklist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updated = await _checklistService.deleteItem(item.itemId);
      setState(() {
        _checklistItems = updated.manualItems;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete item: $e')));
      }
    }
  }

  Future<String?> _showChecklistInputDialog({
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(
            hintText: 'e.g. Morning medicine before school',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final cleaned = (result ?? '').trim();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  Future<void> _toggleCapability(AdvisorCapability cap) async {
    final newEnabled = !cap.isEnabled;
    try {
      await _capService.toggleCapability(cap.capabilityId, newEnabled);
      await _loadCapabilities();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Advisor Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: $_error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadCapabilities,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadCapabilities,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Capabilities', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Control what your Advisor can access and do.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._capabilities.map(
                    (cap) => _CapabilityTile(
                      capability: cap,
                      onToggle: () => _toggleCapability(cap),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Important Checklist',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: _checklistLoading ? null : _reloadChecklist,
                        icon: _checklistLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh checklist',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These items are user-defined priorities used by proactive mode.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._checklistItems.map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(item.text),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit',
                              onPressed: () => _editChecklistItem(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _deleteChecklistItem(item),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_checklistItems.isEmpty)
                    Card(
                      child: ListTile(
                        title: Text(
                          'No important items yet',
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: const Text(
                          'Add what matters most so proactive check-ins stay focused.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _addChecklistItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Important Item'),
                  ),
                  const SizedBox(height: 32),
                  Text('Skills', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'View and configure the skills your Advisor can use.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdvisorSkillListScreen(),
                        ),
                      );
                    },
                    child: const Text('View Skills'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  final AdvisorCapability capability;
  final VoidCallback onToggle;

  const _CapabilityTile({required this.capability, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData statusIcon;
    Color statusColor;
    String statusText;

    switch (capability.status) {
      case 'ready':
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        statusText = 'Ready';
        break;
      case 'enabled_not_ready':
        statusIcon = Icons.warning_amber;
        statusColor = Colors.orange;
        statusText = 'Setup needed';
        break;
      default:
        statusIcon = Icons.circle_outlined;
        statusColor = theme.colorScheme.onSurface.withOpacity(0.4);
        statusText = 'Disabled';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(capability.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(capability.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        value: capability.isEnabled,
        onChanged: (_) => onToggle(),
      ),
    );
  }
}

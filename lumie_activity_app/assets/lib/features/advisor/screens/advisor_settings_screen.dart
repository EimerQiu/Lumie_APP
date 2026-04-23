import 'package:flutter/material.dart';
import '../../../core/services/advisor_capability_service.dart';
import '../../../core/services/advisor_skill_service.dart';
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
  List<AdvisorCapability> _capabilities = [];
  bool _loading = true;
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
      setState(() {
        _capabilities = caps;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

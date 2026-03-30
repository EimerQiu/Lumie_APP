import 'package:flutter/material.dart';
import '../../../core/services/advisor_skill_service.dart';

/// Screen for viewing and editing credentials for a specific skill.
class AdvisorCredentialScreen extends StatefulWidget {
  final String skillId;
  final String skillTitle;
  final bool isLumieInternal;

  const AdvisorCredentialScreen({
    super.key,
    required this.skillId,
    required this.skillTitle,
    this.isLumieInternal = false,
  });

  @override
  State<AdvisorCredentialScreen> createState() =>
      _AdvisorCredentialScreenState();
}

class _AdvisorCredentialScreenState extends State<AdvisorCredentialScreen> {
  final _skillService = AdvisorSkillService();

  SkillCredential? _credential;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  final _baseUrlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCredential();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCredential() async {
    setState(() => _loading = true);
    try {
      final cred = await _skillService.getCredential(widget.skillId);
      setState(() {
        _credential = cred;
        _baseUrlCtrl.text = cred.baseUrl ?? '';
        _usernameCtrl.text = cred.username ?? '';
        _notesCtrl.text = cred.notes ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveCredential() async {
    setState(() => _saving = true);
    try {
      await _skillService.saveCredential(
        widget.skillId,
        baseUrl: _baseUrlCtrl.text.isNotEmpty ? _baseUrlCtrl.text : null,
        username: _usernameCtrl.text.isNotEmpty ? _usernameCtrl.text : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
      );
      await _loadCredential();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credentials saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _testCredential() async {
    setState(() => _testing = true);
    try {
      final result = await _skillService.testCredential(widget.skillId);
      await _loadCredential();
      if (mounted) {
        final success = result['success'] as bool? ?? false;
        final msg = result['message'] as String? ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Test passed: $msg' : 'Test failed: $msg'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.skillTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status card
                  _StatusCard(credential: _credential),
                  const SizedBox(height: 24),

                  if (widget.isLumieInternal) ...[
                    // Lumie internal skills auto-manage credentials
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lock, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Lumie Internal Access',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This skill uses Lumie\'s internal data. '
                              'Access credentials are managed automatically.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _testing ? null : _testCredential,
                              child: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Test Connection'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // External skill credential form
                    Text('Credentials', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),

                    // Only show base URL for non-Gmail skills
                    if (widget.skillId != 'gmail_inbox_check') ...[
                      TextField(
                        controller: _baseUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: 'https://portal.example.edu',
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else
                      // For Gmail, show hint that base URL is automatic
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: theme.colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Gmail URL auto-configured',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: _credential?.hasPassword == true
                            ? '(saved)'
                            : 'Enter password',
                        prefixIcon: const Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Navigation hints, e.g., "After login, click Academics > Homework"',
                        prefixIcon: Icon(Icons.note),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _saveCredential,
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _testing ? null : _testCredential,
                            child: _testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Test'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final SkillCredential? credential;

  const _StatusCard({this.credential});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = credential?.status ?? 'missing';

    IconData icon;
    Color color;
    String label;

    switch (status) {
      case 'valid':
        icon = Icons.check_circle;
        color = Colors.green;
        label = 'Credentials valid';
        break;
      case 'saved_not_tested':
        icon = Icons.warning_amber;
        color = Colors.orange;
        label = 'Saved but not tested';
        break;
      case 'invalid':
        icon = Icons.error;
        color = Colors.red;
        label = 'Credentials invalid';
        break;
      default:
        icon = Icons.circle_outlined;
        color = theme.colorScheme.onSurface.withOpacity(0.4);
        label = 'No credentials configured';
    }

    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (credential?.lastTestResult != null)
                    Text(
                      'Last test: ${credential!.lastTestResult}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

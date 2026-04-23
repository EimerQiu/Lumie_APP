// Create Team Screen - Form to create a new team

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';
import '../widgets/upgrade_prompt_sheet.dart';
import '../../../shared/models/subscription_error.dart';

class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateTeam() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final teamsProvider = context.read<TeamsProvider>();

    try {
      await teamsProvider.createTeam(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (mounted) {
        // Success - go back to teams list
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Team created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on SubscriptionLimitException catch (e) {
      // User hit subscription limit
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        UpgradePromptBottomSheet.show(
          context: context,
          error: e.errorResponse,
          onUpgrade: () {
            Navigator.pop(context); // Close create screen
            Navigator.pushNamed(context, '/subscription/upgrade');
          },
        );
      }
    } catch (e) {
      // Other error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create team: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Team'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header illustration
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.groups,
                      size: 56,
                      color: Colors.blue[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create a New Team',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share health data and coordinate routines\nwith family or friends',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Team name field
            Text(
              'Team Name',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'e.g., Smith Family, Running Club',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: const Icon(Icons.label_outline),
              ),
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a team name';
                }
                if (value.trim().length < 2) {
                  return 'Team name must be at least 2 characters';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Description field (optional)
            Text(
              'Description (Optional)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: 'What is this team about?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: const Icon(Icons.description_outlined),
              ),
              maxLength: 500,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 8),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue[700],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy & Sharing',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You\'ll be the admin of this team. Members you invite won\'t see your data unless you enable sharing in settings.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[800],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Create button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleCreateTeam,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Create Team',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

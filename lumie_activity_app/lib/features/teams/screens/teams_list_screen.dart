// Teams List Screen - Main screen showing active teams and pending invitations

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';
import '../widgets/team_card.dart';
import '../widgets/invitation_card.dart';
import '../widgets/upgrade_prompt_sheet.dart';
import '../../../shared/models/subscription_error.dart';

class TeamsListScreen extends StatefulWidget {
  const TeamsListScreen({super.key});

  @override
  State<TeamsListScreen> createState() => _TeamsListScreenState();
}

class _TeamsListScreenState extends State<TeamsListScreen> {
  @override
  void initState() {
    super.initState();
    // Load teams when screen is first opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamsProvider>().loadTeams();
    });
  }

  void _handleCreateTeamTap() {
    final teamsProvider = context.read<TeamsProvider>();

    if (teamsProvider.hasReachedTeamLimit) {
      // Show upgrade prompt
      UpgradePromptBottomSheet.showCustom(
        context: context,
        title: 'Team Limit Reached',
        message: 'You\'ve reached your team limit (${teamsProvider.teamLimitText}).',
        detail: 'Free users can create 1 team. Upgrade to Pro for up to 100 teams.',
        onUpgrade: () {
          Navigator.pushNamed(context, '/subscription/upgrade');
        },
      );
    } else {
      // Navigate to create team screen
      Navigator.pushNamed(context, '/teams/create');
    }
  }

  Future<void> _handleAcceptInvitation(String teamId) async {
    final teamsProvider = context.read<TeamsProvider>();

    try {
      await teamsProvider.acceptInvitation(teamId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined team!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on SubscriptionLimitException catch (e) {
      if (mounted) {
        UpgradePromptBottomSheet.show(
          context: context,
          error: e.errorResponse,
          onUpgrade: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/subscription/upgrade');
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept invitation: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleIgnoreInvitation(String teamId) async {
    final teamsProvider = context.read<TeamsProvider>();
    await teamsProvider.declineInvitation(teamId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation ignored')),
      );
    }
  }

  Future<void> _handleRefresh() async {
    await context.read<TeamsProvider>().loadTeams();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          // Team limit indicator
          Consumer<TeamsProvider>(
            builder: (context, teamsProvider, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    teamsProvider.teamLimitText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: teamsProvider.hasReachedTeamLimit
                          ? Colors.orange[700]
                          : Colors.grey[600],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<TeamsProvider>(
        builder: (context, teamsProvider, child) {
          if (teamsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (teamsProvider.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load teams',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    teamsProvider.errorMessage ?? 'Unknown error',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _handleRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final hasTeams = teamsProvider.teams.isNotEmpty;
          final hasInvitations = teamsProvider.pendingInvitations.isNotEmpty;

          if (!hasTeams && !hasInvitations) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 88),
              children: [
                // Subscription banner (if applicable)
                if (teamsProvider.subscriptionBannerMessage != null)
                  _buildSubscriptionBanner(
                    context,
                    teamsProvider.subscriptionBannerMessage!,
                    teamsProvider.hasReachedTeamLimit,
                  ),

                // Pending invitations section
                if (hasInvitations) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Pending Invitations',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                  ),
                  ...teamsProvider.pendingInvitations.map(
                    (invitation) => InvitationCard(
                      invitation: invitation,
                      onAccept: () => _handleAcceptInvitation(invitation.teamId),
                      onIgnore: () => _handleIgnoreInvitation(invitation.teamId),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Active teams section
                if (hasTeams) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'My Teams',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                  ),
                  ...teamsProvider.teams.map(
                    (team) => TeamCard(
                      team: team,
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/teams/detail',
                          arguments: team.teamId,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleCreateTeamTap,
        icon: const Icon(Icons.add),
        label: const Text('Create Team'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 96,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            Text(
              'No Teams Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create a team to share health data\nand coordinate routines with family or friends.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _handleCreateTeamTap,
              icon: const Icon(Icons.add),
              label: const Text('Create Your First Team'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionBanner(
    BuildContext context,
    String message,
    bool isLimitReached,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLimitReached ? Colors.orange[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLimitReached ? Colors.orange[200]! : Colors.blue[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLimitReached ? Icons.warning_amber : Icons.info_outline,
            color: isLimitReached ? Colors.orange[700] : Colors.blue[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: isLimitReached ? Colors.orange[900] : Colors.blue[900],
              ),
            ),
          ),
          if (isLimitReached) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/subscription/upgrade');
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange[700],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

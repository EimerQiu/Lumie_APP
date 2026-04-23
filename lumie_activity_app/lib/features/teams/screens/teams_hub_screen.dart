// Teams Hub Screen - Main teams entry point with team switching tabs
// Shows tabs for each team and allows switching between them without navigating back

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';
import '../../../shared/models/team_models.dart';
import '../../../shared/models/subscription_error.dart';
import '../widgets/upgrade_prompt_sheet.dart';
import '../widgets/invitation_card.dart';
import 'team_detail_screen.dart';
import 'teams_list_screen.dart';

class TeamsHubScreen extends StatefulWidget {
  const TeamsHubScreen({super.key});

  @override
  State<TeamsHubScreen> createState() => _TeamsHubScreenState();
}

class _TeamsHubScreenState extends State<TeamsHubScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _lastTeamCount = 0;

  @override
  void initState() {
    super.initState();
    // Load teams when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamsProvider>().loadTeams();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// Sync TabController with teams list length
  void _syncTabController(List<Team> teams) {
    if (teams.length == _lastTeamCount) return;

    final prevIndex = _tabController?.index ?? 0;
    _tabController?.dispose();
    _lastTeamCount = teams.length;

    if (teams.isEmpty) {
      _tabController = null;
      return;
    }

    // Preserve current index if possible
    final newIndex = prevIndex.clamp(0, teams.length - 1);
    _tabController = TabController(
      length: teams.length,
      initialIndex: newIndex,
      vsync: this,
    );
  }

  void _handleCreateTeamTap() {
    final teamsProvider = context.read<TeamsProvider>();

    if (teamsProvider.hasReachedTeamLimit) {
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
      Navigator.pushNamed(context, '/teams/create');
    }
  }

  Future<void> _handleLeaveTeam(String teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Team'),
        content: Text(
          'Are you sure you want to leave "$teamName"?\n\nYou will no longer have access to shared data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<TeamsProvider>().leaveTeam(teamId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully left team'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave team: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteTeam(String teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Team'),
        content: Text(
          'Are you sure you want to delete "$teamName"?\n\nThis action cannot be undone. All members will lose access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<TeamsProvider>().deleteTeam(teamId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Team deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete team: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    await context.read<TeamsProvider>().declineInvitation(teamId);
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
    return Consumer<TeamsProvider>(
      builder: (context, teamsProvider, _) {
        // Sync tab controller with current teams
        _syncTabController(teamsProvider.teams);

        // Loading state
        if (teamsProvider.isLoading) {
          return Scaffold(
            appBar: AppBar(title: const Text('Teams')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Error state
        if (teamsProvider.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Teams')),
            body: Center(
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
            ),
          );
        }

        final hasTeams = teamsProvider.teams.isNotEmpty;
        final hasInvitations = teamsProvider.pendingInvitations.isNotEmpty;

        // Empty state
        if (!hasTeams && !hasInvitations) {
          return Scaffold(
            appBar: AppBar(title: const Text('Teams')),
            body: _buildEmptyState(context),
            floatingActionButton: _buildCreateTeamButton(),
          );
        }

        // Has teams - show hub with tabs
        if (hasTeams && _tabController != null) {
          final currentTeam = teamsProvider.teams[_tabController!.index];
          final isAdmin = currentTeam.role == TeamRole.admin;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Teams'),
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: teamsProvider.teams
                    .map((team) => Tab(text: team.name))
                    .toList(),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'invite':
                        Navigator.pushNamed(
                          context,
                          '/teams/invite',
                          arguments: currentTeam.teamId,
                        );
                        break;
                      case 'create':
                        _handleCreateTeamTap();
                        break;
                      case 'leave':
                        _handleLeaveTeam(currentTeam.teamId, currentTeam.name);
                        break;
                      case 'delete':
                        _handleDeleteTeam(currentTeam.teamId, currentTeam.name);
                        break;
                      case 'all-teams':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TeamsListScreen(),
                          ),
                        );
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'invite',
                        child: Row(
                          children: [
                            Icon(Icons.person_add_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('Invite Member'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'create',
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 20),
                          SizedBox(width: 12),
                          Text('Create Team'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app, size: 20),
                          SizedBox(width: 12),
                          Text('Leave Team'),
                        ],
                      ),
                    ),
                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete Team', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'all-teams',
                      child: Row(
                        children: [
                          Icon(
                            Icons.list,
                            size: 20,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: 12),
                          Text('All Teams', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: TabBarView(
              controller: _tabController,
              children: teamsProvider.teams
                  .map((team) => TeamDetailBody(teamId: team.teamId))
                  .toList(),
            ),
          );
        }

        // Has only invitations, no teams
        return Scaffold(
          appBar: AppBar(title: const Text('Teams')),
          body: RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 88),
              children: [
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
              ],
            ),
          ),
          floatingActionButton: _buildCreateTeamButton(),
        );
      },
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

  Widget _buildCreateTeamButton() {
    return GestureDetector(
      onTap: _handleCreateTeamTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.blue[600],
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }
}

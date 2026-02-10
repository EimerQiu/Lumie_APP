// Team Detail Screen - Shows team information with members and shared data tabs

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';
import '../../../shared/models/team_models.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;

  const TeamDetailScreen({
    super.key,
    required this.teamId,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Team? _team;
  TeamMembersResponse? _membersData;
  bool _isLoadingMembers = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamsProvider = context.read<TeamsProvider>();
    _team = teamsProvider.findTeamById(widget.teamId);

    if (_team != null) {
      setState(() {
        _isLoadingMembers = true;
      });

      try {
        final membersData = await teamsProvider.getTeamMembers(widget.teamId);
        if (mounted) {
          setState(() {
            _membersData = membersData;
            _isLoadingMembers = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingMembers = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load members: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleLeaveTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Team'),
        content: Text(
          'Are you sure you want to leave "${_team?.name}"?\n\nYou will no longer have access to shared data.',
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
      await context.read<TeamsProvider>().leaveTeam(widget.teamId);

      if (mounted) {
        Navigator.pop(context);
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

  Future<void> _handleDeleteTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Team'),
        content: Text(
          'Are you sure you want to delete "${_team?.name}"?\n\nThis action cannot be undone. All members will lose access.',
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
      await context.read<TeamsProvider>().deleteTeam(widget.teamId);

      if (mounted) {
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    if (_team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Details')),
        body: const Center(child: Text('Team not found')),
      );
    }

    final isAdmin = _team!.role == TeamRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: Text(_team!.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'invite':
                  Navigator.pushNamed(
                    context,
                    '/teams/invite',
                    arguments: widget.teamId,
                  );
                  break;
                case 'leave':
                  _handleLeaveTeam();
                  break;
                case 'delete':
                  _handleDeleteTeam();
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
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members', icon: Icon(Icons.people_outline)),
            Tab(text: 'Shared Data', icon: Icon(Icons.bar_chart)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMembersTab(),
          _buildSharedDataTab(),
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    if (_isLoadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_membersData == null || _membersData!.members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No members yet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _membersData!.members.length,
      itemBuilder: (context, index) {
        final member = _membersData!.members[index];
        return _buildMemberCard(member);
      },
    );
  }

  Widget _buildMemberCard(TeamMember member) {
    final isAdmin = member.role == TeamRole.admin;
    final isPending = member.status == MemberStatus.pending;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isAdmin ? Colors.amber[100] : Colors.blue[100],
          child: Icon(
            isAdmin ? Icons.star : Icons.person,
            color: isAdmin ? Colors.amber[700] : Colors.blue[700],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isAdmin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Text(
                  'Admin',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.amber[900],
                  ),
                ),
              ),
            if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              member.email,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (!isPending && member.dataSharing.hasSharedData) ...[
              const SizedBox(height: 6),
              Text(
                '${member.dataSharing.sharedCount} data ${member.dataSharing.sharedCount == 1 ? 'category' : 'categories'} shared',
                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
              ),
            ],
          ],
        ),
        trailing: !isPending && member.dataSharing.hasSharedData
            ? IconButton(
                icon: const Icon(Icons.visibility_outlined),
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/teams/member-data',
                    arguments: {
                      'teamId': widget.teamId,
                      'userId': member.userId,
                      'userName': member.name,
                    },
                  );
                },
                tooltip: 'View shared data',
              )
            : null,
      ),
    );
  }

  Widget _buildSharedDataTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Shared Data View',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'This feature will display aggregated health data from all team members who have enabled sharing.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

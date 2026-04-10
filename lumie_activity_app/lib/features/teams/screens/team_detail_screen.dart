// Team Detail Screen - Shows team information with members and shared data tabs
// This file contains both TeamDetailScreen (for standalone navigation) and TeamDetailBody (for use in TeamsHubScreen)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';
import '../../../shared/models/team_models.dart';
import 'team_dayprint_screen.dart';

// Main screen for standalone navigation
class TeamDetailScreen extends StatelessWidget {
  final String teamId;

  const TeamDetailScreen({
    super.key,
    required this.teamId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Details'),
      ),
      body: TeamDetailBody(teamId: teamId),
    );
  }
}

// Reusable body widget for use in TeamsHubScreen
class TeamDetailBody extends StatefulWidget {
  final String teamId;

  const TeamDetailBody({
    super.key,
    required this.teamId,
  });

  @override
  State<TeamDetailBody> createState() => _TeamDetailBodyState();
}

class _TeamDetailBodyState extends State<TeamDetailBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Team? _team;
  TeamMembersResponse? _membersData;
  bool _isLoadingMembers = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, initialIndex: 1, vsync: this);
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


  @override
  Widget build(BuildContext context) {
    if (_team == null) {
      return const Center(child: Text('Team not found'));
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members', icon: Icon(Icons.people_outline)),
            Tab(text: 'Dayprint', icon: Icon(Icons.photo_library_outlined)),
            Tab(text: 'Shared Data', icon: Icon(Icons.bar_chart)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMembersTab(),
              TeamDayprintScreen(teamId: widget.teamId),
              _buildSharedDataTab(),
            ],
          ),
        ),
      ],
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

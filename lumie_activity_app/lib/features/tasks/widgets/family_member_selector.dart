/// FamilyMemberSelector - Reusable widget for assigning tasks
/// to personal or team member targets.
///
/// Used in both single-task creation and batch task generation flows.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/team_models.dart';
import '../../teams/providers/teams_provider.dart';

/// Result of the family member selection
class FamilyMemberSelection {
  final String? familyId; // null = personal
  final String? memberId; // null = self
  final String? memberName;
  final String? teamName;

  const FamilyMemberSelection({
    this.familyId,
    this.memberId,
    this.memberName,
    this.teamName,
  });

  bool get isPersonal => familyId == null;
}

class FamilyMemberSelector extends StatefulWidget {
  final FamilyMemberSelection? initialSelection;
  final ValueChanged<FamilyMemberSelection> onChanged;

  const FamilyMemberSelector({
    super.key,
    this.initialSelection,
    required this.onChanged,
  });

  @override
  State<FamilyMemberSelector> createState() => _FamilyMemberSelectorState();
}

class _FamilyMemberSelectorState extends State<FamilyMemberSelector> {
  List<Team> _adminTeams = [];
  List<TeamMember> _teamMembers = [];
  String? _selectedTeamId;
  String? _selectedMemberId;
  bool _isLoadingMembers = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelection != null) {
      _selectedTeamId = widget.initialSelection!.familyId;
      _selectedMemberId = widget.initialSelection!.memberId;
    }
    _loadAdminTeams();
  }

  Future<void> _loadAdminTeams() async {
    try {
      final teamsProvider = context.read<TeamsProvider>();
      await teamsProvider.loadTeams();
      if (mounted) {
        setState(() {
          _adminTeams = teamsProvider.teams
              .where((t) => t.role == TeamRole.admin && t.status == MemberStatus.member)
              .toList();
        });
        // If a team was pre-selected, load its members
        if (_selectedTeamId != null) {
          _loadTeamMembers(_selectedTeamId!);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadTeamMembers(String teamId) async {
    setState(() => _isLoadingMembers = true);
    try {
      final teamsProvider = context.read<TeamsProvider>();
      final response = await teamsProvider.getTeamMembers(teamId);
      if (mounted) {
        setState(() {
          _teamMembers = response.members
              .where((m) => m.status == MemberStatus.member)
              .toList();
          _isLoadingMembers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  void _selectPersonal() {
    setState(() {
      _selectedTeamId = null;
      _selectedMemberId = null;
      _teamMembers = [];
    });
    widget.onChanged(const FamilyMemberSelection());
  }

  void _selectTeam(Team team) {
    setState(() {
      _selectedTeamId = team.teamId;
      _selectedMemberId = null;
    });
    _loadTeamMembers(team.teamId);
    // Don't fire onChanged yet - need member selection
  }

  void _selectMember(TeamMember member) {
    final team = _adminTeams.where((t) => t.teamId == _selectedTeamId).firstOrNull;
    setState(() => _selectedMemberId = member.userId);
    widget.onChanged(FamilyMemberSelection(
      familyId: _selectedTeamId,
      memberId: member.userId,
      memberName: member.name,
      teamName: team?.name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_adminTeams.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assign To',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),

        // Team/Personal selection row
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _FamilyCard(
                label: 'Personal Tasks',
                isSelected: _selectedTeamId == null,
                onTap: _selectPersonal,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
                ),
              ),
              ..._adminTeams.map((team) => _FamilyCard(
                    label: team.name,
                    subtitle: '${team.memberCount} members',
                    isSelected: _selectedTeamId == team.teamId,
                    onTap: () => _selectTeam(team),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                    ),
                  )),
            ],
          ),
        ),

        // Member selection (only when a team is selected)
        if (_selectedTeamId != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Select Member',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingMembers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _teamMembers.map((member) {
                  final isSelected = _selectedMemberId == member.userId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(member.name),
                      selected: isSelected,
                      onSelected: (_) => _selectMember(member),
                      selectedColor: AppColors.primaryLemon,
                      backgroundColor: AppColors.backgroundLight,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.textOnYellow : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}

class _FamilyCard extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Gradient gradient;

  const _FamilyCard({
    required this.label,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 130,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: isSelected ? gradient : null,
            color: isSelected ? null : AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryLemonDark : AppColors.surfaceLight,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.textOnYellow : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? AppColors.textOnYellow.withValues(alpha: 0.7) : AppColors.textLight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

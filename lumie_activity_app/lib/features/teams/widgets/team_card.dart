// Team Card - Display team in list view

import 'package:flutter/material.dart';
import '../../../shared/models/team_models.dart';

class TeamCard extends StatelessWidget {
  final Team team;
  final VoidCallback onTap;

  const TeamCard({
    super.key,
    required this.team,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Team icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.groups,
                  size: 32,
                  color: Colors.blue[700],
                ),
              ),

              const SizedBox(width: 16),

              // Team info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Team name
                    Text(
                      team.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Member count and role
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${team.memberCount} ${team.memberCount == 1 ? 'member' : 'members'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildRoleBadge(context),
                      ],
                    ),

                    // Description (if available)
                    if (team.description != null &&
                        team.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        team.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context) {
    final bool isAdmin = team.role == TeamRole.admin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? Colors.amber[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isAdmin ? Colors.amber[200]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Text(
        team.role.displayName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isAdmin ? Colors.amber[900] : Colors.grey[700],
        ),
      ),
    );
  }
}

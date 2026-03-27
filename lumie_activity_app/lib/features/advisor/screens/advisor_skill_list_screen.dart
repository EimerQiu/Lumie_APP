import 'package:flutter/material.dart';
import '../../../core/services/advisor_skill_service.dart';
import 'advisor_credential_screen.dart';

/// Screen showing all indexed system skills.
class AdvisorSkillListScreen extends StatefulWidget {
  const AdvisorSkillListScreen({super.key});

  @override
  State<AdvisorSkillListScreen> createState() => _AdvisorSkillListScreenState();
}

class _AdvisorSkillListScreenState extends State<AdvisorSkillListScreen> {
  final _skillService = AdvisorSkillService();
  List<AdvisorSkill> _skills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    setState(() => _loading = true);
    try {
      final skills = await _skillService.getSkills();
      setState(() {
        _skills = skills;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load skills: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advisor Skills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reindex skills',
            onPressed: () async {
              try {
                await _skillService.reindexSkills();
                await _loadSkills();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Skills reindexed')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reindex failed: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skills.isEmpty
              ? const Center(child: Text('No skills available'))
              : RefreshIndicator(
                  onRefresh: _loadSkills,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _skills.length,
                    itemBuilder: (context, index) {
                      final skill = _skills[index];
                      return _SkillCard(
                        skill: skill,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdvisorCredentialScreen(
                                skillId: skill.skillId,
                                skillTitle: skill.title,
                                isLumieInternal: skill.isLumieInternal,
                              ),
                            ),
                          );
                          _loadSkills();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final AdvisorSkill skill;
  final VoidCallback onTap;

  const _SkillCard({required this.skill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData runtimeIcon;
    switch (skill.skillRuntimeType) {
      case 'lumie_db':
        runtimeIcon = Icons.storage;
        break;
      case 'browser':
        runtimeIcon = Icons.language;
        break;
      case 'external_api':
        runtimeIcon = Icons.cloud;
        break;
      default:
        runtimeIcon = Icons.extension;
    }

    final statusColor = skill.isIndexed ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(runtimeIcon, color: theme.colorScheme.primary),
        title: Text(skill.title),
        subtitle: Text(
          skill.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (skill.requiresCredentials && !skill.isLumieInternal)
              const Icon(Icons.key, size: 16, color: Colors.amber),
            const SizedBox(width: 4),
            Icon(Icons.circle, size: 8, color: statusColor),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

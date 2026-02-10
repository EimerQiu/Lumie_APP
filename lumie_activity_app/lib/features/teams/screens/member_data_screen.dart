// Member Data Screen - View specific member's shared health data

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teams_provider.dart';

class MemberDataScreen extends StatefulWidget {
  final String teamId;
  final String userId;
  final String userName;

  const MemberDataScreen({
    super.key,
    required this.teamId,
    required this.userId,
    required this.userName,
  });

  @override
  State<MemberDataScreen> createState() => _MemberDataScreenState();
}

class _MemberDataScreenState extends State<MemberDataScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _memberData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMemberData();
  }

  Future<void> _loadMemberData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await context.read<TeamsProvider>().getMemberData(
            teamId: widget.teamId,
            userId: widget.userId,
          );

      if (mounted) {
        setState(() {
          _memberData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userName}\'s Data'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Failed to Load Data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadMemberData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_memberData == null || _memberData!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No Shared Data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.userName} has not shared any data yet',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMemberData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card with member info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.blue[100],
                    child: Icon(
                      Icons.person,
                      size: 36,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Team Member',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Data sections
          if (_memberData!.containsKey('profile') &&
              _memberData!['profile'] != null)
            _buildDataSection(
              'Profile Information',
              Icons.person_outline,
              Colors.blue,
              _memberData!['profile'],
            ),

          if (_memberData!.containsKey('activity') &&
              _memberData!['activity'] != null)
            _buildDataSection(
              'Activity Data',
              Icons.directions_run,
              Colors.green,
              _memberData!['activity'],
            ),

          if (_memberData!.containsKey('sleep') &&
              _memberData!['sleep'] != null)
            _buildDataSection(
              'Sleep Data',
              Icons.nightlight_outlined,
              Colors.purple,
              _memberData!['sleep'],
            ),

          if (_memberData!.containsKey('test_results') &&
              _memberData!['test_results'] != null)
            _buildDataSection(
              'Test Results',
              Icons.assessment_outlined,
              Colors.orange,
              _memberData!['test_results'],
            ),

          const SizedBox(height: 16),

          // Privacy notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  color: Colors.grey[700],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This data is shared by ${widget.userName} and can be revoked at any time.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(
    String title,
    IconData icon,
    Color color,
    dynamic data,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildDataContent(data),
          ),
        ],
      ),
    );
  }

  Widget _buildDataContent(dynamic data) {
    if (data is Map<String, dynamic>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatKey(entry.key),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.value?.toString() ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else if (data is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key + 1}. ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value?.toString() ?? 'N/A',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      return Text(
        data?.toString() ?? 'No data available',
        style: const TextStyle(fontSize: 14),
      );
    }
  }

  String _formatKey(String key) {
    // Convert snake_case to Title Case
    return key
        .split('_')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ');
  }
}

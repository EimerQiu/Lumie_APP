import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teams_provider.dart';

class AcceptInvitationScreen extends StatefulWidget {
  final String token;

  const AcceptInvitationScreen({super.key, required this.token});

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  bool _isLoading = true;
  bool _isAccepting = false;
  Map<String, dynamic>? _invitationDetails;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  Future<void> _loadInvitation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final teamsProvider = context.read<TeamsProvider>();
      final details = await teamsProvider.getInvitationFromToken(widget.token);

      setState(() {
        _invitationDetails = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation() async {
    setState(() {
      _isAccepting = true;
    });

    try {
      final teamsProvider = context.read<TeamsProvider>();
      await teamsProvider.acceptInvitationByToken(widget.token);

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully joined the team!'),
          backgroundColor: AppColors.success,
        ),
      );

      // Navigate to teams list
      Navigator.of(context).pushReplacementNamed('/teams');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAccepting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoggedIn = auth.isAuthenticated;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildError()
                  : _buildInvitation(isLoggedIn),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 24),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                text: 'Go to Home',
                onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitation(bool isLoggedIn) {
    final status = _invitationDetails!['status'] as String;
    final teamName = _invitationDetails!['team_name'] as String;
    final invitedBy = _invitationDetails!['invited_by'] as String?;
    final message = _invitationDetails!['message'] as String;
    final description = _invitationDetails!['team_description'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _buildHeader(),
          const SizedBox(height: 48),
          _buildTeamCard(teamName, description, invitedBy),
          const SizedBox(height: 24),
          _buildMessage(message, status),
          const SizedBox(height: 48),
          _buildActionButtons(status, isLoggedIn),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.mintGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.mail_outline,
            size: 32,
            color: AppColors.textOnYellow,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Team Invitation',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTeamCard(String teamName, String? description, String? invitedBy) {
    return GradientCard(
      gradient: AppColors.mintGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            teamName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnYellow,
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textOnYellow.withValues(alpha: 0.9),
              ),
            ),
          ],
          if (invitedBy != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: AppColors.textOnYellow,
                ),
                const SizedBox(width: 8),
                Text(
                  'Invited by $invitedBy',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textOnYellow.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage(String message, String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'already_member':
        icon = Icons.check_circle_outline;
        color = AppColors.success;
        break;
      case 'needs_signup':
        icon = Icons.person_add_outlined;
        color = AppColors.primaryLemon;
        break;
      case 'pending':
      default:
        icon = Icons.mail_outline;
        color = AppColors.primaryLemon;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(String status, bool isLoggedIn) {
    if (status == 'already_member') {
      return SizedBox(
        width: double.infinity,
        child: GradientButton(
          text: 'Go to Teams',
          onPressed: () => Navigator.of(context).pushReplacementNamed('/teams'),
        ),
      );
    }

    if (status == 'needs_signup' || !isLoggedIn) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              text: 'Sign Up',
              onPressed: () {
                // Navigate to signup with invitation token
                Navigator.of(context).pushReplacementNamed(
                  '/welcome',
                  arguments: {'invitation_token': widget.token},
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushReplacementNamed('/login');
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.primaryLemonDark, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Log In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // User is logged in and has pending invitation
    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        text: _isAccepting ? 'Accepting...' : 'Accept Invitation',
        onPressed: _isAccepting ? null : _acceptInvitation,
      ),
    );
  }
}

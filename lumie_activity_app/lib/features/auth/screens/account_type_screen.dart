import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../providers/auth_provider.dart';

class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  AccountRole? _selectedRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                _buildHeader(),
                const SizedBox(height: 48),
                _buildOptions(),
                const Spacer(),
                _buildContinueButton(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
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
            gradient: AppColors.warmGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.person_outline,
            size: 32,
            color: AppColors.textOnYellow,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Who is using Lumie?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This helps us personalize your experience.\nThis choice cannot be changed later.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Column(
      children: AccountRole.values.map((role) {
        final isSelected = _selectedRole == role;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _AccountTypeCard(
            role: role,
            isSelected: isSelected,
            onTap: () {
              setState(() {
                _selectedRole = role;
              });
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContinueButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final isLoading = authProvider.state == AuthState.loading;

        return Column(
          children: [
            if (authProvider.errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  authProvider.errorMessage!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                text: 'Continue',
                isLoading: isLoading,
                onPressed: _selectedRole == null || isLoading
                    ? null
                    : () => _handleContinue(authProvider),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleContinue(AuthProvider authProvider) async {
    if (_selectedRole == null) return;

    await authProvider.selectAccountType(_selectedRole!);
    // Navigation handled by main app
  }
}

class _AccountTypeCard extends StatelessWidget {
  final AccountRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _AccountTypeCard({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _icon {
    switch (role) {
      case AccountRole.teen:
        return Icons.school_outlined;
      case AccountRole.parent:
        return Icons.family_restroom;
    }
  }

  Gradient get _gradient {
    switch (role) {
      case AccountRole.teen:
        return AppColors.warmGradient;
      case AccountRole.parent:
        return AppColors.mintGradient;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isSelected ? _gradient : null,
          color: isSelected ? null : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryLemonDark : AppColors.surfaceLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryLemon.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.backgroundWhite.withValues(alpha: 0.5)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icon,
                size: 28,
                color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.textOnYellow : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected
                          ? AppColors.textOnYellow.withValues(alpha: 0.8)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

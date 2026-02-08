import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';
import 'login_screen.dart';
import 'account_type_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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
              children: [
                const Spacer(flex: 2),
                // Logo and branding
                _buildLogo(),
                const SizedBox(height: 48),
                // Welcome text
                _buildWelcomeText(),
                const Spacer(flex: 3),
                // Action buttons
                _buildActionButtons(context),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: AppColors.sunriseGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryLemonDark.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '☀️',
          style: TextStyle(fontSize: 56),
        ),
      ),
    );
  }

  Widget _buildWelcomeText() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppColors.primaryLemonDark,
              AppColors.accentOrange,
            ],
          ).createShader(bounds),
          child: const Text(
            'Lumie',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your wellness companion',
          style: TextStyle(
            fontSize: 18,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundWhite.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Text(
                'Track your activity, understand your body,',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'and find your balance.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // Sign Up button
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            text: 'Get Started',
            icon: Icons.arrow_forward,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountTypeScreen()),
              );
            },
            gradient: AppColors.activityRingGradient,
          ),
        ),
        const SizedBox(height: 16),
        // Log In button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.primaryLemonDark, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'I already have an account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Privacy note
        const Text(
          'By continuing, you agree to our Terms of Service\nand Privacy Policy',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textLight,
          ),
        ),
      ],
    );
  }
}

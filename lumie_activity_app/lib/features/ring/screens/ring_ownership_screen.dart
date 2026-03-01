// Ring ownership prompt — shown once after initial profile setup.
// Per PRD: "Do you have a Lumie Ring?" with Yes / Skip options.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/ring_provider.dart';
import 'ring_scan_screen.dart';

class RingOwnershipScreen extends StatelessWidget {
  const RingOwnershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Ring illustration
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    gradient: AppColors.coolGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.watch_outlined,
                    size: 90,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              const Text(
                'Do you have a\nLumie Ring?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Connect your ring to unlock activity tracking, sleep monitoring, fatigue insights, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Feature chips
              _FeatureRow(icon: Icons.directions_walk, label: 'Activity Tracking'),
              const SizedBox(height: 10),
              _FeatureRow(icon: Icons.bedtime_outlined, label: 'Sleep Monitoring'),
              const SizedBox(height: 10),
              _FeatureRow(icon: Icons.favorite_border, label: 'Heart Rate & HRV'),
              const SizedBox(height: 10),
              _FeatureRow(icon: Icons.auto_awesome_outlined, label: 'AI Advisor Insights'),

              const Spacer(),

              // CTA buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _onYes(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLemonDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Yes, connect my ring',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => _onSkip(context),
                child: const Text(
                  'Not yet, skip for now',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onYes(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RingScanScreen()),
    );
    // After scan screen exits (paired or skipped), complete setup
    if (context.mounted) {
      _completeSetup(context);
    }
  }

  void _onSkip(BuildContext context) {
    _completeSetup(context);
  }

  void _completeSetup(BuildContext context) {
    context.read<RingProvider>().markRingPromptShown();
    context.read<AuthProvider>().completeRingSetup();
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.coolGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF0369A1)),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          const Icon(Icons.check_circle, color: AppColors.ringConnected, size: 20),
        ],
      ),
    );
  }
}

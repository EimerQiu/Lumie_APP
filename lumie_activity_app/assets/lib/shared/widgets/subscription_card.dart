import 'package:flutter/material.dart';
import '../models/user_models.dart';

class SubscriptionCard extends StatelessWidget {
  final SubscriptionStatus subscription;
  final VoidCallback? onUpgrade;

  const SubscriptionCard({
    super.key,
    required this.subscription,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: _getGradient(),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subscription.tier.displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subscription.tier.priceLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  if (subscription.tier == SubscriptionTier.free && onUpgrade != null)
                    ElevatedButton(
                      onPressed: onUpgrade,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFFFF59D),
                      ),
                      child: const Text('Upgrade'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (subscription.isTrial) _buildTrialBanner(),
              const SizedBox(height: 12),
              _buildFeatureList(),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _getGradient() {
    switch (subscription.tier) {
      case SubscriptionTier.free:
        return const LinearGradient(
          colors: [Color(0xFF757575), Color(0xFF9E9E9E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SubscriptionTier.monthly:
        return const LinearGradient(
          colors: [Color(0xFF5856D6), Color(0xFF007AFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case SubscriptionTier.annual:
        return const LinearGradient(
          colors: [Color(0xFFFF9500), Color(0xFFFFCC00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Widget _buildTrialBanner() {
    if (subscription.trialEndDate == null) return const SizedBox.shrink();

    final daysLeft = subscription.trialEndDate!.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            'Trial ends in $daysLeft days',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = _getFeatures();

    return Column(
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                feature['available'] ? Icons.check_circle : Icons.cancel,
                color: feature['available'] ? Colors.white : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feature['text'],
                  style: TextStyle(
                    color: feature['available'] ? Colors.white : Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _getFeatures() {
    switch (subscription.tier) {
      case SubscriptionTier.free:
        return [
          {'text': 'Med Reminders (2 max)', 'available': true},
          {'text': 'Habit Tracker (3 days)', 'available': true},
          {'text': 'Peer Community (view only)', 'available': true},
          {'text': 'Family Linking', 'available': false},
          {'text': 'Lumie Ring', 'available': false},
          {'text': 'Ring-Based Features', 'available': false},
        ];
      case SubscriptionTier.monthly:
        return [
          {'text': 'Unlimited Med Reminders', 'available': true},
          {'text': 'Unlimited Habit Tracker', 'available': true},
          {'text': 'Full Peer Community Access', 'available': true},
          {'text': 'Family Linking', 'available': true},
          {'text': 'Lumie Ring (purchase required)', 'available': false},
          {'text': 'Ring-Based Features*', 'available': subscription.ringIncluded},
        ];
      case SubscriptionTier.annual:
        return [
          {'text': 'Unlimited Med Reminders', 'available': true},
          {'text': 'Unlimited Habit Tracker', 'available': true},
          {'text': 'Full Peer Community Access', 'available': true},
          {'text': 'Family Linking', 'available': true},
          {'text': 'FREE Lumie Ring', 'available': true},
          {'text': 'All Ring-Based Features', 'available': true},
        ];
    }
  }
}

class SubscriptionBadge extends StatelessWidget {
  final SubscriptionTier tier;

  const SubscriptionBadge({
    super.key,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getColor(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        tier.displayName.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (tier) {
      case SubscriptionTier.free:
        return Colors.grey;
      case SubscriptionTier.monthly:
        return const Color(0xFF5856D6);
      case SubscriptionTier.annual:
        return const Color(0xFFFF9500);
    }
  }
}

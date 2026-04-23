import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';

/// Card for displaying ring-detected activity suggestion
class RingDetectedActivityCard extends StatefulWidget {
  final RingDetectedActivity detectedActivity;
  final ValueChanged<ActivityType> onConfirm;

  const RingDetectedActivityCard({
    super.key,
    required this.detectedActivity,
    required this.onConfirm,
  });

  @override
  State<RingDetectedActivityCard> createState() => _RingDetectedActivityCardState();
}

class _RingDetectedActivityCardState extends State<RingDetectedActivityCard> {
  bool _isExpanded = true;

  String get _confidenceLabel {
    final confidence = widget.detectedActivity.confidence;
    if (confidence >= 0.8) return 'High confidence';
    if (confidence >= 0.5) return 'Medium confidence';
    return 'Low confidence';
  }

  @override
  Widget build(BuildContext context) {
    final suggested = widget.detectedActivity.suggestedActivityType;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F5E9),
            Color(0xFFC8E6C9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.ringConnected.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ringConnected.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.ringConnected.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.watch,
                      color: AppColors.ringConnected,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activity Detected',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your Lumie Ring detected movement',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          if (_isExpanded) ...[
            const Divider(height: 1, color: AppColors.surfaceLight),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Suggested activity
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundWhite.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          suggested.icon,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Suggested: Maybe ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    suggested.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Estimated based on motion patterns • $_confidenceLabel',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.info,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Duration info
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.detectedActivity.durationMinutes} minutes detected',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  const Text(
                    'Please confirm or change the activity type:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Dismiss'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.surfaceLight),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            widget.onConfirm(suggested);
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text('Confirm ${suggested.name}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.ringConnected,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

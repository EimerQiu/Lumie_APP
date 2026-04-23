import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/intensity_badge.dart';
import '../widgets/activity_type_selector.dart';
import '../widgets/time_picker_widget.dart';
import '../widgets/ring_detected_activity_card.dart';

class ManualEntryScreen extends StatefulWidget {
  final RingDetectedActivity? detectedActivity;

  const ManualEntryScreen({
    super.key,
    this.detectedActivity,
  });

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  ActivityType? _selectedActivityType;
  DateTime _startTime = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _endTime = DateTime.now();
  ActivityIntensity? _estimatedIntensity;
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  bool get _hasRingData => widget.detectedActivity != null;

  @override
  void initState() {
    super.initState();
    if (widget.detectedActivity != null) {
      _startTime = widget.detectedActivity!.startTime;
      _endTime = widget.detectedActivity!.endTime;
      _estimatedIntensity = widget.detectedActivity!.measuredIntensity;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  int get _durationMinutes {
    return _endTime.difference(_startTime).inMinutes;
  }

  bool get _canSave {
    return _selectedActivityType != null && _durationMinutes > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasRingData)
                        RingDetectedActivityCard(
                          detectedActivity: widget.detectedActivity!,
                          onConfirm: (activityType) {
                            setState(() {
                              _selectedActivityType = activityType;
                            });
                          },
                        ),
                      const SizedBox(height: 16),
                      _buildActivityTypeSection(),
                      const SizedBox(height: 16),
                      _buildTimeSection(),
                      const SizedBox(height: 16),
                      if (!_hasRingData) _buildIntensitySection(),
                      if (_hasRingData) _buildRingDataSection(),
                      const SizedBox(height: 16),
                      _buildNotesSection(),
                      const SizedBox(height: 16),
                      _buildEstimatedLabel(),
                    ],
                  ),
                ),
              ),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Log Activity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildActivityTypeSection() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Activity Type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ActivityTypeSelector(
            selectedType: _selectedActivityType,
            onTypeSelected: (type) {
              setState(() {
                _selectedActivityType = type;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSection() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Duration',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TimePickerWidget(
            startTime: _startTime,
            endTime: _endTime,
            onStartTimeChanged: (time) {
              setState(() {
                _startTime = time;
                if (_startTime.isAfter(_endTime)) {
                  _endTime = _startTime.add(const Duration(minutes: 15));
                }
              });
            },
            onEndTimeChanged: (time) {
              setState(() {
                _endTime = time;
              });
            },
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: AppColors.warmGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: AppColors.textOnYellow,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Total: $_durationMinutes minutes',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textOnYellow,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntensitySection() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated Intensity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Optional - Based on your perceived effort',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color: AppColors.info,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Estimated',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.info,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IntensityIndicator(
            currentIntensity: _estimatedIntensity,
            isSelectable: true,
            onSelected: (intensity) {
              setState(() {
                _estimatedIntensity = intensity;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRingDataSection() {
    final detected = widget.detectedActivity!;
    return GradientCard(
      gradient: AppColors.mintGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundWhite.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.watch,
                  size: 20,
                  color: AppColors.textOnYellow,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ring-Measured Data',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnYellow,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (detected.heartRateAvg != null)
                Expanded(
                  child: _RingDataItem(
                    icon: Icons.favorite,
                    label: 'Avg HR',
                    value: '${detected.heartRateAvg} bpm',
                  ),
                ),
              if (detected.heartRateMax != null)
                Expanded(
                  child: _RingDataItem(
                    icon: Icons.favorite,
                    label: 'Max HR',
                    value: '${detected.heartRateMax} bpm',
                  ),
                ),
              if (detected.measuredIntensity != null)
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Measured Intensity',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textOnYellow,
                        ),
                      ),
                      const SizedBox(height: 4),
                      IntensityBadge(
                        intensity: detected.measuredIntensity!,
                        isEstimated: false,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notes (Optional)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'How did you feel during this activity?',
              hintStyle: const TextStyle(color: AppColors.textLight),
              filled: true,
              fillColor: AppColors.backgroundWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimatedLabel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.info.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
              color: AppColors.info,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _hasRingData
                    ? 'This activity includes ring-measured data but will be marked as manually confirmed.'
                    : 'This activity will be marked as "Estimated" since it wasn\'t tracked by your Lumie Ring.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.info,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canSave && !_isSaving ? _saveActivity : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primaryLemonDark,
              disabledBackgroundColor: AppColors.surfaceLight,
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveActivity() async {
    if (!_canSave) return;

    setState(() {
      _isSaving = true;
    });

    // Simulate API call
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('${_selectedActivityType!.name} logged successfully'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

class _RingDataItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RingDataItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: AppColors.error.withValues(alpha: 0.8),
          size: 18,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textOnYellow,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textOnYellow,
          ),
        ),
      ],
    );
  }
}

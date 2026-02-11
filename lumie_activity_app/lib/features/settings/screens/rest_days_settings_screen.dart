import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../shared/models/rest_days_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../widgets/weekly_day_picker.dart';
import '../widgets/rest_days_calendar.dart';

/// Screen for managing user rest days configuration.
class RestDaysSettingsScreen extends StatefulWidget {
  const RestDaysSettingsScreen({super.key});

  @override
  State<RestDaysSettingsScreen> createState() => _RestDaysSettingsScreenState();
}

class _RestDaysSettingsScreenState extends State<RestDaysSettingsScreen> {
  final RestDaysService _restDaysService = RestDaysService();

  List<int> _weeklyDays = [];
  List<DateTime> _specificDates = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRestDays();
  }

  Future<void> _loadRestDays() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await _restDaysService.getRestDays();
      setState(() {
        _weeklyDays = settings.weeklyRestDays;
        _specificDates = settings.specificDates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load rest days';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRestDays() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final settings = RestDaySettings(
        weeklyRestDays: _weeklyDays,
        specificDates: _specificDates,
        updatedAt: DateTime.now(),
      );

      await _restDaysService.updateRestDays(settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rest days saved successfully'),
            backgroundColor: AppColors.primaryLemonDark,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save rest days';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rest Days'),
        backgroundColor: AppColors.backgroundLight,
      ),
      backgroundColor: AppColors.backgroundLight,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryLemonDark,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error message
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Weekly rest days section
                  GradientCard(
                    gradient: AppColors.cardGradient,
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Weekly Rest Days',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Select days of the week for regular rest',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        WeeklyDayPicker(
                          selectedDays: _weeklyDays,
                          onChanged: (days) {
                            setState(() => _weeklyDays = days);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Custom rest dates section
                  GradientCard(
                    gradient: AppColors.cardGradient,
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Custom Rest Dates',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Pick specific dates for one-time rest days',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        RestDaysCalendar(
                          selectedDates: _specificDates,
                          onChanged: (dates) {
                            setState(() => _specificDates = dates);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: 'Save Rest Days',
                      onPressed: _isSaving ? null : _saveRestDays,
                      isLoading: _isSaving,
                      icon: Icons.check,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/models/user_models.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/unit_selector.dart';

/// Parent profile setup screen - simpler than teen profile
class ParentProfileSetupScreen extends StatefulWidget {
  const ParentProfileSetupScreen({super.key});

  @override
  State<ParentProfileSetupScreen> createState() => _ParentProfileSetupScreenState();
}

class _ParentProfileSetupScreenState extends State<ParentProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  // Height
  HeightUnit _heightUnit = HeightUnit.cm;
  final _heightCmController = TextEditingController();
  final _heightFtController = TextEditingController();
  final _heightInController = TextEditingController();

  // Weight
  WeightUnit _weightUnit = WeightUnit.kg;
  final _weightController = TextEditingController();

  bool _isLoading = false;
  bool _wantsToPairRing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightCmController.dispose();
    _heightFtController.dispose();
    _heightInController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _createProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Build height data if provided
      HeightData? heightData;
      if (_wantsToPairRing) {
        if (_heightUnit == HeightUnit.cm) {
          final cm = int.tryParse(_heightCmController.text);
          if (cm != null) {
            heightData = HeightData(value: cm.toDouble(), unit: HeightUnit.cm);
          }
        } else {
          final ft = int.tryParse(_heightFtController.text) ?? 0;
          final inches = int.tryParse(_heightInController.text) ?? 0;
          final totalInches = (ft * 12) + inches;
          if (totalInches > 0) {
            heightData = HeightData(value: totalInches.toDouble(), unit: HeightUnit.ftIn);
          }
        }
      }

      // Build weight data if provided
      WeightData? weightData;
      if (_wantsToPairRing) {
        final weight = double.tryParse(_weightController.text);
        if (weight != null) {
          weightData = WeightData(value: weight, unit: _weightUnit);
        }
      }

      await _profileService.createParentProfile(
        name: _nameController.text.trim(),
        age: _wantsToPairRing ? int.tryParse(_ageController.text) : null,
        height: heightData,
        weight: weightData,
      );

      // Update auth state
      await _authService.updateUserState(profileComplete: true);

      if (mounted) {
        // Navigate to home
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundLight, AppColors.backgroundWhite],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryLemon.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.family_restroom,
                        size: 40,
                        color: AppColors.textOnYellow,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Parent Profile',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Set up your account to support your teen',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name field (required)
                        AuthTextField(
                          controller: _nameController,
                          label: 'Your Name',
                          hint: 'Enter your name',
                          prefixIcon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Ring pairing option
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundWhite,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _wantsToPairRing
                                  ? AppColors.primaryLemonDark
                                  : AppColors.surfaceLight,
                              width: _wantsToPairRing ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.mintGradient,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.watch,
                                      color: AppColors.textOnYellow,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pair Your Own Ring?',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Track your own activity alongside your teen',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _wantsToPairRing,
                                    onChanged: (value) {
                                      setState(() => _wantsToPairRing = value);
                                    },
                                    activeTrackColor: AppColors.primaryLemonDark,
                                    activeThumbColor: AppColors.backgroundWhite,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Additional fields if pairing ring
                        if (_wantsToPairRing) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'These details help calibrate your ring',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Age
                          AuthTextField(
                            controller: _ageController,
                            label: 'Age',
                            hint: 'Your age',
                            prefixIcon: Icons.cake_outlined,
                            keyboardType: TextInputType.number,
                            validator: _wantsToPairRing
                                ? (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your age';
                                    }
                                    final age = int.tryParse(value);
                                    if (age == null || age < 18) {
                                      return 'Must be 18 or older';
                                    }
                                    return null;
                                  }
                                : null,
                          ),
                          const SizedBox(height: 16),

                          // Height
                          const Text(
                            'Height',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          UnitSelector<HeightUnit>(
                            value: _heightUnit,
                            options: HeightUnit.values,
                            labelBuilder: (unit) => unit == HeightUnit.cm ? 'cm' : 'ft/in',
                            onChanged: (unit) {
                              setState(() => _heightUnit = unit);
                            },
                          ),
                          const SizedBox(height: 8),
                          if (_heightUnit == HeightUnit.cm)
                            AuthTextField(
                              controller: _heightCmController,
                              label: '',
                              hint: 'Height in cm',
                              keyboardType: TextInputType.number,
                              validator: _wantsToPairRing
                                  ? (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter height';
                                      }
                                      return null;
                                    }
                                  : null,
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: AuthTextField(
                                    controller: _heightFtController,
                                    label: '',
                                    hint: 'Feet',
                                    keyboardType: TextInputType.number,
                                    validator: _wantsToPairRing
                                        ? (value) {
                                            if (value == null || value.isEmpty) {
                                              return 'Feet';
                                            }
                                            return null;
                                          }
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AuthTextField(
                                    controller: _heightInController,
                                    label: '',
                                    hint: 'Inches',
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),

                          // Weight
                          const Text(
                            'Weight',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          UnitSelector<WeightUnit>(
                            value: _weightUnit,
                            options: WeightUnit.values,
                            labelBuilder: (unit) => unit == WeightUnit.kg ? 'kg' : 'lb',
                            onChanged: (unit) {
                              setState(() => _weightUnit = unit);
                            },
                          ),
                          const SizedBox(height: 8),
                          AuthTextField(
                            controller: _weightController,
                            label: '',
                            hint: _weightUnit == WeightUnit.kg ? 'Weight in kg' : 'Weight in lb',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _wantsToPairRing
                                ? (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter weight';
                                    }
                                    return null;
                                  }
                                : null,
                          ),
                        ],

                        const SizedBox(height: 32),

                        // Info box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLemon.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You can link with your teen\'s account after setup to view their progress.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Create Profile Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryLemonDark,
                              foregroundColor: AppColors.textOnYellow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.textOnYellow,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Create Profile',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/profile_service.dart';
import '../../../shared/models/user_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/auth_text_field.dart';
import '../../auth/widgets/unit_selector.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();

  final _heightCmController = TextEditingController();
  final _heightFtController = TextEditingController();
  final _heightInController = TextEditingController();
  final _weightController = TextEditingController();
  final _advisorController = TextEditingController();

  HeightUnit _heightUnit = HeightUnit.cm;
  WeightUnit _weightUnit = WeightUnit.kg;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  void _prefill() {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;

    if (profile.height != null) {
      _heightUnit = profile.height!.unit;
      if (_heightUnit == HeightUnit.cm) {
        _heightCmController.text = profile.height!.value.toStringAsFixed(0);
      } else {
        final totalIn = profile.height!.value.toInt();
        _heightFtController.text = (totalIn ~/ 12).toString();
        _heightInController.text = (totalIn % 12).toString();
      }
    }

    if (profile.weight != null) {
      _weightUnit = profile.weight!.unit;
      _weightController.text = profile.weight!.value.toStringAsFixed(1);
    }

    if (profile.advisorName != null) {
      _advisorController.text = profile.advisorName!;
    }
  }

  @override
  void dispose() {
    _heightCmController.dispose();
    _heightFtController.dispose();
    _heightInController.dispose();
    _weightController.dispose();
    _advisorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; _errorMessage = null; });

    try {
      HeightData? height;
      if (_heightUnit == HeightUnit.cm) {
        final cm = double.tryParse(_heightCmController.text);
        if (cm != null) height = HeightData(value: cm, unit: HeightUnit.cm);
      } else {
        final ft = int.tryParse(_heightFtController.text) ?? 0;
        final inches = int.tryParse(_heightInController.text) ?? 0;
        final total = (ft * 12 + inches).toDouble();
        if (total > 0) height = HeightData(value: total, unit: HeightUnit.ftIn);
      }

      WeightData? weight;
      final w = double.tryParse(_weightController.text);
      if (w != null) weight = WeightData(value: w, unit: _weightUnit);

      await _profileService.updateProfile(
        height: height,
        weight: weight,
        advisorName: _advisorController.text.trim().isEmpty
            ? null
            : _advisorController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _errorMessage = 'Could not save — please try again.'; _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Height ──────────────────────────────────────────────────────
            GradientCard(
              gradient: AppColors.cardGradient,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Height', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  UnitSelector<HeightUnit>(
                    options: HeightUnit.values,
                    value: _heightUnit,
                    labelBuilder: (u) => u == HeightUnit.cm ? 'cm' : 'ft / in',
                    onChanged: (u) => setState(() => _heightUnit = u),
                  ),
                  const SizedBox(height: 12),
                  if (_heightUnit == HeightUnit.cm)
                    AuthTextField(
                      controller: _heightCmController,
                      label: 'Height (cm)',
                      hint: 'e.g. 165',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.height,
                    )
                  else
                    Row(children: [
                      Expanded(
                        child: AuthTextField(
                          controller: _heightFtController,
                          label: 'Feet',
                          hint: '5',
                          keyboardType: TextInputType.number,
                          prefixIcon: Icons.height,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AuthTextField(
                          controller: _heightInController,
                          label: 'Inches',
                          hint: '6',
                          keyboardType: TextInputType.number,
                          prefixIcon: Icons.straighten,
                        ),
                      ),
                    ]),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Weight ──────────────────────────────────────────────────────
            GradientCard(
              gradient: AppColors.cardGradient,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weight', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  UnitSelector<WeightUnit>(
                    options: WeightUnit.values,
                    value: _weightUnit,
                    labelBuilder: (u) => u == WeightUnit.kg ? 'kg' : 'lbs',
                    onChanged: (u) => setState(() => _weightUnit = u),
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _weightController,
                    label: 'Weight (${_weightUnit == WeightUnit.kg ? "kg" : "lbs"})',
                    hint: _weightUnit == WeightUnit.kg ? 'e.g. 60' : 'e.g. 132',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    prefixIcon: Icons.monitor_weight_outlined,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Advisor name ─────────────────────────────────────────────────
            GradientCard(
              gradient: AppColors.cardGradient,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Advisor's Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('The name of your doctor, coach, or healthcare provider.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _advisorController,
                    label: "Advisor's name",
                    hint: 'e.g. Dr. Smith',
                    prefixIcon: Icons.person_outline,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemonDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

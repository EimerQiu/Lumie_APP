import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildBackButton(context),
                const SizedBox(height: 32),
                _buildHeader(),
                const SizedBox(height: 40),
                _buildForm(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
      ),
      onPressed: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to continue your wellness journey',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return Form(
          key: _formKey,
          child: Column(
            children: [
              // Error message
              if (authProvider.errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authProvider.errorMessage!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => authProvider.clearError(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // Email field
              AuthTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'Enter your email',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password field
              AuthTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Enter your password',
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: Implement forgot password
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Login button
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  text: 'Log In',
                  isLoading: authProvider.state == AuthState.loading,
                  onPressed: authProvider.state == AuthState.loading
                      ? null
                      : () => _handleLogin(context, authProvider),
                ),
              ),
              const SizedBox(height: 24),

              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/signup');
                    },
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: AppColors.primaryLemonDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleLogin(BuildContext context, AuthProvider authProvider) async {
    if (!_formKey.currentState!.validate()) return;

    final success = await authProvider.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
      // Navigation will be handled by main app based on auth state
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

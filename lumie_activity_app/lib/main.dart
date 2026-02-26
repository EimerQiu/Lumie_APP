import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/account_type_screen.dart';
import 'features/auth/screens/select_account_type_screen.dart';
import 'features/auth/screens/teen_profile_setup_screen.dart';
import 'features/auth/screens/parent_profile_setup_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/activity/screens/activity_history_screen.dart';
import 'features/manual_entry/screens/manual_entry_screen.dart';
import 'features/walk_test/screens/walk_test_screen.dart';
import 'features/sleep/screens/sleep_screen.dart';
import 'features/sleep/screens/sleep_history_screen.dart';
import 'features/teams/providers/teams_provider.dart';
import 'features/teams/screens/teams_list_screen.dart';
import 'features/teams/screens/create_team_screen.dart';
import 'features/teams/screens/team_detail_screen.dart';
import 'features/teams/screens/invite_member_screen.dart';
import 'features/teams/screens/member_data_screen.dart';
import 'features/teams/screens/accept_invitation_screen.dart';
import 'features/settings/screens/rest_days_settings_screen.dart';
import 'features/settings/screens/edit_profile_screen.dart';
import 'features/advisor/screens/advisor_screen.dart';
import 'shared/models/activity_models.dart';
import 'shared/models/user_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const LumieActivityApp());
}

class LumieActivityApp extends StatelessWidget {
  const LumieActivityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => TeamsProvider()),
      ],
      child: MaterialApp(
        title: 'Lumie Activity',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AuthWrapper(),
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/login': (context) => const LoginScreen(),
          '/account-type': (context) => const AccountTypeScreen(),
          '/profile/teen': (context) => const TeenProfileSetupScreen(),
          '/profile/parent': (context) => const ParentProfileSetupScreen(),
          '/home': (context) => const MainNavigationScreen(),
          '/sleep/history': (context) => const SleepHistoryScreen(),
          '/teams': (context) => const TeamsListScreen(),
          '/teams/create': (context) => const CreateTeamScreen(),
          '/settings/rest-days': (context) => const RestDaysSettingsScreen(),
          '/profile/edit': (context) => const EditProfileScreen(),
        },
        onGenerateRoute: (settings) {
          // Handle routes with arguments
          if (settings.name == '/teams/detail') {
            final teamId = settings.arguments as String;
            return MaterialPageRoute(
              builder: (context) => TeamDetailScreen(teamId: teamId),
            );
          } else if (settings.name == '/teams/invite') {
            final teamId = settings.arguments as String;
            return MaterialPageRoute(
              builder: (context) => InviteMemberScreen(teamId: teamId),
            );
          } else if (settings.name == '/teams/member-data') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => MemberDataScreen(
                teamId: args['teamId'] as String,
                userId: args['userId'] as String,
                userName: args['userName'] as String,
              ),
            );
          } else if (settings.name == '/subscription/upgrade') {
            // Placeholder for subscription upgrade screen
            return MaterialPageRoute(
              builder: (context) => const SubscriptionUpgradeScreen(),
            );
          } else if (settings.name?.startsWith('/invite/') == true) {
            // Handle invitation link: /invite/{token}
            final token = settings.name!.substring('/invite/'.length);
            return MaterialPageRoute(
              builder: (context) => AcceptInvitationScreen(token: token),
            );
          }
          return null;
        },
      ),
    );
  }
}

/// Wrapper that handles auth state navigation
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        switch (auth.state) {
          case AuthState.initial:
          case AuthState.loading:
            return const SplashScreen();

          case AuthState.unauthenticated:
          case AuthState.error:
            return const WelcomeScreen();

          case AuthState.needsAccountType:
            return const SelectAccountTypeScreen();

          case AuthState.needsProfile:
            final role = auth.user?.role;
            if (role == AccountRole.teen) {
              return const TeenProfileSetupScreen();
            } else if (role == AccountRole.parent) {
              return const ParentProfileSetupScreen();
            }
            // Fallback to account type if role is unknown
            return const SelectAccountTypeScreen();

          case AuthState.authenticated:
            return const MainNavigationScreen();
        }
      },
    );
  }
}

/// Splash screen shown during initialization
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: AppColors.warmGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryLemon.withValues(alpha: 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 60,
                    color: AppColors.textOnYellow,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Lumie',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textOnYellow,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Activity Tracking',
                  style: TextStyle(
                    fontSize: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnYellow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initialize TeamsProvider with user's subscription tier
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final teamsProvider = context.read<TeamsProvider>();

      if (authProvider.profile?.subscription.tier != null) {
        teamsProvider.setUserTier(authProvider.profile!.subscription.tier);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),   // Today
      const AdvisorScreen(),     // Advisor
      const SleepScreen(),       // Insights
      const SettingsScreen(),    // Me
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.wb_sunny_outlined,
                selectedIcon: Icons.wb_sunny,
                label: 'Today',
                isSelected: _currentIndex == 0,
                onTap: () => setState(() => _currentIndex = 0),
              ),
              _NavBarItem(
                icon: Icons.auto_awesome_outlined,
                selectedIcon: Icons.auto_awesome,
                label: 'Advisor',
                isSelected: _currentIndex == 1,
                onTap: () => setState(() => _currentIndex = 1),
              ),
              _NavBarItem(
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights,
                label: 'Insights',
                isSelected: _currentIndex == 2,
                onTap: () => setState(() => _currentIndex = 2),
              ),
              _NavBarItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Me',
                isSelected: _currentIndex == 3,
                onTap: () => setState(() => _currentIndex = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddActivitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add Activity',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            _AddActivityOption(
              icon: Icons.edit_note,
              title: 'Log Manual Activity',
              description: 'Record an activity you\'ve completed',
              gradient: AppColors.warmGradient,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ManualEntryScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _AddActivityOption(
              icon: Icons.watch,
              title: 'Review Detected Activity',
              description: 'Confirm activity detected by your ring',
              gradient: AppColors.mintGradient,
              onTap: () {
                Navigator.of(context).pop();
                // Show detected activity with mock data
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ManualEntryScreen(
                      detectedActivity: RingDetectedActivity(
                        startTime: DateTime.now().subtract(const Duration(hours: 1)),
                        endTime: DateTime.now().subtract(const Duration(minutes: 35)),
                        durationMinutes: 25,
                        suggestedActivityTypeId: 'walking',
                        confidence: 0.75,
                        heartRateAvg: 88,
                        heartRateMax: 105,
                        measuredIntensity: ActivityIntensity.moderate,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _AddActivityOption(
              icon: Icons.directions_walk,
              title: 'Start 6-Minute Walk Test',
              description: 'Measure your walking distance',
              gradient: AppColors.coolGradient,
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _currentIndex = 2);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.warmGradient : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddActivityOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Gradient gradient;
  final VoidCallback onTap;

  const _AddActivityOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.backgroundWhite.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textOnYellow, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textOnYellow.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textOnYellow.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings / Me screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _checkInFreq = 'Daily';

  @override
  void initState() {
    super.initState();
    _loadFreq();
  }

  Future<void> _loadFreq() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _checkInFreq = prefs.getString('advisor_checkin_freq') ?? 'Daily');
  }

  Future<void> _setFreq(String freq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('advisor_checkin_freq', freq);
    if (mounted) setState(() => _checkInFreq = freq);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Text(
                    'Me',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Profile Card
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                final profile = auth.profile;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.warmGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWhite.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, size: 32, color: AppColors.textOnYellow),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.name ?? 'User',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textOnYellow,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              auth.user?.email ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textOnYellow.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Subscription: ${profile?.subscription.tier.fullDisplayName ?? 'Free'}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textOnYellow.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/profile/edit');
                        },
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textOnYellow,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Settings Options
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.backgroundWhite,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    // ── Profile ──────────────────────────────────────────────
                    _SettingsItem(
                      icon: Icons.person_outline,
                      title: 'Edit Profile',
                      onTap: () => Navigator.pushNamed(context, '/profile/edit'),
                    ),
                    _SettingsItem(
                      icon: Icons.groups_outlined,
                      title: 'Teams',
                      onTap: () => Navigator.pushNamed(context, '/teams'),
                    ),

                    const Divider(height: 24),

                    // ── Advisor ───────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        'Advisor',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLemon.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.schedule_outlined, size: 22, color: AppColors.textOnYellow),
                              ),
                              const SizedBox(width: 16),
                              const Text(
                                'Check-in Frequency',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: ['Daily', 'Weekly', 'Monthly'].map((freq) {
                              final selected = _checkInFreq == freq;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => _setFreq(freq),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: selected ? AppColors.primaryLemonDark : AppColors.backgroundPaper,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: selected ? AppColors.primaryLemonDark : AppColors.surfaceLight,
                                      ),
                                    ),
                                    child: Text(
                                      freq,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: selected ? Colors.white : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 24),

                    // ── Health & Schedule ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        'Health & Schedule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _SettingsItem(
                      icon: Icons.event_busy_outlined,
                      title: 'Rest Day Schedule',
                      onTap: () => Navigator.pushNamed(context, '/settings/rest-days'),
                    ),
                    _SettingsItem(
                      icon: Icons.watch_outlined,
                      title: 'Ring Settings',
                      onTap: () {},
                    ),

                    const Divider(height: 24),

                    // ── General ───────────────────────────────────────────────
                    _SettingsItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.lock_outline,
                      title: 'Privacy',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: () {},
                    ),
                    const Divider(height: 32),
                    _SettingsItem(
                      icon: Icons.logout,
                      title: 'Log Out',
                      isDestructive: true,
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AuthProvider>().logout();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive
              ? AppColors.error.withValues(alpha: 0.1)
              : AppColors.primaryLemon.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive ? AppColors.error : AppColors.textOnYellow,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDestructive ? AppColors.error : AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

/// Placeholder screen for subscription upgrade
class SubscriptionUpgradeScreen extends StatelessWidget {
  const SubscriptionUpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade to Pro'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.workspace_premium,
                size: 96,
                color: Colors.amber[600],
              ),
              const SizedBox(height: 24),
              Text(
                'Upgrade to Pro',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Get access to up to 100 teams and unlock premium features.',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                'Subscription upgrade screen\ncoming soon!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Ring scanning and connection screen.
// Per PRD §4.2–4.4: Bluetooth check → scan → select ring → connect → success.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/ring_ble_service.dart';
import '../../../shared/models/ring_models.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/ring_provider.dart';

class RingScanScreen extends StatefulWidget {
  /// When true the screen is opened from Settings (not onboarding).
  final bool fromSettings;

  const RingScanScreen({super.key, this.fromSettings = false});

  @override
  State<RingScanScreen> createState() => _RingScanScreenState();
}

class _RingScanScreenState extends State<RingScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _scanComplete = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── Flow ─────────────────────────────────────────────────────────────────

  Future<void> _startFlow() async {
    final btOn = await RingBleService.isBluetoothOn();
    if (!btOn && mounted) {
      _showBluetoothOffDialog();
      return;
    }
    _beginScan();
  }

  void _beginScan() {
    if (!mounted) return;
    setState(() => _scanComplete = false);
    context.read<RingProvider>().startScan().then((_) {
      if (mounted) setState(() => _scanComplete = true);
    });
  }

  Future<void> _connect(DiscoveredRing ring) async {
    final ringProvider = context.read<RingProvider>();
    final authProvider = context.read<AuthProvider>();
    final profile = authProvider.profile;

    await ringProvider.stopScan();

    // Derive user params for ring initialisation (convert units if needed)
    const gender = 0; // ring uses 0=female/1=male; profile has no gender field
    final age = profile?.age ?? 17;
    final h = profile?.height;
    final heightCm = h == null
        ? 165
        : (h.unit.name == 'cm' ? h.value : h.value * 2.54).round();
    final w = profile?.weight;
    final weightKg = w == null
        ? 60
        : (w.unit.name == 'kg' ? w.value : w.value * 0.453592).round();

    final success = await ringProvider.connectAndPair(
      ring: ring,
      gender: gender,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
    );

    if (!mounted) return;
    if (success) {
      _showSuccessScreen(ringProvider.ringInfo!);
    } else {
      _showConnectionError(ringProvider.errorMessage ?? 'Connection failed', ring);
    }
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Bluetooth is Off'),
        content: const Text(
          'Please turn on Bluetooth to find your Lumie Ring.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // back to ownership screen
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // On iOS this opens Settings; on Android it prompts BT enable
              await FlutterBluePlus.turnOn();
              // Re-check after a short delay
              await Future.delayed(const Duration(seconds: 1));
              final on = await RingBleService.isBluetoothOn();
              if (on && mounted) _beginScan();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showConnectionError(String message, DiscoveredRing ring) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Connection Failed'),
        content: Text('Could not connect to this ring.\n\n$message'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip for Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _connect(ring);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showSuccessScreen(RingInfo info) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _RingSuccessScreen(ringInfo: info)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Connect Ring',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      body: Consumer<RingProvider>(
        builder: (context, ring, _) {
          if (ring.state == RingProviderState.connecting) {
            return _buildConnecting();
          }
          return _buildScanBody(ring);
        },
      ),
    );
  }

  Widget _buildScanBody(RingProvider ring) {
    final isScanning = ring.state == RingProviderState.scanning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Pulse animation while scanning
          ScaleTransition(
            scale: isScanning ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                gradient: isScanning ? AppColors.coolGradient : AppColors.warmGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.watch_outlined,
                size: 64,
                color: isScanning ? const Color(0xFF0369A1) : AppColors.textOnYellow,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            isScanning
                ? 'Scanning for Lumie Rings…'
                : _scanComplete && ring.discoveredRings.isEmpty
                    ? 'No rings found nearby'
                    : 'Select your Lumie Ring',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            isScanning
                ? 'Make sure your ring is charged and nearby.'
                : _scanComplete && ring.discoveredRings.isEmpty
                    ? 'Try restarting Bluetooth and placing the ring closer.'
                    : 'Tap a ring below to connect.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),

          const SizedBox(height: 24),

          // Discovered rings list
          Expanded(
            child: ring.discoveredRings.isEmpty
                ? _buildEmptyState(isScanning)
                : ListView.separated(
                    itemCount: ring.discoveredRings.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final discovered = ring.discoveredRings[i];
                      return _RingListTile(
                        ring: discovered,
                        onConnect: () => _connect(discovered),
                      );
                    },
                  ),
          ),

          // Bottom buttons
          if (!isScanning) ...[
            ElevatedButton.icon(
              onPressed: _beginScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemonDark,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Skip for Now',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isScanning) {
    if (isScanning) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryLemonDark),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.watch_off_outlined, size: 56, color: AppColors.textLight),
          const SizedBox(height: 12),
          const Text(
            'No Lumie Rings found',
            style: TextStyle(fontSize: 17, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Make sure your ring is:\n• Charged and powered on\n• Not connected to another device\n• Within Bluetooth range',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textLight, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildConnecting() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryLemonDark),
            strokeWidth: 3,
          ),
          SizedBox(height: 24),
          Text(
            'Connecting to your\nLumie Ring…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This may take a few seconds.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Ring list tile ───────────────────────────────────────────────────────────

class _RingListTile extends StatelessWidget {
  final DiscoveredRing ring;
  final VoidCallback onConnect;

  const _RingListTile({required this.ring, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppColors.coolGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.watch_outlined, size: 24, color: Color(0xFF0369A1)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ring.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    ...List.generate(4, (i) => Icon(
                      Icons.signal_cellular_alt,
                      size: 12,
                      color: i < ring.signalBars
                          ? AppColors.ringConnected
                          : AppColors.surfaceLight,
                    )),
                    const SizedBox(width: 4),
                    Text(
                      ring.signalLabel,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Success screen ───────────────────────────────────────────────────────────

class _RingSuccessScreen extends StatelessWidget {
  final RingInfo ringInfo;

  const _RingSuccessScreen({required this.ringInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),

              // Success icon
              Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  gradient: AppColors.mintGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 72, color: Color(0xFF0F766E)),
              ),

              const SizedBox(height: 32),

              const Text(
                'Your Lumie Ring\nis Connected!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                ringInfo.ringName ?? 'Lumie Ring',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 8),

              if (ringInfo.firmwareVersion != null)
                Text(
                  'Firmware ${ringInfo.firmwareVersion}',
                  style: const TextStyle(fontSize: 14, color: AppColors.textLight),
                ),

              if (ringInfo.batteryLevel != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.battery_charging_full, size: 16, color: AppColors.ringConnected),
                    const SizedBox(width: 4),
                    Text(
                      'Battery ${ringInfo.batteryLevel}%',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Pop back through scan screen to ownership screen
                    Navigator.of(context).pop();
                  },
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
                    'Get Started',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

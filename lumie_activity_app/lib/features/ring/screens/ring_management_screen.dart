// Ring Management screen — accessible from Settings → Ring Settings.
// Per PRD §6: view connected ring, disconnect, connect new ring, reconnect.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/ring_provider.dart';
import '../../../shared/models/ring_models.dart';
import 'ring_scan_screen.dart';

class RingManagementScreen extends StatefulWidget {
  const RingManagementScreen({super.key});

  @override
  State<RingManagementScreen> createState() => _RingManagementScreenState();
}

class _RingManagementScreenState extends State<RingManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RingProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Ring Management',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      body: Consumer<RingProvider>(
        builder: (context, ring, _) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Status card ────────────────────────────────────────────────
              _StatusCard(ring: ring),

              const SizedBox(height: 24),

              // ── Actions ────────────────────────────────────────────────────
              if (ring.isPaired) ...[
                _ActionTile(
                  icon: Icons.refresh,
                  title: 'Reconnect',
                  subtitle: 'Manually trigger a reconnect attempt',
                  onTap: () => _reconnect(context, ring),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.swap_horiz,
                  title: 'Connect a New Ring',
                  subtitle: 'Disconnect current ring and pair a different one',
                  onTap: () => _connectNew(context, ring),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.link_off,
                  title: 'Disconnect Ring',
                  subtitle: 'Unpair and remove ring from your account',
                  isDestructive: true,
                  onTap: () => _confirmDisconnect(context, ring),
                ),
              ] else ...[
                _ActionTile(
                  icon: Icons.add_circle_outline,
                  title: 'Connect a Lumie Ring',
                  subtitle: 'Pair your ring to unlock all features',
                  onTap: () => _connectNew(context, ring),
                ),
              ],

              const SizedBox(height: 32),

              // ── Info section ───────────────────────────────────────────────
              const _InfoSection(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reconnect(BuildContext context, RingProvider ring) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RingScanScreen(fromSettings: true)),
    );
  }

  Future<void> _connectNew(BuildContext context, RingProvider ring) async {
    if (ring.isPaired) {
      // Must disconnect first (per PRD: one ring at a time)
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Replace Ring?'),
          content: const Text(
            'Your current ring will be unpaired. Historical data will be preserved. '
            'Proceed to connect a new ring?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
      await ring.unpairRing();
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RingScanScreen(fromSettings: true)),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context, RingProvider ring) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect Ring?'),
        content: const Text(
          'Your ring will be removed from this account. '
          'Historical data will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ring.unpairRing();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ring disconnected.')),
        );
      }
    }
  }
}

// ─── Status card ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final RingProvider ring;
  const _StatusCard({required this.ring});

  @override
  Widget build(BuildContext context) {
    final info = ring.ringInfo;
    final isPaired = ring.isPaired;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isPaired ? AppColors.coolGradient : AppColors.warmGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.watch_outlined,
              size: 32,
              color: isPaired ? const Color(0xFF0369A1) : AppColors.textOnYellow,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?.ringName ?? 'No Ring Connected',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPaired ? const Color(0xFF0369A1) : AppColors.textOnYellow,
                  ),
                ),
                const SizedBox(height: 4),
                _StatusBadge(status: info?.connectionStatus ?? RingConnectionStatus.neverPaired),
                if (info?.firmwareVersion != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Firmware ${info!.firmwareVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      color: (isPaired ? const Color(0xFF0369A1) : AppColors.textOnYellow)
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (info?.batteryLevel != null) ...[
            Column(
              children: [
                Icon(
                  Icons.battery_charging_full,
                  color: isPaired ? const Color(0xFF0369A1) : AppColors.textOnYellow,
                  size: 22,
                ),
                Text(
                  '${info!.batteryLevel}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isPaired ? const Color(0xFF0369A1) : AppColors.textOnYellow,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final RingConnectionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (status) {
      case RingConnectionStatus.connected:
        color = AppColors.ringConnected;
        label = 'Connected';
      case RingConnectionStatus.disconnected:
        color = AppColors.ringDisconnected;
        label = 'Disconnected';
      case RingConnectionStatus.neverPaired:
        color = AppColors.textLight;
        label = 'Not paired';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Action tile ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.textOnYellow;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                color: (isDestructive ? AppColors.error : AppColors.primaryLemonDark)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? AppColors.error : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}

// ─── Info section ─────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLemon,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.textOnYellow),
              SizedBox(width: 8),
              Text(
                'About Ring Pairing',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnYellow,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Only one ring can be paired at a time.\n'
            '• Disconnecting a ring does not delete your health history.\n'
            '• Ring replacement: contact support if your ring is lost or damaged.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textOnYellow,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

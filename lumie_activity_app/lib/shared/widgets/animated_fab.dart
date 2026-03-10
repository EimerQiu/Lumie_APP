import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A single menu item in the animated FAB menu
class FABMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const FABMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Animated FAB with expandable menu items that grow upward from the button
class AnimatedFAB extends StatefulWidget {
  /// Menu items to show when expanded (displayed bottom to top)
  final List<FABMenuItem> items;

  /// Icon shown on the main FAB button when collapsed
  final IconData mainIcon;

  /// Color of the FAB buttons (defaults to primaryLemonDark)
  final Color? color;

  const AnimatedFAB({
    super.key,
    required this.items,
    this.mainIcon = Icons.add,
    this.color,
  });

  @override
  State<AnimatedFAB> createState() => _AnimatedFABState();
}

class _AnimatedFABState extends State<AnimatedFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
    _isExpanded ? _controller.forward() : _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final fabColor = widget.color ?? AppColors.primaryLemonDark;
    const itemSpacing = 70.0;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Menu items grow upward (index 0 = closest to main FAB)
        for (int i = 0; i < widget.items.length; i++)
          _FABMenuItem(
            animation: _controller,
            offset: Offset(0, itemSpacing * (i + 1)),
            icon: widget.items[i].icon,
            label: widget.items[i].label,
            color: fabColor,
            onTap: () {
              _toggle();
              widget.items[i].onTap();
            },
          ),

        // Main FAB (rendered last so it stays on top)
        Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: fabColor,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Transform.rotate(
                  angle: _controller.value * (3.14159 / 2),
                  child: Icon(
                    _isExpanded ? Icons.close : widget.mainIcon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Internal: animated menu item that slides and scales into position
class _FABMenuItem extends StatelessWidget {
  final Animation<double> animation;
  final Offset offset;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FABMenuItem({
    required this.animation,
    required this.offset,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final scale = animation.value;

        return Positioned(
          bottom: 16 + offset.dy * scale,
          right: 16,
          child: Opacity(
            opacity: scale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

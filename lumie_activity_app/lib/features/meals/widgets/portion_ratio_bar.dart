// PortionRatioBar — proportional segmented bar with draggable dividers.
//
// Each segment width is `weight_i / Σweights`. Dividers between segments are
// draggable horizontally; dragging shifts a fraction from one neighbour to
// the other while keeping every other segment unchanged. Segment labels show
// the food name in small text inside the segment.
//
// Per spec: ratios are relative only — no numbers, no percentages shown.
// Bar is hidden by the parent when there is only one item.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Minimum visible fraction per segment so labels stay legible and the user
/// can always grab the divider on either side.
const double _kMinFraction = 0.06;

/// Granularity at which fractional ratios snap to integer weights when the
/// drag ends. Picks 10 so a 30/40/30 split round-trips cleanly through the
/// integer model.
const int _kWeightScale = 10;

class PortionRatioBar extends StatefulWidget {
  /// Food item names, in order.
  final List<String> names;

  /// Current portion weights (one per name). Always integer ≥1.
  final List<int> weights;

  /// Called with the updated integer weights when the user finishes a drag.
  /// Always emits a list the same length as [names].
  final ValueChanged<List<int>>? onChanged;

  const PortionRatioBar({
    super.key,
    required this.names,
    required this.weights,
    this.onChanged,
  });

  @override
  State<PortionRatioBar> createState() => _PortionRatioBarState();
}

class _PortionRatioBarState extends State<PortionRatioBar> {
  /// Live fractional ratios used during drag. Sum = 1.0. Rebuilt from the
  /// incoming integer weights on every dependency change so external edits
  /// (re-analysis result, item add/remove) propagate cleanly.
  late List<double> _fractions;

  @override
  void initState() {
    super.initState();
    _fractions = _fractionsFromWeights(widget.weights);
  }

  @override
  void didUpdateWidget(covariant PortionRatioBar old) {
    super.didUpdateWidget(old);
    final lengthChanged = old.weights.length != widget.weights.length;
    final namesChanged =
        old.names.length != widget.names.length ||
        !_listEqual(old.names, widget.names);
    final weightsChanged = !_intListEqual(old.weights, widget.weights);
    if (lengthChanged || namesChanged || weightsChanged) {
      _fractions = _fractionsFromWeights(widget.weights);
    }
  }

  static bool _listEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _intListEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<double> _fractionsFromWeights(List<int> weights) {
    if (weights.isEmpty) return const [];
    final clamped = weights.map((w) => w < 1 ? 1 : w).toList();
    final total = clamped.fold<int>(0, (a, b) => a + b);
    if (total <= 0) {
      final equal = 1.0 / weights.length;
      return List.filled(weights.length, equal);
    }
    return clamped.map((w) => w / total).toList();
  }

  /// Convert the live fractions into integer weights. Multiplies by
  /// [_kWeightScale] and rounds; ensures every weight is at least 1 so the
  /// model never carries a "zero portion" item.
  List<int> _weightsFromFractions() {
    final scaled = _fractions
        .map((f) => (f * _kWeightScale).round())
        .map((w) => w < 1 ? 1 : w)
        .toList();
    return scaled;
  }

  void _emit() {
    final cb = widget.onChanged;
    if (cb == null) return;
    cb(_weightsFromFractions());
  }

  /// Apply a delta to the divider between segment [i] and [i+1].
  /// Both segments respect [_kMinFraction]; everything else stays put.
  void _shiftDivider(int i, double deltaFraction) {
    if (i < 0 || i + 1 >= _fractions.length) return;
    final left = _fractions[i];
    final right = _fractions[i + 1];
    var newLeft = left + deltaFraction;
    var newRight = right - deltaFraction;
    if (newLeft < _kMinFraction) {
      newRight = (left + right) - _kMinFraction;
      newLeft = _kMinFraction;
    } else if (newRight < _kMinFraction) {
      newLeft = (left + right) - _kMinFraction;
      newRight = _kMinFraction;
    }
    setState(() {
      _fractions[i] = newLeft;
      _fractions[i + 1] = newRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.names.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Segment row.
              Row(
                children: List.generate(widget.names.length, (i) {
                  final f = i < _fractions.length ? _fractions[i] : 0.0;
                  return SizedBox(
                    width: totalWidth * f,
                    child: _Segment(
                      name: widget.names[i],
                      isFirst: i == 0,
                      isLast: i == widget.names.length - 1,
                      color: _segmentColor(i),
                    ),
                  );
                }),
              ),
              // Divider handles between segments. Each one sits at the running
              // sum of fractions on its left.
              for (var i = 0; i < widget.names.length - 1; i++)
                _DividerHandle(
                  leftFraction: _runningFraction(i + 1),
                  totalWidth: totalWidth,
                  enabled: widget.onChanged != null,
                  onDrag: (dx) => _shiftDivider(i, dx / totalWidth),
                  onDragEnd: _emit,
                ),
            ],
          ),
        );
      },
    );
  }

  double _runningFraction(int upToIndex) {
    var sum = 0.0;
    for (var i = 0; i < upToIndex && i < _fractions.length; i++) {
      sum += _fractions[i];
    }
    return sum.clamp(0.0, 1.0);
  }

  Color _segmentColor(int i) {
    // Alternate two warm tones from the brand palette so adjacent segments
    // stay visually distinct without introducing new colours.
    return i.isEven ? AppColors.primaryLemon : AppColors.primaryLemonLight;
  }
}

class _Segment extends StatelessWidget {
  final String name;
  final bool isFirst;
  final bool isLast;
  final Color color;

  const _Segment({
    required this.name,
    required this.isFirst,
    required this.isLast,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? const Radius.circular(10) : Radius.zero,
          right: isLast ? const Radius.circular(10) : Radius.zero,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _DividerHandle extends StatelessWidget {
  final double leftFraction;
  final double totalWidth;
  final bool enabled;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  const _DividerHandle({
    required this.leftFraction,
    required this.totalWidth,
    required this.enabled,
    required this.onDrag,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    const handleWidth = 18.0;
    final centerLeft = leftFraction * totalWidth - handleWidth / 2;
    return Positioned(
      left: centerLeft,
      top: 0,
      bottom: 0,
      width: handleWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate:
            enabled ? (d) => onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: enabled ? (_) => onDragEnd() : null,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.basic,
          child: Center(
            child: Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.primaryLemonDark
                    : AppColors.textLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

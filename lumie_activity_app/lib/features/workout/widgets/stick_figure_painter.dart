import 'package:flutter/material.dart';
import '../data/exercise_keyframes.dart';

/// Paints a stick figure from a normalized pose map.
///
/// Joint points are drawn as filled yellow circles.  Bones connecting
/// them are drawn as white lines.  Equipment props (dumbbell rectangles
/// or a barbell bar) are drawn at wrist landmarks.
class StickFigurePainter extends CustomPainter {
  final Map<String, Offset> pose;
  final EquipmentProp equipmentProp;

  StickFigurePainter({
    required this.pose,
    this.equipmentProp = EquipmentProp.none,
  });

  // ── Paint configs ─────────────────────────────────────────────────────────

  static const _jointRadius = 5.0;
  static const _boneWidth = 3.0;
  static const _jointColor = Color(0xFFFBBF24); // yellow
  static const _boneColor = Colors.white;
  static const _propColor = Color(0xFFD1D5DB); // grey-300

  static final _jointPaint = Paint()
    ..color = _jointColor
    ..style = PaintingStyle.fill;

  static final _bonePaint = Paint()
    ..color = _boneColor
    ..strokeWidth = _boneWidth
    ..strokeCap = StrokeCap.round;

  static final _propPaint = Paint()
    ..color = _propColor
    ..style = PaintingStyle.fill;

  // ── Bone connections ──────────────────────────────────────────────────────

  /// Front-view bone pairs (bilateral landmarks).
  static const _frontBones = [
    ('head', 'neck'),
    ('neck', 'lShoulder'),
    ('neck', 'rShoulder'),
    ('lShoulder', 'lElbow'),
    ('rShoulder', 'rElbow'),
    ('lElbow', 'lWrist'),
    ('rElbow', 'rWrist'),
    ('lShoulder', 'lHip'),
    ('rShoulder', 'rHip'),
    ('lHip', 'rHip'),
    ('lHip', 'lKnee'),
    ('rHip', 'rKnee'),
    ('lKnee', 'lAnkle'),
    ('rKnee', 'rAnkle'),
  ];

  /// Side-view bone pairs (single-side landmarks).
  static const _sideBones = [
    ('head', 'neck'),
    ('neck', 'shoulder'),
    ('shoulder', 'elbow'),
    ('elbow', 'wrist'),
    ('shoulder', 'hip'),
    ('hip', 'knee'),
    ('knee', 'ankle'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final isFront = pose.containsKey('lShoulder');
    final bones = isFront ? _frontBones : _sideBones;

    // Draw bones
    for (final (a, b) in bones) {
      final pa = pose[a];
      final pb = pose[b];
      if (pa != null && pb != null) {
        canvas.drawLine(
          Offset(pa.dx * size.width, pa.dy * size.height),
          Offset(pb.dx * size.width, pb.dy * size.height),
          _bonePaint,
        );
      }
    }

    // Draw joints
    for (final entry in pose.entries) {
      final p = Offset(entry.value.dx * size.width,
          entry.value.dy * size.height);
      canvas.drawCircle(p, _jointRadius, _jointPaint);
    }

    // Draw equipment props
    _drawEquipment(canvas, size, isFront);
  }

  void _drawEquipment(Canvas canvas, Size size, bool isFront) {
    if (equipmentProp == EquipmentProp.none) return;

    if (equipmentProp == EquipmentProp.dumbbell) {
      _drawDumbbells(canvas, size, isFront);
    } else if (equipmentProp == EquipmentProp.barbell) {
      _drawBarbell(canvas, size, isFront);
    }
  }

  /// Draw small filled rectangles at each wrist to represent dumbbells.
  void _drawDumbbells(Canvas canvas, Size size, bool isFront) {
    const dbWidth = 14.0;
    const dbHeight = 6.0;

    if (isFront) {
      for (final key in ['lWrist', 'rWrist']) {
        final w = pose[key];
        if (w == null) continue;
        final x = w.dx * size.width;
        final y = w.dy * size.height;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y), width: dbWidth, height: dbHeight),
            const Radius.circular(2),
          ),
          _propPaint,
        );
      }
    } else {
      final w = pose['wrist'];
      if (w == null) return;
      final x = w.dx * size.width;
      final y = w.dy * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x, y), width: dbWidth, height: dbHeight),
          const Radius.circular(2),
        ),
        _propPaint,
      );
    }
  }

  /// Draw a horizontal bar connecting wrists with rectangles extending beyond.
  void _drawBarbell(Canvas canvas, Size size, bool isFront) {
    const barThickness = 3.0;
    const plateWidth = 8.0;
    const plateHeight = 16.0;
    const overhang = 12.0;

    final barPaint = Paint()
      ..color = _propColor
      ..strokeWidth = barThickness
      ..strokeCap = StrokeCap.round;

    if (isFront) {
      final lw = pose['lWrist'];
      final rw = pose['rWrist'];
      if (lw == null || rw == null) return;
      final lx = lw.dx * size.width;
      final rx = rw.dx * size.width;
      final ly = lw.dy * size.height;
      final ry = rw.dy * size.height;
      // Bar line
      canvas.drawLine(
        Offset(lx - overhang, ly),
        Offset(rx + overhang, ry),
        barPaint,
      );
      // Left plate
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx - overhang, ly),
              width: plateWidth,
              height: plateHeight),
          const Radius.circular(1),
        ),
        _propPaint,
      );
      // Right plate
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(rx + overhang, ry),
              width: plateWidth,
              height: plateHeight),
          const Radius.circular(1),
        ),
        _propPaint,
      );
    } else {
      // Side view: just draw bar extending from wrist
      final w = pose['wrist'];
      if (w == null) return;
      final x = w.dx * size.width;
      final y = w.dy * size.height;
      canvas.drawLine(
        Offset(x - overhang, y),
        Offset(x + overhang, y),
        barPaint,
      );
      // Plates
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x - overhang, y),
              width: plateWidth,
              height: plateHeight),
          const Radius.circular(1),
        ),
        _propPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + overhang, y),
              width: plateWidth,
              height: plateHeight),
          const Radius.circular(1),
        ),
        _propPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StickFigurePainter old) =>
      pose != old.pose || equipmentProp != old.equipmentProp;
}

/// Interpolate between two pose maps by factor t (0=start, 1=end).
Map<String, Offset> lerpPose(
    Map<String, Offset> a, Map<String, Offset> b, double t) {
  return {
    for (final key in a.keys)
      if (b.containsKey(key))
        key: Offset.lerp(a[key]!, b[key]!, t)!,
  };
}

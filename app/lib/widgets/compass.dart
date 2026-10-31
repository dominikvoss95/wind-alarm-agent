import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/spot_presentation.dart';

class CompassDial extends StatelessWidget {
  final String direction;
  final Color color;
  final double size;

  const CompassDial({
    super.key,
    required this.direction,
    required this.color,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    final bearing = bearingOf(direction);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter: _DialPainter(
            bearing: bearing ?? 0,
            color: color,
            surface: context.mira.surface2,
            outline: context.mira.outline,
            tick: MiraColors.tick,
            cardinal: context.mira.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bearing == null ? direction : '$direction · ${bearing.round()}°',
          style: context.mira.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  final double bearing;
  final Color color;
  final Color surface;
  final Color outline;
  final Color tick;
  final Color cardinal;

  _DialPainter({
    required this.bearing,
    required this.color,
    required this.surface,
    required this.outline,
    required this.tick,
    required this.cardinal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    canvas.drawCircle(center, radius, Paint()..color = surface);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
    for (var degree = 0; degree < 360; degree += 15) {
      final major = degree % 90 == 0;
      final rad = (degree - 90) * math.pi / 180;
      final outer = radius - 1;
      final inner = radius - (major ? 8 : 5);
      final direction = Offset(math.cos(rad), math.sin(rad));
      canvas.drawLine(
        center + direction * inner,
        center + direction * outer,
        Paint()
          ..color = major ? cardinal : tick
          ..strokeWidth = major ? 1.5 : 1,
      );
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((bearing + 180) * math.pi / 180);
    final path = Path()
      ..moveTo(0, -radius + 14)
      ..lineTo(8, radius - 20)
      ..lineTo(0, radius - 28)
      ..lineTo(-8, radius - 20)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) {
    return oldDelegate.bearing != bearing || oldDelegate.color != color;
  }
}

class SectorCompass extends StatelessWidget {
  final Set<String> sectors;
  final double size;

  const SectorCompass({super.key, required this.sectors, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SectorPainter(
        sectors: sectors,
        accent: context.mira.accent,
        surface: context.mira.surface,
        outline: context.mira.outline,
        idle: context.mira.surface2,
      ),
    );
  }
}

class _SectorPainter extends CustomPainter {
  final Set<String> sectors;
  final Color accent;
  final Color surface;
  final Color outline;
  final Color idle;

  _SectorPainter({
    required this.sectors,
    required this.accent,
    required this.surface,
    required this.outline,
    required this.idle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var index = 0; index < kCompassSectors.length; index++) {
      final active = sectors.contains(kCompassSectors[index]);
      final start = -math.pi / 2 + index * math.pi / 4 - math.pi / 8;
      canvas.drawArc(
        rect,
        start,
        math.pi / 4,
        true,
        Paint()..color = active ? accent.withValues(alpha: 0.85) : outline.withValues(alpha: 0.6),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
    canvas.drawCircle(center, radius * 0.28, Paint()..color = surface);
    canvas.drawCircle(center, 1.5, Paint()..color = idle);
  }

  @override
  bool shouldRepaint(covariant _SectorPainter oldDelegate) {
    return oldDelegate.sectors != sectors;
  }
}

class DirectionArrow extends StatelessWidget {
  final String direction;
  final Color color;

  const DirectionArrow({super.key, required this.direction, required this.color});

  @override
  Widget build(BuildContext context) {
    final bearing = bearingOf(direction) ?? 0;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: context.mira.surface2, shape: BoxShape.circle),
      child: Transform.rotate(
        angle: (bearing + 180) * math.pi / 180,
        child: Icon(Icons.navigation_rounded, size: 20, color: color),
      ),
    );
  }
}

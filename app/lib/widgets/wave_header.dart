import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SpotHero extends StatelessWidget {
  final String? asset;
  final double height;
  final Widget? foreground;

  const SpotHero({super.key, required this.asset, this.height = 200, this.foreground});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MiraColors.heroTop, MiraColors.heroMid, MiraColors.bg],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          const CustomPaint(painter: WavePainter()),
          if (asset != null) _SafeAssetCover(asset: asset!),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                  MiraColors.bg,
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
          ?foreground,
        ],
      ),
    );
  }
}

class _SafeAssetCover extends StatefulWidget {
  final String asset;

  const _SafeAssetCover({required this.asset});

  @override
  State<_SafeAssetCover> createState() => _SafeAssetCoverState();
}

class _SafeAssetCoverState extends State<_SafeAssetCover> {
  ImageStream? _stream;
  ImageInfo? _info;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _SafeAssetCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _listen();
  }

  void _listen() {
    final provider = AssetImage(widget.asset);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _detach();
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _info = info);
      },
      onError: (error, stack) {
        debugPrint('Hero image unavailable (${widget.asset}): $error');
        if (mounted) setState(() => _info = null);
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (image == null) return const SizedBox.shrink();
    return RawImage(image: image, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
  }
}

class WavePainter extends CustomPainter {
  const WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 412;
    final scaleY = size.height / 200;
    for (var index = 0; index < 6; index++) {
      final y = (60 + index * 22) * scaleY;
      final amplitude = 20 * scaleY;
      final path = Path()..moveTo(-20 * scaleX, y);
      path.cubicTo(60 * scaleX, y - amplitude, 120 * scaleX, y + amplitude, 210 * scaleX, y);
      path.cubicTo(300 * scaleX, y - amplitude, 360 * scaleX, y - amplitude, 440 * scaleX, y);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = MiraColors.accent.withValues(alpha: 0.08 + index * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) => false;
}

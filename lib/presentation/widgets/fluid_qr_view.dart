import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

class FluidQrView extends StatefulWidget {
  final String data;
  final double size;
  final Color color;
  final int errorCorrectionLevel;

  const FluidQrView({
    super.key,
    required this.data,
    this.size = 300,
    this.color = Colors.black,
    this.errorCorrectionLevel = QrErrorCorrectLevel.M,
  });

  @override
  State<FluidQrView> createState() => _FluidQrViewState();
}

class _FluidQrViewState extends State<FluidQrView> with SingleTickerProviderStateMixin {
  late QrImage _qrImage;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _generateQr();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void didUpdateWidget(FluidQrView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _generateQr();
      _controller.reset();
      _controller.forward();
    }
  }

  void _generateQr() {
    try {
      final qrCode = QrCode.fromData(
        data: widget.data,
        errorCorrectLevel: widget.errorCorrectionLevel,
      );
      _qrImage = QrImage(qrCode);
    } catch (e) {
      // Fallback or error handling
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: FluidQrPainter(
            qrImage: _qrImage,
            color: widget.color,
            animationValue: _controller.value,
          ),
        );
      },
    );
  }
}

class FluidQrPainter extends CustomPainter {
  final QrImage qrImage;
  final Color color;
  final double animationValue;

  FluidQrPainter({
    required this.qrImage,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final moduleCount = qrImage.moduleCount;
    const margin = 4;
    final totalModules = moduleCount + (margin * 2);
    final cellSize = size.width / totalModules;
    final dotRadius = cellSize / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.9 * animationValue)
      ..style = PaintingStyle.fill
      ..filterQuality = FilterQuality.none;

    bool isFinder(int r, int c) {
      if (r < 7 && c < 7) return true;
      if (r < 7 && c >= moduleCount - 7) return true;
      if (r >= moduleCount - 7 && c < 7) return true;
      return false;
    }

    void drawFinder(double x, double y) {
      final s = 7 * cellSize;
      final outerRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, s, s),
        Radius.circular(cellSize * 2),
      );
      
      final innerRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + cellSize, y + cellSize, s - 2 * cellSize, s - 2 * cellSize),
        Radius.circular(cellSize),
      );
      
      final path = Path.combine(
        PathOperation.difference,
        Path()..addRRect(outerRRect),
        Path()..addRRect(innerRRect),
      );
      
      canvas.drawPath(path, paint);

      // Inner solid circle (matching React code exactly)
      canvas.drawCircle(
        Offset(x + s / 2, y + s / 2),
        1.5 * cellSize,
        paint,
      );
    }

    // Draw Finders
    drawFinder(margin * cellSize, margin * cellSize);
    drawFinder((margin + moduleCount - 7) * cellSize, margin * cellSize);
    drawFinder(margin * cellSize, (margin + moduleCount - 7) * cellSize);

    // Draw Data Modules
    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        if (isFinder(r, c)) continue;

        if (qrImage.isDark(r, c)) {
          final cx = (c + margin) * cellSize + dotRadius;
          final cy = (r + margin) * cellSize + dotRadius;

          // Animate scale and opacity like the React code
          final moduleScale = animationValue;
          
          canvas.drawCircle(
            Offset(cx, cy),
            dotRadius * moduleScale,
            paint,
          );

          // Horizontal connection
          if (c + 1 < moduleCount && !isFinder(r, c + 1) && qrImage.isDark(r, c + 1)) {
            canvas.drawRect(
              Rect.fromLTWH(
                cx,
                cy - dotRadius * moduleScale,
                cellSize,
                dotRadius * 2 * moduleScale,
              ),
              paint,
            );
          }

          // Vertical connection
          if (r + 1 < moduleCount && !isFinder(r + 1, c) && qrImage.isDark(r + 1, c)) {
            canvas.drawRect(
              Rect.fromLTWH(
                cx - dotRadius * moduleScale,
                cy,
                dotRadius * 2 * moduleScale,
                cellSize,
              ),
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FluidQrPainter oldDelegate) {
    return oldDelegate.qrImage != qrImage || 
           oldDelegate.animationValue != animationValue ||
           oldDelegate.color != color;
  }
}

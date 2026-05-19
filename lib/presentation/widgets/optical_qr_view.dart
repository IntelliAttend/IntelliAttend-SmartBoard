import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

const int _finderPatternLimit = 7;

class OpticalQrView extends StatelessWidget {
  const OpticalQrView({
    super.key,
    required this.data,
    this.size = 300,
    this.errorCorrectionLevel = QrErrorCorrectLevel.Q,
  });

  final String data;
  final double size;
  final int errorCorrectionLevel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _OpticalQrPainter(
            data: data,
            errorCorrectionLevel: errorCorrectionLevel,
          ),
          size: Size(size, size),
        ),
      ),
    );
  }
}

class _OpticalQrPainter extends CustomPainter {
  _OpticalQrPainter({
    required String data,
    this.errorCorrectionLevel = QrErrorCorrectLevel.Q,
  }) {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: errorCorrectionLevel,
      );
      _qrImage = QrImage(qrCode);
      _moduleCount = qrCode.moduleCount;
    } catch (e) {
      _fatalError = 'QR encode failed: $e';
    }
    _initPaints();
  }

  final int errorCorrectionLevel;
  QrImage? _qrImage;
  int _moduleCount = 1;
  String? _fatalError;

  late final Paint _pixelPaint;
  late final Paint _finderOuterPaint;
  late final Paint _finderInnerPaint;
  late final Paint _finderDotPaint;

  void _initPaints() {
    _pixelPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    _finderOuterPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    _finderInnerPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    _finderDotPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide == 0) return;

    if (_fatalError != null) {
      _drawError(canvas, size);
      return;
    }

    final containerSize = size.shortestSide;
    final pixelSize = containerSize / _moduleCount;
    final image = _qrImage!;

    // White background plane
    final bgPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, containerSize, containerSize),
      bgPaint,
    );

    // Draw finder patterns (three corner squares)
    final fpSize = _finderPatternLimit * pixelSize;
    final farX = containerSize - fpSize;
    final farY = containerSize - fpSize;

    _drawFinderPattern(canvas, 0.0, 0.0, fpSize, pixelSize);
    _drawFinderPattern(canvas, 0.0, farY, fpSize, pixelSize);
    _drawFinderPattern(canvas, farX, 0.0, fpSize, pixelSize);

    // Draw data modules (gapless, nearest-neighbor)
    // We draw each dark module as a single pixelSize square to avoid
    // corruption caused by incorrect merging logic.
    for (int x = 0; x < _moduleCount; x++) {
      for (int y = 0; y < _moduleCount; y++) {
        if (_isFinderPattern(x, y)) continue;
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * pixelSize, y * pixelSize, pixelSize, pixelSize),
            _pixelPaint,
          );
        }
      }
    }
  }

  void _drawError(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final crossPaint = Paint()
      ..color = const Color(0xFFFF0000)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), crossPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), crossPaint);
  }

  void _drawFinderPattern(
    Canvas canvas,
    double ox,
    double oy,
    double fpSize,
    double pixelSize,
  ) {
    _finderOuterPaint.color = const Color(0xFF000000);
    canvas.drawRect(
      Rect.fromLTWH(ox, oy, fpSize, fpSize),
      _finderOuterPaint,
    );

    final innerSize = fpSize - (2 * pixelSize);
    _finderInnerPaint.color = const Color(0xFFFFFFFF);
    canvas.drawRect(
      Rect.fromLTWH(ox + pixelSize, oy + pixelSize, innerSize, innerSize),
      _finderInnerPaint,
    );

    final dotSize = fpSize - (4 * pixelSize);
    _finderDotPaint.color = const Color(0xFF000000);
    canvas.drawRect(
      Rect.fromLTWH(ox + (2 * pixelSize), oy + (2 * pixelSize), dotSize, dotSize),
      _finderDotPaint,
    );
  }

  bool _isFinderPattern(int x, int y) {
    final isTopLeft = y < _finderPatternLimit && x < _finderPatternLimit;
    final isTopRight =
        x >= _moduleCount - _finderPatternLimit && y < _finderPatternLimit;
    final isBottomLeft =
        y >= _moduleCount - _finderPatternLimit && x < _finderPatternLimit;
    return isTopLeft || isTopRight || isBottomLeft;
  }

  @override
  bool shouldRepaint(covariant _OpticalQrPainter oldDelegate) => true;
}

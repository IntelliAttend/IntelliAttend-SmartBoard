import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';

class QRDisplayPane extends StatelessWidget {
  final String? token;
  final double progress; // 3.5s cycle progress (1.0 to 0.0)

  const QRDisplayPane({super.key, this.token, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white, // White background for optimal QR scanning
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: token != null
              ? QrImageView(
                  data: token!,
                  version: QrVersions.auto,
                  size: 320.0,
                  gapless: true,
                  // Use dark colors for the QR modules on white background
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                )
              : const SizedBox(
                  width: 320,
                  height: 320,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
        const SizedBox(height: 32),
        // Precise Rotation Progress Bar (Visual feedback for students)
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('DYNAMIC TOKEN', style: TextStyle(fontSize: 10, letterSpacing: 2, color: AppColors.textMuted)),
                  Text('${(progress * 3.5).toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress < 0.3 ? Colors.redAccent : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

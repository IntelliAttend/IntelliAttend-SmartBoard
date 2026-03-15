
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';

class QRDisplayPane extends StatelessWidget {
  final String? token;
  final double progress; // For the rotation cycle indicator

  const QRDisplayPane({super.key, this.token, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The QR Code
          if (token != null)
            QrImageView(
              data: token!,
              version: QrVersions.auto,
              size: 400.0,
              gapless: true,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.white,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.white,
              ),
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            )
          else
            const Center(child: CircularProgressIndicator()),
          
          // Rotation Progress Ring
          Positioned(
            bottom: -20,
            child: SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

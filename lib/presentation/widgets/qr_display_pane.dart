import 'package:flutter/material.dart';
import 'optical_qr_view.dart';
import '../../core/theme/app_theme.dart';
import 'glass_container.dart';

class QRDisplayPane extends StatelessWidget {
  final String? token;
  final double progress; // 3.5s cycle progress (1.0 to 0.0)

  const QRDisplayPane({super.key, this.token, required this.progress});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: token != null
                ? Padding(
                    padding: const EdgeInsets.all(64),
                    child: OpticalQrView(
                      data: token!,
                      size: 300,
                    ),
                  )
                : const CircularProgressIndicator(color: AppColors.primary),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: 300,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('DYNAMIC TOKEN', style: Theme.of(context).textTheme.labelLarge),
                    Text('${(progress * 3.5).toStringAsFixed(1)}s', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.white10,
                    color: progress < 0.3 ? AppColors.error : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

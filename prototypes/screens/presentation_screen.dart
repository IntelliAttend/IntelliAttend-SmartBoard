import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PresentationScreen extends StatelessWidget {
  final String courseName;
  final String facultyName;

  const PresentationScreen({
    super.key,
    required this.courseName,
    required this.facultyName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(courseName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(facultyName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf_rounded, size: 120, color: AppColors.primary),
            const SizedBox(height: 24),
            const Text(
              'LECTURE MATERIALS READY',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a file to begin the presentation',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('OPEN SLIDESHOW'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

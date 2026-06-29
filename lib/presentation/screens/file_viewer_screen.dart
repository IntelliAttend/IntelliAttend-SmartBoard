import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';

class FileViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final Uint8List? fileBytes;

  const FileViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.fileBytes,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  String? _textContent;
  List<List<String>>? _csvData;
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final ext = widget.fileName.split('.').last.toLowerCase();
    try {
      final bytes = widget.fileBytes ?? await File(widget.filePath).readAsBytes();
      _imageBytes = bytes;

      if (_isTextFile(ext)) {
        final text = String.fromCharCodes(bytes);
        if (ext == 'csv') {
          _csvData = _parseCsv(text);
        } else {
          _textContent = text;
        }
      } else if (_isImageFile(ext)) {
        // Bytes already loaded
      }
    } catch (e) {
      _error = 'Failed to load file: $e';
      Log.e('[FileViewer] Load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isTextFile(String ext) {
    return ['txt', 'md', 'log', 'csv', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'bat', 'sh', 'html'].contains(ext);
  }

  bool _isImageFile(String ext) {
    return ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
  }

  bool _isOfficeFile(String ext) {
    return ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext);
  }

  List<List<String>> _parseCsv(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.map((l) => l.split(',').map((c) => c.trim()).toList()).toList();
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'doc': case 'docx': return Icons.description_outlined;
      case 'xls': case 'xlsx': return Icons.table_chart_outlined;
      case 'ppt': case 'pptx': return Icons.slideshow_outlined;
      case 'csv': return Icons.table_rows_outlined;
      case 'json': case 'xml': case 'yaml': case 'yml': return Icons.code_outlined;
      case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp': return Icons.image_outlined;
      case 'html': return Icons.language_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.split('.').last.toLowerCase();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(widget.fileName, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isOfficeFile(ext))
            TextButton.icon(
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('Open Externally',
                  style: GoogleFonts.inter(color: AppColors.primaryTeal, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(ext),
    );
  }

  Widget _buildContent(String ext) {
    if (_isTextFile(ext)) {
      return _buildTextViewer(ext);
    }
    if (_isImageFile(ext)) {
      return _buildImageViewer();
    }
    if (ext == 'html') {
      return _buildHtmlViewer();
    }
    if (_isOfficeFile(ext)) {
      return _buildOfficeInfo();
    }
    return _buildUnsupported();
  }

  // ── Text viewer (txt, md, log, json, etc.) ──

  Widget _buildTextViewer(String ext) {
    if (ext == 'csv' && _csvData != null && _csvData!.isNotEmpty) {
      return _buildCsvTable();
    }
    return GestureDetector(
      onVerticalDragUpdate: (_) {},
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          _textContent ?? '',
          style: GoogleFonts.jetBrainsMono(
            color: Colors.white.withValues(alpha: 0.87),
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  // ── CSV table viewer ──

  Widget _buildCsvTable() {
    final headers = _csvData!.isNotEmpty ? _csvData![0] : <String>[];
    final rows = _csvData!.length > 1 ? _csvData!.sublist(1) : <List<String>>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.06)),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          headingTextStyle: GoogleFonts.inter(
            color: AppColors.primaryTeal,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          dataTextStyle: GoogleFonts.jetBrainsMono(
            color: Colors.white.withValues(alpha: 0.80),
            fontSize: 13,
          ),
          columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
          rows: rows.map((row) {
            return DataRow(
              cells: List.generate(headers.length, (i) {
                return DataCell(Text(i < row.length ? row[i] : ''));
              }),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Image viewer ──

  Widget _buildImageViewer() {
    if (_imageBytes == null) return _buildError();
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.memory(
          _imageBytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.broken_image, size: 64, color: Colors.white24),
        ),
      ),
    );
  }

  // ── HTML viewer (raw source) ──

  Widget _buildHtmlViewer() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white.withValues(alpha: 0.04),
          child: Row(
            children: [
              Icon(Icons.language_outlined, color: AppColors.primaryTeal, size: 20),
              const SizedBox(width: 8),
              Text('HTML source preview',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: _openExternally,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Open in Browser',
                    style: GoogleFonts.inter(color: AppColors.primaryTeal, fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              _textContent ?? '',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Office file info (docx, xlsx, pptx) ──

  Widget _buildOfficeInfo() {
    final ext = widget.fileName.split('.').last.toLowerCase();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconForExt(ext), size: 80,
                color: AppColors.primaryTeal.withValues(alpha: 0.6)),
            const SizedBox(height: 24),
            Text(widget.fileName,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('.$ext',
                  style: GoogleFonts.inter(
                      color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 24),
            Text(
              'This file type cannot be previewed inline.\nOpen it with an external application.',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Externally'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Go Back',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 80,
                color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 24),
            Text('Cannot preview this file',
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Go Back'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64,
                color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 20),
            Text('Unable to open document',
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_error != null)
              Text(_error!,
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
                  textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Go Back'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternally() async {
    final uri = Uri.file(widget.filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No app found to open this file',
              style: GoogleFonts.inter(fontSize: 14)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

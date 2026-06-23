import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../core/theme/app_theme.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const DocumentViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  PdfViewerController? _controller;
  int _totalPages = 0;
  int _currentPage = 0;
  double _currentZoom = 1.0;
  bool _controlsVisible = true;
  String? _error;

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  void _goToPreviousPage() {
    if (_currentPage > 1) _controller?.goToPage(pageNumber: _currentPage - 1);
  }

  void _goToNextPage() {
    if (_currentPage < _totalPages) _controller?.goToPage(pageNumber: _currentPage + 1);
  }

  void _showPageJumpDialog() {
    final controller = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Go to Page',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Enter page number (1\u2013$_totalPages)',
            hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryTeal, width: 1.5),
            ),
          ),
          onSubmitted: (value) {
            final page = int.tryParse(value);
            if (page != null && page >= 1 && page <= _totalPages) {
              _controller?.goToPage(pageNumber: page);
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= _totalPages) {
                _controller?.goToPage(pageNumber: page);
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Go', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _zoomIn() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newZoom = (ctrl.currentZoom * 1.25).clamp(0.5, 5.0);
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: newZoom));
  }

  void _zoomOut() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newZoom = (ctrl.currentZoom / 1.25).clamp(0.5, 5.0);
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: newZoom));
  }

  void _zoomReset() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.split('.').last.toLowerCase();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          if (_error != null)
            _buildErrorState(ext)
          else if (ext == 'pdf')
            _buildPdfViewer()
          else
            _buildUnsupportedViewer(ext),

          // Top overlay — filename, page indicator, close
          AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: _toggleControls,
              child: Container(
                height: kToolbarHeight + MediaQuery.of(context).padding.top + 16,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      _controlButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                        tooltip: 'Close (Esc)',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          onTap: _totalPages > 0 ? _showPageJumpDialog : null,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.fileName,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_totalPages > 0) ...[
                                const SizedBox(width: 10),
                                _buildPageChip(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom overlay — zoom bar + page navigation
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: _controlsVisible ? 0 : -120,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: _toggleControls,
              child: Container(
                padding: EdgeInsets.only(
                  top: 28,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: _totalPages > 1
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildZoomBar(),
                          const SizedBox(height: 14),
                          _buildPageNavigation(),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Full-screen tap to toggle controls
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.translucent,
            ),
          ),
        ],
      ),
    );
  }

  bool _onKey(PdfViewerKeyHandlerParams params, LogicalKeyboardKey key, bool isRealKeyPress) {
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goToPreviousPage();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _goToNextPage();
      return true;
    }
    if (key == LogicalKeyboardKey.home) {
      _controller?.goToPage(pageNumber: 1);
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      _controller?.goToPage(pageNumber: _totalPages);
      return true;
    }
    return false;
  }

  // ── Top bar widgets ──

  Widget _buildPageChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryTeal.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pages_rounded, size: 14, color: AppColors.primaryTeal),
          const SizedBox(width: 4),
          Text(
            '$_currentPage / $_totalPages',
            style: GoogleFonts.inter(
              color: AppColors.primaryTeal,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar widgets ──

  Widget _buildZoomBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(
          icon: Icons.zoom_out_rounded,
          onTap: _zoomOut,
          tooltip: 'Zoom Out',
          enabled: _currentZoom > 0.5,
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _zoomReset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              '${(_currentZoom * 100).round()}%',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _iconButton(
          icon: Icons.zoom_in_rounded,
          onTap: _zoomIn,
          tooltip: 'Zoom In',
          enabled: _currentZoom < 5.0,
        ),
        const SizedBox(width: 20),
        Container(width: 1, height: 28, color: Colors.white12),
        const SizedBox(width: 20),
        _iconButton(
          icon: Icons.fit_screen_rounded,
          onTap: _zoomReset,
          tooltip: 'Actual Size (100%)',
        ),
      ],
    );
  }

  Widget _buildPageNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(
          icon: Icons.first_page_rounded,
          onTap: () => _controller?.goToPage(pageNumber: 1),
          tooltip: 'First Page (Home)',
          enabled: _currentPage > 1,
        ),
        const SizedBox(width: 4),
        _iconButton(
          icon: Icons.navigate_before_rounded,
          onTap: _goToPreviousPage,
          tooltip: 'Previous Page (\u2190)',
          enabled: _currentPage > 1,
        ),
        GestureDetector(
          onTap: _showPageJumpDialog,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primaryTeal.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'Page $_currentPage of $_totalPages',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        _iconButton(
          icon: Icons.navigate_next_rounded,
          onTap: _goToNextPage,
          tooltip: 'Next Page (\u2192)',
          enabled: _currentPage < _totalPages,
        ),
        const SizedBox(width: 4),
        _iconButton(
          icon: Icons.last_page_rounded,
          onTap: () => _controller?.goToPage(pageNumber: _totalPages),
          tooltip: 'Last Page (End)',
          enabled: _currentPage < _totalPages,
        ),
      ],
    );
  }

  // ── Shared button widget ──

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white24,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  // ── PDF viewer ──

  Widget _buildPdfViewer() {
    return PdfViewer.file(
      widget.filePath,
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: AppColors.bgDark,
        margin: 8,
        pageDropShadow: BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          spreadRadius: 2,
        ),
        textSelectionParams: PdfTextSelectionParams(enabled: true),
        enableKeyboardNavigation: false,
        onKey: _onKey,
        onDocumentChanged: (doc) {
          if (doc != null && mounted) {
            setState(() => _totalPages = doc.pages.length);
          }
        },
        onViewerReady: (doc, controller) {
          if (mounted) {
            setState(() {
              _controller = controller;
              _totalPages = doc.pages.length;
            });
            controller.addListener(() {
              if (mounted) {
                setState(() => _currentZoom = controller.currentZoom);
              }
            });
          }
        },
        onDocumentLoadFinished: (ref, succeeded) {
          if (!succeeded && mounted) {
            setState(() => _error = 'Failed to load PDF');
          }
        },
        onPageChanged: (pageNumber) {
          if (mounted && pageNumber != null) {
            setState(() => _currentPage = pageNumber);
          }
        },
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
            _buildLoader(),
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            _buildErrorBanner(),
      ),
    );
  }

  // ── States ──

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading document\u2026',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
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
            Text('The file may be corrupted or unsupported.',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String ext) {
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
            Text('The file may be corrupted or unsupported.',
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

  Widget _buildUnsupportedViewer(String ext) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_fileIcon(ext), size: 80,
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
              'This file type cannot be previewed on the board.\nOpen it on a connected device.',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
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

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}

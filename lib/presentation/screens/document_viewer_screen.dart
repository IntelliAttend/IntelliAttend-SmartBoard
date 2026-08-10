import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../core/theme/app_theme.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final Uint8List? fileBytes;

  const DocumentViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.fileBytes,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen>
    with SingleTickerProviderStateMixin {
  PdfViewerController? _controller;
  PdfDocument? _document;
  int _totalPages = 0;
  int _currentPage = 0;
  double _currentZoom = 1.0;
  bool _bottomBarVisible = true;
  String? _error;

  // Search
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  PdfTextSearcher? _textSearcher;
  int _searchMatchCount = 0;
  int _searchCurrentIndex = 0;
  bool _searching = false;

  // Thumbnails
  bool _thumbnailsVisible = false;
  List<Uint8List?> _thumbnails = [];
  bool _thumbnailsLoading = false;

  // Outline / bookmarks
  bool _outlineVisible = false;
  List<PdfOutlineNode>? _outlineNodes;

  // Rotation (cumulative degrees per page)
  final Map<int, int> _pageRotations = {};

  // Scroll mode: false = single page, true = continuous
  bool _continuousScroll = false;

  // Fit mode: false = actual size, true = fit width
  bool _fitToWidth = false;

  // Bottom bar auto-hide timer
  Timer? _bottomBarTimer;

  // Thumbnail scroll controller
  final ScrollController _thumbnailScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _startBottomBarTimer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bottomBarTimer?.cancel();
    _thumbnailScrollCtrl.dispose();
    super.dispose();
  }

  void _startBottomBarTimer() {
    _bottomBarTimer?.cancel();
    _bottomBarTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _bottomBarVisible = false);
    });
  }

  void _toggleBottomBar() {
    setState(() => _bottomBarVisible = !_bottomBarVisible);
    if (_bottomBarVisible) _startBottomBarTimer();
  }

  void _goToPreviousPage() {
    if (_currentPage > 1) _controller?.goToPage(pageNumber: _currentPage - 1);
  }

  void _goToNextPage() {
    if (_currentPage < _totalPages) _controller?.goToPage(pageNumber: _currentPage + 1);
  }

  void _showPageJumpDialog() {
    final ctrl = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Go to Page',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          readOnly: true,
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
              final page = int.tryParse(ctrl.text);
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

  void _rotatePage(int degrees) {
    if (_controller == null) return;
    final current = _pageRotations[_currentPage] ?? 0;
    _pageRotations[_currentPage] = (current + degrees) % 360;
    setState(() {});
    _controller?.goToPage(pageNumber: _currentPage);
  }

  void _toggleFitToWidth() {
    setState(() => _fitToWidth = !_fitToWidth);
    if (_fitToWidth) {
      _applyFitToWidth();
    } else {
      _zoomReset();
    }
  }

  void _applyFitToWidth() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: _fitToWidth ? 1.5 : 1.0));
  }

  void _zoomIn() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newZoom = (ctrl.currentZoom * 1.25).clamp(0.5, 5.0);
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: newZoom));
    if (_fitToWidth) setState(() => _fitToWidth = false);
  }

  void _zoomOut() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newZoom = (ctrl.currentZoom / 1.25).clamp(0.5, 5.0);
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: newZoom));
    if (_fitToWidth) setState(() => _fitToWidth = false);
  }

  void _zoomReset() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final center = ctrl.centerPosition;
    ctrl.goTo(ctrl.calcMatrixFor(center, zoom: 1.0));
  }

  // ── Search ──

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchController.clear();
        _clearSearchHighlights();
      }
    });
    if (_searchVisible) _searchController.clear();
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    _textSearcher?.startTextSearch(query, caseInsensitive: true, goToFirstMatch: true, searchImmediately: true);
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _searchMatchCount = _textSearcher?.matches.length ?? 0;
        _searchCurrentIndex = (_textSearcher?.currentIndex ?? 0);
        _searching = _textSearcher?.isSearching ?? false;
      });
    }
  }

  void _clearSearchHighlights() {
    _textSearcher?.resetTextSearch();
    setState(() {
      _searchMatchCount = 0;
      _searchCurrentIndex = 0;
    });
  }

  void _previousMatch() {
    if (_searchMatchCount == 0) return;
    _textSearcher?.goToPrevMatch();
  }

  void _nextMatch() {
    if (_searchMatchCount == 0) return;
    _textSearcher?.goToNextMatch();
  }

  // ── Thumbnails ──

  Future<void> _loadThumbnails() async {
    if (_document == null || _thumbnails.isNotEmpty) return;
    setState(() => _thumbnailsLoading = true);
    final images = <Uint8List?>[];
    for (int i = 0; i < _totalPages; i++) {
      try {
        final page = _document!.pages[i];
        final h = 150 * page.height / page.width;
        final pdfImage = await page.render(fullWidth: 150, fullHeight: h);
        if (pdfImage != null) {
          final uiImage = await pdfImage.createImage();
          final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          images.add(byteData?.buffer.asUint8List());
          uiImage.dispose();
          pdfImage.dispose();
        } else {
          images.add(null);
        }
      } catch (_) {
        images.add(null);
      }
    }
    if (mounted) {
      setState(() {
        _thumbnails = images;
        _thumbnailsLoading = false;
      });
    }
  }

  Future<void> _loadOutline() async {
    if (_document == null) return;
    try {
      final outline = await _document!.loadOutline();
      if (mounted) setState(() => _outlineNodes = outline);
    } catch (_) {}
  }

  // ── Keyboard ──

  bool _onKey(PdfViewerKeyHandlerParams params, LogicalKeyboardKey key, bool isRealKeyPress) {
    if (key == LogicalKeyboardKey.escape) {
      if (_searchVisible) {
        _toggleSearch();
        return true;
      }
      if (_thumbnailsVisible) {
        setState(() => _thumbnailsVisible = false);
        return true;
      }
      if (_outlineVisible) {
        setState(() => _outlineVisible = false);
        return true;
      }
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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.split('.').last.toLowerCase();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + MediaQuery.of(context).padding.top + 8,
        ),
        child: _buildTopBar(),
      ),
      body: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.of(context).pop();
        },
        child: Stack(
          children: [
            // Main content
            if (_error != null)
              _buildErrorState(ext)
            else if (ext == 'pdf')
              _buildPdfViewer()
            else
              _buildUnsupportedViewer(ext),

            // Full-screen tap target to toggle bottom bar (placed BELOW controls
            // so sidebars and error-state buttons receive taps first)
            if (_error == null && ext == 'pdf')
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleBottomBar,
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                ),
              ),

            // Search bar (conditionally visible)
            if (_searchVisible) _buildSearchBar(),

            // Thumbnail sidebar
            if (_thumbnailsVisible) _buildThumbnailSidebar(),

            // Outline sidebar
            if (_outlineVisible) _buildOutlineSidebar(),

            // Bottom bar (auto-hides)
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ──

  Widget _buildTopBar() {
    return Container(
      height: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.92),
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(width: 4),
            _toolButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
              tooltip: 'Back (Esc)',
            ),
            const SizedBox(width: 6),
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
            // Search
            _toolButton(
              icon: Icons.search_rounded,
              onTap: _toggleSearch,
              tooltip: 'Search (Ctrl+F)',
              active: _searchVisible,
            ),
            // Thumbnails
            _toolButton(
              icon: Icons.grid_view_rounded,
              onTap: () {
                setState(() {
                  _thumbnailsVisible = !_thumbnailsVisible;
                  _outlineVisible = false;
                });
                if (_thumbnailsVisible) _loadThumbnails();
              },
              tooltip: 'Page Thumbnails',
              active: _thumbnailsVisible,
            ),
            // Outline
            _toolButton(
              icon: Icons.toc_rounded,
              onTap: () {
                setState(() {
                  _outlineVisible = !_outlineVisible;
                  _thumbnailsVisible = false;
                });
                if (_outlineVisible && _outlineNodes == null) _loadOutline();
              },
              tooltip: 'Bookmarks',
              active: _outlineVisible,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

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

  // ── Search bar ──

  Widget _buildSearchBar() {
    return Positioned(
      top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  readOnly: true,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search in document\u2026',
                    hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 18, color: Colors.white38),
                            onPressed: () {
                              _searchController.clear();
                              _clearSearchHighlights();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _performSearch(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            if (_searchMatchCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                '${_searchCurrentIndex + 1} / $_searchMatchCount',
                style: GoogleFonts.inter(
                  color: AppColors.primaryTeal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              _miniButton(Icons.chevron_left_rounded, _previousMatch, 'Previous match'),
              _miniButton(Icons.chevron_right_rounded, _nextMatch, 'Next match'),
            ],
            const SizedBox(width: 4),
            if (_searching)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _miniButton(
                Icons.search_rounded,
                _performSearch,
                'Search',
              ),
          ],
        ),
      ),
    );
  }

  // ── Thumbnail sidebar ──

  Widget _buildThumbnailSidebar() {
    return Positioned(
      top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
      left: 0,
      bottom: 80,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            color: const Color(0xF01A1A1A),
            border: Border(
              right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text('Pages',
                        style: GoogleFonts.inter(
                            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _thumbnailsVisible = false),
                      child: Icon(Icons.close, size: 18, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: _thumbnailsLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _thumbnails.isEmpty
                        ? Center(
                            child: Text('Loading\u2026',
                                style: GoogleFonts.inter(color: Colors.white30, fontSize: 13)))
                        : ListView.builder(
                            controller: _thumbnailScrollCtrl,
                            padding: const EdgeInsets.all(8),
                            itemCount: _thumbnails.length,
                            itemBuilder: (context, index) {
                              final isCurrent = index + 1 == _currentPage;
                              return GestureDetector(
                                onTap: () {
                                  _controller?.goToPage(pageNumber: index + 1);
                                  setState(() => _thumbnailsVisible = false);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isCurrent
                                          ? AppColors.primaryTeal
                                          : Colors.white.withValues(alpha: 0.1),
                                      width: isCurrent ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: _thumbnails[index] != null
                                      ? Image.memory(
                                          _thumbnails[index]!,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                        )
                                      : Container(
                                          height: 80,
                                          color: Colors.white.withValues(alpha: 0.04),
                                          child: Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: GoogleFonts.inter(
                                                  color: Colors.white38, fontSize: 13),
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Outline / bookmarks sidebar ──

  Widget _buildOutlineSidebar() {
    return Positioned(
      top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
      left: 0,
      bottom: 80,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            color: const Color(0xF01A1A1A),
            border: Border(
              right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text('Bookmarks',
                        style: GoogleFonts.inter(
                            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _outlineVisible = false),
                      child: Icon(Icons.close, size: 18, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: _outlineNodes == null
                    ? Center(
                        child: Text('No bookmarks in this document',
                            style: GoogleFonts.inter(color: Colors.white30, fontSize: 13)))
                    : ListView(
                        padding: const EdgeInsets.all(8),
                        children: _buildOutlineItems(_outlineNodes!, 0),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOutlineItems(List<PdfOutlineNode> items, int depth) {
    final widgets = <Widget>[];
    for (final item in items) {
      widgets.add(
        GestureDetector(
          onTap: () {
            if (item.dest?.pageNumber != null) {
              _controller?.goToPage(pageNumber: item.dest!.pageNumber);
              setState(() => _outlineVisible = false);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 8.0 + depth * 16,
              top: 4,
              bottom: 4,
              right: 8,
            ),
            child: Text(
              item.title,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      if (item.children.isNotEmpty) {
        widgets.addAll(_buildOutlineItems(item.children, depth + 1));
      }
    }
    return widgets;
  }

  // ── Bottom bar ──

  Widget _buildBottomBar() {
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: _bottomBarVisible ? 0 : -140,
      duration: const Duration(milliseconds: 250),
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: EdgeInsets.only(
            top: 20,
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 12,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_totalPages > 0) ...[
                _buildZoomBar(),
                const SizedBox(height: 10),
                _buildPageNavigation(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(Icons.zoom_out_rounded, _zoomOut, 'Zoom Out', _currentZoom > 0.5),
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
        _iconButton(Icons.zoom_in_rounded, _zoomIn, 'Zoom In', _currentZoom < 5.0),
        const SizedBox(width: 16),
        Container(width: 1, height: 28, color: Colors.white12),
        const SizedBox(width: 16),
        // Fit to width
        _iconButtonToggle(
          Icons.fit_screen_rounded,
          _toggleFitToWidth,
          _fitToWidth ? 'Fit to Width (on)' : 'Fit to Width',
          _fitToWidth,
        ),
        const SizedBox(width: 8),
        // Rotate CW
        _iconButton(Icons.rotate_right_rounded, () => _rotatePage(90), 'Rotate Clockwise', true),
        const SizedBox(width: 8),
        // Continuous scroll
        _iconButtonToggle(
          _continuousScroll ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
          () => setState(() => _continuousScroll = !_continuousScroll),
          _continuousScroll ? 'Continuous Scroll (on)' : 'Single Page',
          _continuousScroll,
        ),
      ],
    );
  }

  Widget _buildPageNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(Icons.first_page_rounded, () => _controller?.goToPage(pageNumber: 1),
            'First Page (Home)', _currentPage > 1),
        const SizedBox(width: 4),
        _iconButton(Icons.navigate_before_rounded, _goToPreviousPage, 'Previous Page (\u2190)',
            _currentPage > 1),
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
        _iconButton(Icons.navigate_next_rounded, _goToNextPage, 'Next Page (\u2192)',
            _currentPage < _totalPages),
        const SizedBox(width: 4),
        _iconButton(Icons.last_page_rounded, () => _controller?.goToPage(pageNumber: _totalPages),
            'Last Page (End)', _currentPage < _totalPages),
      ],
    );
  }

  // ── Shared button widgets ──

  Widget _toolButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? AppColors.primaryTeal.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: active ? AppColors.primaryTeal : Colors.white70,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, String tooltip, bool enabled) {
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

  Widget _iconButtonToggle(IconData icon, VoidCallback onTap, String tooltip, bool active) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? AppColors.primaryTeal.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: active ? AppColors.primaryTeal : Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white70, size: 20),
          ),
        ),
      ),
    );
  }

  // ── PDF viewer ──

  Widget _buildPdfViewer() {
    final params = PdfViewerParams(
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
          _document = doc;
        }
      },
      onViewerReady: (doc, controller) {
        if (mounted) {
          setState(() {
            _controller = controller;
            _totalPages = doc.pages.length;
            _document = doc;
          });
          _textSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
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
          // Scroll thumbnail list to current page
          if (_thumbnailsVisible && pageNumber > 0) {
            final offset = (pageNumber - 1) * 100.0;
            if (_thumbnailScrollCtrl.hasClients) {
              _thumbnailScrollCtrl.animateTo(
                offset.clamp(0, _thumbnailScrollCtrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          }
        }
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => _buildLoader(),
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        if (mounted && _error == null) {
          final msg = error.toString();
          setState(() => _error = msg.length > 120 ? 'Failed to load PDF' : msg);
        }
        return _buildErrorBanner();
      },
      panAxis: _continuousScroll ? PanAxis.vertical : PanAxis.horizontal,
      pagePaintCallbacks: [
        (canvas, pageRect, page) {
          _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
        },
      ],
    );

    if (widget.fileBytes != null) {
      return PdfViewer.data(
        widget.fileBytes!,
        sourceName: widget.filePath,
        controller: _controller,
        params: params,
      );
    }
    return PdfViewer.file(
      widget.filePath,
      controller: _controller,
      params: params,
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
            Text(
              _error ?? 'This file type is not supported for on-device preview.',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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

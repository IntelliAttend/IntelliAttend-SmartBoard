import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/logger.dart';
import '../../models/media_push_event.dart';

class MediaOverlay extends StatefulWidget {
  final MediaPushEvent event;
  final VoidCallback? onClear;

  const MediaOverlay({
    super.key,
    required this.event,
    this.onClear,
  });

  @override
  State<MediaOverlay> createState() => _MediaOverlayState();
}

class _MediaOverlayState extends State<MediaOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isDisposing = false;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    _initMedia();
  }

  Future<void> _initMedia() async {
    if (widget.event.mediaType == 'video') {
      try {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.event.mediaUrl),
        );
        await _videoController!.initialize();
        _videoController!
          ..setLooping(true)
          ..setVolume(0)
          ..play();
        if (mounted) {
          setState(() => _isVideoInitialized = true);
        }
      } catch (e) {
        Log.e('[MediaOverlay] Failed to initialize video: $e');
      }
    }

    if (widget.event.displayDurationSeconds != null && mounted) {
      _durationTimer = Timer(
        Duration(seconds: widget.event.displayDurationSeconds!),
        _autoExpire,
      );
    }
  }

  void _autoExpire() {
    if (_isDisposing || !mounted) return;
    Log.i('[MediaOverlay] Auto-expiring after ${widget.event.displayDurationSeconds}s');
    _dismiss();
  }

  Future<void> _dismiss() async {
    if (_isDisposing) return;
    _isDisposing = true;
    _durationTimer?.cancel();
    await _fadeController.reverse();
    widget.onClear?.call();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _durationTimer?.cancel();
    _videoController?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.event.mediaType == 'video' && _isVideoInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else if (widget.event.mediaType == 'image')
            SizedBox.expand(
              child: Image.network(
                widget.event.mediaUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  Log.e('[MediaOverlay] Failed to load image: $error');
                  return const SizedBox.shrink();
                },
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

void main() {
  runApp(const LottieTestApp());
}

class LottieTestApp extends StatelessWidget {
  const LottieTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lottie Previewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C20),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5252),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF1E1B30),
        ),
      ),
      home: const LottiePreviewScreen(),
    );
  }
}

class LottiePreviewScreen extends StatefulWidget {
  const LottiePreviewScreen({super.key});

  @override
  State<LottiePreviewScreen> createState() => _LottiePreviewScreenState();
}

class _LottiePreviewScreenState extends State<LottiePreviewScreen> with TickerProviderStateMixin {
  late final AnimationController _controller;
  Duration? _originalDuration;
  bool _isLooping = true;
  bool _isPlaying = true;
  double _speed = 1.0;
  String _status = "Playing";
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) {
      setState(() {
        if (status == AnimationStatus.completed) {
          _status = "Completed";
          if (_isLooping) {
            _controller.forward(from: 0.0);
            _isPlaying = true;
            _status = "Playing (Loop)";
          } else {
            _isPlaying = false;
          }
        } else if (status == AnimationStatus.dismissed) {
          _status = "Dismissed";
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_isPlaying) {
        _controller.stop();
        _isPlaying = false;
        _status = "Paused";
      } else {
        if (_controller.status == AnimationStatus.completed) {
          _controller.forward(from: 0.0);
        } else {
          _controller.forward();
        }
        _isPlaying = true;
        _status = "Playing";
      }
    });
  }

  void _restart() {
    setState(() {
      _controller.forward(from: 0.0);
      _isPlaying = true;
      _status = "Playing";
    });
  }

  void _updateSpeed(double newSpeed) {
    setState(() {
      _speed = newSpeed;
      if (_originalDuration != null) {
        _controller.duration = _originalDuration! * (1 / _speed);
        if (_isPlaying) {
          final currentValue = _controller.value;
          _controller.forward(from: currentValue);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient decoration
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.3),
                  radius: 1.2,
                  colors: [
                    Color(0xFF2E1A47),
                    Color(0xFF0F0C20),
                  ],
                ),
              ),
            ),
          ),
          // Ambient Glow behind the Lottie
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5252).withOpacity(0.08),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Title
                    const Text(
                      'LOTTIE ANIMATION PREVIEW',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        color: Color(0xFF9E99B3),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Errorfailure (1).lottie',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Lottie Container
                    Container(
                      width: 340,
                      height: 340,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B30).withOpacity(0.7),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFFFFFFF).withOpacity(0.08),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          else
                            Lottie.asset(
                              'assets/Errorfailure.lottie',
                              controller: _controller,
                              onLoaded: (composition) {
                                setState(() {
                                  _originalDuration = composition.duration;
                                  _controller.duration = _originalDuration! * (1 / _speed);
                                  if (_isPlaying) {
                                    _controller.forward();
                                  }
                                });
                              },
                              decoder: (List<int> bytes) {
                                try {
                                  return LottieComposition.decodeZip(
                                    bytes,
                                    filePicker: (files) {
                                      for (var f in files) {
                                        if (f.name.endsWith('.json') && f.name != 'manifest.json') {
                                          return f;
                                        }
                                      }
                                      throw Exception("No valid .json file found inside the .lottie zip");
                                    },
                                  );
                                } catch (e) {
                                  setState(() {
                                    _errorMessage = e.toString();
                                  });
                                  rethrow;
                                }
                              },
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'Lottie Error:\n$error',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.redAccent),
                                  ),
                                );
                              },
                            ),
                          
                          // Subtle play state indicator badge
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Text(
                                _status.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF5252),
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Playback Controls
                    Card(
                      color: const Color(0xFF161326),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: const Color(0xFFFFFFFF).withOpacity(0.05),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Restart
                                IconButton(
                                  onPressed: _restart,
                                  icon: const Icon(Icons.replay_rounded),
                                  color: Colors.white,
                                  iconSize: 28,
                                  tooltip: 'Restart',
                                ),
                                // Play / Pause
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Color(0xFFFF5252), Color(0xFF7C4DFF)],
                                    ),
                                  ),
                                  child: IconButton(
                                    onPressed: _togglePlay,
                                    icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                    color: Colors.white,
                                    iconSize: 32,
                                    tooltip: _isPlaying ? 'Pause' : 'Play',
                                  ),
                                ),
                                // Loop Toggle
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLooping = !_isLooping;
                                    });
                                  },
                                  icon: Icon(
                                    _isLooping ? Icons.loop_rounded : Icons.trending_flat_rounded,
                                    color: _isLooping ? const Color(0xFFFF5252) : Colors.white60,
                                  ),
                                  iconSize: 28,
                                  tooltip: _isLooping ? 'Looping On' : 'Looping Off',
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 20),
                            // Speed control slider
                            Row(
                              children: [
                                const Icon(Icons.speed, size: 20, color: Colors.white60),
                                const SizedBox(width: 12),
                                const Text(
                                  'Speed:',
                                  style: TextStyle(color: Colors.white60, fontSize: 14),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _speed,
                                    min: 0.25,
                                    max: 2.0,
                                    divisions: 7,
                                    activeColor: const Color(0xFFFF5252),
                                    inactiveColor: const Color(0xFF2E2A40),
                                    label: '${_speed}x',
                                    onChanged: _updateSpeed,
                                  ),
                                ),
                                Text(
                                  '${_speed}x',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Technical Details Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.white38),
                              SizedBox(width: 8),
                              Text(
                                'Lottie Info & Metadata',
                                style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow("Asset Path:", "assets/Errorfailure.lottie"),
                          _buildDetailRow("Archive Content:", "animations/12345.json"),
                          _buildDetailRow("Lottie Package:", "lottie ^3.3.3"),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

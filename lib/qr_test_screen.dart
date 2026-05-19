import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:google_fonts/google_fonts.dart';
import 'presentation/widgets/fluid_qr_view.dart';
import 'services/time_sync_service.dart';

void main() {
  runApp(const MaterialApp(
    home: QrTestScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class QrTestScreen extends StatefulWidget {
  const QrTestScreen({super.key});

  @override
  State<QrTestScreen> createState() => _QrTestScreenState();
}

class _QrTestScreenState extends State<QrTestScreen> {
  // Test Constants
  final String _sessionId = "ANIME-FLUX-2026";
  final String _sessionSecret = "SUPER_HARDWARE_SECRET_999";
  
  String _currentPayload = "";
  String _rawInner = "";
  String _shortText = "INITIALIZING";
  Timer? _timer;
  final Random _secureRandom = Random.secure();

  // Background image URL
  final String _bgImageUrl = "https://images.unsplash.com/photo-1614850523296-d8c1af93d400?q=80&w=2070&auto=format&fit=crop";

  @override
  void initState() {
    super.initState();
    _generate();
    // Rotate every 3.5 seconds to match the React reference
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (timer) {
      setState(() {
        _generate();
      });
    });
  }

  void _generate() {
    // 1. Calculate Corrected Unix Epoch in Milliseconds (Virtual Server Clock).
    final int skewMs = TimeSyncService.getSkew();
    final int timestampMs = DateTime.now().millisecondsSinceEpoch + skewMs;

    // 2. Construct Data String: session_id|timestamp_ms|nonce
    final List<int> nonceBytes = List<int>.generate(4, (_) => _secureRandom.nextInt(256));
    final String nonce = base64.encode(nonceBytes);
    
    _rawInner = '$_sessionId|$timestampMs|$nonce';
    _shortText = nonce.toUpperCase();

    // 3. Encode Assembled Inner String to Standard Base64
    final String base64Payload = base64.encode(utf8.encode(_rawInner));

    // 4. HMAC-SHA256 Cryptographic Signature (64 Hex Chars, full 256-bit)
    final hmac = hmacSha256(_sessionSecret);
    final Digest digest = hmac.convert(utf8.encode(base64Payload));
    final String signatureHex = digest.toString();

    // 5. Final Protocol String: IATT::[Payload]::[Signature]
    _currentPayload = 'IATT::$base64Payload::$signatureHex';

    // Log to console for background output inspection
    debugPrint('--- PROTOCOL DIAGNOSTIC ---');
    debugPrint('RAW_INNER: $_rawInner');
    debugPrint('FINAL_QR : $_currentPayload');
    debugPrint('---------------------------');
  }

  Hmac hmacSha256(String secret) {
    return Hmac(sha256, utf8.encode(secret));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Image Layer (Blurred)
          Opacity(
            opacity: 0.3,
            child: Transform.scale(
              scale: 1.1,
              child: Image.network(
                _bgImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. Main Container (Maximized for Distance Testing)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(80),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 64,
                      offset: const Offset(0, 32),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Inner background image
                    Positioned.fill(
                      child: Image.network(
                        _bgImageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Frosted Glass Overlay
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: Center(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Occupy 85% of the available height for maximum scanning distance
                                final qrSize = constraints.maxHeight * 0.85;
                                return Container(
                                  padding: const EdgeInsets.all(40),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(80),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 64,
                                      ),
                                    ],
                                  ),
                                  child: FluidQrView(
                                    data: _currentPayload,
                                    size: qrSize,
                                    color: Colors.black,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Diagnostic Overlay
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimal Status Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("NONCE:", style: GoogleFonts.firaCode(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(_shortText, style: GoogleFonts.firaCode(color: Colors.white, fontSize: 9)),
                      const SizedBox(width: 20),
                      Text("LEN:", style: GoogleFonts.firaCode(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text("${_currentPayload.length}", style: GoogleFonts.firaCode(color: Colors.white, fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Compact Payload Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: SelectableText(
                    _currentPayload,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaCode(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 9,
                    ),
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


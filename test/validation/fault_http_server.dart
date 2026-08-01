import 'dart:convert';
import 'dart:io';

/// Local fault-injecting HTTP server used by the Phase 1 validation suite.
///
/// Binds to 127.0.0.1 on a random port so the real `http.Client()` in
/// AutoUpdater can stream from it without external network access. Modes:
///   - success (throttled / normal)
///   - truncated body (partial download)
///   - connection reset mid-body
///   - status codes (404 / 500 / 403)
///   - redirect (302)
///   - hang (client timeout)
class FaultHttpServer {
  FaultHttpServer._(this._server);

  final HttpServer _server;

  int get port => _server.port;
  String get base => 'http://127.0.0.1:$port';

  static Future<FaultHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FaultHttpServer._(server);
  }

  /// Serve [bytes] as the installer body.
  ///
  /// [chunkDelay] throttles the transfer (slow-network scenarios).
  /// [maxBytes] truncates the body and closes cleanly (partial download).
  /// [resetAfterBytes] resets the socket mid-body (connection reset).
  /// [statusCode] forces an HTTP error before any body is sent.
  void serveInstaller(
    List<int> bytes, {
    Duration chunkDelay = Duration.zero,
    int chunkSize = 65536,
    int? maxBytes,
    int? resetAfterBytes,
    int statusCode = HttpStatus.ok,
  }) {
    _server.listen((req) async {
      final resp = req.response;
      resp.statusCode = statusCode;
      if (statusCode != HttpStatus.ok) {
        await resp.close();
        return;
      }
      // Connection reset mid-body: `detachSocket()` can only be called before
      // any response bytes are written (afterwards it throws "Headers already
      // sent" and the connection would hang open, never actually injecting the
      // fault). So hand-craft the HTTP response over the raw socket and destroy
      // it once [resetAfterBytes] bytes have been sent.
      if (resetAfterBytes != null) {
        try {
          final socket = await resp.detachSocket();
          final header = 'HTTP/1.1 200 OK\r\n'
              'Content-Length: ${bytes.length}\r\n'
              'Content-Type: application/octet-stream\r\n\r\n';
          final send = resetAfterBytes.clamp(0, bytes.length);
          socket.add(utf8.encode(header));
          socket.add(bytes.sublist(0, send));
          await socket.flush();
          socket.destroy();
          return;
        } catch (_) {
          return;
        }
      }
      resp.headers.contentLength = bytes.length;
      var sent = 0;
      try {
        while (sent < bytes.length) {
          if (maxBytes != null && sent >= maxBytes) {
            break;
          }
          final end = (sent + chunkSize > bytes.length)
              ? bytes.length
              : sent + chunkSize;
          resp.add(bytes.sublist(sent, end));
          sent = end;
          if (chunkDelay > Duration.zero) {
            await Future<void>.delayed(chunkDelay);
          }
        }
        await resp.close();
      } catch (_) {
        // Client reset / aborted — nothing to do.
      }
    });
  }

  /// Serve a 302 redirect to [target].
  void serveRedirect(String target) {
    _server.listen((req) {
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set(HttpHeaders.locationHeader, target);
      req.response.close();
    });
  }

  /// Accept the connection and immediately destroy it (no response).
  void serveReset() {
    _server.listen((req) async {
      try {
        final socket = await req.response.detachSocket();
        socket.destroy();
      } catch (_) {}
    });
  }

  /// Accept the connection but never respond (client-side timeout scenario).
  void serveHang() {
    _server.listen((req) {
      // Intentionally never writes a response.
    });
  }

  Future<void> close() => _server.close(force: true);
}

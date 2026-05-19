import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intelliattend_smartboard/core/platform/kiosk_service.dart';

/// Extracts a named bool from a window_manager method call argument map.
/// These maps use keys like `isFullScreen`, `isPreventClose`, etc.
bool argBool(Object? args, String key) =>
    (args as Map<dynamic, dynamic>)[key] as bool;

/// Drains the microtask queue so fire-and-forget async chains (like the
/// window listener's unawaited setMode call) settle before we assert on the
/// recorded channel calls.
Future<void> drainAsync() async {
  for (int i = 0; i < 20; i++) {
    await Future(() {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> channelCalls;
  late List<Object?> channelArgs;

  setUp(() {
    channelCalls = [];
    channelArgs = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('window_manager'),
      (MethodCall methodCall) async {
        channelCalls.add(methodCall.method);
        channelArgs.add(methodCall.arguments);
        switch (methodCall.method) {
          case 'getBounds':
            return [0.0, 0.0, 1920.0, 1080.0];
          case 'isMinimized':
            return false;
          default:
            return true;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel('window_manager'), null);
  });

  // ---------------------------------------------------------------------------
  // KioskService
  // ---------------------------------------------------------------------------
  group('KioskService', () {
    // ── setMode — fullscreen ───────────────────────────────────────────────
    group('setMode', () {
      test('fullscreen: resizable, always-on-top, fullscreen in order',
          () async {
        await KioskService.setMode(KioskMode.fullscreen);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'setFullScreen',
        ]));
        final resizableIdx = channelCalls.indexOf('setResizable');
        final fullscreenIdx = channelCalls.indexOf('setFullScreen');
        expect(resizableIdx, lessThan(fullscreenIdx));
      });

      test('fullscreen: preventClose true', () async {
        await KioskService.setMode(KioskMode.fullscreen);

        if (Platform.isWindows) {
          final idx = channelCalls.indexOf('setPreventClose');
          expect(idx, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[idx], 'isPreventClose'), isTrue);
        }
      });

      test('fullscreen: skipTaskbar false', () async {
        await KioskService.setMode(KioskMode.fullscreen);

        if (Platform.isWindows) {
          final idx = channelCalls.indexOf('setSkipTaskbar');
          expect(idx, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[idx], 'isSkipTaskbar'), isFalse);
        }
      });
    });

    // ── setMode — locked ──────────────────────────────────────────────────
    group('locked', () {
      test('locked: show → focus → fullscreen → alwaysOnTop', () async {
        await KioskService.setMode(KioskMode.locked);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'show',
          'focus',
          'setFullScreen',
          'setAlwaysOnTop',
        ]));
      });

      test('locked: preventClose true, skipTaskbar true', () async {
        await KioskService.setMode(KioskMode.locked);

        if (Platform.isWindows) {
          final ci = channelCalls.indexOf('setPreventClose');
          expect(ci, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[ci], 'isPreventClose'), isTrue);

          final si = channelCalls.indexOf('setSkipTaskbar');
          expect(si, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[si], 'isSkipTaskbar'), isTrue);
        }
      });
    });

    // ── setMode — absoluteLocked ──────────────────────────────────────────
    group('absoluteLocked', () {
      test('absoluteLocked: locked chain + brightness', () async {
        await KioskService.setMode(KioskMode.absoluteLocked);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'show',
          'focus',
          'setFullScreen',
          'setAlwaysOnTop',
        ]));
      });
    });

    // ── setMode — suspended ───────────────────────────────────────────────
    group('suspended', () {
      test('suspended: alwaysOnTop off, fullscreen off, minimize', () async {
        await KioskService.setMode(KioskMode.suspended);

        expect(channelCalls, containsAllInOrder([
          'setAlwaysOnTop',
          'setFullScreen',
          'setResizable',
          'minimize',
        ]));

        final idx = channelCalls.indexOf('setFullScreen');
        expect(argBool(channelArgs[idx], 'isFullScreen'), isFalse);
      });
    });

    // ── Serialization ─────────────────────────────────────────────────────
    group('serialization', () {
      test('concurrent setMode calls are serialized', () async {
        final results = await Future.wait([
          KioskService.setMode(KioskMode.fullscreen),
          KioskService.setMode(KioskMode.locked),
          KioskService.setMode(KioskMode.suspended),
        ]);

        expect(results, everyElement(isNull));

        // Last mode is suspended → last setFullScreen is false.
        final idx = channelCalls.lastIndexOf('setFullScreen');
        expect(idx, greaterThanOrEqualTo(0));
        expect(argBool(channelArgs[idx], 'isFullScreen'), isFalse);
      });

      test('serializer recovers after thrown error', () async {
        int callCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('window_manager'),
          (MethodCall methodCall) async {
            callCount++;
            channelCalls.add(methodCall.method);
            channelArgs.add(methodCall.arguments);
            if (methodCall.method == 'setAlwaysOnTop') {
              throw PlatformException(code: 'TEST_ERROR');
            }
            return true;
          },
        );

        await KioskService.setMode(KioskMode.fullscreen);
        await KioskService.setMode(KioskMode.locked);
        expect(callCount, greaterThanOrEqualTo(6));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // KioskWindowListener
  // ---------------------------------------------------------------------------
  group('KioskWindowListener', () {
    WindowListener createListener() => KioskService.createWindowListener();

    setUp(() async {
      await KioskService.setMode(KioskMode.fullscreen);
      channelCalls.clear();
      channelArgs.clear();
    });

    // ── onWindowRestore ───────────────────────────────────────────────────
    group('onWindowRestore', () {
      test('restores pre-suspend mode when suspended', () async {
        await KioskService.setMode(KioskMode.fullscreen);
        channelCalls.clear();
        await KioskService.setMode(KioskMode.suspended);
        channelCalls.clear();

        createListener().onWindowRestore();
        await drainAsync();

        // Should have re-applied fullscreen chain.
        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'setFullScreen',
        ]));
        // Last setFullScreen should be true (fullscreen, not false).
        final last = channelCalls.lastIndexOf('setFullScreen');
        expect(last, greaterThanOrEqualTo(0));
        expect(argBool(channelArgs[last], 'isFullScreen'), isTrue);
      });

      test('falls back to fullscreen when _preSuspendMode is null', () async {
        await KioskService.setMode(KioskMode.suspended);
        channelCalls.clear();
        channelArgs.clear();

        createListener().onWindowRestore();
        await drainAsync();

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'setFullScreen',
        ]));
        final last = channelCalls.lastIndexOf('setFullScreen');
        expect(last, greaterThanOrEqualTo(0));
        expect(argBool(channelArgs[last], 'isFullScreen'), isTrue);
      });

      test('re-applies current non-suspended mode', () async {
        await KioskService.setMode(KioskMode.locked);
        channelCalls.clear();

        createListener().onWindowRestore();
        await drainAsync();

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'show',
          'focus',
          'setFullScreen',
          'setAlwaysOnTop',
        ]));
      });
    });

    // ── onWindowMinimize ──────────────────────────────────────────────────
    group('onWindowMinimize', () {
      test('blocks minimize during absoluteLocked', () async {
        await KioskService.setMode(KioskMode.absoluteLocked);
        channelCalls.clear();

        createListener().onWindowMinimize();
        await drainAsync();

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'show',
          'focus',
          'setFullScreen',
          'setAlwaysOnTop',
        ]));
        final last = channelCalls.lastIndexOf('setFullScreen');
        expect(last, greaterThanOrEqualTo(0));
        expect(argBool(channelArgs[last], 'isFullScreen'), isTrue);
      });

      test('allows minimize during fullscreen', () async {
        await KioskService.setMode(KioskMode.fullscreen);
        channelCalls.clear();

        createListener().onWindowMinimize();
        await drainAsync();
        expect(channelCalls, isEmpty);
      });

      test('allows minimize during locked', () async {
        await KioskService.setMode(KioskMode.locked);
        channelCalls.clear();

        createListener().onWindowMinimize();
        await drainAsync();
        expect(channelCalls, isEmpty);
      });

      test('allows minimize during suspended', () async {
        await KioskService.setMode(KioskMode.suspended);
        channelCalls.clear();

        createListener().onWindowMinimize();
        await drainAsync();
        expect(channelCalls, isEmpty);
      });
    });
  });
}

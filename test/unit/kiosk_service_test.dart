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
          case 'isFullScreen':
            return false;
          case 'getId':
            return 12345; // Mock HWND
          default:
            return true;
        }
      },
    );

    // Mock the kiosk platform channel so setMode can call
    // _setBlockSysCommands without throwing MissingPluginException.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('com.intelliattend/kiosk'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel('window_manager'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel('com.intelliattend/kiosk'), null);
  });

  // ---------------------------------------------------------------------------
  // KioskService
  // ---------------------------------------------------------------------------
  group('KioskService', () {
    // ── setMode — fullscreen ───────────────────────────────────────────────
    group('setMode', () {
      test('fullscreen: resizable, always-on-top, show, focus, fullscreen in order',
          () async {
        await KioskService.setMode(KioskMode.fullscreen);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
        ]));
      });

      test('fullscreen: preventClose true', () async {
        await KioskService.setMode(KioskMode.fullscreen);

        if (Platform.isWindows) {
          final idx = channelCalls.indexOf('setPreventClose');
          expect(idx, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[idx], 'isPreventClose'), isTrue);
        }
      });

      test('fullscreen: skipTaskbar true', () async {
        await KioskService.setMode(KioskMode.fullscreen);

        if (Platform.isWindows) {
          final idx = channelCalls.indexOf('setSkipTaskbar');
          expect(idx, greaterThanOrEqualTo(0));
          expect(argBool(channelArgs[idx], 'isSkipTaskbar'), isTrue);
        }
      });
    });

    // ── setMode — locked ──────────────────────────────────────────────────
    group('locked', () {
      test('locked: alwaysOnTop → show → focus → fullscreen', () async {
        await KioskService.setMode(KioskMode.locked);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
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
      test('absoluteLocked: alwaysOnTop → show → focus → fullscreen', () async {
        await KioskService.setMode(KioskMode.absoluteLocked);

        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
        ]));
      });
    });

    // ── setMode — suspended ───────────────────────────────────────────────
    group('suspended', () {
      test('suspended: alwaysOnTop off, fullscreen off, resizable off, minimize', () async {
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
        // Reset to a known state so no cached _currentMode matches.
        await KioskService.setMode(KioskMode.fullscreen, force: true);
        channelCalls.clear();
        channelArgs.clear();

        final results = await Future.wait([
          KioskService.setMode(KioskMode.locked),
          KioskService.setMode(KioskMode.absoluteLocked),
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
            if (methodCall.method == 'setFullScreen') {
              throw PlatformException(code: 'TEST_ERROR');
            }
            // Return false for isFullScreen so the condition check proceeds.
            if (methodCall.method == 'isFullScreen') return false;
            return true;
          },
        );

        await KioskService.setMode(KioskMode.fullscreen);
        await KioskService.setMode(KioskMode.locked);
        // Each call should at least attempt setResizable, setAlwaysOnTop, show,
        // focus, setFullScreen, plus the isFullScreen condition check per mode.
        expect(callCount, greaterThanOrEqualTo(10));
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

    // Force-release after each window-listener test to reset KioskService
    // static state so subsequent tests start with a clean slate.
    tearDown(() async {
      await KioskService.forceRelease();
      channelCalls.clear();
      channelArgs.clear();
    });

    // ── onWindowRestore ───────────────────────────────────────────────────
    group('onWindowRestore', () {
      test('restores pre-suspend mode when suspended', () async {
        await KioskService.setMode(KioskMode.fullscreen);
        channelCalls.clear();
        channelArgs.clear();
        await KioskService.setMode(KioskMode.suspended);
        channelCalls.clear();
        channelArgs.clear();

        createListener().onWindowRestore();
        await drainAsync();

        // Debug: print actual channel state
        // ignore: avoid_print
        print('DEBUG-RESTORE channelCalls: $channelCalls');
        // ignore: avoid_print
        print('DEBUG-RESTORE channelArgs: $channelArgs');
        final last = channelCalls.lastIndexOf('setFullScreen');
        // ignore: avoid_print
        print('DEBUG-RESTORE last: $last');
        if (last >= 0 && last < channelArgs.length) {
          // ignore: avoid_print
          print('DEBUG-RESTORE channelArgs[$last]: ${channelArgs[last]} (${channelArgs[last].runtimeType})');
        }

        // Should have re-applied fullscreen chain.
        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
        ]));
        // Last setFullScreen should be true (fullscreen, not false).
        expect(last, greaterThanOrEqualTo(0));
        // Cast to Map first to check key existence before extraction
        expect(channelArgs[last], isA<Map>());
        expect((channelArgs[last] as Map).containsKey('isFullScreen'), isTrue);
        expect((channelArgs[last] as Map)['isFullScreen'], isTrue);
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
          'show',
          'focus',
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
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
        ]));
      });
    });

    // ── onWindowMinimize ──────────────────────────────────────────────────
    group('onWindowMinimize', () {
      test('blocks minimize during absoluteLocked', () async {
        await KioskService.setMode(KioskMode.absoluteLocked);
        channelCalls.clear();
        channelArgs.clear();

        createListener().onWindowMinimize();
        await drainAsync();

        final last = channelCalls.lastIndexOf('setFullScreen');
        expect(channelCalls, containsAllInOrder([
          'setResizable',
          'setAlwaysOnTop',
          'show',
          'focus',
          'setFullScreen',
        ]));
        expect(last, greaterThanOrEqualTo(0));
        expect(channelArgs[last], isA<Map>());
        expect((channelArgs[last] as Map).containsKey('isFullScreen'), isTrue);
        expect((channelArgs[last] as Map)['isFullScreen'], isTrue);
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

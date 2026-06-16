import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:intelliattend_smartboard/core/auth/token_manager.dart';
import 'package:intelliattend_smartboard/core/errors/auth_exceptions.dart';
import 'package:intelliattend_smartboard/core/security/secure_storage_service.dart';

/// Helper: a [MockClient] request handler that returns a successful
/// token-refresh response.
http.Response _successfulRefreshResponse(http.Request request) {
  return http.Response(
    '{"id_token":"refreshed_id_token","refresh_token":"new_rt","expires_in":"3600"}',
    200,
  );
}

void main() {
  setUp(() async {
    await dotenv.load(isOptional: true, mergeWith: {'FIREBASE_API_KEY': 'test_firebase_key'});
    FlutterSecureStorage.setMockInitialValues({});
    TokenManager.resetInstance();
  });

  tearDown(() {
    dotenv.clean();
  });

  group('executeHardReAuth', () {
    test('throws NoCredentialsException when no board credentials stored',
        () async {
      // Storage is completely empty — nothing to re-auth with.
      await expectLater(
        () => TokenManager().executeHardReAuth(),
        throwsA(isA<NoCredentialsException>()),
      );
    });
  });

  group('getValidToken', () {
    test('deduplicates concurrent refresh into a single HTTP call', () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';

      await SecureStorageService.storeRefreshToken('test_refresh_token');

      int callCount = 0;
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });

      // ── Act ─────────────────────────────────────────────────────────
      // Fire 5 concurrent requests — they should all resolve to the same
      // single future, resulting in just 1 HTTP call.
      final results = await Future.wait([
        TokenManager().getValidToken(),
        TokenManager().getValidToken(),
        TokenManager().getValidToken(),
        TokenManager().getValidToken(),
        TokenManager().getValidToken(),
      ]);

      // ── Assert ──────────────────────────────────────────────────────
      expect(callCount, equals(1),
          reason: 'Only one refresh should hit the wire regardless of '
              'how many callers arrive concurrently.');
      for (final token in results) {
        expect(token, equals('refreshed_id_token'));
      }
    });

    test('returns cached token on subsequent calls within 5-min buffer',
        () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';

      await SecureStorageService.storeRefreshToken('test_refresh_token');

      int callCount = 0;
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });

      // ── Act ─────────────────────────────────────────────────────────
      // First call hits the network.
      final first = await TokenManager().getValidToken();
      // Second call should hit the memory cache (no network).
      final second = await TokenManager().getValidToken();

      // ── Assert ──────────────────────────────────────────────────────
      expect(callCount, equals(1),
          reason: 'Second call must use memory cache — 0 network calls.');
      expect(first, equals('refreshed_id_token'));
      expect(second, equals(first));
    });

    test('forceRefresh bypasses memory cache', () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';

      await SecureStorageService.storeRefreshToken('test_refresh_token');

      int callCount = 0;
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });

      // ── Act ─────────────────────────────────────────────────────────
      // Warm the cache.
      await TokenManager().getValidToken();
      // Force-refresh should bypass cache and hit the network again.
      final forced = await TokenManager().getValidToken(forceRefresh: true);

      // ── Assert ──────────────────────────────────────────────────────
      expect(callCount, equals(2),
          reason: 'forceRefresh must bypass the memory cache.');
      expect(forced, equals('refreshed_id_token'));
    });

    test('falls through to hard re-auth when refresh token is missing',
        () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';
      // No refresh token in storage — forces fall-through to hard re-auth.
      // No board credentials either — so it throws NoCredentialsException.

      // ── Act / Assert ────────────────────────────────────────────────
      await expectLater(
        () => TokenManager().getValidToken(),
        throwsA(isA<NoCredentialsException>()),
      );
    });
  });

  group('invalidateCache', () {
    test('clears in-memory state', () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';

      await SecureStorageService.storeRefreshToken('test_refresh_token');

      int callCount = 0;
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });

      // Warm the cache.
      await TokenManager().getValidToken();

      // ── Act ─────────────────────────────────────────────────────────
      TokenManager().invalidateCache();
      // After invalidation the next call should refresh again.
      await TokenManager().getValidToken();

      // ── Assert ──────────────────────────────────────────────────────
      expect(callCount, equals(2),
          reason:
              'After invalidation the cache miss must trigger a new refresh.');
    });
  });

  group('resetInstance', () {
    test('produces a fresh singleton with empty cache', () async {
      // ── Arrange ─────────────────────────────────────────────────────
      dotenv.env['FIREBASE_API_KEY'] = 'test_firebase_key';
      await SecureStorageService.storeRefreshToken('test_refresh_token');

      int callCount = 0;
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });

      // Warm cache on old instance.
      await TokenManager().getValidToken();

      // ── Act ─────────────────────────────────────────────────────────
      TokenManager.resetInstance();

      // New instance has no cache — must refresh.
      TokenManager().client = MockClient((request) async {
        callCount++;
        return _successfulRefreshResponse(request);
      });
      await TokenManager().getValidToken();

      // ── Assert ──────────────────────────────────────────────────────
      expect(callCount, equals(2),
          reason:
              'resetInstance wipes the singleton — second call is a cache miss.');
    });
  });
}

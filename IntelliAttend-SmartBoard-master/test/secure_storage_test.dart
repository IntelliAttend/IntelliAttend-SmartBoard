import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/security/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  group('SecureStorageService Verification', () {
    const testApiKey = 'test_api_key_12345';
    const testToken = 'test_access_token_67890';
    
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('should store and retrieve API key', () async {
      await SecureStorageService.storeApiKey(testApiKey);
      final retrieved = await SecureStorageService.getApiKey();
      expect(retrieved, testApiKey);
    });

    test('should store and retrieve valid access token', () async {
      final expiry = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      await SecureStorageService.storeAccessToken(testToken, expiry);
      final retrieved = await SecureStorageService.getValidAccessToken();
      expect(retrieved, testToken);
    });

    test('should return null for expired access token', () async {
      final expiry = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      await SecureStorageService.storeAccessToken(testToken, expiry);
      final retrieved = await SecureStorageService.getValidAccessToken();
      expect(retrieved, isNull);
    });

    test('should clear all tokens', () async {
      await SecureStorageService.storeApiKey(testApiKey);
      await SecureStorageService.clearAll();
      final retrieved = await SecureStorageService.getApiKey();
      expect(retrieved, isNull);
    });
  });
}

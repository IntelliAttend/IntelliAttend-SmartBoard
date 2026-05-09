import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../services/hardware_fingerprint_service.dart';
import '../../services/secure_storage_service.dart';
import '../../core/utils/logger.dart';

abstract class IAuthRepository {
  Future<Map<String, dynamic>?> login(String boardId, String password);
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp);
  Future<bool> completeBinding(String verificationToken);
}

class AuthRepository implements IAuthRepository {
  final ApiClient apiClient;

  AuthRepository(this.apiClient);

  @override
  Future<Map<String, dynamic>?> login(String boardId, String password) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/auth/device/login',
        data: {
          'board_id': boardId,
          'password': password,
        },
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] Login failed: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/auth/device/verify',
        data: {
          'board_id': boardId,
          'otp': otp,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] Verify OTP failed: $e');
      return null;
    }
  }

  @override
  Future<bool> completeBinding(String verificationToken) async {
    try {
      final hardwareId = await HardwareFingerprintService.getDeviceId();
      
      final response = await apiClient.dio.post(
        '/api/v1/auth/device/complete',
        data: {
          'verification_token': verificationToken,
          'hardware_id': hardwareId,
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        
        // Store tokens securely
        final accessToken = data['access_token']?.toString();
        final refreshToken = data['refresh_token']?.toString();
        final expiresIn = data['expires_in'] ?? 3600;
        
        if (accessToken != null) {
          final expiry = DateTime.now().millisecondsSinceEpoch + (expiresIn as int) * 1000;
          await SecureStorageService.storeAccessToken(accessToken, expiry);
        }
        
        if (refreshToken != null) {
          await SecureStorageService.storeRefreshToken(refreshToken);
        }
        
        return true;
      }
      return false;
    } catch (e) {
      Log.e('[AuthRepository] Complete Binding failed: $e');
      return false;
    }
  }
}

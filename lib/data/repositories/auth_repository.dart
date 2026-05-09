import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:isar/isar.dart';
import '../../core/network/api_client.dart';
import '../../models/isar_schemas.dart';
import '../../services/hardware_fingerprint_service.dart';
import '../../services/secure_storage_service.dart';
import '../../core/utils/logger.dart';

abstract class IAuthRepository {
  Future<Map<String, dynamic>?> login(String boardId, String password);
  Future<Map<String, dynamic>?> initiateRegistration(String boardId, String password);
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp);
  Future<Map<String, dynamic>?> completeRegistration(String boardId, String hardwareId, String verificationToken);
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar);
  Future<void> logout();
}

class AuthRepository implements IAuthRepository {
  final ApiClient apiClient;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthRepository(this.apiClient);

  @override
  Future<Map<String, dynamic>?> login(String boardId, String password) async {
    try {
      Log.i('[AuthRepository] Attempting Firebase Login for Board: $boardId');
      
      // SmartBoard ID is mapped to a lowercase email format as per Accountable Device spec.
      final email = boardId.contains('@') ? boardId.toLowerCase() : '${boardId.toLowerCase()}@smartboard.intelliattend.com';
      
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return null;

      final doc = await _firestore.collection('smart_boards').doc(boardId).get();
      
      bool isRegistered = false;
      String? adminEmail;
      Map<String, dynamic>? profile;

      if (doc.exists) {
        final data = doc.data()!;
        isRegistered = data['is_registered'] ?? false;
        adminEmail = data['admin_email'];
        if (isRegistered) {
          profile = {
            'smart_board_id': boardId,
            'room_id': data['room_id'],
            'room_name': data['room_name'],
            'building': data['building'],
            'department': data['department'],
          };
        }
      }

      return {
        'uid': user.uid,
        'email': user.email,
        'is_registered': isRegistered,
        'admin_email': adminEmail ?? 'IT Administrator',
        'profile': profile,
      };
    } on FirebaseAuthException catch (e) {
      Log.e('[AuthRepository] Firebase Login failed: ${e.code}');
      rethrow;
    } catch (e) {
      Log.e('[AuthRepository] Unexpected login error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> initiateRegistration(String boardId, String password) async {
    try {
      // Phase 2: Ignition Login (Trigger OTP)
      final response = await apiClient.dio.post(
        '/api/v1/device/register/login',
        data: {
          'smart_board_id': boardId,
          'password': password,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] Initiate Registration failed: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/device/register/verify',
        data: {
          'smart_board_id': boardId,
          'otp': otp,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] OTP Verification failed: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> completeRegistration(
    String boardId, 
    String hardwareId, 
    String verificationToken
  ) async {
    try {
      // Phase 3: Hardware Binding
      final idToken = await _auth.currentUser?.getIdToken();
      
      final response = await apiClient.dio.post(
        '/api/v1/device/register/complete',
        options: Options(
          headers: idToken != null ? {'Authorization': 'Bearer $idToken'} : null,
        ),
        data: {
          'smart_board_id': boardId,
          'hardware_id': hardwareId,
          'verification_token': verificationToken,
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        
        final accessToken = data['access_token']?.toString();
        final refreshToken = data['refresh_token']?.toString();
        
        if (accessToken != null) {
          await SecureStorageService.storeAccessToken(accessToken, DateTime.now().millisecondsSinceEpoch + 3600000);
        }
        if (refreshToken != null) {
          await SecureStorageService.storeRefreshToken(refreshToken);
        }

        // Store hardwareId as ApiKey for heartbeat tracking
        await SecureStorageService.storeApiKey(hardwareId);
        
        return data;
      }
      return null;
    } catch (e) {
      Log.e('[AuthRepository] Complete Registration failed: $e');
      return null;
    }
  }

  @override
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar) async {
    final reg = DeviceRegistration()
      ..smartBoardId = profile['smart_board_id'] ?? 'UNKNOWN'
      ..classroomId = profile['room_id'] ?? 'UNKNOWN'
      ..roomName = profile['room_name'] ?? 'Unknown'
      ..building = profile['building'] ?? 'Unknown'
      ..department = profile['department'] ?? 'Unknown'
      ..capacity = profile['capacity'] ?? 60
      ..hardwareId = await HardwareFingerprintService.getDeviceId()
      ..registrationDate = DateTime.now();

    await isar.writeTxn(() async {
      await isar.deviceRegistrations.put(reg);
    });
    Log.i('[AuthRepository] Device Registration cached to Isar.');
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    await SecureStorageService.clearAll();
    Log.i('[AuthRepository] User logged out.');
  }
}

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:isar/isar.dart';
import '../../core/network/api_client.dart';
import '../../models/isar_schemas.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';

abstract class IAuthRepository {
  Future<Map<String, dynamic>?> login(String boardId, String password);
  Future<Map<String, dynamic>?> initiateRegistration(String boardId, String password);
  Future<Map<String, dynamic>?> verifyOtp(String boardId, String otp);
  Future<Map<String, dynamic>?> completeRegistration(String boardId, String hardwareId, String verificationToken);
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar, {String? hardwareId});
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
        // Contract field is 'it_admin_email'; fall back to 'admin_email' for legacy docs
        adminEmail = data['it_admin_email'] ?? data['admin_email'];
        if (isRegistered) {
          profile = {
            'smart_board_id': boardId,
            // Contract field is 'classroom_id'; fall back to 'room_id' for legacy docs
            'room_id': data['classroom_id'] ?? data['room_id'],
            'room_name': data['room_name'],
            'building': data['building'],
            'department': data['department'],
            'capacity': data['capacity'],
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
      // Phase 2 — Contract v1.1: POST /register/login with NO request body.
      // Identity is conveyed entirely via the Firebase ID Token in the
      // Authorization header (obtained from the signInWithEmailAndPassword
      // call that preceded this step in RegistrationProvider.login()).
      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) {
        Log.e('[AuthRepository] Initiate Registration: no Firebase ID token — user not signed in');
        return null;
      }

      final response = await apiClient.dio.post(
        '/api/v1/device/register/login',
        options: Options(
          headers: {'Authorization': 'Bearer $idToken'},
        ),
        // No body — contract v1.1 Step 1 is identity-from-token only.
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status >= 500) {
        // 5xx: infrastructure error (e.g. Cloudflare 502).
        // The origin server likely processed the request and sent the OTP before
        // the response was lost. Re-throw so the provider can decide to show the
        // OTP entry screen rather than a hard failure.
        Log.w('[AuthRepository] Initiate Registration got $status — OTP may have been sent. Re-throwing for caller.');
        rethrow;
      }
      Log.e('[AuthRepository] Initiate Registration failed ($status): $e');
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
      // Phase 3: Hardware Binding — collect metadata in parallel with token fetch
      final results = await Future.wait([
        HardwareFingerprintService.getHardwareMetadata(),
        _auth.currentUser?.getIdToken() ?? Future.value(null),
      ]);

      final metadata = results[0] as Map<String, dynamic>;
      final idToken = results[1] as String?;

      final response = await apiClient.dio.post(
        '/api/v1/device/register/complete',
        options: Options(
          headers: idToken != null ? {'Authorization': 'Bearer $idToken'} : null,
        ),
        data: {
          'smart_board_id': boardId,
          'hardware_id': hardwareId,
          'verification_token': verificationToken,
          'metadata': metadata,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // Sign in with custom token from server to get a proper Firebase session
        // with role: smartboard claims.
        //
        // IMPORTANT: signInWithCustomToken() is NOT allowed to block registration.
        // The server has already:
        //   1. Bound the hardware_id
        //   2. Set the board status to ACTIVE
        //   3. Returned the full registration profile
        //
        // If the custom token is stale/expired (server-side caching bug where the
        // server returns a pre-generated token from a previous 502'd attempt),
        // Firebase SDK throws [firebase_auth/invalid-custom-token]. We catch this,
        // fall back to storing the refresh token from the existing email/password
        // session (which is still valid), and continue registration normally.
        // The missing "role: smartboard" claims will be resolved when the server
        // fixes its token generation; the device will work in the interim.
        final customToken = data['custom_token']?.toString();
        if (customToken != null) {
          try {
            await _auth.signInWithCustomToken(customToken);
            Log.i('[AuthRepository] signInWithCustomToken succeeded — role:smartboard claims active.');
          } catch (tokenError) {
            // Custom token rejected (expired, malformed, or stale from server cache).
            // Fall back: keep the existing signInWithEmailAndPassword session.
            Log.w('[AuthRepository] signInWithCustomToken failed ($tokenError). '
                'Using email/password session as fallback. '
                'Notify server team: custom_token may be stale/pre-cached.');
          }
        }

        // Store whatever refresh token the current session has — whether that
        // came from signInWithCustomToken or the original email/password sign-in.
        final firebaseRefreshToken = _auth.currentUser?.refreshToken;
        if (firebaseRefreshToken != null && firebaseRefreshToken.isNotEmpty) {
          await SecureStorageService.storeRefreshToken(firebaseRefreshToken);
          Log.i('[AuthRepository] Firebase refresh token stored.');
        } else {
          Log.w('[AuthRepository] No refresh token available — boot screen token check will force re-registration.');
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
  Future<void> saveRegistration(Map<String, dynamic> profile, Isar isar, {String? hardwareId}) async {
    final resolvedHardwareId = hardwareId ?? await HardwareFingerprintService.getDeviceId();
    final reg = DeviceRegistration()
      ..smartBoardId = profile['smart_board_id'] ?? profile['board_id'] ?? 'UNKNOWN'
      // Contract uses 'classroom_id'; RegistrationProvider maps it to 'room_id'
      ..classroomId = profile['room_id'] ?? profile['classroom_id'] ?? 'UNKNOWN'
      ..roomName = profile['room_name'] ?? 'Unknown'
      ..building = profile['building'] ?? 'Unknown'
      ..department = profile['department'] ?? 'Unknown'
      ..capacity = profile['capacity'] ?? 60
      ..hardwareId = resolvedHardwareId
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

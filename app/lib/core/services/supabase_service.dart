import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get client => _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Helper to hash emergency password client-side before storing or transmitting
  String hashEmergencyPassword(String rawPassword, String salt) {
    final bytes = utf8.encode(salt + rawPassword);
    final digest = sha256.convert(bytes);
    return '$salt\$$digest';
  }

  /// Sign In with Email & Password
  Future<AuthResponse> signIn(String email, String password) async {
    return await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sign Up with Profile Metadata (Full Name, Phone, Community Responder, Emergency Duress Password)
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    bool isCommunityResponder = false,
    String? emergencyPassword,
  }) async {
    String? emergencyHash;
    if (emergencyPassword != null && emergencyPassword.isNotEmpty) {
      final salt = DateTime.now().millisecondsSinceEpoch.toString();
      emergencyHash = hashEmergencyPassword(emergencyPassword, salt);
    }

    final data = <String, dynamic>{
      'full_name': fullName.trim(),
      'phone_number': phone.trim(),
      'is_community_responder': isCommunityResponder,
    };
    if (emergencyHash != null) {
      data['emergency_password_hash'] = emergencyHash;
    }

    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: data,
    );

    // Direct insertion backup in case trigger is not yet installed on remote Supabase instance
    if (response.user != null) {
      try {
        final upsertData = <String, dynamic>{
          'id': response.user!.id,
          'full_name': fullName.trim(),
          'phone_number': phone.trim(),
          'email': email.trim(),
          'is_community_responder': isCommunityResponder,
          'responder_status': isCommunityResponder ? 'available' : null,
          'responder_opted_in_at': isCommunityResponder ? DateTime.now().toIso8601String() : null,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (emergencyHash != null) {
          upsertData['emergency_password_hash'] = emergencyHash;
        }
        await _client.from('users').upsert(upsertData);
      } catch (e) {
        // Surface the real error for debugging
        debugPrint('[SUPABASE ERROR] Failed inserting into public.users: $e');
      }

      // Also sync with FastAPI backend so it shows up in backend console & database
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final syncUri = Uri.parse('$backendBase/users/profile');
        debugPrint('[BACKEND SYNC] Syncing user profile to: $syncUri');
        http.post(
          syncUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': response.user!.id,
            'full_name': fullName.trim(),
            'phone_number': phone.trim(),
            'email': email.trim(),
            'is_community_responder': isCommunityResponder,
            'emergency_password': emergencyPassword,
          }),
        ).catchError((_) => http.Response('{}', 500));
      } catch (backendErr) {
        debugPrint('[BACKEND SYNC NOTICE] Backend sync optional: $backendErr');
      }
    }

    return response;
  }

  /// Sign Out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Check whether MFA is required for the current session (e.g. user is at AAL1 but enrolled in AAL2)
  bool isMfaChallengeRequired() {
    final aal = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
           aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
  }

  /// Start enrolling TOTP MFA factor. Returns AuthMFAEnrollResponse.
  Future<AuthMFAEnrollResponse> enrollTotpMfa({String friendlyName = 'SafeGuard Authenticator'}) async {
    return await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: friendlyName,
    );
  }

  /// Verify and activate a newly enrolled TOTP MFA factor
  Future<AuthMFAVerifyResponse> verifyMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    return await _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// Verify an MFA challenge during login (elevates session from AAL1 to AAL2)
  Future<AuthMFAVerifyResponse> verifyMfaLogin({
    required String factorId,
    required String code,
  }) async {
    return await _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// List enrolled MFA factors for the current user
  Future<List<Factor>> listMfaFactors() async {
    final response = await _client.auth.mfa.listFactors();
    return response.all;
  }

  /// Unenroll an MFA factor
  Future<AuthMFAUnenrollResponse> unenrollMfaFactor(String factorId) async {
    return await _client.auth.mfa.unenroll(factorId);
  }

  /// Send password reset OTP code directly to email (Pure 6-digit OTP, no localhost links)
  Future<void> sendPasswordResetEmail(String email) async {
    // Send 6-digit OTP code directly to email (avoids localhost redirect links)
    await _client.auth.signInWithOtp(email: email.trim());
  }

  /// Verify OTP sent via email for password recovery
  Future<AuthResponse> verifyRecoveryOtp({
    required String email,
    required String otp,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        email: email.trim(),
        token: otp.trim(),
        type: OtpType.magiclink,
      );
    } catch (_) {
      try {
        return await _client.auth.verifyOTP(
          email: email.trim(),
          token: otp.trim(),
          type: OtpType.email,
        );
      } catch (_) {
        return await _client.auth.verifyOTP(
          email: email.trim(),
          token: otp.trim(),
          type: OtpType.recovery,
        );
      }
    }
  }

  /// Update user profile details in public.users
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    bool? isCommunityResponder,
  }) async {
    final Map<String, dynamic> updates = {
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (fullName != null && fullName.trim().isNotEmpty) {
      updates['full_name'] = fullName.trim();
    }
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      updates['phone_number'] = phoneNumber.trim();
    }
    if (isCommunityResponder != null) {
      updates['is_community_responder'] = isCommunityResponder;
      updates['responder_status'] = isCommunityResponder ? 'available' : 'unavailable';
      if (isCommunityResponder) {
        updates['responder_opted_in_at'] = DateTime.now().toIso8601String();
      } else {
        updates['responder_opted_out_at'] = DateTime.now().toIso8601String();
      }
    }
    await _client.from('users').update(updates).eq('id', userId);

    try {
      await _client.auth.updateUser(UserAttributes(
        data: {
          if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
          if (phoneNumber != null && phoneNumber.trim().isNotEmpty) 'phone': phoneNumber.trim(),
        },
      ));
    } catch (_) {}
  }


  /// Update password once recovery session is active or user is logged in
  Future<UserResponse> updatePassword(String newPassword) async {
    return await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Fetch full user profile from public.users table
  Future<UserModel?> fetchUserProfile(String userId) async {
    try {
      final res = await _client.from('users').select().eq('id', userId).maybeSingle();
      if (res == null) return null;
      return UserModel.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  /// Set or update Emergency Duress Password
  Future<void> updateEmergencyPassword({
    required String userId,
    required String emergencyPassword,
  }) async {
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    final hash = hashEmergencyPassword(emergencyPassword, salt);
    await _client.from('users').update({
      'emergency_password_hash': hash,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Opt-in or opt-out of Community Responder mode
  Future<void> toggleCommunityResponder({
    required String userId,
    required bool optIn,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _client.from('users').update({
      'is_community_responder': optIn,
      'responder_status': optIn ? 'available' : 'unavailable',
      if (optIn) 'responder_opted_in_at': now,
      if (!optIn) 'responder_opted_out_at': now,
      'updated_at': now,
    }).eq('id', userId);
  }

  /// Send 6-digit OTP code to email for login or email confirmation
  Future<void> sendEmailOtp(String email) async {
    await _client.auth.signInWithOtp(email: email.trim());
  }

  /// Verify 6-digit OTP code received via email
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
    OtpType type = OtpType.magiclink,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: type,
    );
  }

  /// Sign In with Google via OAuth
  Future<bool> signInWithGoogle() async {
    return await _client.auth.signInWithOAuth(OAuthProvider.google);
  }
}

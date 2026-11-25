import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;
  HttpServer? _oauthLoopbackServer;
  Timer? _oauthServerTimeout;

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
    String? avatarUrl,
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
      'avatar_url': ?avatarUrl,
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
          'avatar_url': avatarUrl ?? 'guardian',
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

  /// Ensures an OAuth user (e.g. Google Sign-In) has a valid row in `public.users`.
  /// Generates a unique placeholder phone number if Google did not provide one so
  /// the `phone_number UNIQUE NOT NULL` constraint is always satisfied.
  Future<UserModel> ensureOAuthUserProfile(User user) async {
    final existing = await fetchUserProfile(user.id);
    if (existing != null) return existing;

    final meta = user.userMetadata ?? const <String, dynamic>{};
    final email = (user.email ?? meta['email']?.toString() ?? '').trim();
    String fullName = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
    if (fullName.isEmpty) {
      if (email.contains('@')) {
        final prefix = email.split('@').first;
        fullName = prefix.isNotEmpty
            ? prefix[0].toUpperCase() + prefix.substring(1)
            : 'SafeLink User';
      } else {
        fullName = 'SafeLink User';
      }
    }

    String phone = (meta['phone_number'] ?? meta['phone'] ?? user.phone ?? '').toString().trim();
    if (phone.isEmpty) {
      // Unique deterministic fallback phone derived from UUID hex digits
      final hexDigits = user.id.replaceAll('-', '').codeUnits
          .map((c) => (c % 10).toString())
          .take(6)
          .join();
      phone = '+254700$hexDigits';
    }

    final avatarUrl = (meta['avatar_url'] ?? meta['picture'] ?? 'guardian').toString();
    final isResponder = meta['is_community_responder'] as bool? ?? false;
    final nowIso = DateTime.now().toIso8601String();

    try {
      await _client.from('users').upsert({
        'id': user.id,
        'full_name': fullName,
        'phone_number': phone,
        'email': email.isNotEmpty ? email : null,
        'avatar_url': avatarUrl,
        'is_community_responder': isResponder,
        'responder_status': isResponder ? 'available' : null,
        'updated_at': nowIso,
      });
    } catch (e) {
      debugPrint('[OAUTH PROFILE] Upsert notice: $e');
    }

    return await fetchUserProfile(user.id) ??
        UserModel(
          id: user.id,
          fullName: fullName,
          phoneNumber: phone,
          email: email,
          avatarUrl: avatarUrl,
          isCommunityResponder: isResponder,
          hasWearable: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
  }

  /// Sign Out
  Future<void> signOut() async {
    await _stopOAuthLoopbackServer();
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

  /// Send password reset instructions via Supabase
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
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
        type: OtpType.recovery,
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
          type: OtpType.magiclink,
        );
      }
    }
  }

  /// Update user profile details in public.users
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? avatarUrl,
    bool? isCommunityResponder,
    String? responderStatus,
    double? lastLat,
    double? lastLng,
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
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      updates['avatar_url'] = avatarUrl.trim();
    }
    if (isCommunityResponder != null) {
      updates['is_community_responder'] = isCommunityResponder;
      updates['responder_status'] = responderStatus ?? (isCommunityResponder ? 'available' : 'unavailable');
      if (isCommunityResponder) {
        updates['responder_opted_in_at'] = DateTime.now().toIso8601String();
      } else {
        updates['responder_opted_out_at'] = DateTime.now().toIso8601String();
      }
    } else if (responderStatus != null) {
      updates['responder_status'] = responderStatus;
    }
    // Note: last_lat and last_lng are omitted from public.users updates if not present in schema
    try {
      await _client.from('users').update(updates).eq('id', userId);
    } catch (e) {
      debugPrint('[SUPABASE] updateUserProfile error: $e');
    }

    try {
      await _client.auth.updateUser(UserAttributes(
        data: {
          if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
          if (phoneNumber != null && phoneNumber.trim().isNotEmpty) 'phone': phoneNumber.trim(),
          if (avatarUrl != null && avatarUrl.trim().isNotEmpty) 'avatar_url': avatarUrl.trim(),
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

  Future<void> _stopOAuthLoopbackServer() async {
    _oauthServerTimeout?.cancel();
    _oauthServerTimeout = null;
    try {
      await _oauthLoopbackServer?.close(force: true);
    } catch (_) {}
    _oauthLoopbackServer = null;
  }

  /// Starts a local loopback HTTP listener on port 3000 so that if Supabase
  /// redirects to its default Site URL (`http://localhost:3000`) instead of
  /// `io.supabase.safelink://login-callback`, the app still captures the OAuth
  /// session seamlessly on both Android and Desktop.
  Future<void> _startOAuthLoopbackServer() async {
    if (kIsWeb) return;
    await _stopOAuthLoopbackServer();
    try {
      _oauthLoopbackServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        3000,
        shared: true,
      );
      debugPrint('[OAUTH] Loopback callback listener started on http://localhost:3000');

      _oauthServerTimeout = Timer(const Duration(minutes: 4), () {
        _stopOAuthLoopbackServer();
      });

      _oauthLoopbackServer!.listen((HttpRequest req) async {
        final uri = req.uri;
        debugPrint('[OAUTH] Loopback received request: ${req.method} $uri');

        // 1. Handle forwarded hash fragment or query parameters from browser
        if (uri.path == '/oauth-callback') {
          final code = uri.queryParameters['code'];
          final refreshToken = uri.queryParameters['refresh_token'];
          final accessToken = uri.queryParameters['access_token'];
          final fullUrl = uri.queryParameters['href'];

          try {
            if (code != null && code.isNotEmpty) {
              await _client.auth.exchangeCodeForSession(code);
            } else if (fullUrl != null && fullUrl.isNotEmpty) {
              await _client.auth.getSessionFromUrl(Uri.parse(fullUrl));
            } else if (refreshToken != null && refreshToken.isNotEmpty) {
              await _client.auth.setSession(refreshToken);
            } else if (accessToken != null && accessToken.isNotEmpty) {
              final reconstructed = Uri.parse(
                'io.supabase.safelink://login-callback#${uri.query}',
              );
              await _client.auth.getSessionFromUrl(reconstructed);
            }
          } catch (e) {
            debugPrint('[OAUTH] Token exchange notice: $e');
          }

          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write('{"ok":true}');
          await req.response.close();
          Future.delayed(const Duration(seconds: 2), _stopOAuthLoopbackServer);
          return;
        }

        // 2. If ?code= arrived directly in the initial GET request, exchange immediately
        final directCode = uri.queryParameters['code'];
        if (directCode != null && directCode.isNotEmpty) {
          try {
            await _client.auth.exchangeCodeForSession(directCode);
          } catch (e) {
            debugPrint('[OAUTH] Direct code exchange notice: $e');
          }
        }

        // 3. Serve HTML bridge page that captures URL hash/search, posts to /oauth-callback,
        // and deep-links back to io.supabase.safelink://login-callback
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>SafeLink Sign-In</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
           background: #0B0F19; color: #FFFFFF; display: flex; align-items: center;
           justify-content: center; height: 100vh; margin: 0; text-align: center; }
    .card { background: #151C2C; padding: 32px 24px; border-radius: 20px;
            border: 1px solid #1E293B; max-width: 340px; width: 90%; }
    .icon { width: 56px; height: 56px; border-radius: 50%; background: #10B98122;
            color: #10B981; display: inline-flex; align-items: center;
            justify-content: center; font-size: 28px; margin-bottom: 16px; }
    h2 { margin: 0 0 8px; font-size: 20px; }
    p { color: #94A3B8; font-size: 14px; line-height: 1.5; margin: 0 0 20px; }
    .btn { display: inline-block; background: #0066FF; color: #fff; text-decoration: none;
           padding: 12px 24px; border-radius: 12px; font-weight: 700; font-size: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✓</div>
    <h2>Google Sign-In Complete</h2>
    <p>You are now signed in to SafeLink. Returning to the app automatically...</p>
    <a id="openApp" class="btn" href="io.supabase.safelink://login-callback">Return to SafeLink App</a>
  </div>
  <script>
    (function() {
      var hash = window.location.hash ? window.location.hash.substring(1) : '';
      var search = window.location.search ? window.location.search.substring(1) : '';
      var query = [search, hash].filter(Boolean).join('&');
      var deepLink = 'io.supabase.safelink://login-callback' + window.location.search + window.location.hash;
      document.getElementById('openApp').setAttribute('href', deepLink);
      var callbackUrl = '/oauth-callback?' + (query ? query + '&' : '') + 'href=' + encodeURIComponent(window.location.href);
      fetch(callbackUrl).finally(function() {
        setTimeout(function() {
          window.location.replace(deepLink);
        }, 300);
      });
    })();
  </script>
</body>
</html>
''');
        await req.response.close();
      });
    } catch (e) {
      debugPrint('[OAUTH] Could not bind port 3000 (may already be in use): $e');
    }
  }

  /// Sign In with Google via OAuth
  Future<bool> signInWithGoogle() async {
    await _startOAuthLoopbackServer();
    return await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.safelink://login-callback',
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      queryParams: const {
        'prompt': 'select_account',
      },
    );
  }
}

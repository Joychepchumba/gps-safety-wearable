import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/navigation/navigation_service.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  mfaRequired,
  unauthenticated,
  error,
}

class AuthController extends ChangeNotifier {
  final SupabaseService _supabaseService = sl<SupabaseService>();
  StreamSubscription<AuthState>? _authSub;

  AuthStatus _status = AuthStatus.initial;
  AuthStatus get status => _status;

  bool get isLoading => _status == AuthStatus.loading;
  String? errorMessage;
  UserModel? currentUser;

  // Pending MFA data when user logs in with AAL1 but requires AAL2
  String? pendingMfaFactorId;

  AuthController() {
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    _authSub = _supabaseService.authStateChanges.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      debugPrint('[AUTH] AuthState changed: event=$event, user=${session?.user.id}');

      if ((event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated) &&
          session?.user != null) {
        final user = session!.user;
        final wasAuthenticated =
            _status == AuthStatus.authenticated && currentUser?.id == user.id;
        currentUser = await _supabaseService.ensureOAuthUserProfile(user);
        _status = AuthStatus.authenticated;
        notifyListeners();
        if (!wasAuthenticated || event == AuthChangeEvent.signedIn) {
          NavigationService.pushNamedAndRemoveUntil('/home', (route) => false);
        }
      } else if (event == AuthChangeEvent.signedOut) {
        currentUser = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        NavigationService.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// Re-fetches the signed-in user's row from `public.users` and notifies all
  /// listeners. AuthController.currentUser is the single source of truth for
  /// the profile shown on Home, Profile and every other screen.
  Future<void> refreshProfile() async {
    final authUser = _supabaseService.currentUser;
    if (authUser == null) return;
    try {
      final fresh = await _supabaseService.ensureOAuthUserProfile(authUser);
      currentUser = fresh;
      notifyListeners();
    } catch (e) {
      debugPrint('[AUTH] refreshProfile failed: $e');
    }
  }

  /// Initial check to see if user is already logged in
  Future<void> checkInitialSession(BuildContext ctx) async {
    final user = _supabaseService.currentUser;
    if (user == null) {
      if (_status == AuthStatus.authenticated && currentUser != null) {
        if (ctx.mounted) {
          Navigator.of(ctx).pushReplacementNamed('/home');
        }
        return;
      }
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/login');
      }
      return;
    }

    try {
      // 1. Instantly authenticate and route to /home so emergency SOS is immediately available!
      // Placeholder built from auth metadata; replaced by the public.users row below.
      currentUser = UserModel(
        id: user.id,
        fullName: user.userMetadata?['full_name'] as String? ??
            user.userMetadata?['name'] as String? ??
            '',
        phoneNumber: user.userMetadata?['phone_number'] as String? ??
            user.userMetadata?['phone'] as String? ??
            '',
        email: user.email ?? '',
        avatarUrl: user.userMetadata?['avatar_url'] as String?,
        isCommunityResponder:
            user.userMetadata?['is_community_responder'] as bool? ?? false,
        hasWearable: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _status = AuthStatus.authenticated;
      notifyListeners();

      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/home');
      }

      // 2. Asynchronously refresh/create full profile in background without blocking emergency screen
      _supabaseService.ensureOAuthUserProfile(user).then((profile) {
        currentUser = profile;
        notifyListeners();
      }).catchError((_) {});
    } catch (_) {
      // In case of any error, keep user on home screen if session exists
      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
    }
  }

  /// Send OTP to Email for passwordless sign-in / verification
  Future<bool> sendEmailOtp(String email, BuildContext ctx) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.sendEmailOtp(email);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('A 6-digit login code was sent to $email')),
        );
      }
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Verify Email OTP code
  Future<bool> verifyEmailOtp({
    required String email,
    required String token,
    required BuildContext ctx,
  }) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      final res = await _supabaseService.verifyEmailOtp(email: email, token: token);
      if (res.user != null) {
        currentUser = await _supabaseService.ensureOAuthUserProfile(res.user!);
        _status = AuthStatus.authenticated;
        notifyListeners();
        if (ctx.mounted) {
          Navigator.of(ctx).pushNamedAndRemoveUntil('/home', (route) => false);
        }
        return true;
      }
      throw Exception('Invalid or expired OTP code');
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Sign In with Google via OAuth
  Future<void> signInWithGoogle(BuildContext ctx) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      final launched = await _supabaseService.signInWithGoogle();
      if (!launched) {
        throw Exception('Could not launch Google Sign-In in browser.');
      }
      // Reset loading spinner after launching external browser so UI stays responsive
      // if the user navigates back before completing OAuth; _listenToAuthChanges
      // will automatically transition to authenticated & route to /home upon callback.
      Future.delayed(const Duration(seconds: 2), () {
        if (_status == AuthStatus.loading && _supabaseService.currentUser == null) {
          _status = AuthStatus.unauthenticated;
          notifyListeners();
        }
      });
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In: ${_formatErrorMessage(e)}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// User Login with Email and Password
  Future<void> login(String email, String password, BuildContext ctx) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      final response = await _supabaseService.signIn(email, password);
      if (response.user == null) {
        throw Exception('Login failed: Invalid credentials');
      }

      // Check if user has MFA enabled (AAL2 needed)
      final isMfaNeeded = _supabaseService.isMfaChallengeRequired();
      if (isMfaNeeded) {
        final factors = await _supabaseService.listMfaFactors();
        if (factors.isNotEmpty) {
          pendingMfaFactorId = factors.first.id;
          _status = AuthStatus.mfaRequired;
          notifyListeners();
          if (ctx.mounted) {
            Navigator.of(ctx).pushNamed('/mfa-verify');
          }
          return;
        }
      }

      currentUser = await _supabaseService.ensureOAuthUserProfile(response.user!);
      _status = AuthStatus.authenticated;
      notifyListeners();
      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
    }
  }

  /// Verify MFA TOTP Code during login
  Future<bool> verifyMfaLogin(String code, BuildContext ctx) async {
    if (pendingMfaFactorId == null) {
      final factors = await _supabaseService.listMfaFactors();
      if (factors.isNotEmpty) {
        pendingMfaFactorId = factors.first.id;
      } else {
        errorMessage = 'No MFA factor found for this account.';
        notifyListeners();
        return false;
      }
    }

    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.verifyMfaLogin(
        factorId: pendingMfaFactorId!,
        code: code,
      );

      final user = _supabaseService.currentUser;
      if (user != null) {
        currentUser = await _supabaseService.ensureOAuthUserProfile(user);
      }

      _status = AuthStatus.authenticated;
      pendingMfaFactorId = null;
      notifyListeners();
      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.mfaRequired;
      notifyListeners();
      return false;
    }
  }

  /// User Registration with optional Community Responder opt-in, Avatar, and Duress Password
  Future<void> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    bool isCommunityResponder = false,
    String? emergencyPassword,
    String? avatarUrl,
    required BuildContext ctx,
  }) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      // 1. Send registration to FastAPI backend (logs live in terminal and creates in DB)
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final regUri = Uri.parse('$backendBase/users/register');
        debugPrint('[BACKEND] Sending registration request to: $regUri');
        final res = await http.post(
          regUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'full_name': fullName.trim(),
            'phone_number': phone.trim(),
            'email': email.trim(),
            'password': password,
            'is_community_responder': isCommunityResponder,
            'emergency_password': emergencyPassword,
            'avatar_url': avatarUrl ?? 'guardian',
          }),
        ).timeout(const Duration(seconds: 10));
        debugPrint('[BACKEND] Registration response: ${res.statusCode} ${res.body}');
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Backend registration error: $backendError');
      }

      // 2. Register with Supabase
      final response = await _supabaseService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        isCommunityResponder: isCommunityResponder,
        emergencyPassword: emergencyPassword,
        avatarUrl: avatarUrl ?? 'guardian',
      );

      if (response.user != null) {
        currentUser = await _supabaseService.fetchUserProfile(response.user!.id);
      }
      _status = AuthStatus.authenticated;
      notifyListeners();

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Account registered successfully! Welcome.')),
        );
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
    }
  }

  /// User Logout
  Future<void> logout(BuildContext ctx) async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      await _supabaseService.signOut();
      currentUser = null;
      pendingMfaFactorId = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      if (ctx.mounted) {
        Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
    }
  }

  /// Start MFA Enrollment (returns AuthMFAEnrollResponse)
  Future<AuthMFAEnrollResponse?> startMfaEnrollment() async {
    try {
      clearError();
      return await _supabaseService.enrollTotpMfa();
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  /// Confirm and activate newly enrolled MFA factor
  Future<bool> confirmMfaEnrollment({
    required String factorId,
    required String code,
    required BuildContext ctx,
  }) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.verifyMfaEnrollment(
        factorId: factorId,
        code: code,
      );
      _status = AuthStatus.authenticated;
      notifyListeners();

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Two-Factor Authentication successfully enabled!')),
        );
      }
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return false;
    }
  }

  /// Unenroll an MFA factor
  Future<bool> unenrollMfaFactor(String factorId) async {
    try {
      clearError();
      await _supabaseService.unenrollMfaFactor(factorId);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Request password reset email
  Future<bool> requestPasswordReset(String email) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.sendPasswordResetEmail(email);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Verify recovery OTP code from email
  Future<bool> verifyRecoveryOtp(String email, String otp) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.verifyRecoveryOtp(email: email, otp: otp);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Set new password after recovery OTP verified
  Future<bool> setNewPassword(String newPassword, BuildContext ctx) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      await _supabaseService.updatePassword(newPassword);
      _status = AuthStatus.authenticated;
      notifyListeners();

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Password updated successfully!')),
        );
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Set or update Emergency Duress Password
  Future<bool> updateEmergencyPassword(String duressPassword) async {
    if (currentUser == null) return false;
    try {
      await _supabaseService.updateEmergencyPassword(
        userId: currentUser!.id,
        emergencyPassword: duressPassword,
      );
      currentUser = await _supabaseService.fetchUserProfile(currentUser!.id);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Toggle Community Responder mode
  Future<bool> toggleCommunityResponder(bool optIn) async {
    if (currentUser == null) return false;
    try {
      await _supabaseService.toggleCommunityResponder(
        userId: currentUser!.id,
        optIn: optIn,
      );
      currentUser = await _supabaseService.fetchUserProfile(currentUser!.id);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Update user profile details (Name, Phone, Avatar, Responder Opt-in, Emergency PIN)
  Future<bool> updateProfile({
    required String fullName,
    required String phoneNumber,
    String? avatarUrl,
    bool? isCommunityResponder,
    String? emergencyPassword,
  }) async {
    if (currentUser == null) return false;
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      // 1. Update in Supabase public.users
      await _supabaseService.updateUserProfile(
        userId: currentUser!.id,
        fullName: fullName.trim(),
        phoneNumber: phoneNumber.trim(),
        avatarUrl: avatarUrl,
        isCommunityResponder: isCommunityResponder,
      );

      // 2. Update duress password if provided
      if (emergencyPassword != null && emergencyPassword.trim().isNotEmpty) {
        await _supabaseService.updateEmergencyPassword(
          userId: currentUser!.id,
          emergencyPassword: emergencyPassword.trim(),
        );
      }

      // 3. Sync to FastAPI backend
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final patchUri = Uri.parse('$backendBase/users/profile');
        await http.patch(
          patchUri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'user_id': currentUser!.id,
            'full_name': fullName.trim(),
            'phone_number': phoneNumber.trim(),
            'is_community_responder': isCommunityResponder,
            'emergency_password': emergencyPassword != null && emergencyPassword.trim().isNotEmpty
                ? emergencyPassword.trim()
                : null,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (backendError) {
        debugPrint('[BACKEND NOTICE] Backend profile update notice: $backendError');
      }

      // 4. Refresh current user profile
      currentUser = await _supabaseService.fetchUserProfile(currentUser!.id);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _formatErrorMessage(e);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return false;
    }
  }

  String _formatErrorMessage(dynamic error) {
    if (error is AuthException) {
      return error.message;
    }
    final str = error.toString();
    if (str.startsWith('Exception: ')) {
      return str.substring(11);
    }
    return str;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

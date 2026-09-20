import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/di/service_locator.dart';

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

  AuthStatus _status = AuthStatus.initial;
  AuthStatus get status => _status;

  bool get isLoading => _status == AuthStatus.loading;
  String? errorMessage;
  UserModel? currentUser;

  // Pending MFA data when user logs in with AAL1 but requires AAL2
  String? pendingMfaFactorId;

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// Initial check to see if user is already logged in
  Future<void> checkInitialSession(BuildContext ctx) async {
    final user = _supabaseService.currentUser;
    if (user == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final isMfaNeeded = _supabaseService.isMfaChallengeRequired();
      if (isMfaNeeded) {
        final factors = await _supabaseService.listMfaFactors();
        if (factors.isNotEmpty) {
          pendingMfaFactorId = factors.first.id;
          _status = AuthStatus.mfaRequired;
          notifyListeners();
          if (ctx.mounted) {
            Navigator.of(ctx).pushReplacementNamed('/mfa-verify');
          }
          return;
        }
      }

      currentUser = await _supabaseService.fetchUserProfile(user.id);
      _status = AuthStatus.authenticated;
      notifyListeners();
      if (ctx.mounted) {
        Navigator.of(ctx).pushReplacementNamed('/home');
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
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

      currentUser = await _supabaseService.fetchUserProfile(response.user!.id);
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
        currentUser = await _supabaseService.fetchUserProfile(user.id);
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

  /// User Registration with optional Community Responder opt-in and Duress Password
  Future<void> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    bool isCommunityResponder = false,
    String? emergencyPassword,
    required BuildContext ctx,
  }) async {
    _status = AuthStatus.loading;
    clearError();
    notifyListeners();

    try {
      final response = await _supabaseService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        isCommunityResponder: isCommunityResponder,
        emergencyPassword: emergencyPassword,
      );

      if (response.user == null) {
        throw Exception('Registration did not return a valid user.');
      }

      currentUser = await _supabaseService.fetchUserProfile(response.user!.id);
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
}

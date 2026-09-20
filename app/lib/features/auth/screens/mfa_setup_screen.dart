import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../controllers/auth_controller.dart';

class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  AuthMFAEnrollResponse? _enrollResponse;
  bool _isLoadingEnrollment = true;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEnrollment();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _fetchEnrollment() async {
    final authController = context.read<AuthController>();
    final resp = await authController.startMfaEnrollment();
    if (mounted) {
      setState(() {
        _enrollResponse = resp;
        _isLoadingEnrollment = false;
      });
    }
  }

  void _verifyAndEnable(AuthController authController) async {
    if (_enrollResponse == null) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit code from your authenticator app'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final success = await authController.confirmMfaEnrollment(
      factorId: _enrollResponse!.id,
      code: code,
      ctx: context,
    );

    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          AppStrings.mfaSetupTitle,
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: _isLoadingEnrollment
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : _enrollResponse == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Failed to initialize MFA enrollment.',
                          style: TextStyle(color: AppColors.error),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _isLoadingEnrollment = true);
                            _fetchEnrollment();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.qr_code_scanner,
                          size: 64,
                          color: AppColors.accent,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          AppStrings.mfaSetupDesc,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 24),

                        // Secret Key Display Box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Manual Entry Secret Key:',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      _enrollResponse!.totp?.secret ?? '',
                                      style: const TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 16,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 20),
                                    tooltip: 'Copy Key',
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: _enrollResponse!.totp?.secret ?? ''),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Secret key copied to clipboard!')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        const Text(
                          'Step 2: Enter the 6-digit code generated by your app:',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 6-digit code input
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.accent, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        authController.isLoading
                            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                            : ElevatedButton(
                                onPressed: () => _verifyAndEnable(authController),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                ),
                                child: const Text(
                                  'Activate 2FA Protection',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

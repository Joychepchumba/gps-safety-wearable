class AppStrings {
  static const String appName = 'SafeLink';
  static const String tagline = 'Your safety, always connected';
  
  // Screen Titles
  static const String homeTitle = 'Home';
  static const String mapTitle = 'Map';
  static const String emergencyTitle = 'Emergency';
  static const String contactsTitle = 'Contacts';
  static const String alertHistoryTitle = 'Alert History';
  static const String wearableTitle = 'Wearable';
  static const String loginTitle = 'Login';
  static const String registerTitle = 'Register';

  // Button Labels
  static const String sosBtn = 'SOS';
  static const String cancelBtn = 'Cancel';
  static const String addContactBtn = 'Add Contact';
  static const String pairDeviceBtn = 'Pair Device';
  static const String optInResponderBtn = 'Opt In as Responder';
  static const String optOutResponderBtn = 'Opt Out';

  // Error Messages
  static const String errorLocationDenied = 'Location permission denied.';
  static const String errorBleUnavailable = 'Bluetooth is unavailable or disabled.';
  static const String errorNoNetwork = 'No internet connection available.';

  // Emergency Messages
  static const String emergencyAlertSent = 'Emergency alert sent!';
  static const String sendingAlert = 'Sending alert...';
  static const String cancelEmergency = 'Cancel (Xs)';

  // SMS Templates
  static const String smsTemplateEmergency = 'EMERGENCY! {name} has triggered an SOS. Location: {location_url} Time: {time}';
  static const String smsTemplateCommunity = 'Urgent: Someone near you triggered an SOS alert. Please open SafeGuard to respond if you can.';

  // Auth & Security Strings
  static const String mfaTitle = 'Two-Factor Authentication';
  static const String mfaPrompt = 'Enter the 6-digit code from your authenticator app';
  static const String mfaSetupTitle = 'Setup Authenticator (MFA)';
  static const String mfaSetupDesc = 'Scan this QR code or copy the secret key into Google Authenticator or Authy to protect your account:';
  static const String mfaVerifyBtn = 'Verify Code';
  static const String forgotPassword = 'Forgot Password?';
  static const String resetPasswordTitle = 'Reset Password';
  static const String emergencyPasswordLabel = 'Emergency Duress Code / PIN';
  static const String emergencyPasswordHint = 'Enter 4-6 digit secret duress code';
  static const String emergencyPasswordDesc = 'If coerced by an attacker, entering this code sends a silent distress alert while appearing to comply.';
  static const String communityOptInLabel = 'Join as Community Responder';
  static const String communityOptInDesc = 'Receive anonymous alerts when someone within 1km needs emergency help.';
}

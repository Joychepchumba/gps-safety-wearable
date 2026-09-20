enum PasswordStrength { weak, medium, strong }

class Validators {
  static bool isValidPhone(String phone) {
    // Kenyan format: starts with 07 or 01 or +254, 10-13 digits
    final regex = RegExp(r'^(\+254|07|01)\d{8}$');
    return regex.hasMatch(phone);
  }

  static bool isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email);
  }

  static bool isValidName(String name) {
    return name.trim().length >= 2;
  }

  static PasswordStrength passwordStrength(String pwd) {
    if (pwd.length < 6) return PasswordStrength.weak;
    bool hasUppercase = pwd.contains(RegExp(r'[A-Z]'));
    bool hasDigits = pwd.contains(RegExp(r'[0-9]'));
    bool hasSpecialCharacters = pwd.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    
    if (pwd.length >= 8 && hasUppercase && hasDigits && hasSpecialCharacters) {
      return PasswordStrength.strong;
    } else if (pwd.length >= 6 && (hasUppercase || hasDigits)) {
      return PasswordStrength.medium;
    }
    return PasswordStrength.weak;
  }
}

import '../app_user.dart';

/// Account and session credentials returned after a successful signup OTP.
class SignupVerificationResult {
  const SignupVerificationResult({required this.user, this.tokens});

  final AppUser user;
  final Map<String, dynamic>? tokens;

  bool get hasSessionTokens {
    final access = tokens?['access']?.toString().trim() ?? '';
    final refresh = tokens?['refresh']?.toString().trim() ?? '';
    return access.isNotEmpty && refresh.isNotEmpty;
  }
}

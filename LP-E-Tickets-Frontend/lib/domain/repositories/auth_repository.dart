import '../models/app_user.dart';
import '../models/auth/acpec_mobile_auth_bootstrap.dart';
import '../models/auth/signup_otp_challenge.dart';
import '../models/auth/signup_verification_result.dart';
import '../models/user_role.dart';

abstract interface class AuthRepositoryContract {
  AppUser userFromOdooProfileMap(
    Map<String, dynamic> profile, {
    Map<String, dynamic>? envelope,
  });
  Future<AcpecVersionCheckData> checkAcpecVersion(Map<String, dynamic> params);
  Future<List<AcpecSignupCompany>> signupCompanies();
  Future<AppUser> confirmOpenPin(String pin);
  Future<AppUser> login(String identifier, String pin);
  Future<AppUser?> tryRestoreRemoteSession();
  Future<SignupOtpChallenge> requestLoginOtp({required String identifier});
  Future<AppUser> verifyLoginOtp({
    required String identifier,
    required String code,
    int? challengeId,
  });
  Future<SignupOtpChallenge> requestSignupOtp({required String phoneFull});
  Future<SignupVerificationResult> verifySignupOtp({
    required String identifier,
    required String code,
    required String name,
    required String pin,
    required int companyId,
    int? challengeId,
  });
  Future<SignupOtpChallenge> requestSignupOtpResend({
    required String identifier,
  });
  Future<SignupOtpChallenge> requestPasswordResetOtp({
    required String phoneFull,
  });
  Future<void> verifyPasswordResetOtp({
    required String identifier,
    required String code,
    required String pin,
    int? challengeId,
  });
  Future<AppUser> register({
    required String email,
    required String name,
    required String phone,
    required String pin,
  });
  Future<AppUser> adoptRemoteUser({
    required AppUser user,
    required String pin,
    Map<String, dynamic>? tokens,
  });
  Future<void> resetPinForIdentifier({
    required String identifier,
    required String newPin,
  });
  Future<void> logout();
  Future<AppUser> changeRole(
    String userId,
    UserRole newRole, {
    String? stationId,
  });
}

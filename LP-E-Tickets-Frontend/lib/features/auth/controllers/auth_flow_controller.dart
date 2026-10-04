import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/auth/acpec_mobile_auth_bootstrap.dart';
import '../../../domain/models/auth/signup_otp_challenge.dart';
import '../../../domain/models/auth/signup_verification_result.dart';

/// Coordinates authentication forms with the authentication repository.
class AuthFlowController {
  AuthFlowController({required AuthRepositoryContract repository})
    : _repository = repository;

  static AuthFlowController? _instance;
  static AuthFlowController get instance =>
      _instance ?? (throw StateError('AuthFlowController not configured'));
  static void configure(AuthRepositoryContract repository) {
    _instance = AuthFlowController(repository: repository);
  }

  final AuthRepositoryContract _repository;

  Future<AcpecVersionCheckData> checkAcpecVersion(
    Map<String, dynamic> params,
  ) => _repository.checkAcpecVersion(params);

  Future<List<AcpecSignupCompany>> signupCompanies() =>
      _repository.signupCompanies();

  Future<SignupOtpChallenge> requestSignupOtp({required String phoneFull}) =>
      _repository.requestSignupOtp(phoneFull: phoneFull);

  Future<SignupVerificationResult> verifySignupOtp({
    required String identifier,
    required String code,
    required String name,
    required String pin,
    required int companyId,
    int? challengeId,
  }) => _repository.verifySignupOtp(
    identifier: identifier,
    code: code,
    name: name,
    pin: pin,
    companyId: companyId,
    challengeId: challengeId,
  );

  AppUser userFromOdooProfileMap(
    Map<String, dynamic> profile, {
    Map<String, dynamic>? envelope,
  }) => _repository.userFromOdooProfileMap(profile, envelope: envelope);

  Future<SignupOtpChallenge> requestSignupOtpResend({
    required String identifier,
  }) => _repository.requestSignupOtpResend(identifier: identifier);

  Future<SignupOtpChallenge> requestPasswordResetOtp({
    required String phoneFull,
  }) => _repository.requestPasswordResetOtp(phoneFull: phoneFull);

  Future<void> verifyPasswordResetOtp({
    required String identifier,
    required String code,
    required String pin,
    int? challengeId,
  }) => _repository.verifyPasswordResetOtp(
    identifier: identifier,
    code: code,
    pin: pin,
    challengeId: challengeId,
  );

  Future<void> resetPinForIdentifier({
    required String identifier,
    required String newPin,
  }) =>
      _repository.resetPinForIdentifier(identifier: identifier, newPin: newPin);
}

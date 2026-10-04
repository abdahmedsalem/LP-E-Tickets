/// Public OTP challenge details needed by the registration flow.
class SignupOtpChallenge {
  const SignupOtpChallenge({this.challengeId, this.expiresInSeconds = 300});

  final int? challengeId;
  final int expiresInSeconds;
}

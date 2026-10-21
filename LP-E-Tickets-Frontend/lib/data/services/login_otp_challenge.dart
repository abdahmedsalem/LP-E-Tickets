import 'shared_services/acpec_public_api_error.dart';

/// A login may advance to SMS verification only with a real server challenge.
class LoginOtpChallenge {
  const LoginOtpChallenge(this.id);

  final int id;

  static const accountUnavailableMessage =
      'Aucun compte associé à ce numéro. Vérifiez le numéro ou créez un compte.';

  factory LoginOtpChallenge.fromResponse(Map<String, dynamic> response) {
    if (AcpecPublicApiError.hasBusinessError(response)) {
      throw AcpecPublicApiError.fromBusinessEnvelope(response).toException();
    }
    final data = response['data'];
    if (data is! Map) {
      throw const FormatException(
        'Réponse serveur invalide. Veuillez réessayer.',
      );
    }
    final payload = Map<String, dynamic>.from(data);
    if (AcpecPublicApiError.hasBusinessError(payload)) {
      throw AcpecPublicApiError.fromBusinessEnvelope(payload).toException();
    }
    final rawId = payload['otp_challenge_id'] ?? payload['challenge_id'];
    final id = int.tryParse(rawId?.toString() ?? '');
    if (id != null && id > 0) return LoginOtpChallenge(id);

    // Odoo returns an accepted message without a challenge when the account
    // cannot receive a login OTP. Never show a code field for that response.
    if ((rawId == null || rawId == false) && payload['message'] is String) {
      throw Exception(accountUnavailableMessage);
    }
    throw const FormatException(
      'Réponse serveur invalide. Veuillez réessayer.',
    );
  }
}

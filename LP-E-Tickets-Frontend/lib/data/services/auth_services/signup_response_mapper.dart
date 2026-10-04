import '../../../domain/models/auth/signup_otp_challenge.dart';
import '../../../domain/models/auth/signup_verification_result.dart';
import 'app_user_mapper.dart';

/// Maps raw ACPEC signup responses to stable domain results.
class SignupResponseMapper {
  SignupResponseMapper._();

  static SignupOtpChallenge challengeFromResponse(
    Map<String, dynamic> response, {
    DateTime? now,
  }) {
    final data = _map(response['data']) ?? response;
    final rawId =
        data['otp_challenge_id'] ??
        data['challenge_id'] ??
        response['otp_challenge_id'] ??
        response['challenge_id'];
    final parsedId = int.tryParse(rawId?.toString() ?? '');
    final rawExpiry =
        data['otp_expires_at'] ??
        data['expires_at'] ??
        response['otp_expires_at'] ??
        response['expires_at'];
    return SignupOtpChallenge(
      challengeId: parsedId != null && parsedId > 0 ? parsedId : null,
      expiresInSeconds: _secondsUntilExpiry(rawExpiry, now: now),
    );
  }

  static SignupVerificationResult verificationFromResponse(
    Map<String, dynamic> response,
  ) {
    final payload = _map(response['data']) ?? response;
    final user = AppUserMapper.fromOdooProfileMap(payload, envelope: response);
    return SignupVerificationResult(
      user: user,
      tokens: _tokensFromResponse(response),
    );
  }

  static Map<String, dynamic>? _tokensFromResponse(
    Map<String, dynamic> response,
  ) {
    final data = _map(response['data']);
    final user = _map(response['user']);
    final candidates = <Map<String, dynamic>>[response, ?data, ?user];
    for (final map in candidates) {
      final access = _firstString(map, const [
        'access_token',
        'ACCESS_TOKEN',
        'accessToken',
      ]);
      final refresh = _firstString(map, const [
        'refresh_token',
        'REFRESH_TOKEN',
        'refreshToken',
      ]);
      if ((access ?? '').isNotEmpty || (refresh ?? '').isNotEmpty) {
        final tokens = <String, dynamic>{};
        if (access != null) tokens['access'] = access;
        if (refresh != null) tokens['refresh'] = refresh;
        return tokens;
      }
    }
    return null;
  }

  static int _secondsUntilExpiry(dynamic raw, {DateTime? now}) {
    if (raw == null || raw.toString().trim().isEmpty) return 300;
    try {
      final clean = raw.toString().trim().replaceAll(' ', 'T');
      final expiresAt = DateTime.parse(
        clean.contains('Z') ? clean : '${clean}Z',
      );
      final current = now ?? DateTime.now().toUtc();
      final diff = expiresAt.difference(current.toUtc()).inSeconds;
      return diff > 0 ? diff : 300;
    } catch (_) {
      return 300;
    }
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final text = map[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'false' && text != 'null') return text;
    }
    return null;
  }
}

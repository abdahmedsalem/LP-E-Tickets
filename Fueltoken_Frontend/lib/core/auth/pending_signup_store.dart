import 'package:shared_preferences/shared_preferences.dart';

class PendingSignup {
  const PendingSignup({
    required this.name,
    required this.phoneFull,
    required this.challengeId,
    required this.companyId,
    required this.createdAt,
  });

  static const ttl = Duration(minutes: 30);

  final String name;
  final String phoneFull;
  final int challengeId;
  final int companyId;
  final DateTime createdAt;

  bool get isUsable {
    if (phoneFull.trim().isEmpty) return false;
    if (challengeId <= 0) return false;
    final age = DateTime.now().difference(createdAt);
    return !age.isNegative && age <= ttl;
  }
}

class PendingSignupStore {
  PendingSignupStore._();

  static const _kName = 'ft_pending_signup_name';
  static const _kPhone = 'ft_pending_signup_phone';
  static const _kChallengeId = 'ft_pending_signup_challenge_id';
  static const _kCompanyId = 'ft_pending_signup_company_id';
  static const _kCreatedAt = 'ft_pending_signup_created_at';

  static Future<void> save({
    required String name,
    required String phoneFull,
    required int challengeId,
    required int companyId,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, name.trim());
    await p.setString(_kPhone, phoneFull.trim());
    await p.setInt(_kChallengeId, challengeId);
    await p.setInt(_kCompanyId, companyId);
    await p.setString(_kCreatedAt, DateTime.now().toIso8601String());
  }

  static Future<PendingSignup?> load() async {
    final p = await SharedPreferences.getInstance();
    final phone = p.getString(_kPhone)?.trim() ?? '';
    final challengeId = p.getInt(_kChallengeId) ?? 0;
    final companyId = p.getInt(_kCompanyId) ?? 0;
    final rawCreatedAt = p.getString(_kCreatedAt)?.trim() ?? '';
    final createdAt = DateTime.tryParse(rawCreatedAt);

    if (phone.isEmpty ||
        challengeId <= 0 ||
        companyId <= 0 ||
        createdAt == null) {
      return null;
    }

    return PendingSignup(
      name: p.getString(_kName)?.trim() ?? '',
      phoneFull: phone,
      challengeId: challengeId,
      companyId: companyId,
      createdAt: createdAt,
    );
  }

  static Future<PendingSignup?> loadUsable() async {
    final pending = await load();
    if (pending == null) return null;
    if (!pending.isUsable) {
      await clear();
      return null;
    }
    return pending;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kName);
    await p.remove(_kPhone);
    await p.remove(_kChallengeId);
    await p.remove(_kCompanyId);
    await p.remove(_kCreatedAt);
  }
}

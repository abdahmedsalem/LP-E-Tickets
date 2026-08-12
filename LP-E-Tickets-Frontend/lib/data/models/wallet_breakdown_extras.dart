import 'dart:convert';

/// Données complémentaires du portefeuille (hors solde principal affiché).
class WalletBreakdownExtras {
  const WalletBreakdownExtras({
    this.breakdownByFaceValue,
    this.breakdownByCarnetType,
    this.nearExpirationFaces = const [],
    this.expiredFaces = const [],
  });

  final Object? breakdownByFaceValue;
  final Object? breakdownByCarnetType;
  final List<dynamic> nearExpirationFaces;
  final List<dynamic> expiredFaces;

  WalletBreakdownExtras copyWith({
    Object? breakdownByFaceValue,
    Object? breakdownByCarnetType,
    List<dynamic>? nearExpirationFaces,
    List<dynamic>? expiredFaces,
  }) {
    return WalletBreakdownExtras(
      breakdownByFaceValue: breakdownByFaceValue ?? this.breakdownByFaceValue,
      breakdownByCarnetType:
          breakdownByCarnetType ?? this.breakdownByCarnetType,
      nearExpirationFaces: nearExpirationFaces ?? this.nearExpirationFaces,
      expiredFaces: expiredFaces ?? this.expiredFaces,
    );
  }

  bool get isEmpty =>
      breakdownByFaceValue == null &&
      breakdownByCarnetType == null &&
      nearExpirationFaces.isEmpty &&
      expiredFaces.isEmpty;

  static List<dynamic> _asList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return List<dynamic>.from(v);
    return const [];
  }

  static WalletBreakdownExtras? fromWalletPayload(Map<String, dynamic> m) {
    final near = _asList(m['near_expiration_faces']);
    final exp = _asList(m['expired_faces']);
    final bfv = m['breakdown_by_face_value'];
    final bct = m['breakdown_by_carnet_type'];
    if (bfv == null && bct == null && near.isEmpty && exp.isEmpty) {
      return null;
    }
    return WalletBreakdownExtras(
      breakdownByFaceValue: bfv,
      breakdownByCarnetType: bct,
      nearExpirationFaces: near,
      expiredFaces: exp,
    );
  }

  /// Texte lisible pour une ligne de liste (objet ou primitive).
  static String lineLabel(dynamic item) {
    if (item == null) return '—';
    if (item is Map) {
      try {
        return const JsonEncoder.withIndent('  ').convert(item);
      } catch (_) {
        return item.toString();
      }
    }
    return item.toString();
  }
}

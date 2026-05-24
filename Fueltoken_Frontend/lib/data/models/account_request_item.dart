import 'package:equatable/equatable.dart';

import '../../core/utils/rejection_reason.dart';

/// Demande d’inscription ou de compte (liste admin).
class AccountRequestItem extends Equatable {
  const AccountRequestItem({
    required this.raw,
    this.id,
    required this.displayName,
    this.email,
    this.phone,
    required this.state,
    this.companyName,
    this.createdAt,
  });

  final Map<String, dynamic> raw;
  final int? id;
  final String displayName;
  final String? email;
  final String? phone;
  final String state;
  final String? companyName;
  final DateTime? createdAt;

  bool get isRejected => mapStateLooksRejected(state);

  bool get isApproved {
    final n = state.toLowerCase();
    return n.contains('approv') || n == 'done' || n.contains('accept');
  }

  bool get isPending {
    final n = state.toLowerCase();
    return n.contains('pending') || n == 'draft' || n == 'submitted';
  }

  /// Uniquement pour les demandes rejetées ; ignore `false` / `true` de l’API.
  String? get rejectionMotif {
    if (!isRejected) return null;
    return rejectionReasonFromMap(raw);
  }

  static int? _parseId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['request_id'] ?? m['account_request_id'];
    if (v is int) return v;
    return int.tryParse(v?.toString().trim() ?? '');
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  static String? _companyName(Map<String, dynamic> m) {
    final direct = m['company_name'] ?? m['company'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    final c = m['company_id'];
    if (c is List && c.length > 1) {
      final n = c[1];
      if (n != null && n.toString().trim().isNotEmpty) return n.toString().trim();
    }
    return null;
  }

  factory AccountRequestItem.fromMap(Map<String, dynamic> m) {
    final id = _parseId(m);
    final name = m['name']?.toString().trim();
    final signupId = m['signup_identifier']?.toString().trim();
    final email = (m['email'] ?? m['login'] ?? m['signup_email'])?.toString().trim();
    final display = (name != null && name.isNotEmpty)
        ? name
        : (signupId != null && signupId.isNotEmpty)
            ? signupId
            : (email != null && email.isNotEmpty)
                ? email
                : 'Demande #${id ?? '?'}';
    final phone = (m['phone'] ?? m['mobile'] ?? m['phone_number'])?.toString().trim();
    final rawState = m['state']?.toString().trim();
    final state =
        (rawState != null && rawState.isNotEmpty) ? rawState : 'pending';
    return AccountRequestItem(
      raw: Map<String, dynamic>.from(m),
      id: id,
      displayName: display,
      email: (email == null || email.isEmpty) ? null : email,
      phone: (phone == null || phone.isEmpty) ? null : phone,
      state: state,
      companyName: _companyName(m),
      createdAt: _parseDate(
        m['create_date'] ?? m['created_at'] ?? m['date'] ?? m['write_date'],
      ),
    );
  }

  @override
  List<Object?> get props => [id, displayName, email, state, companyName, createdAt];
}

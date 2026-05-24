import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/account_request_item.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart' show OdooJsonRpcException;
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/section_label.dart';
import 'admin_acpec_account_requests_screen.dart' show RejectAccountRequestSheet;

/// Détail d’une demande de compte (données de la liste, pas d’appel API dédié).
class AdminAccountRequestDetailScreen extends StatefulWidget {
  const AdminAccountRequestDetailScreen({
    super.key,
    required this.item,
  });

  final AccountRequestItem item;

  @override
  State<AdminAccountRequestDetailScreen> createState() =>
      _AdminAccountRequestDetailScreenState();
}

class _AdminAccountRequestDetailScreenState
    extends State<AdminAccountRequestDetailScreen> {
  final _facade = OdooFueltokenFacade();
  bool _busy = false;

  AccountRequestItem get item => widget.item;

  String _messageForUser(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  String _primaryLabel() {
    final name = item.raw['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    if (item.email != null && item.email!.trim().isNotEmpty) return item.email!;
    if (item.phone != null && item.phone!.trim().isNotEmpty) return item.phone!;
    if (item.companyName != null && item.companyName!.trim().isNotEmpty) {
      return item.companyName!;
    }
    return 'Demande de compte';
  }

  String _labelForRawKey(String key) {
    switch (key.toLowerCase()) {
      case 'name':
        return 'Nom';
      case 'email':
      case 'login':
      case 'signup_email':
        return 'E-mail';
      case 'phone':
      case 'mobile':
      case 'phone_number':
        return 'Téléphone';
      case 'company_name':
      case 'company':
      case 'company_id':
        return 'Société';
      case 'created_at':
      case 'create_date':
      case 'write_date':
      case 'date':
        return 'Date';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  bool _isTechnicalKey(String key) {
    switch (key.toLowerCase()) {
      case 'id':
      case 'request_id':
      case 'account_request_id':
      case 'state':
      case 'name':
      case 'email':
      case 'login':
      case 'signup_email':
      case 'phone':
      case 'mobile':
      case 'phone_number':
      case 'company_name':
      case 'company':
      case 'company_id':
      case 'created_at':
      case 'create_date':
      case 'write_date':
      case 'date':
      case 'signup_identifier':
        return true;
      default:
        return false;
    }
  }

  List<MapEntry<String, String>> _extraInfoRows() {
    final rows = <MapEntry<String, String>>[];
    item.raw.forEach((key, value) {
      if (_isTechnicalKey(key)) return;
      if (value == null) return;
      if (value is Map || value is List) return;
      final text = value.toString().trim();
      if (text.isEmpty || text == 'false' || text == 'null') return;
      rows.add(MapEntry(_labelForRawKey(key), text));
    });
    return rows;
  }

  Future<void> _approve() async {
    final id = item.id;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _facade.adminApproveAccountRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande approuvée.')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForUser(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final id = item.id;
    if (id == null || _busy) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => RejectAccountRequestSheet(
        item: item,
        defaultReason: 'Dossier incomplet.',
        onCancel: () => Navigator.pop(sheetCtx),
        onConfirm: (r) => Navigator.pop(sheetCtx, r),
      ),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await _facade.adminRejectAccountRequest(id, {'reason': reason.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande rejetée.')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForUser(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static PillTone _pillTone(AccountRequestItem item) {
    if (item.isRejected) return PillTone.red;
    if (item.isApproved) return PillTone.green;
    if (item.isPending) return PillTone.amber;
    return PillTone.gray;
  }

  static String _stateLabelFr(AccountRequestItem item) {
    if (item.isPending) return 'En attente';
    if (item.isApproved) return 'Approuvé';
    if (item.isRejected) return 'Rejeté';
    return item.state;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    final motif = item.rejectionMotif;
    final extras = _extraInfoRows();

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(
          'Demande de compte',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _AccountHeroCard(
                  item: item,
                  title: _primaryLabel(),
                  stateLabel: _stateLabelFr(item),
                  tone: _pillTone(item),
                ),
                if (item.isRejected && motif != null) ...[
                  const SizedBox(height: 14),
                  _AccountRejectionCard(reason: motif),
                ],
                const SizedBox(height: 20),
                const SectionLabel('Informations'),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.flag_outlined,
                        label: 'Statut',
                        value: _stateLabelFr(item),
                      ),
                      _InfoRow(
                        icon: Icons.person_outline,
                        label: 'Nom',
                        value: _primaryLabel(),
                      ),
                      if (item.email != null)
                        _InfoRow(
                          icon: Icons.mail_outline_rounded,
                          label: 'E-mail',
                          value: item.email!,
                        ),
                      if (item.phone != null)
                        _InfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Téléphone',
                          value: item.phone!,
                        ),
                      if (item.companyName != null)
                        _InfoRow(
                          icon: Icons.business_outlined,
                          label: 'Société',
                          value: item.companyName!,
                        ),
                      if (item.createdAt != null)
                        _InfoRow(
                          icon: Icons.schedule_rounded,
                          label: 'Soumis le',
                          value: Formatters.dateTime(item.createdAt!),
                        ),
                    ],
                  ),
                ),
                if (extras.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('Informations complémentaires'),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Column(
                      children: [
                        for (final row in extras)
                          _InfoRow(
                            icon: Icons.notes_outlined,
                            label: row.key,
                            value: row.value,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.isPending && item.id != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _approve,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(_busy ? '…' : 'Approuver'),
                        style: FilledButton.styleFrom(
                          foregroundColor: AppColors.success,
                          backgroundColor:
                              AppColors.success.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _reject,
                        icon: Icon(
                          Icons.cancel_outlined,
                          color: AppColors.danger.withValues(alpha: 0.95),
                        ),
                        label: Text(
                          'Rejeter',
                          style: TextStyle(
                            color: AppColors.danger.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountHeroCard extends StatelessWidget {
  const _AccountHeroCard({
    required this.item,
    required this.title,
    required this.stateLabel,
    required this.tone,
  });

  final AccountRequestItem item;
  final String title;
  final String stateLabel;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: AppColors.walletGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.walletGlowShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              AppPill(label: stateLabel, tone: tone),
            ],
          ),
          if (item.email != null || item.phone != null || item.companyName != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.email != null)
                  _HeroMetaChip(
                    icon: Icons.mail_outline_rounded,
                    label: item.email!,
                  ),
                if (item.phone != null)
                  _HeroMetaChip(
                    icon: Icons.phone_outlined,
                    label: item.phone!,
                  ),
                if (item.companyName != null)
                  _HeroMetaChip(
                    icon: Icons.business_outlined,
                    label: item.companyName!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.95)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRejectionCard extends StatelessWidget {
  const _AccountRejectionCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSurface,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motif de rejet',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

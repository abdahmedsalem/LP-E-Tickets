import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/account_request_item.dart';
import '../../../data/services/acpec_account_request_mapper.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/app_status_lottie.dart';

String _ellipsisSnippet(String text, int maxChars) {
  final t = text.trim();
  if (t.length <= maxChars) return t;
  return '${t.substring(0, maxChars - 1)}…';
}

/// Liste paginée des demandes de compte (administrateur ACPEC).
class AdminAcpecAccountRequestsScreen extends StatefulWidget {
  const AdminAcpecAccountRequestsScreen({super.key});

  static const int pageSize = 20;

  @override
  State<AdminAcpecAccountRequestsScreen> createState() =>
      _AdminAcpecAccountRequestsScreenState();
}

class _AdminAcpecAccountRequestsScreenState
    extends State<AdminAcpecAccountRequestsScreen> {
  final _facade = OdooFueltokenFacade();
  final _scrollController = ScrollController();

  List<AccountRequestItem> _items = [];
  int? _totalCount;
  bool _hasMore = false;
  int _offset = 0;
  String? _stateFilter = 'pending';

  bool _loading = true;
  bool _loadingMore = false;
  bool _rejectBusy = false;
  String? _error;

  static const String _defaultRejectReason = 'Dossier incomplet.';

  String _messageForUser(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session Odoo expirée. Déconnectez-vous puis reconnectez-vous.';
    }
    var msg = e.toString().replaceFirst('Exception: ', '');
    final low = msg.toLowerCase();
    if (low.contains('session expired') ||
        low.contains('session expir') ||
        low.contains('sessionexpired')) {
      return 'Session Odoo expirée. Déconnectez-vous puis reconnectez-vous.';
    }
    if (msg.length > 480) {
      return 'Erreur serveur Odoo. Réessayez ou reconnectez-vous. '
          '(Si besoin, consultez les logs de l’équipe technique.)';
    }
    return msg;
  }

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      _load(reset: true);
    } else {
      _loading = false;
      _error =
          'Mode ACPEC live désactivé (ODOO_USE_ACPEC_AUTH et Odoo requis).';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _listParams(int offset) {
    final p = <String, dynamic>{
      'limit': AdminAcpecAccountRequestsScreen.pageSize,
      'offset': offset,
    };
    if (_stateFilter != null && _stateFilter!.isNotEmpty) {
      p['state'] = _stateFilter;
    }
    return p;
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _items = [];
        _offset = 0;
        _totalCount = null;
        _hasMore = false;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final requestOffset = reset ? 0 : _offset;

    try {
      if (reset) {
        await OdooAuthService.instance.sessionMe();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = _messageForUser(e);
      });
      return;
    }

    try {
      final raw = await _facade.adminAccountRequests(
        _listParams(requestOffset),
      );
      final page = AcpecAccountRequestMapper.parseListEnvelope(
        raw,
        requestedOffset: requestOffset,
        limit: AdminAcpecAccountRequestsScreen.pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items = List<AccountRequestItem>.from(page.items);
        } else {
          _items = [..._items, ...page.items];
        }
        _totalCount = page.totalCount ?? _totalCount;
        _offset = _items.length;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (reset) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = _messageForUser(e);
        });
      } else {
        setState(() => _loadingMore = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageForUser(e))));
      }
    }
  }

  Future<void> _onFilterChanged(String? newState) async {
    if (_stateFilter == newState && _items.isNotEmpty) return;
    setState(() => _stateFilter = newState);
    await _load(reset: true);
  }

  Future<void> _approve(int id) async {
    try {
      await _facade.adminApproveAccountRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Demande approuvée.')));
      }
      await _load(reset: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageForUser(e))));
      }
    }
  }

  Future<void> _reject(AccountRequestItem item) async {
    if (item.id == null) return;
    final id = item.id!;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => RejectAccountRequestSheet(
        item: item,
        defaultReason: _defaultRejectReason,
        onCancel: () => Navigator.pop(sheetCtx),
        onConfirm: (r) => Navigator.pop(sheetCtx, r),
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _rejectBusy = true);
    try {
      await _facade.adminRejectAccountRequest(id, {'reason': reason});
      if (!mounted) return;
      await _load(reset: true);
      if (!mounted) return;
      final scheme = Theme.of(context).colorScheme;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.inverseSurface,
          content: Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: scheme.onInverseSurface,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demande rejetée',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: scheme.onInverseSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'État enregistré : rejected · Motif : ${_ellipsisSnippet(reason, 140)}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: scheme.onInverseSurface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
          action: _stateFilter == 'pending'
              ? SnackBarAction(
                  textColor: scheme.primary,
                  label: 'Voir rejetés',
                  onPressed: () {
                    if (!mounted) return;
                    _onFilterChanged('rejected');
                  },
                )
              : null,
        ),
      );
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_messageForUser(e)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_messageForUser(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _rejectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        title: Text(
          'Demandes de compte',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: AppLoadingLottie(size: 100))
          : _error != null && _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: scheme.error.withValues(alpha: 0.9),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _load(reset: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtre par état',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Tous',
                              selected: _stateFilter == null,
                              onTap: () => _onFilterChanged(null),
                            ),
                            _FilterChip(
                              label: 'En attente',
                              selected: _stateFilter == 'pending',
                              onTap: () => _onFilterChanged('pending'),
                            ),
                            _FilterChip(
                              label: 'Approuvés',
                              selected: _stateFilter == 'approved',
                              onTap: () => _onFilterChanged('approved'),
                            ),
                            _FilterChip(
                              label: 'Rejetés',
                              selected: _stateFilter == 'rejected',
                              onTap: () => _onFilterChanged('rejected'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.25,
                              ),
                              Center(
                                child: Text(
                                  'Aucune demande pour ce filtre.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i >= _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Center(
                                    child: _loadingMore
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: AppInlineLoading(size: 36),
                                          )
                                        : TextButton.icon(
                                            onPressed: () =>
                                                _load(reset: false),
                                            icon: const Icon(
                                              Icons.expand_more_rounded,
                                            ),
                                            label: const Text(
                                              'Charger la suite',
                                            ),
                                          ),
                                  ),
                                );
                              }
                              final item = _items[i];
                              final canOpenDetail =
                                  item.id != null &&
                                  (item.isApproved || item.isRejected);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _RequestCard(
                                  item: item,
                                  onTap: canOpenDetail
                                      ? () async {
                                          final changed = await context
                                              .push<bool>(
                                                '/admin/accounts/${item.id}',
                                                extra: item,
                                              );
                                          if (changed == true && mounted) {
                                            await _load(reset: true);
                                          }
                                        }
                                      : null,
                                  onApprove:
                                      item.id != null &&
                                          item.isPending &&
                                          !_rejectBusy
                                      ? () => _approve(item.id!)
                                      : null,
                                  onReject:
                                      item.id != null &&
                                          item.isPending &&
                                          !_rejectBusy
                                      ? () => _reject(item)
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RejectAccountRequestSheet extends StatefulWidget {
  const RejectAccountRequestSheet({
    super.key,
    required this.item,
    required this.defaultReason,
    required this.onCancel,
    required this.onConfirm,
  });

  final AccountRequestItem item;
  final String defaultReason;
  final VoidCallback onCancel;
  final void Function(String reason) onConfirm;

  @override
  State<RejectAccountRequestSheet> createState() =>
      _RejectAccountRequestSheetState();
}

class _RejectAccountRequestSheetState extends State<RejectAccountRequestSheet> {
  static const _presets = [
    'Dossier incomplet.',
    'Pièce d’identité illisible.',
    'Coordonnées invalides.',
  ];

  late final TextEditingController _reasonCtrl;

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController(text: widget.defaultReason);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String s) {
    setState(() => _reasonCtrl.text = s);
  }

  void _submit() {
    final r = _reasonCtrl.text.trim();
    if (r.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez un motif de rejet.')),
      );
      return;
    }
    widget.onConfirm(r);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
          boxShadow: AppColors.softShadow,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.cancel_outlined,
                        color: AppColors.danger.withValues(alpha: 0.95),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rejeter la demande',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Le serveur enregistre la demande en état « rejected » '
                            'avec le motif ci-dessous (champ JSON « reason »).',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: scheme.brightness == Brightness.dark ? 0.55 : 0.65,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Motifs rapides',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _presets)
                      ActionChip(
                        label: Text(
                          p,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => _applyPreset(p),
                        side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.4),
                        ),
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Motif (reason)',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirmer le rejet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    this.onTap,
    this.onApprove,
    this.onReject,
  });

  final AccountRequestItem item;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  static Color _stateColor(String s) {
    final n = s.toLowerCase();
    if (n.contains('pending') || n.contains('draft')) {
      return AppColors.warning;
    }
    if (n.contains('approv') || n.contains('done') || n.contains('accept')) {
      return AppColors.success;
    }
    if (n.contains('reject') || n.contains('refus') || n.contains('cancel')) {
      return AppColors.danger;
    }
    return AppColors.muted;
  }

  static String _stateLabelFr(String s) {
    final n = s.toLowerCase();
    if (n.contains('pending') || n == 'draft') return 'En attente';
    if (n.contains('approv') || n == 'done') return 'Approuvé';
    if (n.contains('reject') || n.contains('refus')) return 'Rejeté';
    return s;
  }

  static String _primaryLabel(AccountRequestItem item) {
    final name = item.raw['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    if (item.email != null && item.email!.trim().isNotEmpty) return item.email!;
    if (item.phone != null && item.phone!.trim().isNotEmpty) return item.phone!;
    if (item.companyName != null && item.companyName!.trim().isNotEmpty) {
      return item.companyName!;
    }
    return 'Demande de compte';
  }

  @override
  Widget build(BuildContext context) {
    final stColor = _stateColor(item.state);
    final motif = item.rejectionMotif;
    final scheme = Theme.of(context).colorScheme;
    final primary = _primaryLabel(item);
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
        boxShadow: AppColors.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [stColor, stColor.withValues(alpha: 0.45)],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            primary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: scheme.onSurface,
                              height: 1.2,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: stColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _stateLabelFr(item.state),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: stColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (item.email != null)
                          _MiniInfoChip(
                            icon: Icons.mail_outline_rounded,
                            text: item.email!,
                          ),
                        if (item.phone != null)
                          _MiniInfoChip(
                            icon: Icons.phone_outlined,
                            text: item.phone!,
                          ),
                        if (item.companyName != null)
                          _MiniInfoChip(
                            icon: Icons.business_outlined,
                            text: item.companyName!,
                          ),
                      ],
                    ),
                    if (item.email != null) ...[
                      const SizedBox(height: 10),
                      _RowIcon(
                        icon: Icons.mail_outline_rounded,
                        text: item.email!,
                      ),
                    ],
                    if (item.phone != null) ...[
                      const SizedBox(height: 6),
                      _RowIcon(icon: Icons.phone_outlined, text: item.phone!),
                    ],
                    if (item.companyName != null) ...[
                      const SizedBox(height: 6),
                      _RowIcon(
                        icon: Icons.business_outlined,
                        text: item.companyName!,
                      ),
                    ],
                    if (item.createdAt != null) ...[
                      const SizedBox(height: 6),
                      _RowIcon(
                        icon: Icons.schedule_rounded,
                        text: Formatters.dateTime(item.createdAt!),
                      ),
                    ],
                    if (motif != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSurface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.notes_rounded,
                              size: 18,
                              color: AppColors.danger.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                motif,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (onApprove != null || onReject != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (onApprove != null)
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: onApprove,
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 20,
                                ),
                                label: const Text('Approuver'),
                                style: FilledButton.styleFrom(
                                  foregroundColor: AppColors.success,
                                  backgroundColor: AppColors.success.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                              ),
                            ),
                          if (onApprove != null && onReject != null)
                            const SizedBox(width: 10),
                          if (onReject != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onReject,
                                icon: Icon(
                                  Icons.cancel_outlined,
                                  size: 20,
                                  color: AppColors.danger.withValues(
                                    alpha: 0.95,
                                  ),
                                ),
                                label: Text(
                                  'Rejeter',
                                  style: TextStyle(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.95,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}


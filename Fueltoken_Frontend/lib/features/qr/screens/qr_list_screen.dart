import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/history_aligned_page_header.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';

class QrListScreen extends StatefulWidget {
  const QrListScreen({super.key});

  @override
  State<QrListScreen> createState() => _QrListScreenState();
}

class _QrListScreenState extends State<QrListScreen> {
  QrState? _filterState;
  List<QrToken> _liveQrs = [];
  bool _liveLoading = false;
  String? _liveError;

  static const _filters = <(String, QrState?)>[
    ('Tous', null),
    ('Actifs', QrState.active),
    ('Bloqués', QrState.blocked),
    ('Consommés', QrState.consumed),
    ('Expirés', QrState.expired),
  ];

  late final VoidCallback _qrBusListener;

  @override
  void initState() {
    super.initState();
    _filterState = QrState.active;
    _qrBusListener = () {
      if (mounted && AppEnvironment.useAcpecLiveData) {
        _refreshLive(force: true);
      }
    };
    QrRefreshBus.instance.revision.addListener(_qrBusListener);
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _refreshLive(force: true),
      );
    }
  }

  @override
  void dispose() {
    QrRefreshBus.instance.revision.removeListener(_qrBusListener);
    super.dispose();
  }

  Map<String, dynamic> _listRpcParams() {
    if (_filterState == null) return <String, dynamic>{};
    return {'state': _filterState!.apiListState};
  }

  void _invalidateQrListCache({bool allVariants = false}) {
    if (!allVariants) {
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
        _listRpcParams(),
      );
      return;
    }

    const variants = <Map<String, dynamic>?>[
      null,
      <String, dynamic>{},
      <String, dynamic>{'state': 'active'},
      <String, dynamic>{'state': 'blocked'},
      <String, dynamic>{'state': 'consumed'},
      <String, dynamic>{'state': 'expired'},
    ];

    for (final params in variants) {
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
        params,
      );
    }
  }

  Future<void> _refreshLive({bool force = false}) async {
    if (!AppEnvironment.useAcpecLiveData) return;
    if (force) _invalidateQrListCache(allVariants: true);
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() {
      _liveLoading = true;
      _liveError = null;
    });
    try {
      final raw = await OdooFueltokenFacade().qrList(_listRpcParams());
      final list = AcpecQrMapper.listFromRpc(
        raw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      if (!mounted) return;
      setState(() {
        _liveQrs = list;
        _liveLoading = false;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : ErrorPresenter.message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = ErrorPresenter.isBackendUnavailable(e)
            ? ErrorPresenter.backendUnavailable()
            : ErrorPresenter.message(e);
      });
    }
  }

  Future<void> _onSelectTab(QrState? state) async {
    setState(() => _filterState = state);
    if (AppEnvironment.useAcpecLiveData) {
      await _refreshLive(force: true);
    } else {
      setState(() {});
    }
  }

  List<QrToken> _visibleQrs() {
    if (!AppEnvironment.useAcpecLiveData) return const [];
    return _liveQrs;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: _QrListShell(
            filterRow: _QrFilterRow(
              selected: _filterState,
              totalCount: 0,
              onSelected: _onSelectTab,
            ),
            child: const _QrLoadingSkeleton(),
          ),
        ),
      );
    }
    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: _QrListShell(
            filterRow: _QrFilterRow(
              selected: _filterState,
              totalCount: 0,
              onSelected: _onSelectTab,
            ),
            child: const ApiRequiredView(),
          ),
        ),
      );
    }

    final qrs = _visibleQrs();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: () => _refreshLive(force: true),
          child: _QrListShell(
            filterRow: _QrFilterRow(
              selected: _filterState,
              totalCount: qrs.length,
              onSelected: _onSelectTab,
            ),
            child: _liveLoading
                ? const _QrLoadingSkeleton()
                : qrs.isEmpty
                ? _QrEmptyState(
                    icon: _liveError != null
                        ? Icons.cloud_off_outlined
                        : Icons.filter_alt_off_rounded,
                    title: _liveError != null
                        ? 'Erreur de chargement'
                        : (_filterState == null
                              ? 'Aucun QR'
                              : 'Aucun résultat'),
                    message: _liveError != null
                        ? _liveError!
                        : (_filterState == null
                              ? 'Aucun QR n’est disponible pour le moment.'
                              : 'Ce filtre ne contient aucun QR. Essayez un autre filtre ou revenez à tous les résultats.'),
                    onRefresh: () => _refreshLive(force: true),
                    onClearFilter: _filterState == null
                        ? null
                        : () => _onSelectTab(null),
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: qrs.length + (_liveError != null ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      if (_liveError != null && i == 0) {
                        return BackendUnavailableBanner(
                          message: _liveError!,
                          onRetry: () {
                            _refreshLive(force: true);
                          },
                        );
                      }
                      final qr = qrs[_liveError != null ? i - 1 : i];
                      return _QrCompactListTile(qr: qr);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _QrListShell extends StatelessWidget {
  const _QrListShell({required this.filterRow, required this.child});

  final Widget filterRow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HistoryAlignedPageHeader(title: 'Mes QR'),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          clipBehavior: Clip.none,
          child: filterRow,
        ),
        const SizedBox(height: 18),
        Expanded(child: child),
      ],
    );
  }
}

class _QrLoadingSkeleton extends StatelessWidget {
  const _QrLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: const [
        AppLoadingSkeleton(
          style: AppLoadingSkeletonStyle.qrCards,
          itemCount: 4,
        ),
      ],
    );
  }
}

class _QrEmptyState extends StatelessWidget {
  const _QrEmptyState({
    required this.message,
    required this.onRefresh,
    this.onClearFilter,
    this.icon = Icons.qr_code_2,
    this.title = 'Aucun QR',
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRefresh;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.26,
          child: EmptyState(
            icon: icon,
            title: title,
            message: message,
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualiser'),
                ),
                if (onClearFilter != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onClearFilter,
                    icon: const Icon(Icons.layers_clear_rounded),
                    label: const Text('Voir tous les QR'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QrCompactListTile extends StatelessWidget {
  const _QrCompactListTile({required this.qr});

  final QrToken qr;

  QrState get _displayState =>
      qr.hasMixedExpiration ? QrState.blocked : qr.state;

  bool get _hasPublicCode => qr.publicCode.trim().isNotEmpty;

  String get _referenceLabel {
    final ref = (qr.internalRef ?? '').trim();
    return ref.isEmpty ? 'Référence QR indisponible' : ref;
  }

  DateTime? get _effectiveExpiration {
    final direct = qr.expiresAt;
    if (direct != null && direct.year > 1970) {
      return direct;
    }

    DateTime? fallback;
    for (final line in qr.lines) {
      final d = line.expirationDate;
      if (d.year <= 1970) {
        continue;
      }
      if (fallback == null || d.isBefore(fallback)) {
        fallback = d;
      }
    }
    return fallback;
  }

  String get _expirationLabel {
    final exp = _effectiveExpiration;
    if (exp == null) return 'Expiration non définie';
    return 'Expire dès ${Formatters.dateTimeDash(exp)}';
  }

  String get _stateDateLabel {
    switch (_displayState) {
      case QrState.consumed:
        final consumed = qr.consumedAt;
        if (consumed != null) {
          return 'Consommé le ${Formatters.dateTimeDash(consumed)}';
        }
        return 'Consommé';
      case QrState.expired:
        return _expirationLabel.replaceFirst('Expire dès', 'Expiré dès');
      case QrState.blocked:
        return qr.hasMixedExpiration
            ? 'Expiration partielle détectée'
            : 'Bloqué';
      case QrState.active:
        return _expirationLabel;
    }
  }

  void _openDetail(BuildContext context) {
    if (!_hasPublicCode) {
      return;
    }
    final seg = AppEnvironment.useAcpecLiveData
        ? Uri.encodeComponent(qr.publicCode)
        : qr.id;
    context.push('/qr/$seg');
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = _hasPublicCode;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: canOpen ? () => _openDetail(context) : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _QrCodeLeadingIcon(state: _displayState),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusBadge.qr(_displayState),
                        const Spacer(),
                        AmountInline(
                          amount: qr.totalAmount,
                          textAlign: TextAlign.right,
                          valueStyle: const TextStyle(
                            fontSize: 14.2,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDeep,
                          ),
                          unitStyle: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _referenceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _stateDateLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodeLeadingIcon extends StatelessWidget {
  const _QrCodeLeadingIcon({required this.state});

  final QrState state;

  Color get _foreground {
    switch (state) {
      case QrState.active:
        return AppColors.leaderGreen;
      case QrState.blocked:
        return AppColors.warning;
      case QrState.consumed:
        return AppColors.muted;
      case QrState.expired:
        return AppColors.danger;
    }
  }

  Color get _background {
    switch (state) {
      case QrState.active:
        return AppColors.successSurface;
      case QrState.blocked:
        return AppColors.warningSurface;
      case QrState.consumed:
        return AppColors.lineSoft;
      case QrState.expired:
        return AppColors.dangerSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.qr_code_2_rounded, color: _foreground, size: 25),
    );
  }
}

class _QrFilterRow extends StatelessWidget {
  const _QrFilterRow({
    required this.selected,
    required this.totalCount,
    required this.onSelected,
  });

  final QrState? selected;
  final int totalCount;
  final ValueChanged<QrState?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < _QrListScreenState._filters.length; i++) ...[
            _QrFilterChip(
              label: _QrListScreenState._filters[i].$1,
              selected: selected == _QrListScreenState._filters[i].$2,
              count: _QrListScreenState._filters[i].$2 == null
                  ? totalCount
                  : null,
              onTap: () => onSelected(_QrListScreenState._filters[i].$2),
            ),
            if (i != _QrListScreenState._filters.length - 1)
              const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _QrFilterChip extends StatelessWidget {
  const _QrFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            count == null ? label : '$label $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

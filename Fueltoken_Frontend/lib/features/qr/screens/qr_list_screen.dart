import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/mini_qr.dart';
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
  ];

  late final VoidCallback _qrBusListener;

  @override
  void initState() {
    super.initState();
    _qrBusListener = () {
      if (mounted && AppEnvironment.useAcpecLiveData) _refreshLive();
    };
    QrRefreshBus.instance.revision.addListener(_qrBusListener);
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLive());
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

  Future<void> _refreshLive() async {
    if (!AppEnvironment.useAcpecLiveData) return;
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
            : e.message;
        _liveQrs = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.toString().replaceFirst('Exception: ', '');
        _liveQrs = [];
      });
    }
  }

  Future<void> _onSelectTab(QrState? state) async {
    setState(() => _filterState = state);
    if (AppEnvironment.useAcpecLiveData) {
      await _refreshLive();
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
        body: SafeArea(
          child: ListView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            children: [
              AppLoadingSkeleton(
                style: AppLoadingSkeletonStyle.qrCards,
                itemCount: 4,
              ),
            ],
          ),
        ),
      );
    }
    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HistoryTitleBar(title: 'Mes QR', showBack: false),
              const SizedBox(height: 4),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    final qrs = _visibleQrs();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HistoryTitleBar(title: 'Mes QR', showBack: false),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QrFilterRow(
                    selected: _filterState,
                    totalCount: qrs.length,
                    onSelected: _onSelectTab,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                color: scheme.primary,
                onRefresh: () async => _refreshLive(),
                child: _liveLoading && qrs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        children: const [
                          AppLoadingSkeleton(
                            style: AppLoadingSkeletonStyle.qrCards,
                            itemCount: 4,
                          ),
                        ],
                      )
                    : qrs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.22,
                            child: EmptyState(
                              icon: Icons.qr_code_2,
                              title: 'Aucun QR',
                              message: _liveError != null
                                  ? _liveError!
                                  : 'Aucun QR ne correspond à ce filtre.',
                              action: AppEnvironment.useAcpecLiveData
                                  ? FilledButton.tonalIcon(
                                      onPressed: _refreshLive,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Actualiser'),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: qrs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) => _QRCard(qr: qrs[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTitleBar extends StatelessWidget {
  const _HistoryTitleBar({required this.title, this.showBack = true});

  final String title;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          if (showBack) ...[
            _HeaderButton(icon: Icons.chevron_left_rounded, onTap: () {}),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
          ),
          if (showBack) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.95)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, size: 22, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _QRCard extends StatelessWidget {
  const _QRCard({required this.qr});

  final QrToken qr;

  QrState get _displayState =>
      qr.hasMixedExpiration ? QrState.blocked : qr.state;

  String get _stateLabel => _displayState.label;

  String get _dateStateLabel {
    switch (_displayState) {
      case QrState.active:
        return 'Généré le';
      case QrState.blocked:
        return 'Bloqué depuis';
      case QrState.consumed:
        return 'Consommé le';
      case QrState.expired:
        return 'Expiré le';
    }
  }

  Color get _amountColor {
    switch (_displayState) {
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

  DateTime? get _displayDate {
    final created = qr.createdAt;
    if (created.millisecondsSinceEpoch > 0) return created;
    if (qr.expiresAt != null) return qr.expiresAt;
    DateTime? fallback;
    for (final line in qr.lines) {
      if (fallback == null || line.expirationDate.isBefore(fallback)) {
        fallback = line.expirationDate;
      }
    }
    return fallback;
  }

  String get _dateLabel =>
      '$_dateStateLabel ${DateFormat('dd-MM-yyyy HH:mm').format(_displayDate ?? DateTime.now())}';

  String get _amountLabel => Formatters.numberFr(qr.totalAmount);

  bool get _hasQuantity => qr.totalQty > 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = _hasQuantity
        ? AppColors.leaderGreen.withValues(alpha: 0.38)
        : scheme.outline.withValues(alpha: 0.12);
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          final seg = AppEnvironment.useAcpecLiveData
              ? Uri.encodeComponent(qr.publicCode)
              : qr.id;
          context.push('/qr/$seg');
        },
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: borderColor,
              width: _hasQuantity ? 1.3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _hasQuantity
                    ? AppColors.leaderGreen.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MiniQR(data: qr.publicCode, state: _displayState, size: 58),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _QrStateBadge(state: _displayState, label: _stateLabel),
                        Text(
                          _dateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                            height: 1,
                          ),
                        ),
                        if (_displayState == QrState.blocked)
                          Text(
                            'Blocage lié à des tickets expirés.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _amountLabel,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _amountColor,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const TextSpan(
                              text: ' MRU',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrStateBadge extends StatelessWidget {
  const _QrStateBadge({required this.state, required this.label});

  final QrState state;
  final String label;

  ({Color bg, Color fg, Color icon, IconData glyph}) get _palette {
    switch (state) {
      case QrState.active:
        return (
          bg: AppColors.successSurface,
          fg: AppColors.leaderGreenDark,
          icon: AppColors.leaderGreen,
          glyph: Icons.check_circle_rounded,
        );
      case QrState.blocked:
        return (
          bg: AppColors.warningSurface,
          fg: const Color(0xFF92400E),
          icon: AppColors.warning,
          glyph: Icons.lock_outline_rounded,
        );
      case QrState.consumed:
        return (
          bg: AppColors.lineSoft,
          fg: AppColors.body,
          icon: AppColors.muted,
          glyph: Icons.check_circle_rounded,
        );
      case QrState.expired:
        return (
          bg: AppColors.dangerSurface,
          fg: AppColors.danger,
          icon: AppColors.danger,
          glyph: Icons.hourglass_bottom_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(palette.glyph, size: 14, color: palette.icon),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: palette.fg,
              height: 1,
            ),
          ),
        ],
      ),
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
            style: GoogleFonts.inter(
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

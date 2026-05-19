import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/qr_token.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/empty_state.dart';
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
    ('Consommé', QrState.consumed),
  ];

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLive());
    }
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
      return const Scaffold(body: AppPageLoading());
    }
    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QrListHeader(onBack: () => popOrGoClientHome(context)),
              const SizedBox(height: 18),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    final qrs = _visibleQrs();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QrListHeader(onBack: () => popOrGoClientHome(context)),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _QrFilterRow(
                selected: _filterState,
                totalCount: qrs.length,
                onSelected: _onSelectTab,
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
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 100),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.24,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        ],
                      )
                    : qrs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
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
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
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

class _QrListHeader extends StatelessWidget {
  const _QrListHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Navigator.maybeOf(context)?.canPop() ?? false)
            _QrRoundButton(icon: Icons.chevron_left_rounded, onTap: onBack)
          else
            const SizedBox(width: 0),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Mes QR',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.7,
                  height: 1.0,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QRCard extends StatelessWidget {
  const _QRCard({required this.qr});

  final QrToken qr;

  String get _stateLabel => qr.state.label;

  String get _dateStateLabel {
    switch (qr.state) {
      case QrState.active:
        return 'Actif le';
      case QrState.blocked:
        return 'Bloqué le';
      case QrState.split:
        return 'Splittée le';
      case QrState.consumed:
        return 'Consommée le';
      case QrState.expired:
        return 'Expirée le';
    }
  }

  Color get _amountColor {
    switch (qr.state) {
      case QrState.active:
        return AppColors.leaderGreen;
      case QrState.blocked:
        return AppColors.warning;
      case QrState.split:
        return AppColors.accentViolet;
      case QrState.consumed:
        return AppColors.muted;
      case QrState.expired:
        return AppColors.danger;
    }
  }

  String get _ticketLabel =>
      '${qr.totalQty} ticket${qr.totalQty > 1 ? 's' : ''}';

  String get _dateLabel =>
      '$_dateStateLabel ${DateFormat('dd-MM-yyyy HH:mm').format(qr.createdAt)}';

  String get _amountLabel => Formatters.numberFr(qr.totalAmount);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
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
                  MiniQR(data: qr.publicCode, state: qr.state, size: 58),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _QrStateBadge(state: qr.state, label: _stateLabel),
                        const SizedBox(height: 7),
                        Text(
                          _ticketLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                                fontSize: 8,
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
      case QrState.split:
        return (
          bg: AppColors.accentVioletSoft,
          fg: AppColors.accentViolet,
          icon: AppColors.accentViolet,
          glyph: Icons.call_split_rounded,
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

class _QrRoundButton extends StatelessWidget {
  const _QrRoundButton({required this.icon, required this.onTap});

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
    final bg = selected ? AppColors.leaderGreen : Colors.white;
    final fg = selected ? Colors.white : AppColors.ink2;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? null
                : Border.all(color: AppColors.line.withValues(alpha: 0.5)),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.leaderGreen.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Text(
            count == null ? label : '$label $count',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

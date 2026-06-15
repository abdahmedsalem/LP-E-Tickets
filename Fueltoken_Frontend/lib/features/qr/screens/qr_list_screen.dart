import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/history_aligned_page_header.dart';
import '../../../shared/widgets/loading_skeleton.dart';
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
          onRefresh: _refreshLive,
          child: _QrListShell(
            filterRow: _QrFilterRow(
              selected: _filterState,
              totalCount: qrs.length,
              onSelected: _onSelectTab,
            ),
            child: _liveLoading && qrs.isEmpty
                ? const _QrLoadingSkeleton()
                : qrs.isEmpty
                ? _QrEmptyState(
                    message: _liveError != null
                        ? _liveError!
                        : 'Aucun QR ne correspond a ce filtre.',
                    onRefresh: _refreshLive,
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.84,
                        ),
                    itemCount: qrs.length,
                    itemBuilder: (ctx, i) => _QRCard(qr: qrs[i]),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
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
  const _QrEmptyState({required this.message, required this.onRefresh});

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.26,
          child: EmptyState(
            icon: Icons.qr_code_2,
            title: 'Aucun QR',
            message: message,
            action: FilledButton.tonalIcon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualiser'),
            ),
          ),
        ),
      ],
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

  bool get _hasQuantity => qr.totalQty > 0;
  bool get _hasPublicCode => qr.publicCode.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final borderColor = _hasQuantity
        ? AppColors.leaderGreen.withValues(alpha: 0.28)
        : AppColors.line.withValues(alpha: 0.95);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          if (!_hasPublicCode) return;
          final seg = AppEnvironment.useAcpecLiveData
              ? Uri.encodeComponent(qr.publicCode)
              : qr.id;
          context.push('/qr/$seg');
        },
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _QrThumbnail(data: qr.publicCode, state: _displayState),
                const SizedBox(height: 10),
                _QrStateBadge(state: _displayState, label: _stateLabel),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _amountLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w800,
                          color: _amountColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const TextSpan(
                        text: ' MRU',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                Text(
                  _dateLabel,
                  textAlign: TextAlign.center,
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
        ),
      ),
    );
  }
}

class _QrThumbnail extends StatelessWidget {
  const _QrThumbnail({required this.data, required this.state});

  final String data;
  final QrState state;

  Color get _color {
    switch (state) {
      case QrState.active:
        return AppColors.ink;
      case QrState.blocked:
        return const Color(0xFF92400E);
      case QrState.consumed:
        return AppColors.muted;
      case QrState.expired:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) {
      return Container(
        width: 86,
        height: 86,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: const Icon(
          Icons.qr_code_2_rounded,
          color: AppColors.muted,
          size: 30,
        ),
      );
    }
    return Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: QrImageView(
        data: trimmed,
        version: QrVersions.auto,
        backgroundColor: Colors.transparent,
        gapless: true,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: _color),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _color,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(palette.glyph, size: 13, color: palette.icon),
          const SizedBox(width: 4),
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
            style: GoogleFonts.poppins(
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

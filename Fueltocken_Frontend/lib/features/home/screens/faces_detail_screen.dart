import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Tickets disponibles — vue par face et par carnet.
class FacesDetailScreen extends StatefulWidget {
  const FacesDetailScreen({super.key});

  @override
  State<FacesDetailScreen> createState() => _FacesDetailScreenState();
}

class _FacesDetailScreenState extends State<FacesDetailScreen> {
  bool _liveLoading = false;
  String? _liveError;
  List<FaceLine> _liveLines = [];
  Map<String, int> _carnetSizeById = {};
  Map<String, int> _carnetSizeByCode = {};

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadLiveFaces();
        _loadCarnetSizes();
      });
    }
  }

  Future<void> _loadCarnetSizes() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    try {
      final result = await AcpecCarnetCatalogService.instance.loadAdminCatalog(
        companyId: AppEnvironment.companyIdForUser(user),
      );
      if (!mounted) return;
      final byId = <String, int>{};
      final byCode = <String, int>{};
      for (final type in result.types) {
        if (type.id.trim().isNotEmpty) {
          byId[type.id.trim()] = type.size;
        }
        if (type.code.trim().isNotEmpty) {
          byCode[type.code.trim().toUpperCase()] = type.size;
        }
      }
      setState(() {
        _carnetSizeById = byId;
        _carnetSizeByCode = byCode;
      });
    } catch (_) {
      // Fallback to local inference in the UI.
    }
  }

  Future<void> _loadLiveFaces() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() {
      _liveLoading = true;
      _liveError = null;
    });
    try {
      final raw = await OdooFueltokenFacade().faces(const <String, dynamic>{});
      final lines = AcpecFacesMapper.fromRpcResult(raw, ownerId: user.id);
      if (!mounted) return;
      setState(() {
        _liveLines = lines;
        _liveLoading = false;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int _carnetSizeFor(FaceLine line) {
    final byId = _carnetSizeById[line.carnetTypeId.trim()];
    if (byId != null && byId > 0) return byId;
    final byCode = _carnetSizeByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode > 0) return byCode;
    final raw = line.carnetTypeCode.trim();
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match != null) {
      final parsed = int.tryParse(match.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }
    return line.faceValue;
  }

  Future<void> _openCarnetDetail(FaceLine line) async {
    final carnetSize = _carnetSizeFor(line);
    final scheme = Theme.of(context).colorScheme;
    final stateLabel = line.isExpired
        ? 'Expiré'
        : line.availableQty > 0
        ? 'Disponible'
        : 'Indisponible';
    final stateColor = line.isExpired
        ? AppColors.danger
        : line.availableQty > 0
        ? AppColors.success
        : AppColors.warning;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final bottomPadding = MediaQuery.paddingOf(context).bottom + 16;
        return FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          heightFactor: 0.86,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ListView(
              padding: EdgeInsets.only(
                top: 10,
                left: 16,
                right: 16,
                bottom: bottomPadding,
              ),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FaceValueChip(value: line.faceValue, size: 58),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Carnet ${Formatters.numberFr(carnetSize)}',
                            style: GoogleFonts.inter(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Expire le ${DateFormat('dd-MM-yyyy HH:mm', 'fr_FR').format(line.expirationDate)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.muted,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formatters.numberFr(line.availableValue),
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        Text(
                          'MRU',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted.withValues(alpha: 0.95),
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _CarnetDetailSummaryCard(
                  totalLabel: 'Tickets disponibles',
                  totalValue: Formatters.numberFr(line.availableQty),
                  amountLabel: 'Valeur disponible',
                  amountValue:
                      '${Formatters.numberFr(line.availableValue)} MRU',
                  stateLabel: stateLabel,
                  stateColor: stateColor,
                ),
                const SizedBox(height: 14),
                _CarnetDetailStatsGrid(line: line),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TicketsHeader(onBack: () => popOrGoClientHome(context)),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    final allLines = _liveLines.where((l) => l.availableQty > 0).toList();
    final groupedByFaceValue = <int, List<FaceLine>>{};
    for (final line in allLines) {
      groupedByFaceValue.putIfAbsent(line.faceValue, () => []).add(line);
    }
    final faceValues = groupedByFaceValue.keys.toList()..sort();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _loadLiveFaces,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
            children: [
              _TicketsHeader(onBack: () => popOrGoClientHome(context)),
              const SizedBox(height: 14),
              ...(_liveLoading && allLines.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ]
                  : _liveError != null && allLines.isEmpty
                  ? [
                      EmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: "Erreur de chargement",
                        message: _liveError!,
                        action: FilledButton.tonalIcon(
                          onPressed: _loadLiveFaces,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Reessayer"),
                        ),
                      ),
                    ]
                  : allLines.isEmpty
                  ? [
                      EmptyState(
                        icon: Icons.layers_outlined,
                        title: "Aucun ticket disponible",
                        message:
                            "Le serveur a renvoye aucune ligne avec des quantites disponibles.",
                      ),
                    ]
                  : [
                      for (final faceValue in faceValues)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _FaceGroupCard(
                            faceValue: faceValue,
                            lines: groupedByFaceValue[faceValue]!,
                            carnetSizeFor: _carnetSizeFor,
                            onLineTap: _openCarnetDetail,
                          ),
                        ),
                    ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarnetDetailSummaryCard extends StatelessWidget {
  const _CarnetDetailSummaryCard({
    required this.totalLabel,
    required this.totalValue,
    required this.amountLabel,
    required this.amountValue,
    required this.stateLabel,
    required this.stateColor,
  });

  final String totalLabel;
  final String totalValue;
  final String amountLabel;
  final String amountValue;
  final String stateLabel;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalValue,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  amountLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  amountValue,
                  style: GoogleFonts.inter(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              stateLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: stateColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarnetDetailStatsGrid extends StatelessWidget {
  const _CarnetDetailStatsGrid({required this.line});

  final FaceLine line;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CarnetDetailMetric(
          label: 'Initial',
          value: Formatters.numberFr(line.initialQty),
        ),
        _CarnetDetailMetric(
          label: 'Disponibles',
          value: Formatters.numberFr(line.availableQty),
        ),
        _CarnetDetailMetric(
          label: 'Actifs QR',
          value: Formatters.numberFr(line.qrActiveQty),
        ),
        _CarnetDetailMetric(
          label: 'Bloqués QR',
          value: Formatters.numberFr(line.qrBlockedQty),
        ),
      ],
    );
  }
}

class _CarnetDetailMetric extends StatelessWidget {
  const _CarnetDetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.sizeOf(context).width - 42) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketsHeader extends StatelessWidget {
  const _TicketsHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Navigator.maybeOf(context)?.canPop() ?? false)
            _TicketsHeaderButton(onTap: onBack)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 8),
          Text(
            'Mes tickets',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
              height: 1.02,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketsHeaderButton extends StatelessWidget {
  const _TicketsHeaderButton({required this.onTap});

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
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 22,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _FaceGroupCard extends StatelessWidget {
  const _FaceGroupCard({
    required this.faceValue,
    required this.lines,
    required this.carnetSizeFor,
    required this.onLineTap,
  });

  final int faceValue;
  final List<FaceLine> lines;
  final int Function(FaceLine line) carnetSizeFor;
  final ValueChanged<FaceLine> onLineTap;

  @override
  Widget build(BuildContext context) {
    final totalQty = lines.fold<int>(0, (sum, line) => sum + line.availableQty);
    final groupValue = totalQty * faceValue;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FaceValueChip(value: faceValue, size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${Formatters.numberFr(totalQty)} tickets',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        Formatters.numberFr(groupValue),
                        style: GoogleFonts.inter(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      Text(
                        'MRU',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted.withValues(alpha: 0.95),
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.lineSoft)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: AppColors.lineSoft),
                  _FaceLineRow(
                    line: lines[i],
                    carnetSize: carnetSizeFor(lines[i]),
                    onTap: () => onLineTap(lines[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceLineRow extends StatelessWidget {
  const _FaceLineRow({
    required this.line,
    required this.carnetSize,
    required this.onTap,
  });

  final FaceLine line;
  final int carnetSize;
  final VoidCallback onTap;
  String get _expirationLabel =>
      DateFormat('dd-MM-yyyy HH:mm', 'fr_FR').format(line.expirationDate);

  @override
  Widget build(BuildContext context) {
    final qty = line.availableQty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Carnet ${Formatters.numberFr(carnetSize)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${Formatters.numberFr(line.availableValue)} MRU',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.body,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Expire le $_expirationLabel',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$qty',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'disponible',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.muted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

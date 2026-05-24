import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
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
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

/// carnets disponibles — vue par face et par carnet.
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
    final displayQty = _displayQty(line);
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
                          Formatters.numberFr(displayQty),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line.isExpired ? 'Expiré' : 'Disponibles',
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
                  totalLabel: line.isExpired
                      ? 'Carnets expirés'
                      : 'carnets disponibles',
                  totalValue: Formatters.numberFr(displayQty),
                  amountLabel: 'Expire le',
                  amountValue: DateFormat('dd-MM-yyyy HH:mm', 'fr_FR')
                      .format(line.expirationDate),
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
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: ListView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 88),
            children: [
              _HistoryTitleBar(title: 'Mes carnets', showBack: false),
              SizedBox(height: 20),
              AppLoadingSkeleton(
                style: AppLoadingSkeletonStyle.ticketGroups,
                itemCount: 3,
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
            children: [
              _HistoryTitleBar(title: 'Mes carnets', showBack: false),
              const SizedBox(height: 28),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    final allLines = _liveLines;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _loadLiveFaces,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 88),
            children: [
              _HistoryTitleBar(title: 'Mes carnets', showBack: false),
              const SizedBox(height: 20),
              ...(_liveLoading && allLines.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 10),
                        child: AppLoadingSkeleton(
                          style: AppLoadingSkeletonStyle.ticketGroups,
                          itemCount: 3,
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
                        title: "Aucun carnet disponible",
                        message:
                            "Le serveur n’a renvoyé aucune ligne avec des quantités de carnets disponibles.",
                      ),
                    ]
                  : [
                      for (final line in allLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _CarnetLineCard(
                            line: line,
                            carnetSize: _carnetSizeFor(line),
                            onTap: () => _openCarnetDetail(line),
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

class _HistoryTitleBar extends StatelessWidget {
  const _HistoryTitleBar({required this.title, this.showBack = false});

  final String title;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
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

int _displayQty(FaceLine line) {
  if (line.isExpired) return line.expiredQty > 0 ? line.expiredQty : 0;
  return math.min(line.availableQty, 15);
}

class _CarnetLineCard extends StatelessWidget {
  const _CarnetLineCard({
    required this.line,
    required this.carnetSize,
    required this.onTap,
  });

  final FaceLine line;
  final int carnetSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = line.isExpired ? AppColors.danger : AppColors.success;

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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FaceValueChip(value: line.faceValue, size: 60),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Carnet ${Formatters.numberFr(carnetSize)}',
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
                    const SizedBox.shrink(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: Text(
                          'Expire le',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd-MM-yyyy', 'fr_FR').format(
                          line.expirationDate,
                        ),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




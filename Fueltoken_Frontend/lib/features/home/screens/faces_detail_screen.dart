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
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

/// carnets disponibles â€” vue par face et par carnet.
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
  Map<String, int> _carnetSizeByName = {};
  Map<int, int> _carnetSizeByFaceValue = {};
  Map<String, String> _carnetNameById = {};
  Map<String, String> _carnetNameByCode = {};
  Map<int, String> _carnetNameByFaceValue = {};

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
      final byName = <String, int>{};
      final byFaceValue = <int, int>{};
      final nameById = <String, String>{};
      final nameByCode = <String, String>{};
      final nameByFaceValue = <int, String>{};
      for (final type in result.types) {
        if (type.id.trim().isNotEmpty) {
          byId[type.id.trim()] = type.size;
          nameById[type.id.trim()] = type.name;
        }
        if (type.code.trim().isNotEmpty) {
          byCode[type.code.trim().toUpperCase()] = type.size;
          nameByCode[type.code.trim().toUpperCase()] = type.name;
        }
        if (type.name.trim().isNotEmpty) {
          byName[type.name.trim().toLowerCase()] = type.size;
        }
        if (type.faceValue > 0 && !byFaceValue.containsKey(type.faceValue)) {
          byFaceValue[type.faceValue] = type.size;
          nameByFaceValue[type.faceValue] = type.name;
        }
      }
      setState(() {
        _carnetSizeById = byId;
        _carnetSizeByCode = byCode;
        _carnetSizeByName = byName;
        _carnetSizeByFaceValue = byFaceValue;
        _carnetNameById = nameById;
        _carnetNameByCode = nameByCode;
        _carnetNameByFaceValue = nameByFaceValue;
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
            ? 'Session expirÃ©e. Reconnectez-vous.'
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
    if (line.carnetFaceCount > 0) return line.carnetFaceCount;
    final byId = _carnetSizeById[line.carnetTypeId.trim()];
    if (byId != null && byId > 0) return byId;
    final byCode = _carnetSizeByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode > 0) return byCode;
    final byName = _carnetSizeByName[line.carnetTypeName.trim().toLowerCase()];
    if (byName != null && byName > 0) return byName;
    final byFaceValue = _carnetSizeByFaceValue[line.faceValue];
    if (byFaceValue != null && byFaceValue > 0) return byFaceValue;

    final nameMatch = RegExp(r'\d+').firstMatch(line.carnetTypeName);
    if (nameMatch != null) {
      final parsed = int.tryParse(nameMatch.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final raw = line.carnetTypeCode.trim();
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match != null) {
      final parsed = int.tryParse(match.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  String _carnetTypeLabelFor(FaceLine line) {
    final carnetSize = _carnetSizeFor(line);
    if (carnetSize > 0) {
      return Formatters.carnetTypeLabel(carnetSize, line.faceValue);
    }

    final byId = _carnetNameById[line.carnetTypeId.trim()];
    if (byId != null && byId.trim().isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(byId);
    }

    final byCode = _carnetNameByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode.trim().isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(byCode);
    }

    final byFaceValue = _carnetNameByFaceValue[line.faceValue];
    if (byFaceValue != null && byFaceValue.trim().isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(byFaceValue);
    }

    final rawName = line.carnetTypeName.trim();
    if (rawName.isNotEmpty) return Formatters.normalizeCarnetTypeLabel(rawName);

    final rawCode = line.carnetTypeCode.trim();
    if (rawCode.isNotEmpty) return rawCode;

    return 'Carnet';
  }

  Future<void> _openCarnetDetail(FaceLine line) async {
    final scheme = Theme.of(context).colorScheme;
    final totalQty = line.initialQty;
    final availableQty = line.availableQty;
    final activeQty = line.qrActiveQty;
    final blockedQty = line.qrBlockedQty;
    final consumedQty = line.consumedQty;
    final expiredQty = line.expiredQty;
    final displayQty = line.isExpired ? expiredQty : availableQty;
    final stateLabel = line.isExpired
        ? 'Expiré'
        : availableQty > 0
        ? 'Disponible'
        : 'Indisponible';
    final stateColor = line.isExpired
        ? AppColors.danger
        : availableQty > 0
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
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _carnetTypeLabelFor(line),
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text(
                                  'Expire le',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    Formatters.dateTimeDash(
                                      line.expirationDate,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            Formatters.numberFr(displayQty),
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            line.isExpired ? 'Expiré' : 'Disponibles',
                            textAlign: TextAlign.right,
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
                const SizedBox(height: 16),
                _CarnetDetailSummaryCard(
                  totalLabel: 'Quantité totale',
                  totalValue: Formatters.numberFr(totalQty),
                  amountLabel: 'Expire le',
                  amountValue: DateFormat(
                    'dd-MM-yyyy HH:mm',
                    'fr_FR',
                  ).format(line.expirationDate),
                  stateLabel: stateLabel,
                  stateColor: stateColor,
                ),
                const SizedBox(height: 14),
                _CarnetDetailStatsGrid(
                  availableQty: availableQty,
                  activeQty: activeQty,
                  blockedQty: blockedQty,
                  consumedQty: consumedQty,
                  expiredQty: expiredQty,
                ),
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
                            "Le serveur nâ€™a renvoyÃ© aucune ligne avec des quantitÃ©s de carnets disponibles.",
                      ),
                    ]
                  : [
                      for (final line in allLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _CarnetLineCard(
                            line: line,
                            carnetTypeLabel: _carnetTypeLabelFor(line),
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
  const _CarnetDetailStatsGrid({
    required this.availableQty,
    required this.activeQty,
    required this.blockedQty,
    required this.consumedQty,
    required this.expiredQty,
  });

  final int availableQty;
  final int activeQty;
  final int blockedQty;
  final int consumedQty;
  final int expiredQty;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CarnetDetailMetric(
          label: 'Disponibles',
          value: Formatters.numberFr(availableQty),
        ),
        _CarnetDetailMetric(
          label: 'Actifs QR',
          value: Formatters.numberFr(activeQty),
        ),
        _CarnetDetailMetric(
          label: 'Bloqués QR',
          value: Formatters.numberFr(blockedQty),
        ),
        _CarnetDetailMetric(
          label: 'Consommés',
          value: Formatters.numberFr(consumedQty),
        ),
        _CarnetDetailMetric(
          label: 'Expirés',
          value: Formatters.numberFr(expiredQty),
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

class _CarnetLineCard extends StatelessWidget {
  const _CarnetLineCard({
    required this.line,
    required this.carnetTypeLabel,
    required this.onTap,
  });

  final FaceLine line;
  final String carnetTypeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final availableColor = line.isExpired
        ? AppColors.danger
        : AppColors.leaderGreen;
    final availableLabel = line.isExpired ? 'Expiré' : 'Disponibles';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    carnetTypeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        '${Formatters.numberFr(line.availableQty)} tickets ${availableLabel.toLowerCase()}',
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: line.isExpired
                              ? availableColor
                              : AppColors.muted.withValues(alpha: 0.95),
                          height: 1.08,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Expire le ${Formatters.dateTimeDash(line.expirationDate)}',
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
    );
  }
}

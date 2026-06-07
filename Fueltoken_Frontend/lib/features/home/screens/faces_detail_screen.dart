import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/faces_refresh_bus.dart';
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

/// Carnets disponibles — vue par face et par carnet.
class FacesDetailScreen extends StatefulWidget {
  const FacesDetailScreen({super.key});

  @override
  State<FacesDetailScreen> createState() => _FacesDetailScreenState();
}

class _FacesDetailScreenState extends State<FacesDetailScreen> {
  bool _liveLoading = false;
  String? _liveError;
  List<FaceLine> _liveLines = [];
  _CarnetQuickFilter _quickFilter = _CarnetQuickFilter.all;
  Map<String, int> _carnetSizeById = {};
  Map<String, int> _carnetSizeByCode = {};
  Map<String, int> _carnetSizeByName = {};
  Map<int, int> _carnetSizeByFaceValue = {};
  Map<String, String> _carnetNameById = {};
  Map<String, String> _carnetNameByCode = {};
  Map<int, String> _carnetNameByFaceValue = {};

  late final VoidCallback _facesBusListener;

  @override
  void initState() {
    super.initState();
    _facesBusListener = () {
      if (mounted && AppEnvironment.useAcpecLiveData) _loadLiveFaces();
    };
    FacesRefreshBus.instance.revision.addListener(_facesBusListener);
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadLiveFaces();
        _loadCarnetSizes();
      });
    }
  }

  @override
  void dispose() {
    FacesRefreshBus.instance.revision.removeListener(_facesBusListener);
    super.dispose();
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

  bool _matchesQuickFilter(FaceLine line) {
    switch (_quickFilter) {
      case _CarnetQuickFilter.all:
        return true;
      case _CarnetQuickFilter.active:
        return !line.isExpired;
      case _CarnetQuickFilter.expired:
        return line.isExpired;
    }
  }

  void _setQuickFilter(_CarnetQuickFilter next) {
    if (_quickFilter == next) return;
    setState(() => _quickFilter = next);
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
    final bottom = MediaQuery.paddingOf(context).bottom;
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
    final facts = <_CarnetDetailFact>[
      _CarnetDetailFact(
        label: 'Etat',
        value: stateLabel,
        icon: Icons.verified_outlined,
        color: stateColor,
      ),
      _CarnetDetailFact(
        label: 'Expire le',
        value: Formatters.dateTime(line.expirationDate),
        icon: Icons.event_outlined,
        color: const Color(0xFF2563EB),
      ),
      _CarnetDetailFact(
        label: 'Valeur faciale',
        value: '${Formatters.numberFr(line.faceValue)} MRU',
        icon: Icons.payments_outlined,
        color: AppColors.primaryDeep,
      ),
      _CarnetDetailFact(
        label: 'Tickets totaux',
        value: Formatters.numberFr(totalQty),
        icon: Icons.confirmation_number_outlined,
        color: const Color(0xFF1B8F3A),
      ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.54,
          minChildSize: 0.36,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return DecoratedBox(
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
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottom),
                      children: [
                        _CarnetDetailOverviewCard(
                          title: _carnetTypeLabelFor(line),
                          expirationDate: line.expirationDate,
                          displayQty: displayQty,
                          stateLabel: stateLabel,
                          stateColor: stateColor,
                        ),
                        const SizedBox(height: 14),
                        _CarnetDetailFactsGrid(facts: facts),
                        const SizedBox(height: 16),
                        Text(
                          'Repartition des tickets',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                ],
              ),
            );
          },
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            children: [
              const _LeftAlignedHeader(title: 'Mes carnets'),
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
              const _LeftAlignedHeader(title: 'Mes carnets'),
              const SizedBox(height: 28),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    final allLines = _liveLines.where(_matchesQuickFilter).toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _loadLiveFaces,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            children: [
              const _LeftAlignedHeader(title: 'Mes carnets'),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _CarnetFilterChips(
                  selected: _quickFilter,
                  onSelected: _setQuickFilter,
                ),
              ),
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
                        title: "Aucun carnet",
                        message:
                            "Vous n'avez encore aucun carnet disponible.",
                      ),
                    ]
                  : [
                      for (final line in allLines)
                        _CarnetLineCard(
                          line: line,
                          carnetTypeLabel: _carnetTypeLabelFor(line),
                          onTap: () => _openCarnetDetail(line),
                        ),
                    ]),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CarnetQuickFilter { all, active, expired }

class _LeftAlignedHeader extends StatelessWidget {
  const _LeftAlignedHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Align(
        alignment: Alignment.centerLeft,
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
    );
  }
}

class _CarnetFilterChips extends StatelessWidget {
  const _CarnetFilterChips({
    required this.selected,
    required this.onSelected,
  });

  final _CarnetQuickFilter selected;
  final ValueChanged<_CarnetQuickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_CarnetQuickFilter.all, 'Tous'),
      (_CarnetQuickFilter.active, 'Actifs'),
      (_CarnetQuickFilter.expired, 'Expirés'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _CarnetFilterChip(
              label: items[i].$2,
              selected: selected == items[i].$1,
              onTap: () => onSelected(items[i].$1),
            ),
            if (i != items.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _CarnetFilterChip extends StatelessWidget {
  const _CarnetFilterChip({
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
            label,
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

class _CarnetDetailOverviewCard extends StatelessWidget {
  const _CarnetDetailOverviewCard({
    required this.title,
    required this.expirationDate,
    required this.displayQty,
    required this.stateLabel,
    required this.stateColor,
  });

  final String title;
  final DateTime expirationDate;
  final int displayQty;
  final String stateLabel;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.layers_outlined, color: AppColors.primaryDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Expire le ${Formatters.dateTime(expirationDate)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  stateLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: stateColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.numberFr(displayQty)} tickets',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: stateColor,
                    height: 1,
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

class _CarnetDetailFactsGrid extends StatelessWidget {
  const _CarnetDetailFactsGrid({required this.facts});

  final List<_CarnetDetailFact> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final fact in facts) _CarnetDetailFactCard(fact: fact)],
    );
  }
}

class _CarnetDetailFactCard extends StatelessWidget {
  const _CarnetDetailFactCard({required this.fact});

  final _CarnetDetailFact fact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: (MediaQuery.sizeOf(context).width - 42) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(fact.icon, size: 16, color: fact.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fact.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fact.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarnetDetailFact {
  const _CarnetDetailFact({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
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
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        '${Formatters.numberFr(line.availableQty)} tickets ${availableLabel.toLowerCase()}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
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

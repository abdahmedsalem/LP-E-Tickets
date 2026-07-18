import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_host.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/list_screen_header.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Carnets disponibles - vue par face et par carnet.
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
  Map<String, String> _carnetCurrencyById = {};
  Map<String, String> _carnetCurrencyByCode = {};
  Map<int, String> _carnetCurrencyByFaceValue = {};

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

  // Load catalog metadata so carnet labels can be inferred consistently.
  Future<void> _loadCarnetSizes() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    try {
      final result = await AcpecCarnetCatalogService.instance
          .loadMobileCatalogFacesOnly(
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
      final currencyById = <String, String>{};
      final currencyByCode = <String, String>{};
      final currencyByFaceValue = <int, String>{};
      for (final type in result.types) {
        final currency = type.displayCurrency.trim();
        if (type.id.trim().isNotEmpty) {
          final key = type.id.trim();
          byId[key] = type.size;
          nameById[key] = type.name;
          if (currency.isNotEmpty) {
            currencyById[key] = currency;
          }
        }
        if (type.code.trim().isNotEmpty) {
          final key = type.code.trim().toUpperCase();
          byCode[key] = type.size;
          nameByCode[key] = type.name;
          if (currency.isNotEmpty) {
            currencyByCode[key] = currency;
          }
        }
        if (type.name.trim().isNotEmpty) {
          byName[type.name.trim().toLowerCase()] = type.size;
        }
        if (type.faceValue > 0 && !byFaceValue.containsKey(type.faceValue)) {
          byFaceValue[type.faceValue] = type.size;
          nameByFaceValue[type.faceValue] = type.name;
          if (currency.isNotEmpty) {
            currencyByFaceValue[type.faceValue] = currency;
          }
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
        _carnetCurrencyById = currencyById;
        _carnetCurrencyByCode = currencyByCode;
        _carnetCurrencyByFaceValue = currencyByFaceValue;
      });
    } catch (_) {
      // Fallback to local inference in the UI.
    }
  }

  // Fetch the live "Mes carnets" payload and map it into UI rows.
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
      if (e.requiresReLogin) {
        AuthSessionHost.instance.notifySessionExpired();
        return;
      }
      setState(() {
        _liveLoading = false;
        _liveError = ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = ErrorPresenter.localizedMessage(context, e);
      });
    }
  }

  // Filters only affect visibility, never the fetched data itself.
  bool _matchesQuickFilter(FaceLine line) {
    switch (_quickFilter) {
      case _CarnetQuickFilter.all:
        return true;
      case _CarnetQuickFilter.active:
        return !line.isExpired && line.availableQty > 0;
      case _CarnetQuickFilter.expired:
        return line.isExpired;
    }
  }

  void _setQuickFilter(_CarnetQuickFilter next) {
    if (_quickFilter == next) return;
    setState(() => _quickFilter = next);
  }

  // Resolve the carnet size from the strongest identifier available.
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

  // Keep raw labels readable by normalizing catalog text before display.
  String _normalizedCarnetLabel(
    String raw, {
    int? fallbackSize,
    int? fallbackFaceValue,
  }) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    return Formatters.normalizeCarnetTypeLabel(
      value,
      fallbackSize: fallbackSize,
      fallbackFaceValue: fallbackFaceValue,
    );
  }

  String _carnetTypeLabelFor(FaceLine line) {
    final rawName = line.carnetTypeName.trim();
    if (rawName.isNotEmpty) {
      return _normalizedCarnetLabel(rawName);
    }

    final byId = _carnetNameById[line.carnetTypeId.trim()];
    if (byId != null && byId.trim().isNotEmpty) {
      return _normalizedCarnetLabel(byId);
    }

    final byCode = _carnetNameByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode.trim().isNotEmpty) {
      return _normalizedCarnetLabel(byCode);
    }

    final byFaceValue = _carnetNameByFaceValue[line.faceValue];
    if (byFaceValue != null && byFaceValue.trim().isNotEmpty) {
      return _normalizedCarnetLabel(byFaceValue);
    }

    final rawCode = line.carnetTypeCode.trim();
    if (rawCode.isNotEmpty) return rawCode;

    final carnetSize = _carnetSizeFor(line);
    if (carnetSize > 0) {
      return AppLocalizations.of(context).carnetTypeFallback(
        Formatters.numberFr(carnetSize),
        Formatters.numberFr(line.faceValue),
        _currencyFor(line),
      );
    }

    return AppLocalizations.of(context).carnet;
  }

  String _currencyFor(FaceLine line) {
    final byId = _carnetCurrencyById[line.carnetTypeId.trim()];
    if (byId != null && byId.trim().isNotEmpty) return byId.trim();

    final byCode =
        _carnetCurrencyByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode.trim().isNotEmpty) return byCode.trim();

    final byFaceValue = _carnetCurrencyByFaceValue[line.faceValue];
    if (byFaceValue != null && byFaceValue.trim().isNotEmpty) {
      return byFaceValue.trim();
    }

    return '';
  }

  String _amountLabel(int amount, FaceLine line) {
    final currency = _currencyFor(line);
    final number = Formatters.numberFr(amount);
    return currency.isEmpty ? number : '$number $currency';
  }

  String _summaryAmountLabel(List<FaceLine> lines) {
    if (lines.isEmpty) return Formatters.numberFr(0);
    final amount = lines.fold<int>(0, (sum, line) => sum + line.availableValue);
    final ref = lines.firstWhere(
      (line) => _currencyFor(line).isNotEmpty,
      orElse: () => lines.first,
    );
    return _amountLabel(amount, ref);
  }

  String _carnetDisplayCodeFor(FaceLine line) {
    final shortCode = line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) {
      return shortCode;
    }

    final fallback = line.carnetNo.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }

    return AppLocalizations.of(context).carnetCodeUnavailable;
  }

  String _carnetFullNoFor(FaceLine line) {
    return line.carnetNo.trim();
  }

  // ignore: unused_element
  Future<void> _openCarnetDetail(FaceLine line) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final availableQty = line.availableQty;
    final activeQty = line.qrActiveQty;
    final blockedQty = line.qrBlockedQty;
    final consumedQty = line.consumedQty;
    final expiredQty = line.expiredQty;
    final displayQty = line.isExpired ? expiredQty : availableQty;
    final stateLabel = line.isExpired
        ? l10n.carnetStatusExpired
        : availableQty > 0
        ? l10n.carnetStatusAvailable
        : l10n.carnetStatusUnavailable;
    final stateColor = line.isExpired
        ? AppColors.danger
        : availableQty > 0
        ? AppColors.success
        : AppColors.warning;
    final carnetCode = _carnetDisplayCodeFor(line);
    final carnetTitle = '${l10n.carnet} $carnetCode';
    final carnetTypeLabel = _carnetTypeLabelFor(line);
    final fullCarnetNo = _carnetFullNoFor(line);
    final carnetSize = _carnetSizeFor(line);
    final ticketsAvailableLabel = _ticketAvailabilityLabel(
      availableQty,
      carnetSize,
    );
    final totalAmount = carnetSize > 0
        ? line.faceValue * carnetSize
        : line.availableValue;
    final availableAmountLabel = _amountLabel(line.availableValue, line);
    final totalAmountLabel = _amountLabel(totalAmount, line);
    // Use a full page when possible, otherwise fall back to a bottom sheet.
    final showDetailAsPage = context.mounted;
    if (showDetailAsPage) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _CarnetDetailScreen(
            title: carnetTitle,
            carnetTypeLabel: carnetTypeLabel,
            fullCarnetNo: fullCarnetNo,
            ticketsAvailableLabel: ticketsAvailableLabel,
            availableAmountLabel: availableAmountLabel,
            totalAmountLabel: totalAmountLabel,
            expirationDate: line.expirationDate,
            displayQty: displayQty,
            stateLabel: stateLabel,
            stateColor: stateColor,
            availableQty: availableQty,
            activeQty: activeQty,
            blockedQty: blockedQty,
            consumedQty: consumedQty,
            expiredQty: expiredQty,
          ),
        ),
      );
    } else {
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
                            title: carnetTitle,
                            carnetTypeLabel: carnetTypeLabel,
                            fullCarnetNo: fullCarnetNo,
                            ticketsAvailableLabel: ticketsAvailableLabel,
                            availableAmountLabel: availableAmountLabel,
                            totalAmountLabel: totalAmountLabel,
                            expirationDate: line.expirationDate,
                            displayQty: displayQty,
                            stateLabel: stateLabel,
                            stateColor: stateColor,
                            activeQty: activeQty,
                            consumedQty: consumedQty,
                          ),
                          const SizedBox(height: 14),
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
  }

  Widget _listHeader(
    AppLocalizations l10n, {
    required double horizontalPadding,
  }) {
    return ListScreenHeader<_CarnetQuickFilter>(
      title: l10n.carnetsTitle,
      horizontalPadding: horizontalPadding,
      options: [
        ListScreenFilterOption(
          value: _CarnetQuickFilter.all,
          label: l10n.filterAll,
        ),
        ListScreenFilterOption(
          value: _CarnetQuickFilter.active,
          label: l10n.filterAvailable,
        ),
        ListScreenFilterOption(
          value: _CarnetQuickFilter.expired,
          label: l10n.filterExpired,
        ),
      ],
      selected: _quickFilter,
      onSelected: _setQuickFilter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      // Keep the page shell visible while the session is not ready yet.
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: ListView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            children: [
              _listHeader(l10n, horizontalPadding: 10),
              const SizedBox(height: 16),
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
      // Explain why the list is empty when live ACPEC data is disabled.
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _listHeader(l10n, horizontalPadding: 26),
              const SizedBox(height: 16),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }

    // Apply the selected filter before rendering the visible list.
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
              _listHeader(l10n, horizontalPadding: 10),
              if (_liveLines.isNotEmpty) ...[
                const SizedBox(height: 14),
                // Summary cards only show once live data has been loaded.
                _CarnetsSummaryCard(
                  availableTickets: _liveLines.fold<int>(
                    0,
                    (sum, line) => sum + line.availableQty,
                  ),
                  availableAmountLabel: _summaryAmountLabel(_liveLines),
                  activeQrTickets: _liveLines.fold<int>(
                    0,
                    (sum, line) => sum + line.qrActiveQty,
                  ),
                  expiredTickets: _liveLines.fold<int>(
                    0,
                    (sum, line) => sum + line.expiredQty,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_liveError != null && allLines.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BackendUnavailableBanner(
                    message: _liveError!,
                    onRetry: () {
                      _loadLiveFaces();
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // The list can be loading, empty, errored, or populated.
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
                        title: l10n.carnetsLoadError,
                        message: _liveError!,
                        action: FilledButton.tonalIcon(
                          onPressed: _loadLiveFaces,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.commonRetry),
                        ),
                      ),
                    ]
                  : allLines.isEmpty
                  ? [
                      EmptyState(
                        icon: Icons.layers_outlined,
                        title: l10n.carnetsEmptyTitle,
                        message: l10n.carnetsEmptyMessage,
                      ),
                    ]
                  : [
                      for (final line in allLines)
                        _CarnetLineCard(
                          line: line,
                          carnetTypeLabel: _carnetTypeLabelFor(line),
                          carnetSize: _carnetSizeFor(line),
                          carnetCurrency: _currencyFor(line),
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

String _ticketAvailabilityLabel(int availableQty, int carnetSize) {
  final available = Formatters.numberFr(availableQty);
  if (carnetSize > 0) {
    return '$available/${Formatters.numberFr(carnetSize)}';
  }
  return available;
}

class _CarnetsSummaryCard extends StatelessWidget {
  const _CarnetsSummaryCard({
    required this.availableTickets,
    required this.availableAmountLabel,
    required this.activeQrTickets,
    required this.expiredTickets,
  });

  final int availableTickets;
  final String availableAmountLabel;
  final int activeQrTickets;
  final int expiredTickets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.carnetsSummaryTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CarnetSummaryMetric(
                  label: l10n.carnetsAvailableTickets,
                  value: Formatters.numberFr(availableTickets),
                  icon: Icons.confirmation_number_outlined,
                  accent: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CarnetSummaryMetric(
                  label: l10n.carnetsValue,
                  value: availableAmountLabel,
                  icon: Icons.payments_outlined,
                  accent: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CarnetSummaryMetric(
                  label: l10n.carnetsActiveQr,
                  value: Formatters.numberFr(activeQrTickets),
                  icon: Icons.qr_code_2_outlined,
                  accent: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CarnetSummaryMetric(
                  label: l10n.carnetsExpired,
                  value: Formatters.numberFr(expiredTickets),
                  icon: Icons.event_busy_outlined,
                  accent: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarnetSummaryMetric extends StatelessWidget {
  const _CarnetSummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.1,
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

// Full-screen detail view for one carnet, reused from the list tap action.
class _CarnetDetailScreen extends StatelessWidget {
  const _CarnetDetailScreen({
    required this.title,
    required this.carnetTypeLabel,
    required this.fullCarnetNo,
    required this.ticketsAvailableLabel,
    required this.availableAmountLabel,
    required this.totalAmountLabel,
    required this.expirationDate,
    required this.displayQty,
    required this.stateLabel,
    required this.stateColor,
    required this.availableQty,
    required this.activeQty,
    required this.blockedQty,
    required this.consumedQty,
    required this.expiredQty,
  });

  final String title;
  final String carnetTypeLabel;
  final String fullCarnetNo;
  final String ticketsAvailableLabel;
  final String availableAmountLabel;
  final String totalAmountLabel;
  final DateTime expirationDate;
  final int displayQty;
  final String stateLabel;
  final Color stateColor;
  final int availableQty;
  final int activeQty;
  final int blockedQty;
  final int consumedQty;
  final int expiredQty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: l10n.carnetDetailTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 20 + bottom),
                children: [
                  Text(
                    l10n.carnetDetailDescription,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CarnetDetailOverviewCard(
                    title: title,
                    carnetTypeLabel: carnetTypeLabel,
                    fullCarnetNo: fullCarnetNo,
                    ticketsAvailableLabel: ticketsAvailableLabel,
                    availableAmountLabel: availableAmountLabel,
                    totalAmountLabel: totalAmountLabel,
                    expirationDate: expirationDate,
                    displayQty: displayQty,
                    stateLabel: stateLabel,
                    stateColor: stateColor,
                    activeQty: activeQty,
                    consumedQty: consumedQty,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarnetDetailOverviewCard extends StatelessWidget {
  const _CarnetDetailOverviewCard({
    required this.title,
    required this.carnetTypeLabel,
    required this.fullCarnetNo,
    required this.ticketsAvailableLabel,
    required this.availableAmountLabel,
    required this.totalAmountLabel,
    required this.expirationDate,
    required this.displayQty,
    required this.stateLabel,
    required this.stateColor,
    required this.activeQty,
    required this.consumedQty,
  });

  final String title;
  final String carnetTypeLabel;
  final String fullCarnetNo;
  final String ticketsAvailableLabel;
  final String availableAmountLabel;
  final String totalAmountLabel;
  final DateTime expirationDate;
  final int displayQty;
  final String stateLabel;
  final Color stateColor;
  final int activeQty;
  final int consumedQty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amountLabel = availableAmountLabel.trim().isNotEmpty
        ? availableAmountLabel.trim()
        : totalAmountLabel.trim();

    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          _DetailInfoRow(
            label: l10n.referenceCode,
            value: title.trim().isNotEmpty ? title : l10n.notAvailable,
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _DetailInfoRow(
            label: l10n.carnetFullNumber,
            value: fullCarnetNo.trim().isNotEmpty
                ? fullCarnetNo
                : l10n.notAvailable,
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _DetailInfoRow(
            label: l10n.carnetsActiveQr,
            value: Formatters.numberFr(activeQty),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _DetailInfoRow(
            label: l10n.consumedQr,
            value: Formatters.numberFr(consumedQty),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _DetailInfoRow(
            label: l10n.availableAmount,
            value: amountLabel.isNotEmpty ? amountLabel : l10n.notAvailable,
          ),
        ],
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 7,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Main list row showing one carnet group and its remaining tickets.
class _CarnetLineCard extends StatefulWidget {
  const _CarnetLineCard({
    required this.line,
    required this.carnetTypeLabel,
    required this.carnetSize,
    required this.carnetCurrency,
  });

  final FaceLine line;
  final String carnetTypeLabel;
  final int carnetSize;
  final String carnetCurrency;

  @override
  State<_CarnetLineCard> createState() => _CarnetLineCardState();
}

class _CarnetLineCardState extends State<_CarnetLineCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  String get _titleLabel => widget.carnetTypeLabel.trim().isEmpty
      ? AppLocalizations.of(context).carnet
      : widget.carnetTypeLabel.trim();

  String get _availabilityLabel {
    final value = _ticketAvailabilityLabel(
      widget.line.availableQty,
      widget.carnetSize,
    );
    return value;
  }

  String _amountLabel(int amount) {
    final number = Formatters.numberFr(amount);
    return widget.carnetCurrency.trim().isEmpty
        ? number
        : '$number ${widget.carnetCurrency.trim()}';
  }

  String _carnetDisplayCodeFor(FaceLine line) {
    final shortCode = line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) {
      return shortCode;
    }

    final fallback = line.carnetNo.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }

    return AppLocalizations.of(context).carnetCodeUnavailable;
  }

  String _carnetFullNoFor(FaceLine line) {
    return line.carnetNo.trim();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final line = widget.line;
    final availableQty = line.availableQty;
    final expiredQty = line.expiredQty;
    final displayQty = line.isExpired ? expiredQty : availableQty;
    final activeQty = line.qrActiveQty;
    final consumedQty = line.consumedQty;
    final stateLabel = line.isExpired
        ? l10n.carnetStatusExpired
        : availableQty > 0
        ? l10n.carnetStatusAvailable
        : l10n.carnetStatusUnavailable;
    final stateColor = line.isExpired
        ? AppColors.danger
        : availableQty > 0
        ? AppColors.success
        : AppColors.warning;
    final carnetCode = _carnetDisplayCodeFor(line);
    final carnetTitle = l10n.carnetWithCode(carnetCode);
    final carnetTypeLabel = widget.carnetTypeLabel;
    final fullCarnetNo = _carnetFullNoFor(line);
    final carnetSize = widget.carnetSize;
    final ticketsAvailableLabel = _ticketAvailabilityLabel(
      availableQty,
      carnetSize,
    );
    final totalAmount = carnetSize > 0
        ? line.faceValue * carnetSize
        : line.availableValue;
    final availableAmountLabel = _amountLabel(line.availableValue);
    final totalAmountLabel = _amountLabel(totalAmount);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SingleLineCardTitle(
                          text: _titleLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _availabilityLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDeep,
                          height: 1,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.carnetExpiresOn(
                            Formatters.dateTimeDash(line.expirationDate),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: AppColors.muted,
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _CarnetDetailOverviewCard(
                              title: carnetTitle,
                              carnetTypeLabel: carnetTypeLabel,
                              fullCarnetNo: fullCarnetNo,
                              ticketsAvailableLabel: ticketsAvailableLabel,
                              availableAmountLabel: availableAmountLabel,
                              totalAmountLabel: totalAmountLabel,
                              expirationDate: line.expirationDate,
                              displayQty: displayQty,
                              stateLabel: stateLabel,
                              stateColor: stateColor,
                              activeQty: activeQty,
                              consumedQty: consumedQty,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

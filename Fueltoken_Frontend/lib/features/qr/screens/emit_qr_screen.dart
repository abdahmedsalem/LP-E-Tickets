import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/qr_refresh_bus.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import 'qr_action_confirmation_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

class EmitQrScreen extends StatefulWidget {
  const EmitQrScreen({super.key});
  @override
  State<EmitQrScreen> createState() => _EmitQrScreenState();
}

class _EmitQrScreenState extends State<EmitQrScreen> {
  final Map<String, int> _request = {};
  bool _emitting = false;
  bool _liveLoading = false;
  String? _liveError;
  List<CarnetType> _offerTypes = [];
  List<FaceLine> _liveFaceLines = [];

  static const String _unconfirmedQrIssueMessage =
      'Action non confirmée. Vérifiez la liste des QR avant de réessayer.';

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLiveFaces());
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
      final facesFuture = OdooFueltokenFacade().faces(const {});
      final typesFuture = AcpecCarnetCatalogService.instance
          .listPurchaseOfferTypes(
            companyId: AppEnvironment.companyIdForUser(user),
          )
          .catchError((_) => <CarnetType>[]);
      final raw = await facesFuture;
      final offerTypes = await typesFuture;
      final lines = AcpecFacesMapper.fromRpcResult(raw, ownerId: user.id);
      if (!mounted) return;
      setState(() {
        _liveFaceLines = lines;
        _offerTypes = offerTypes;
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

  String _qrIssueErrorMessage(Object error) {
    if (ErrorPresenter.isBackendUnavailable(error)) {
      return _unconfirmedQrIssueMessage;
    }

    final message = ErrorPresenter.message(error).trim();
    final lower = message.toLowerCase();

    final looksLikeInvalidPin =
        (lower.contains('pin') ||
            lower.contains('action_code') ||
            lower.contains('action code') ||
            lower.contains('code action')) &&
        (lower.contains('incorrect') ||
            lower.contains('invalide') ||
            lower.contains('invalid') ||
            lower.contains('refus'));

    if (looksLikeInvalidPin) {
      return 'PIN incorrect. L’opération n’a pas été effectuée.';
    }

    if (message.isEmpty) {
      return 'Le QR n’a pas été créé. Réessayez.';
    }
    return message;
  }

  int _lineCarnetSize(FaceLine line) {
    if (line.carnetFaceCount > 0) return line.carnetFaceCount;
    for (final type in _offerTypes) {
      if (type.id == line.carnetTypeId && type.size > 0) return type.size;
      if (type.code.isNotEmpty &&
          type.code == line.carnetTypeCode &&
          type.size > 0) {
        return type.size;
      }
      if (type.faceValue == line.faceValue && type.size > 0) return type.size;
    }
    return 1;
  }

  String _lineCarnetLabel(FaceLine line) {
    final shortCode = line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) return 'Carnet $shortCode';

    final size = _lineCarnetSize(line);
    return Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackSize: size,
      fallbackFaceValue: line.faceValue,
      fallbackCode: line.carnetTypeCode,
    );
  }

  List<FaceLine> _availableLinesFor(String ownerId) {
    final lines =
        _liveFaceLines
            .where(
              (f) => f.ownerId == ownerId && !f.isExpired && f.availableQty > 0,
            )
            .toList()
          ..sort((a, b) {
            if (a.faceValue != b.faceValue) {
              return a.faceValue.compareTo(b.faceValue);
            }
            final sizeCmp = _lineCarnetSize(a).compareTo(_lineCarnetSize(b));
            if (sizeCmp != 0) return sizeCmp;
            return a.expirationDate.compareTo(b.expirationDate);
          });
    return lines;
  }

  /// Corps de requête d'émission : sélection explicite par carnet.
  List<Map<String, dynamic>> _acpecIssueLinePayload(String ownerId) {
    final out = <Map<String, dynamic>>[];

    for (final line in _availableLinesFor(ownerId)) {
      final qty = _request[line.id] ?? 0;
      if (qty <= 0) continue;
      final take = qty < line.availableQty ? qty : line.availableQty;
      if (take <= 0) continue;

      final faceLineId = int.tryParse(line.id.trim());
      if (faceLineId == null || faceLineId <= 0) {
        continue;
      }

      out.add({'face_line_id': faceLineId, 'qty': take});
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Générer QR Code',
                onBack: () => popOrGo(context, '/qr'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 120),
                  children: [
                    Text(
                      'Sélectionnez les carnets à inclure dans le QR.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppLoadingSkeleton(
                      style: AppLoadingSkeletonStyle.qrGeneration,
                      itemCount: 4,
                    ),
                  ],
                ),
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
              ScreenHeader(
                title: 'Générer QR Code',
                onBack: () => popOrGo(context, '/qr'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  children: [
                    Text(
                      'Sélectionnez les carnets à inclure dans le QR Code.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ApiRequiredView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_liveLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Générer QR Code',
                onBack: () => popOrGo(context, '/qr'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  children: [
                    Text(
                      'Sélectionnez les carnets à inclure dans le QR Code.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppLoadingSkeleton(
                      style: AppLoadingSkeletonStyle.qrGeneration,
                      itemCount: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (AppEnvironment.useAcpecLiveData && _liveError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Générer QR Code',
                onBack: () => popOrGo(context, '/qr'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _liveError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.body),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadLiveFaces,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final availableLines = _availableLinesFor(user.id);
    final hasEntries = availableLines.isNotEmpty;
    final totalQty = _request.values.fold(0, (s, v) => s + v);
    final totalAmount = availableLines.fold<int>(0, (sum, line) {
      final qty = _request[line.id] ?? 0;
      return sum + (line.faceValue * qty);
    });

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: _BottomBar(
          totalAmount: totalAmount,
          emitting: _emitting,
          onEmit: totalQty == 0 || _emitting
              ? null
              : () => _confirmEmit(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: 'Générer QR Code',
              onBack: () => popOrGo(context, '/qr'),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: hasEntries
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
                      children: [
                        Text(
                          'Choisissez un carnet et une quantité.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: AppColors.muted,
                            height: 1.35,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...availableLines.map((line) {
                          final selected = _request[line.id] ?? 0;
                          return _CompositionRow(
                            title: _lineCarnetLabel(line),
                            faceValue: line.faceValue,
                            available: line.availableQty,
                            initialQty: line.initialQty,
                            carnetFaceCount: line.carnetFaceCount,
                            expirationDate: line.expirationDate,
                            selected: selected,
                            onChange: (n) => setState(() {
                              if (n <= 0) {
                                _request.remove(line.id);
                              } else {
                                _request[line.id] = n;
                              }
                            }),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    )
                  : const _EmptyAvailable(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEmit(BuildContext context) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    final availableLines = _availableLinesFor(user.id);
    final selectedLines = availableLines
        .where((line) => (_request[line.id] ?? 0) > 0)
        .toList();
    if (selectedLines.isEmpty) {
      AppMessage.warning(context, 'Sélectionnez au moins un carnet.');
      return;
    }

    final totalQty = selectedLines.fold<int>(0, (sum, line) {
      return sum + (_request[line.id] ?? 0);
    });
    final totalAmount = selectedLines.fold<int>(0, (sum, line) {
      return sum + (line.faceValue * (_request[line.id] ?? 0));
    });
    final successLines = selectedLines
        .map(
          (line) => QrGenerationSuccessLine(
            label: _lineCarnetLabel(line),
            qty: _request[line.id] ?? 0,
            faceValue: line.faceValue,
            expirationDate: line.expirationDate,
          ),
        )
        .toList(growable: false);

    final actionCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrActionConfirmationScreen(
          args: QrActionConfirmationArgs(
            title: 'Confirmer la génération',
            confirmLabel: 'Générer le QR',
            showHero: false,
            hero: _EmitConfirmationHero(
              totalQty: totalQty,
              totalAmount: totalAmount,
            ),
            details: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ConfirmationSectionHeader(title: 'Tickets à émettre'),
                const SizedBox(height: 14),
                _EmitConfirmationLinesSection(
                  lines: selectedLines,
                  request: _request,
                ),
              ],
            ),
            summaryRows: const [],
            disclaimer:
                'La génération créera un QR à partir des carnets sélectionnés.',
          ),
        ),
      ),
    );

    if (actionCode != null && actionCode.isNotEmpty) {
      final intent = SensitiveActionIntent.create('qr-issue');
      await _performEmit(
        actionCode: actionCode,
        intent: intent,
        totalQty: totalQty,
        totalAmount: totalAmount,
        successLines: successLines,
      );
    }
  }

  void _refreshClientReadModelsAfterQrIssue() {
    const qrListCacheVariants = <Map<String, dynamic>?>[
      null,
      <String, dynamic>{},
      <String, dynamic>{'state': 'active'},
      <String, dynamic>{'state': 'blocked'},
      <String, dynamic>{'state': 'consumed'},
      <String, dynamic>{'state': 'expired'},
    ];

    for (final params in qrListCacheVariants) {
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrList,
        params,
      );
    }

    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.faces,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.transactions,
      null,
    );

    QrRefreshBus.instance.bump();
    FacesRefreshBus.instance.bump();
    WalletRefreshBus.instance.bump();
    ClientHistoryRefreshBus.instance.bump();
  }

  Future<void> _performEmit({
    required String actionCode,
    required SensitiveActionIntent intent,
    required int totalQty,
    required int totalAmount,
    required List<QrGenerationSuccessLine> successLines,
  }) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() => _emitting = true);
    try {
      if (AppEnvironment.useAcpecLiveData) {
        final linesPayload = _acpecIssueLinePayload(user.id);
        if (linesPayload.isEmpty) {
          throw Exception('Aucune ligne à émettre (stock ou sélection vide).');
        }
        final raw = await OdooFueltokenFacade().qrIssue(
          intent.withAuthParams({
            'lines': linesPayload,
          }, actionCode: actionCode),
        );
        final guarded = acpecRpcMapOrThrow(
          raw,
          fallbackMessage: 'Émission QR refusée par le serveur.',
          publicErrorMessage:
              'L’émission du QR a échoué. Réessayez ou contactez l’administrateur.',
        );
        AcpecQrMapper.fromRpcIssueEnvelope(
          guarded,
          ownerId: user.id,
          ownerName: user.name,
          companyId: AppEnvironment.companyIdForUser(user),
        );
        if (!mounted) return;
        _refreshClientReadModelsAfterQrIssue();
        setState(() {
          _request.clear();
          _emitting = false;
        });
        if (!mounted) return;
        await showQrGenerationSuccessDialog(
          context,
          totalAmount: totalAmount,
          confirmedAt: DateTime.now(),
          lines: successLines,
        );
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go('/home');
          }
        });
        return;
      } else {
        throw Exception('Connexion serveur ACPEC requise pour générer un QR.');
      }
    } on OdooJsonRpcException catch (err) {
      if (mounted) {
        AppMessage.error(context, _qrIssueErrorMessage(err));
      }
      return;
    } catch (err) {
      if (mounted) {
        AppMessage.error(context, _qrIssueErrorMessage(err));
      }
      return;
    } finally {
      if (mounted) setState(() => _emitting = false);
    }
  }
}

// --------------------------------------------------------------------------
// Bottom bar: white summary card + green action button
// --------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.emitting,
    required this.onEmit,
  });

  final int totalAmount;
  final bool emitting;
  final VoidCallback? onEmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onEmit == null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.75)),
        boxShadow: AppColors.softShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MONTANT TOTAL QR',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _AmountInline(
                    amount: totalAmount,
                    valueStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                    unitStyle: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: disabled ? null : onEmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43A047),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(
                  0xFF43A047,
                ).withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                elevation: 0,
              ),
              child: emitting
                  ? const AppInlineLoading(size: 20)
                  : const Text(
                      'Générer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Composition row & stepper
// --------------------------------------------------------------------------

class _CompositionRow extends StatelessWidget {
  final String title;
  final int faceValue;
  final int available;
  final int initialQty;
  final int carnetFaceCount;
  final DateTime? expirationDate;
  final int selected;
  final ValueChanged<int> onChange;

  const _CompositionRow({
    required this.title,
    required this.faceValue,
    required this.available,
    required this.initialQty,
    required this.carnetFaceCount,
    required this.expirationDate,
    required this.selected,
    required this.onChange,
  });

  String _availabilityLabel() {
    final denominator = initialQty > 0
        ? initialQty
        : (carnetFaceCount > 0 ? carnetFaceCount : 0);

    if (denominator > 0 && denominator >= available) {
      return '${Formatters.numberFr(available)}/${Formatters.numberFr(denominator)} disponibles';
    }

    return '${Formatters.numberFr(available)} disponibles';
  }

  String _subtitle() {
    return 'Ticket ${Formatters.numberFr(faceValue)} ${Formatters.defaultCurrency} · ${_availabilityLabel()}';
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = selected > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 110),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          borderColor: isSelected ? AppColors.leaderGreen : AppColors.line,
          borderWidth: isSelected ? 1.5 : 1,
          shadow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 112),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _subtitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF667085),
                            height: 1.08,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      '${Formatters.numberFr(faceValue)} ${Formatters.defaultCurrency}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.08,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Container(height: 1, color: const Color(0xFFEAECEF)),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(
                    'Quantité',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                  const Spacer(),
                  _Stepper(value: selected, max: available, onChange: onChange),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChange;
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove,
          enabled: value > 0,
          onTap: () => onChange(value - 1),
          primary: false,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _StepBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChange(value + 1),
          primary: true,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: enabled
            ? (primary ? const Color(0xFF43A047) : const Color(0xFFF2F4F7))
            : const Color(0xFFF3F4F6),
        foregroundColor: enabled
            ? (primary ? Colors.white : const Color(0xFF344054))
            : const Color(0xFFB8BEC7),
        disabledBackgroundColor: const Color(0xFFF3F4F6),
        disabledForegroundColor: const Color(0xFFB8BEC7),
      ),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmitConfirmationHero extends StatelessWidget {
  const _EmitConfirmationHero({
    required this.totalQty,
    required this.totalAmount,
  });

  final int totalQty;
  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF43A047).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.qr_code_rounded,
            color: Color(0xFF2E7D32),
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Montant total QR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              _AmountInline(
                amount: totalAmount,
                valueStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF2E7D32),
                ),
                unitStyle: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$totalQty ticket${totalQty > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmitConfirmationLinesSection extends StatelessWidget {
  const _EmitConfirmationLinesSection({
    required this.lines,
    required this.request,
  });

  final List<FaceLine> lines;
  final Map<String, int> request;

  String _labelFor(FaceLine line) {
    final shortCode = line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) return 'Carnet $shortCode';

    return Formatters.normalizeCarnetTypeLabel(
      line.carnetTypeName,
      fallbackSize: line.carnetFaceCount,
      fallbackFaceValue: line.faceValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = lines.fold<int>(
      0,
      (sum, line) => sum + (line.faceValue * (request[line.id] ?? 0)),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            _EmitConfirmationLineRow(
              label: _labelFor(lines[i]),
              selectedQty: request[lines[i].id] ?? 0,
              faceValue: lines[i].faceValue,
              expirationDate: lines[i].expirationDate,
            ),
            if (i < lines.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
          ],
          if (lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(height: 1, color: const Color(0xFFE5E7EB)),
            ),
          _EmitConfirmationTotalRow(totalAmount: totalAmount),
        ],
      ),
    );
  }
}

class _EmitConfirmationTotalRow extends StatelessWidget {
  const _EmitConfirmationTotalRow({required this.totalAmount});

  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Montant total',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.body,
            ),
          ),
        ),
        _AmountInline(
          amount: totalAmount,
          textAlign: TextAlign.right,
          valueStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E7D32),
          ),
          unitStyle: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2E7D32).withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}

class _ConfirmationSectionHeader extends StatelessWidget {
  const _ConfirmationSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
  }
}

class _EmitConfirmationLineRow extends StatelessWidget {
  const _EmitConfirmationLineRow({
    required this.label,
    required this.selectedQty,
    required this.faceValue,
    required this.expirationDate,
  });

  final String label;
  final int selectedQty;
  final int faceValue;
  final DateTime expirationDate;

  String _title() {
    final qtyLabel =
        '${Formatters.numberFr(selectedQty)} ticket${selectedQty > 1 ? 's' : ''}';
    final carnetLabel = label.trim().isNotEmpty
        ? label.trim().replaceFirst(
            RegExp(r'^Carnet\s+', caseSensitive: false),
            '',
          )
        : 'Carnet';
    return '$qtyLabel de carnet $carnetLabel';
  }

  @override
  Widget build(BuildContext context) {
    final amount = selectedQty * faceValue;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Expire le ${Formatters.dateTimeDash(expirationDate)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AmountInline(
          amount: amount,
          textAlign: TextAlign.right,
          valueStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E7D32),
          ),
          unitStyle: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// Empty state
// --------------------------------------------------------------------------

class _EmptyAvailable extends StatelessWidget {
  const _EmptyAvailable();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.layers_clear_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucun ticket disponible',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Soumettez un achat de tickets et attendez la validation pour générer un QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.body),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountInline extends StatelessWidget {
  const _AmountInline({
    required this.amount,
    required this.valueStyle,
    required this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  final int amount;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Formatters.numberFr(amount), style: valueStyle),
          TextSpan(text: ' ${Formatters.defaultCurrency}', style: unitStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

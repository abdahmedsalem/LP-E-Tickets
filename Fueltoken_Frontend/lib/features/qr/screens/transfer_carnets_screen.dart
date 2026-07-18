import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../transfer_carnets_logic.dart';
import 'transfer_confirmation_screen.dart';
import '../../../shared/widgets/overview_info_card.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

bool _isReasonableExpirationDate(DateTime date) {
  return date.year > 1971 && date.year < 2100;
}

String _expirationLabel(DateTime date, AppLocalizations l10n) {
  if (!_isReasonableExpirationDate(date)) {
    return l10n.expirationUnknown;
  }
  return l10n.expiresOn(Formatters.dateTimeDash(date));
}

class TransferCarnetsScreen extends StatefulWidget {
  const TransferCarnetsScreen({super.key});

  @override
  State<TransferCarnetsScreen> createState() => _TransferCarnetsScreenState();
}

class _TransferCarnetsScreenState extends State<TransferCarnetsScreen> {
  final _phoneController = TextEditingController();
  final Map<String, int> _selectedQtyByLineId = <String, int>{};

  Map<String, int> _carnetSizeById = <String, int>{};
  Map<String, int> _carnetSizeByCode = <String, int>{};
  Map<String, int> _carnetSizeByName = <String, int>{};
  List<FaceLine> _faces = [];
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    _loading = AppEnvironment.useAcpecLiveData;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: ScreenHeader(
        title: AppLocalizations.of(context).transferCarnetsTitle,
        onBack: () {
          Navigator.of(context).maybePop();
        },
      ),
    );
  }

  int _carnetSizeFor(FaceLine line) {
    if (line.carnetFaceCount > 0) return line.carnetFaceCount;
    final byId = _carnetSizeById[line.carnetTypeId.trim()];
    if (byId != null && byId > 0) return byId;
    final byCode = _carnetSizeByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode > 0) return byCode;
    final byName = _carnetSizeByName[line.carnetTypeName.trim().toLowerCase()];
    if (byName != null && byName > 0) return byName;

    final nameMatch = RegExp(r'\d+').firstMatch(line.carnetTypeName);
    if (nameMatch != null) {
      final parsed = int.tryParse(nameMatch.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final match = RegExp(r'\d+').firstMatch(line.carnetTypeCode);
    if (match != null) {
      final parsed = int.tryParse(match.group(0)!);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  List<FaceLine> get _transferableFaces {
    final lines = <FaceLine>[];
    for (final line in _faces) {
      final size = _carnetSizeFor(line);
      if (!isTransferableCarnetLine(line, size)) continue;
      lines.add(line);
    }
    lines.sort((a, b) {
      final sizeA = _carnetSizeFor(a);
      final sizeB = _carnetSizeFor(b);
      if (a.faceValue != b.faceValue) return a.faceValue.compareTo(b.faceValue);
      if (sizeA != sizeB) return sizeA.compareTo(sizeB);
      return a.expirationDate.compareTo(b.expirationDate);
    });
    return lines;
  }

  int _selectedCarnetsFor(FaceLine line) => _selectedQtyByLineId[line.id] ?? 0;

  int _selectedCarnetsTotal() =>
      _selectedQtyByLineId.values.fold(0, (sum, qty) => sum + qty);

  int _selectedTransferAmount() {
    var total = 0;
    for (final line in _transferableFaces) {
      final qty = _selectedQtyByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      final size = _carnetSizeFor(line);
      total += qty * size * line.faceValue;
    }
    return total;
  }

  String _normalizeRecipientPhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('222') && digits.length == 11) {
      digits = digits.substring(3);
    }
    return digits;
  }

  Future<String?> _resolveRecipientName(String phone) async {
    final rawRecipient = await OdooFueltokenFacade().carnetsTransferRecipient({
      'recipient_phone': phone,
    });
    final data = rawRecipient is Map && rawRecipient['data'] is Map
        ? Map<String, dynamic>.from(rawRecipient['data'] as Map)
        : rawRecipient is Map
        ? Map<String, dynamic>.from(rawRecipient)
        : <String, dynamic>{};
    final resolvedName = data['recipient_name']?.toString().trim();
    if (resolvedName != null && resolvedName.isNotEmpty) {
      return resolvedName;
    }
    return null;
  }

  String _carnetTypeLabelFor(FaceLine line) {
    final rawName = line.carnetTypeName.trim();
    if (rawName.isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(
        rawName,
        fallbackSize: _carnetSizeFor(line),
        fallbackFaceValue: line.faceValue,
      );
    }

    final rawCode = line.carnetTypeCode
        .trim()
        .replaceAll(' ', '')
        .toUpperCase();
    if (rawCode.isNotEmpty) {
      if (RegExp(r'[A-Z]{3}$').hasMatch(rawCode)) {
        return rawCode;
      }
      return rawCode;
    }

    final size = _carnetSizeFor(line);
    if (size > 0) {
      return 'C${size}T-${line.faceValue}';
    }

    return AppLocalizations.of(context).carnet;
  }

  void _toggleLineSelection(FaceLine line) {
    final size = _carnetSizeFor(line);
    final maxCarnets = transferableCarnetCount(line, size);
    if (maxCarnets <= 0) return;
    final current = _selectedCarnetsFor(line);
    setState(() {
      if (current > 0) {
        _selectedQtyByLineId.remove(line.id);
      } else {
        _selectedQtyByLineId[line.id] = maxCarnets;
      }
    });
  }

  Future<void> _loadData() async {
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).commonServerUnavailable;
      });
      return;
    }

    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final companyId = AppEnvironment.companyIdForUser(user);
      final facesRaw = await OdooFueltokenFacade().faces(
        const <String, dynamic>{'transferable_only': true},
      );
      final catalogResult = await AcpecCarnetCatalogService.instance
          .loadMobileCatalogFacesOnly(companyId: companyId);

      final faces = AcpecFacesMapper.fromRpcResult(facesRaw, ownerId: user.id);
      final byId = <String, int>{};
      final byCode = <String, int>{};
      final byName = <String, int>{};
      for (final type in catalogResult.types) {
        if (type.id.trim().isNotEmpty) {
          byId[type.id.trim()] = type.size;
        }
        if (type.code.trim().isNotEmpty) {
          byCode[type.code.trim().toUpperCase()] = type.size;
        }
        if (type.name.trim().isNotEmpty) {
          byName[type.name.trim().toLowerCase()] = type.size;
        }
      }

      if (!mounted) return;
      setState(() {
        _faces = faces;
        _carnetSizeById = byId;
        _carnetSizeByCode = byCode;
        _carnetSizeByName = byName;
        _loading = false;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorPresenter.localizedMessage(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorPresenter.localizedMessage(context, e);
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    final phone = _normalizeRecipientPhone(_phoneController.text.trim());
    final currentUser = context.read<AuthBloc>().state.user;
    final currentPhone = _normalizeRecipientPhone(currentUser?.phone ?? '');

    if (currentPhone.isNotEmpty && phone == currentPhone) {
      AppMessage.warning(context, l10n.transferOwnCarnetsForbidden);
      return;
    }
    if (phone.isEmpty) {
      AppMessage.warning(context, l10n.recipientPhoneRequired);
      return;
    }
    if (phone.length != 8) {
      AppMessage.error(context, l10n.recipientPhoneInvalid);
      return;
    }

    // Construire les lignes de confirmation et les lignes API
    final confirmLines = <TransferConfirmationLine>[];
    final apiLines = <Map<String, dynamic>>[];
    for (final line in _transferableFaces) {
      final qty = _selectedQtyByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      final faceLineId = int.tryParse(line.id);
      if (faceLineId == null) {
        AppMessage.error(context, l10n.transferMissingCarnetLine);
        return;
      }
      final size = _carnetSizeFor(line);
      confirmLines.add(
        TransferConfirmationLine(
          faceLine: line,
          carnetQty: qty,
          carnetSize: size,
        ),
      );
      apiLines.add({'face_line_id': faceLineId, 'carnet_qty': qty});
    }

    if (confirmLines.isEmpty) {
      AppMessage.warning(context, l10n.transferSelectCarnet);
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      var recipientName = phone;
      try {
        final resolvedName = await _resolveRecipientName(phone);
        if (resolvedName != null) {
          recipientName = resolvedName;
        } else {
          if (!mounted) return;
          AppMessage.error(context, l10n.transferRecipientNotFound);
          return;
        }
      } catch (e) {
        if (!mounted) return;
        final errorMsg = ErrorPresenter.localizedMessage(context, e);
        AppMessage.error(context, errorMsg);
        return;
      }

      var confirmedRecipientName = recipientName;

      // Naviguer vers l'écran de confirmation
      if (!mounted) return;
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TransferConfirmationScreen(
            args: TransferConfirmationArgs(
              recipientPhone: phone,
              recipientName: recipientName,
              lines: confirmLines,
              title: l10n.transferConfirmTitle,
              introText: l10n.transferReviewCarnets,
              confirmLabel: l10n.transferConfirmTitle,
              sectionLabel: l10n.transferredCarnets,
              intentOperation: 'carnet-transfer',
              unconfirmedActionMessage: l10n.transferUnconfirmedCarnets,
              onConfirm: (actionCode, intent) async {
                final raw = await OdooFueltokenFacade().carnetsTransfer(
                  intent.withAuthParams({
                    'recipient_phone': phone,
                    'lines': apiLines,
                  }, actionCode: actionCode),
                );
                final data = acpecRpcMapOrThrow(
                  raw,
                  fallbackMessage: l10n.transferRejected,
                  publicErrorMessage: l10n.transferFailed,
                );
                final responseName = data['dest_partner']?.toString().trim();
                if (responseName != null && responseName.isNotEmpty) {
                  confirmedRecipientName = responseName;
                }
              },
            ),
          ),
        ),
      );

      if (!mounted) return;
      if (confirmed == true) {
        final totalAmount = confirmLines.fold(0, (s, l) => s + l.totalAmount);
        // Rafraîchir les sections concernées
        WalletRefreshBus.instance.bump();
        FacesRefreshBus.instance.bump();
        ClientHistoryRefreshBus.instance.bump();
        setState(() => _selectedQtyByLineId.clear());
        if (!mounted) return;
        await showTransferSuccessDialog(
          context,
          totalAmount: totalAmount,
          confirmedAt: DateTime.now(),
          recipientName: confirmedRecipientName,
          lines: confirmLines,
          linesTitle: l10n.transferredCarnets,
        );
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go('/home');
          }
        });
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AppLoadingSkeleton(
                    style: AppLoadingSkeletonStyle.qrGeneration,
                    itemCount: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadData,
                        child: Text(AppLocalizations.of(context).commonRetry),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final transferable = _transferableFaces;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: transferable.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _TransferSelectionBottomBar(
                  totalLabel: AppLocalizations.of(context).transferTotal,
                  totalAmount: _selectedTransferAmount(),
                  hasSelection: _selectedCarnetsTotal() > 0,
                  submitting: _submitting,
                  onSubmit: _submitting ? null : _submit,
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 132),
                children: [
                  if (transferable.isNotEmpty) ...[
                    Text(
                      AppLocalizations.of(context).transferCarnetsInstruction,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (transferable.isEmpty) ...[
                    EmptyState(
                      icon: Icons.send_rounded,
                      title: AppLocalizations.of(
                        context,
                      ).transferCarnetsEmptyTitle,
                      message: AppLocalizations.of(
                        context,
                      ).transferCarnetsEmptyMessage,
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        hintText: AppLocalizations.of(
                          context,
                        ).recipientPhoneHint,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.muted,
                        ),
                        suffixIcon: const Icon(
                          Icons.contact_page_outlined,
                          size: 20,
                          color: AppColors.muted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8DDE6),
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8DDE6),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.leaderGreen,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < transferable.length; i++) ...[
                      _TransferLineCard(
                        line: transferable[i],
                        carnetTypeLabel: _carnetTypeLabelFor(transferable[i]),
                        carnetSize: _carnetSizeFor(transferable[i]),
                        selected: _selectedCarnetsFor(transferable[i]),
                        onTap: () => _toggleLineSelection(transferable[i]),
                      ),
                      if (i < transferable.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferSelectionBottomBar extends StatelessWidget {
  const _TransferSelectionBottomBar({
    required this.totalLabel,
    required this.totalAmount,
    required this.hasSelection,
    required this.submitting,
    required this.onSubmit,
  });

  final String totalLabel;
  final int totalAmount;
  final bool hasSelection;
  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onSubmit == null || !hasSelection;
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
                  totalLabel,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AmountInline(
                    amount: totalAmount,
                    valueStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1,
                    ),
                    unitStyle: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
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
              onPressed: disabled ? null : onSubmit,
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
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).commonContinue,
                      style: const TextStyle(
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

class _TransferLineCard extends StatefulWidget {
  const _TransferLineCard({
    required this.line,
    required this.carnetTypeLabel,
    required this.carnetSize,
    required this.selected,
    required this.onTap,
  });

  final FaceLine line;
  final String carnetTypeLabel;
  final int carnetSize;
  final int selected;
  final VoidCallback onTap;

  @override
  State<_TransferLineCard> createState() => _TransferLineCardState();
}

class _TransferLineCardState extends State<_TransferLineCard> {
  bool _expanded = false;

  String _referenceCode() {
    final shortCode = widget.line.carnetShortCode.trim();
    if (shortCode.isNotEmpty) return shortCode;
    final typeCode = widget.line.carnetTypeCode.trim();
    if (typeCode.isNotEmpty) return typeCode;
    final carnetNo = widget.line.carnetNo.trim();
    if (carnetNo.isNotEmpty) return carnetNo;
    return AppLocalizations.of(context).carnetCodeUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final transferableValue =
        (line.availableQty ~/ widget.carnetSize) *
        widget.carnetSize *
        line.faceValue;
    final isSelected = widget.selected > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.leaderGreen
                  : const Color(0xFFEAECEF),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleLineCardTitle(
                      text: widget.carnetTypeLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AmountInline(amount: transferableValue),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: _expirationLabel(
                          line.expirationDate,
                          AppLocalizations.of(context),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: AppColors.muted,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: OverviewInfoCard(
                          items: [
                            OverviewInfoItem(
                              label: AppLocalizations.of(
                                context,
                              ).referenceIdentifier,
                              value: _referenceCode(),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

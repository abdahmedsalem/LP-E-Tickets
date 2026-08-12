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
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/overview_info_card.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';
import 'transfer_confirmation_screen.dart';

bool _isReasonableTicketExpirationDate(DateTime date) {
  return date.year > 1971 && date.year < 2100;
}

String _ticketExpirationLabel(DateTime date, AppLocalizations l10n) {
  if (!_isReasonableTicketExpirationDate(date)) {
    return l10n.expirationUnknown;
  }
  return l10n.expiresOn(Formatters.dateTimeDash(date));
}

class TransferTicketsScreen extends StatefulWidget {
  const TransferTicketsScreen({super.key});

  @override
  State<TransferTicketsScreen> createState() => _TransferTicketsScreenState();
}

class _TransferTicketsScreenState extends State<TransferTicketsScreen> {
  final _phoneController = TextEditingController();
  final Map<String, int> _selectedTicketsByLineId = <String, int>{};

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
        title: AppLocalizations.of(context).transferTicketsTitle,
        onBack: () {
          Navigator.of(context).maybePop();
        },
      ),
    );
  }

  List<FaceLine> get _transferableTicketLines {
    final lines = <FaceLine>[];
    for (final line in _faces) {
      if (line.isExpired) continue;
      if (line.availableQty <= 0) continue;
      lines.add(line);
    }
    lines.sort((a, b) {
      if (a.expirationDate != b.expirationDate) {
        return a.expirationDate.compareTo(b.expirationDate);
      }
      if (a.faceValue != b.faceValue) return a.faceValue.compareTo(b.faceValue);
      return a.carnetShortCode.compareTo(b.carnetShortCode);
    });
    return lines;
  }

  int _selectedTicketsFor(FaceLine line) =>
      _selectedTicketsByLineId[line.id] ?? 0;

  int _selectedTicketsTotal() =>
      _selectedTicketsByLineId.values.fold(0, (sum, qty) => sum + qty);

  int _selectedTransferAmount() {
    var total = 0;
    for (final line in _transferableTicketLines) {
      final qty = _selectedTicketsByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      total += qty * line.faceValue;
    }
    return total;
  }

  void _setSelectedTickets(FaceLine line, int qty) {
    final safeQty = qty.clamp(0, line.availableQty).toInt();
    setState(() {
      if (safeQty <= 0) {
        _selectedTicketsByLineId.remove(line.id);
      } else {
        _selectedTicketsByLineId[line.id] = safeQty;
      }
    });
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
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    return label.isNotEmpty ? label : AppLocalizations.of(context).carnet;
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
        const <String, dynamic>{},
      );
      final catalogResult = await AcpecCarnetCatalogService.instance
          .loadMobileCatalogFacesOnly(companyId: companyId);

      final faces = AcpecCarnetCatalogService.localizeFaceLinesByCarnetTypes(
        lines: AcpecFacesMapper.fromRpcResult(facesRaw, ownerId: user.id),
        types: catalogResult.types,
      );

      if (!mounted) return;
      setState(() {
        _faces = faces;
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
      AppMessage.warning(context, l10n.transferOwnTicketsForbidden);
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
    final confirmLines = <TransferConfirmationLine>[];
    final apiLines = <Map<String, dynamic>>[];
    for (final line in _transferableTicketLines) {
      final qty = _selectedTicketsByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      if (qty > line.availableQty) {
        AppMessage.error(context, l10n.transferTicketQuantityUnavailable);
        return;
      }
      final faceLineId = int.tryParse(line.id);
      if (faceLineId == null) {
        AppMessage.error(context, l10n.transferMissingTicketLine);
        return;
      }
      confirmLines.add(
        TransferConfirmationLine(faceLine: line, carnetQty: qty, carnetSize: 1),
      );
      apiLines.add({'face_line_id': faceLineId, 'qty_tickets': qty});
    }

    if (confirmLines.isEmpty) {
      AppMessage.warning(context, l10n.transferSelectTicket);
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

      if (!mounted) return;
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TransferConfirmationScreen(
            args: TransferConfirmationArgs(
              recipientPhone: phone,
              recipientName: recipientName,
              lines: confirmLines,
              showQuantity: true,
              title: l10n.transferConfirmTitle,
              introText: l10n.transferReviewTickets,
              confirmLabel: l10n.transferConfirmTitle,
              confirmIcon: Icons.confirmation_number_outlined,
              sectionLabel: l10n.transferredTickets,
              intentOperation: 'ticket-transfer',
              unconfirmedActionMessage: l10n.transferUnconfirmedTickets,
              onConfirm: (actionCode, intent) async {
                final raw = await OdooFueltokenFacade().ticketsTransfer(
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
        WalletRefreshBus.instance.bump();
        FacesRefreshBus.instance.bump();
        ClientHistoryRefreshBus.instance.bump();
        setState(() => _selectedTicketsByLineId.clear());
        if (!mounted) return;
        await showTransferSuccessDialog(
          context,
          totalAmount: totalAmount,
          confirmedAt: DateTime.now(),
          recipientName: confirmedRecipientName,
          lines: confirmLines,
          linesTitle: l10n.transferredTickets,
          showQuantity: true,
        );
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/home');
        });
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

    final transferable = _transferableTicketLines;

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
                  hasSelection: _selectedTicketsTotal() > 0,
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
                      AppLocalizations.of(context).transferTicketsInstruction,
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
                      icon: Icons.confirmation_number_outlined,
                      title: AppLocalizations.of(
                        context,
                      ).transferTicketsEmptyTitle,
                      message: AppLocalizations.of(
                        context,
                      ).transferTicketsEmptyMessage,
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
                      decoration: _inputDecoration(
                        hintText: AppLocalizations.of(
                          context,
                        ).recipientPhoneHint,
                        suffixIcon: Icons.contact_page_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < transferable.length; i++) ...[
                      _TransferTicketLineCard(
                        line: transferable[i],
                        carnetTypeLabel: _carnetTypeLabelFor(transferable[i]),
                        selected: _selectedTicketsFor(transferable[i]),
                        onChanged: (qty) =>
                            _setSelectedTickets(transferable[i], qty),
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

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.muted,
      ),
      suffixIcon: Icon(suffixIcon, size: 20, color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8DDE6), width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8DDE6), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.leaderGreen, width: 1.4),
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

class _TransferTicketLineCard extends StatefulWidget {
  const _TransferTicketLineCard({
    required this.line,
    required this.carnetTypeLabel,
    required this.selected,
    required this.onChanged,
  });

  final FaceLine line;
  final String carnetTypeLabel;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<_TransferTicketLineCard> createState() =>
      _TransferTicketLineCardState();
}

class _TransferTicketLineCardState extends State<_TransferTicketLineCard> {
  bool _expanded = false;

  String _ticketAvailabilityLabel(int availableQty, int carnetSize) {
    final available = Formatters.numberFr(availableQty);
    if (carnetSize > 0) {
      return '$available/${Formatters.numberFr(carnetSize)}';
    }
    return available;
  }

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
    final isSelected = widget.selected > 0;
    final availableQtyLabel = _ticketAvailabilityLabel(
      widget.line.availableQty,
      widget.line.carnetFaceCount > 0
          ? widget.line.carnetFaceCount
          : widget.line.availableQty,
    );
    final subtitleParts = <String>[
      _ticketExpirationLabel(
        widget.line.expirationDate,
        AppLocalizations.of(context),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.leaderGreen : AppColors.line,
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
              Text(
                availableQtyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
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
          Text(
            subtitleParts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF667085),
              height: 1.08,
            ),
          ),
          const SizedBox(height: 5),
          Container(height: 1, color: const Color(0xFFEAECEF)),
          const SizedBox(height: 1),
          Row(
            children: [
              Text(
                AppLocalizations.of(context).purchaseQuantity,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              _QtyButton(
                icon: Icons.remove,
                onTap: widget.selected <= 0
                    ? null
                    : () => widget.onChanged(widget.selected - 1),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 30,
                child: Text(
                  '${widget.selected}',
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
              _QtyButton(
                icon: Icons.add,
                onTap: widget.selected >= widget.line.availableQty
                    ? null
                    : () => widget.onChanged(widget.selected + 1),
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
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: onTap != null
            ? (icon == Icons.add
                  ? const Color(0xFF43A047)
                  : const Color(0xFFF2F4F7))
            : const Color(0xFFF3F4F6),
        foregroundColor: onTap != null
            ? (icon == Icons.add ? Colors.white : const Color(0xFF344054))
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

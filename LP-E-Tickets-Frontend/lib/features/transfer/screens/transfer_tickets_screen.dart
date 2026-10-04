import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/screen_header.dart';
import '../controllers/transfer_tickets_controller.dart';
import '../models/transfer_confirmation.dart';
import '../../../domain/models/transfer_inventory.dart';
import '../../../core/models/client_session.dart';
import '../widgets/transfer_selection_bottom_bar.dart';
import '../widgets/transfer_ticket_line_card.dart';
import 'transfer_tickets_confirmation_screen.dart';
import 'transfer_tickets_success_screen.dart';

class TransferTicketsScreen extends StatefulWidget {
  const TransferTicketsScreen({
    super.key,
    required this.session,
    required this.controller,
  });

  final ClientSession session;
  final TransferTicketsController controller;

  @override
  State<TransferTicketsScreen> createState() => _TransferTicketsScreenState();
}

class _TransferTicketsScreenState extends State<TransferTicketsScreen> {
  TransferTicketsController get _controller => widget.controller;
  final _phoneController = TextEditingController();
  final Map<String, int> _selectedTicketsByLineId = <String, int>{};

  List<TransferInventoryItem> _faces = [];
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
    _loading = widget.session.isLiveDataEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _controller.dispose();
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

  List<TransferInventoryItem> get _transferableTicketLines {
    final lines = <TransferInventoryItem>[];
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

  int _selectedTicketsFor(TransferInventoryItem line) =>
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

  void _setSelectedTickets(TransferInventoryItem line, int qty) {
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
    return _controller.recipientName(phone);
  }

  String _carnetTypeLabelFor(TransferInventoryItem line) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    return label.isNotEmpty ? label : AppLocalizations.of(context).carnet;
  }

  Future<void> _loadData() async {
    if (!widget.session.isLiveDataEnabled) {
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).commonServerUnavailable;
      });
      return;
    }

    final ownerId = widget.session.ownerId;
    final companyId = widget.session.companyId;
    if (ownerId == null || ownerId.isEmpty || companyId.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final catalogResult = await _controller.loadFaces(
        ownerId: ownerId,
        companyId: companyId,
      );
      final faces = catalogResult.faces;

      if (!mounted) return;
      setState(() {
        _faces = faces;
        _loading = false;
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
    final currentPhone = _normalizeRecipientPhone(widget.session.ownerPhone);

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
        TransferConfirmationLine(item: line, quantity: qty, unitSize: 1),
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
          builder: (_) => TransferTicketsConfirmationScreen(
            args: TransferConfirmationArgs(
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
                final data = await _controller.ticketsTransfer(
                  intent.withAuthParams({
                    'recipient_phone': phone,
                    'lines': apiLines,
                  }, actionCode: actionCode),
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
        await showTransferTicketsSuccessDialog(
          context,
          totalAmount: totalAmount,
          confirmedAt: DateTime.now(),
          recipientName: confirmedRecipientName,
          lines: confirmLines,
          linesTitle: l10n.transferredTickets,
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
                child: TransferSelectionBottomBar(
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
                      TransferTicketLineCard(
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

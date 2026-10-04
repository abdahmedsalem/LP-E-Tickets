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
import '../controllers/transfer_carnets_controller.dart';
import '../logic/transfer_carnets_logic.dart';
import '../models/transfer_confirmation.dart';
import '../../../domain/models/transfer_inventory.dart';
import '../../../core/models/client_session.dart';
import '../widgets/transfer_carnet_line_card.dart';
import '../widgets/transfer_selection_bottom_bar.dart';
import 'transfer_carnets_confirmation_screen.dart';
import 'transfer_carnets_success_screen.dart';

class TransferCarnetsScreen extends StatefulWidget {
  const TransferCarnetsScreen({
    super.key,
    required this.session,
    required this.controller,
  });

  final ClientSession session;
  final TransferCarnetsController controller;

  @override
  State<TransferCarnetsScreen> createState() => _TransferCarnetsScreenState();
}

class _TransferCarnetsScreenState extends State<TransferCarnetsScreen> {
  TransferCarnetsController get _controller => widget.controller;
  final _phoneController = TextEditingController();
  final Map<String, int> _selectedQtyByLineId = <String, int>{};

  Map<String, int> _carnetSizeById = <String, int>{};
  Map<String, int> _carnetSizeByCode = <String, int>{};
  Map<String, int> _carnetSizeByName = <String, int>{};
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
        title: AppLocalizations.of(context).transferCarnetsTitle,
        onBack: () {
          Navigator.of(context).maybePop();
        },
      ),
    );
  }

  int _carnetSizeFor(TransferInventoryItem line) {
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

  List<TransferInventoryItem> get _transferableFaces {
    final lines = <TransferInventoryItem>[];
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

  int _selectedCarnetsFor(TransferInventoryItem line) =>
      _selectedQtyByLineId[line.id] ?? 0;

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
    return _controller.recipientName(phone);
  }

  String _carnetTypeLabelFor(TransferInventoryItem line) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    return label.isNotEmpty ? label : AppLocalizations.of(context).carnet;
  }

  void _toggleLineSelection(TransferInventoryItem line) {
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
        TransferConfirmationLine(item: line, quantity: qty, unitSize: size),
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
          builder: (_) => TransferCarnetsConfirmationScreen(
            args: TransferConfirmationArgs(
              recipientName: recipientName,
              lines: confirmLines,
              title: l10n.transferConfirmTitle,
              introText: l10n.transferReviewCarnets,
              confirmLabel: l10n.transferConfirmTitle,
              sectionLabel: l10n.transferredCarnets,
              intentOperation: 'carnet-transfer',
              unconfirmedActionMessage: l10n.transferUnconfirmedCarnets,
              onConfirm: (actionCode, intent) async {
                final data = await _controller.carnetsTransfer(
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
        // Rafraîchir les sections concernées
        WalletRefreshBus.instance.bump();
        FacesRefreshBus.instance.bump();
        ClientHistoryRefreshBus.instance.bump();
        setState(() => _selectedQtyByLineId.clear());
        if (!mounted) return;
        await showTransferCarnetsSuccessDialog(
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
                child: TransferSelectionBottomBar(
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
                      TransferCarnetLineCard(
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

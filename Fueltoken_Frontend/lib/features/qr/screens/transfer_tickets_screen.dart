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
import '../../../shared/widgets/amount_inline.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../auth/bloc/auth_bloc.dart';
import 'transfer_confirmation_screen.dart';

bool _isReasonableTicketExpirationDate(DateTime date) {
  return date.year > 1971 && date.year < 2100;
}

String _ticketExpirationLabel(DateTime date) {
  if (!_isReasonableTicketExpirationDate(date)) {
    return 'Expiration non renseignée';
  }
  return 'Expire le ${Formatters.dateTimeDash(date)}';
}

class TransferTicketsScreen extends StatefulWidget {
  const TransferTicketsScreen({super.key});

  @override
  State<TransferTicketsScreen> createState() => _TransferTicketsScreenState();
}

class _TransferTicketsScreenState extends State<TransferTicketsScreen> {
  final _phoneController = TextEditingController();
  final Map<String, int> _selectedTicketsByLineId = <String, int>{};

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
        title: 'Transfert de tickets',
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
    final rawCode = line.carnetTypeCode
        .trim()
        .replaceAll(' ', '')
        .toUpperCase();
    if (rawCode.isNotEmpty) {
      if (RegExp(r'[A-Z]{3}$').hasMatch(rawCode)) {
        return rawCode;
      }
      return '$rawCode${Formatters.defaultCurrency}';
    }

    final size = _carnetSizeFor(line);
    if (size > 0) {
      return 'C${size}T-${line.faceValue}${Formatters.defaultCurrency}';
    }

    final rawName = line.carnetTypeName.trim();
    if (rawName.isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(
        rawName,
        fallbackSize: size,
        fallbackFaceValue: line.faceValue,
      );
    }

    return 'Carnet';
  }

  Future<void> _loadData() async {
    if (!AppEnvironment.useAcpecLiveData) {
      setState(() {
        _loading = false;
        _error = 'Connexion serveur ACPEC requise pour transférer des tickets.';
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

      final faces = AcpecFacesMapper.fromRpcResult(facesRaw, ownerId: user.id);
      final byId = <String, int>{};
      final byCode = <String, int>{};
      final byName = <String, int>{};
      for (final type in catalogResult.types) {
        if (type.id.trim().isNotEmpty) byId[type.id.trim()] = type.size;
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
        _error = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : ErrorPresenter.message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorPresenter.message(e);
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final phone = _normalizeRecipientPhone(_phoneController.text.trim());
    final currentUser = context.read<AuthBloc>().state.user;
    final currentPhone = _normalizeRecipientPhone(currentUser?.phone ?? '');

    if (currentPhone.isNotEmpty && phone == currentPhone) {
      AppMessage.warning(
        context,
        'Vous ne pouvez pas transférer des tickets vers votre propre compte.',
      );
      return;
    }
    if (phone.isEmpty) {
      AppMessage.warning(context, 'Saisissez le téléphone du destinataire.');
      return;
    }
    if (phone.length != 8) {
      AppMessage.error(
        context,
        'Le numéro du destinataire doit contenir 8 chiffres.',
      );
      return;
    }
    final confirmLines = <TransferConfirmationLine>[];
    final apiLines = <Map<String, dynamic>>[];
    for (final line in _transferableTicketLines) {
      final qty = _selectedTicketsByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      if (qty > line.availableQty) {
        AppMessage.error(
          context,
          'Quantité supérieure aux tickets disponibles.',
        );
        return;
      }
      final faceLineId = int.tryParse(line.id);
      if (faceLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de ticket manquant. Rechargez les carnets.',
        );
        return;
      }
      confirmLines.add(
        TransferConfirmationLine(faceLine: line, carnetQty: qty, carnetSize: 1),
      );
      apiLines.add({'face_line_id': faceLineId, 'qty_tickets': qty});
    }

    if (confirmLines.isEmpty) {
      AppMessage.warning(
        context,
        'Sélectionnez au moins un ticket à transférer.',
      );
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
          AppMessage.error(
            context,
            "Le client n'existe pas avec cet identifiant.",
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        final errorMsg = ErrorPresenter.message(e);
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
              noteRequired: true,
              noteLabel: 'Motif du transfert (facultatif)',
              noteHint:
                  'Facultatif. Si vide, le transfert sera enregistré sans motif renseigné.',
              title: 'Confirmer le transfert',
              introText: 'Vérifiez les tickets avant de confirmer.',
              confirmLabel: 'Confirmer le transfert',
              confirmIcon: Icons.confirmation_number_outlined,
              sectionLabel: 'Tickets transférés',
              intentOperation: 'ticket-transfer',
              unconfirmedActionMessage:
                  'Action non confirmée. Vérifiez l’état de vos tickets avant de réessayer.',
              onConfirmWithNote: (actionCode, intent, note) async {
                final raw = await OdooFueltokenFacade().ticketsTransfer(
                  intent.withAuthParams({
                    'recipient_phone': phone,
                    'note': note,
                    'lines': apiLines,
                  }, actionCode: actionCode),
                );
                final data = acpecRpcMapOrThrow(
                  raw,
                  fallbackMessage:
                      'Transfert de tickets refusé par le serveur.',
                  publicErrorMessage:
                      'Le transfert a échoué. Réessayez ou contactez l’administrateur.',
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
          recipientPhone: phone,
          lines: confirmLines,
          linesTitle: 'Tickets transférés',
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
                        child: const Text('Réessayer'),
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
                  totalLabel: 'TOTAL TRANSFERT',
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
                  Text(
                    'Entrez le numéro du destinataire, puis sélectionnez les tickets à transférer.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (transferable.isEmpty) ...[
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.48,
                      child: const EmptyState(
                        icon: Icons.confirmation_number_outlined,
                        title: 'Aucun ticket disponible',
                        message: 'Vos tickets disponibles apparaîtront ici',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Seuls les tickets disponibles et non expirés peuvent être transférés.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.body, height: 1.35),
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                      ),
                      decoration: _inputDecoration(
                        hintText: 'Numéro de téléphone',
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
                  alignment: Alignment.centerLeft,
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
                  : const Text(
                      'Continuer',
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

class _TransferTicketLineCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isSelected = selected > 0;
    final selectedAmount = selected * line.faceValue;
    final subtitleParts = <String>[
      _ticketExpirationLabel(line.expirationDate),
      '${Formatters.numberFr(line.availableQty)} ticket(s) disponible(s)',
    ];
    final carnetCode = line.carnetShortCode.trim().isNotEmpty
        ? line.carnetShortCode.trim()
        : line.carnetNo.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.leaderGreen : const Color(0xFFEAECEF),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      carnetTypeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.08,
                      ),
                    ),
                    if (carnetCode.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        carnetCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSelected ? AppColors.leaderGreen : AppColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subtitleParts.join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QtyButton(
                icon: Icons.remove_rounded,
                onTap: selected <= 0 ? null : () => onChanged(selected - 1),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: Text(
                  Formatters.numberFr(selected),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _QtyButton(
                icon: Icons.add_rounded,
                onTap: selected >= line.availableQty
                    ? null
                    : () => onChanged(selected + 1),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: selected == line.availableQty
                    ? null
                    : () => onChanged(line.availableQty),
                child: const Text('Tout'),
              ),
              const Spacer(),
              AmountInline(amount: selectedAmount, textAlign: TextAlign.right),
            ],
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
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: AppColors.leaderGreen,
          side: BorderSide(color: AppColors.line.withValues(alpha: 0.9)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

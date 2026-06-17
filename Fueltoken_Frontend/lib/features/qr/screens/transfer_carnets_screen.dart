import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/faces_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../transfer_carnets_logic.dart';
import 'transfer_confirmation_screen.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/amount_inline.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../shared/widgets/app_message.dart';

const _transferHeaderPadding = EdgeInsets.fromLTRB(12, 8, 12, 0);
const _transferHeaderGap = 18.0;
const _transferHeaderTitleSize = 32.0;
const _headerNavy = Color(0xFF0F2747);

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
  final bool _submitting = false;
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
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: AppBarHeader(
        title: 'Transférer',
        showBack: true,
        largeTitle: true,
        largeTitlePadding: _transferHeaderPadding,
        largeTitleGap: _transferHeaderGap,
        largeTitleFontSize: _transferHeaderTitleSize,
        largeTitleTextStyle: GoogleFonts.poppins(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: _headerNavy,
          letterSpacing: -0.4,
          height: 1.05,
        ),
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
      return Formatters.normalizeCarnetTypeLabel(rawName);
    }

    final rawCode = line.carnetTypeCode.trim();
    if (rawCode.isNotEmpty) {
      return rawCode;
    }

    final size = _carnetSizeFor(line);
    if (size > 0) {
      return Formatters.carnetTypeLabel(size, line.faceValue);
    }

    return 'Carnet';
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
        _error = 'Connexion serveur ACPEC requise pour transférer des carnets.';
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
          .loadAdminCatalog(companyId: companyId);

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
        _error = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _submit() async {
    final phone = _normalizeRecipientPhone(_phoneController.text.trim());
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

    // Construire les lignes de confirmation et les lignes API
    final confirmLines = <TransferConfirmationLine>[];
    final apiLines = <Map<String, dynamic>>[];
    for (final line in _transferableFaces) {
      final qty = _selectedQtyByLineId[line.id] ?? 0;
      if (qty <= 0) continue;
      final faceLineId = int.tryParse(line.id);
      if (faceLineId == null) {
        AppMessage.error(
          context,
          'Identifiant de face manquant. Rechargez les faces.',
        );
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
      AppMessage.warning(
        context,
        'Sélectionnez au moins un carnet à transférer.',
      );
      return;
    }

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
      final errorMsg = e is OdooJsonRpcException
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
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
            onConfirm: () async {
              final raw = await OdooFueltokenFacade().carnetsTransfer({
                'recipient_phone': phone,
                'lines': apiLines,
                'idempotency_key': 'ft-transfer-${const Uuid().v4()}',
              });
              final data = raw is Map && raw['data'] is Map
                  ? Map<String, dynamic>.from(raw['data'] as Map)
                  : raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : <String, dynamic>{};
              if (data.isEmpty) {
                throw Exception('Réponse de transfert invalide.');
              }
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
        recipientPhone: phone,
        lines: confirmLines,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/home');
        }
      });
      return;
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

    final transferable = _transferableFaces;

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: AppColors.line.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++) ...[
                Expanded(
                  child: _TransferTabButton(
                    destination: _tabs[i],
                    selected: i == 2,
                    onTap: () => _goToTab(context, i),
                  ),
                ),
                if (i != _tabs.length - 1) const SizedBox(width: 6),
              ],
            ],
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
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
                children: [
                  Text(
                    'Entrez le numéro de téléphone du destinataire et sélectionnez les carnets à transférer.',
                    style: GoogleFonts.poppins(
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
                        icon: Icons.send_rounded,
                        title: 'Aucun carnet disponible',
                        message: 'Vos carnets disponibles apparaîtront ici',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Seuls les carnets complets, non expirés et non utilisés dans un QR peuvent être envoyés.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.body, height: 1.35),
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.poppins(
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
                        hintText: 'Numéro de téléphone',
                        hintStyle: GoogleFonts.poppins(
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
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.leaderGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(_submitting ? 'Envoi...' : 'Envoyer'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToTab(BuildContext context, int index) {
    switch (index) {
      case 0:
        popOrGoClientHome(context);
        return;
      case 1:
        context.go('/faces');
        return;
      case 2:
        context.go('/qr');
        return;
      case 3:
        context.go('/transactions');
        return;
      case 4:
        context.go('/settings');
        return;
    }
  }
}

const _tabs = <_TransferTabDestination>[
  _TransferTabDestination(
    label: 'Accueil',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  _TransferTabDestination(
    label: 'Carnets',
    icon: Icons.confirmation_number_outlined,
    selectedIcon: Icons.confirmation_number,
  ),
  _TransferTabDestination(
    label: 'QR',
    icon: Icons.qr_code_2_outlined,
    selectedIcon: Icons.qr_code_2,
  ),
  _TransferTabDestination(
    label: 'Historique',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  _TransferTabDestination(
    label: 'Profil',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

class _TransferTabDestination {
  const _TransferTabDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _TransferTabButton extends StatelessWidget {
  const _TransferTabButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _TransferTabDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.leaderGreen;
    final inactiveColor = AppColors.muted;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.transparent,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 26,
                  color: selected ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.0,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? activeColor : inactiveColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferLineCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final transferableValue =
        (line.availableQty ~/ carnetSize) * carnetSize * line.faceValue;
    final isSelected = selected > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                    child: Text(
                      carnetTypeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.08,
                      ),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Expire le ${Formatters.dateTimeDash(line.expirationDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AmountInline(amount: transferableValue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

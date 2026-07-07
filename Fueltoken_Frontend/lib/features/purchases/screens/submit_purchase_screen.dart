import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/purchases_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/purchase_payment_proof_guard.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/models/acpec_purchase_create_result.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../auth/bloc/auth_bloc.dart';
import 'purchase_confirmation_screen.dart';
import '../../../shared/widgets/app_message.dart';

const int _kMaxTicketsPerPurchase = 500;

class SubmitPurchaseScreen extends StatefulWidget {
  const SubmitPurchaseScreen({super.key});
  @override
  State<SubmitPurchaseScreen> createState() => _SubmitPurchaseScreenState();
}

class _SubmitPurchaseScreenState extends State<SubmitPurchaseScreen> {
  List<CarnetType> _offerTypes = [];
  final Map<String, int> _qty = {};
  final Set<String> _selectedTypeIds = {};

  String? _proofPath;
  String? _proofFilename;
  Uint8List? _proofBytes;
  bool _submitting = false;
  bool _loadingOffers = false;
  String? _offerLoadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadOffers());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _reloadOffers() async {
    final user = context.read<AuthBloc>().state.user;
    if (!mounted || user == null) return;
    setState(() {
      _loadingOffers = true;
      _offerLoadError = null;
    });
    try {
      if (!AppEnvironment.useAcpecLiveData) {
        if (!mounted) return;
        setState(() {
          _loadingOffers = false;
          _offerTypes = [];
          _offerLoadError =
              'Connexion serveur ACPEC requise pour proposer des offres.';
        });
        return;
      }
      final offers = await AcpecCarnetCatalogService.instance
          .listPurchaseOfferTypes(
            companyId: AppEnvironment.companyIdForUser(user),
          );
      if (!mounted) return;
      setState(() {
        _loadingOffers = false;
        _offerTypes = offers;
        for (final t in offers) {
          _qty.putIfAbsent(t.id, () => 0);
          if ((_qty[t.id] ?? 0) > 0) {
            _selectedTypeIds.add(t.id);
          }
        }
        for (final id in List<String>.from(_selectedTypeIds)) {
          if (!offers.any((t) => t.id == id)) {
            _selectedTypeIds.remove(id);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOffers = false;
        _offerLoadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int _totalTickets() => _qty.values.fold(0, (a, q) => a + q);

  int _otherTickets(String exceptTypeId) {
    var s = 0;
    for (final t in _offerTypes) {
      if (t.id == exceptTypeId) continue;
      s += _qty[t.id] ?? 0;
    }
    return s;
  }

  int _maxAllowedFor(String typeId) =>
      math.max(0, _kMaxTicketsPerPurchase - _otherTickets(typeId));

  int _totalAmount() {
    var s = 0;
    for (final t in _offerTypes) {
      s += (_qty[t.id] ?? 0) * t.totalAmount;
    }
    return s;
  }

  bool get _hasSelection => _totalTickets() > 0;

  void _setQty(String typeId, int v) {
    final cap = _maxAllowedFor(typeId);
    final clamped = math.max(0, math.min(v, cap));
    setState(() {
      _qty[typeId] = clamped;
      if (clamped > 0) {
        _selectedTypeIds.add(typeId);
      } else {
        _selectedTypeIds.remove(typeId);
      }
    });
    if (v > clamped && cap < v) {
      AppMessage.warning(
        context,
        'Plafond : $_kMaxTicketsPerPurchase tickets au total (${_otherTickets(typeId)} déjà sur d\'autres tickets).',
      );
    }
  }

  void _selectType(String id) {
    setState(() {
      if (_selectedTypeIds.contains(id)) {
        _selectedTypeIds.remove(id);
        _qty[id] = 0;
      } else {
        _selectedTypeIds.add(id);
        _qty[id] = _qty[id] ?? 0;
        if (_qty[id] == 0) {
          _qty[id] = 1;
        }
      }
    });
  }

  void _clearProof() {
    setState(() {
      _proofPath = null;
      _proofFilename = null;
      _proofBytes = null;
    });
  }

  Future<void> _pickProof() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: PurchasePaymentProofGuard.allowedExtensions,
        allowMultiple: false,
        // Sur mobile, on évite de charger le fichier en mémoire avant d'avoir
        // contrôlé extension + taille. Sur web, FilePicker a besoin des bytes.
        withData: kIsWeb,
      );

      final file = result?.files.single;
      if (file == null) return;

      final filename = PurchasePaymentProofGuard.normalizedFilename(file.name);
      final metadataError = PurchasePaymentProofGuard.validateFileNameAndSize(
        filename: filename,
        sizeBytes: file.size,
      );
      if (metadataError != null) {
        if (!mounted) return;
        _clearProof();
        AppMessage.error(context, metadataError);
        return;
      }

      final bytes =
          file.bytes ??
          (file.path == null || kIsWeb
              ? null
              : await File(file.path!).readAsBytes());

      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        _clearProof();
        AppMessage.error(context, 'La preuve de paiement est illisible.');
        return;
      }

      final contentError = PurchasePaymentProofGuard.validateBytes(
        filename: filename,
        bytes: bytes,
      );
      if (contentError != null) {
        if (!mounted) return;
        _clearProof();
        AppMessage.error(context, contentError);
        return;
      }

      setState(() {
        _proofPath = file.path ?? filename;
        _proofFilename = filename;
        _proofBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      AppMessage.error(context, "Impossible de charger la preuve de paiement.");
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) return;
      if (!user.isDeviceTrusted) {
        AppMessage.error(
          context,
          'Cet appareil doit être validé par un administrateur avant de pouvoir créer une commande.',
        );
        return;
      }
      if (_totalTickets() > _kMaxTicketsPerPurchase) {
        AppMessage.warning(
          context,
          'Maximum $_kMaxTicketsPerPurchase tickets par achat.',
        );
        return;
      }
      if (!_hasSelection) {
        AppMessage.warning(context, 'Indiquez au moins un ticket.');
        return;
      }
      if (_proofPath == null || _proofFilename == null) {
        AppMessage.error(context, 'La preuve de paiement est obligatoire.');
        return;
      }

      // Construire les lignes de confirmation
      final confirmLines = <PurchaseConfirmationLine>[];
      for (final t in _offerTypes) {
        final q = _qty[t.id] ?? 0;
        if (q <= 0) continue;
        confirmLines.add(PurchaseConfirmationLine(carnetType: t, qty: q));
      }
      if (confirmLines.isEmpty) return;

      final proofPath = _proofPath!;
      final navigator = Navigator.of(context);
      final proofBytes =
          _proofBytes ?? (kIsWeb ? null : await File(proofPath).readAsBytes());
      if (!mounted) return;
      if (proofBytes == null || proofBytes.isEmpty) {
        AppMessage.error(context, 'La preuve de paiement est illisible.');
        return;
      }
      final proofValidationError = PurchasePaymentProofGuard.validateBytes(
        filename: _proofFilename,
        bytes: proofBytes,
      );
      if (proofValidationError != null) {
        AppMessage.error(context, proofValidationError);
        return;
      }
      // Naviguer vers l'écran de confirmation
      final result = await navigator.push<AcpecPurchaseCreateResult>(
        MaterialPageRoute(
          builder: (_) => PurchaseConfirmationScreen(
            args: PurchaseConfirmationArgs(
              lines: confirmLines,
              proofPath: proofPath,
              proofBytes: proofBytes,
              onConfirm: (actionCode) async {
                // Appel API réel: les erreurs remontent au confirmation screen
                if (!AppEnvironment.useAcpecLiveData) {
                  throw Exception(
                    'Connexion serveur ACPEC requise pour soumettre un achat.',
                  );
                }
                if (kIsWeb) {
                  throw Exception(
                    "L'envoi de lot ACPEC avec preuve nécessite l'application mobile.",
                  );
                }
                final rpcLines = <Map<String, dynamic>>[];
                for (final line in confirmLines) {
                  final t = line.carnetType;
                  final q = line.qty;
                  if (q <= 0) continue;
                  final idOdoo = int.tryParse(line.carnetType.id);
                  if (idOdoo == null) {
                    throw Exception(
                      'Type « ${t.code} » : identifiant serveur inconnu. '
                      'Rafraîchissez la liste des offres.',
                    );
                  }
                  final cq = line.qty;
                  if (cq <= 0) continue;
                  rpcLines.add({'carnet_type_id': idOdoo, 'carnet_qty': cq});
                }
                if (rpcLines.isEmpty) {
                  throw Exception('Aucune ligne valide à envoyer.');
                }
                final fileName = _proofFilename?.trim() ?? '';
                if (fileName.isEmpty) {
                  throw Exception('La preuve de paiement est obligatoire.');
                }
                final payRef = 'MOBL-${DateTime.now().millisecondsSinceEpoch}';
                final idem = const Uuid().v4();
                final raw = await OdooFueltokenFacade().purchasesCreate({
                  'lines': rpcLines,
                  'proof_filename': fileName,
                  'proof_data': base64Encode(proofBytes),
                  'payment_reference': payRef,
                  'action_code': actionCode,
                  'idempotency_key': idem,
                });
                return AcpecPurchasesMapper.parseCreateResult(raw);
              },
            ),
          ),
        ),
      );

      if (!mounted) return;
      if (result != null) {
        ClientHistoryRefreshBus.instance.bump();
        PurchasesRefreshBus.instance.bump();
        final confirmedAt = DateTime.now();
        if (!mounted) return;
        await showPurchaseSubmitSuccessDialog(
          context,
          result: result,
          confirmedAt: confirmedAt,
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
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openPaymentProofSheet() async {
    if (!_hasSelection || _submitting) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final selectedTypes = _offerTypes
                .where((type) => (_qty[type.id] ?? 0) > 0)
                .toList();
            final currency = _selectedCurrency;
            final hasProof = _proofPath != null;
            final canSubmit = hasProof && !_submitting;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E3E8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ajouter la preuve de paiement',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vérifiez le panier, puis joignez un reçu ou un virement avant de confirmer.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _PurchaseLinesSummaryCard(
                          lines: selectedTypes
                              .map(
                                (type) => _PurchaseLinesSummaryLine(
                                  label: '${_qty[type.id] ?? 0} × ${type.name}',
                                  qty: _qty[type.id] ?? 0,
                                  amount:
                                      (_qty[type.id] ?? 0) * type.totalAmount,
                                  currency: currency,
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Preuve de paiement',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProofPicker(
                          path: _proofPath,
                          onTap: () async {
                            await _pickProof();
                            if (mounted) {
                              modalSetState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: canSubmit
                                ? () async {
                                    Navigator.of(bottomSheetContext).pop();
                                    await _submit();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF43A047),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(
                                0xFF43A047,
                              ).withValues(alpha: 0.35),
                              disabledForegroundColor: Colors.white.withValues(
                                alpha: 0.7,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              elevation: 0,
                            ),
                            child: _submitting
                                ? const AppInlineLoading(size: 20)
                                : const Text(
                                    'Soumettre la commande',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String get _selectedCurrency {
    for (final type in _offerTypes) {
      if ((_qty[type.id] ?? 0) > 0) {
        return type.displayCurrency;
      }
    }
    return _offerTypes.isNotEmpty
        ? _offerTypes.first.displayCurrency
        : Formatters.fallbackCurrency;
  }

  @override
  Widget build(BuildContext context) {
    final amt = _totalAmount();

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _BottomBar(
            totalAmount: amt,
            currency: _selectedCurrency,
            hasSelection: _hasSelection,
            submitting: _submitting,
            onSubmit: _submitting ? null : _openPaymentProofSheet,
          ),
        ),
      ),
      body: SafeArea(
        top: true,
        child: Column(
          children: [
            ScreenHeader(title: 'Commander', onBack: () => context.pop()),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: [
                  Text(
                    'Sélectionnez les carnets et indiquez la quantité.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingOffers)
                    const _PurchaseOffersSkeleton()
                  else if (_offerLoadError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Text(
                            _offerLoadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _reloadOffers,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Actualiser'),
                          ),
                        ],
                      ),
                    )
                  else if (_offerTypes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: AppColors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppEnvironment.useAcpecLiveData
                                ? 'Aucun type de ticket détecté pour le moment.'
                                : "Aucun type de ticket unitaire n'est disponible pour votre société.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppEnvironment.useAcpecLiveData
                                ? "Lorsque des offres seront disponibles pour votre compte, elles s'afficheront ici."
                                : '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: _reloadOffers,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Actualiser'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 0,
                            mainAxisExtent: 110,
                          ),
                      itemCount: _offerTypes.length,
                      itemBuilder: (context, i) {
                        final t = _offerTypes[i];
                        final q = _qty[t.id] ?? 0;
                        final maxAllowed = _maxAllowedFor(t.id);
                        return _CarnetCard(
                          type: t,
                          quantity: q,
                          maxAllowed: maxAllowed,
                          selected: q > 0,
                          onMinus: () => _setQty(t.id, q - 1),
                          onPlus: () => _setQty(t.id, q + 1),
                          onTap: () => _selectType(t.id),
                        );
                      },
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
}

class _PurchaseOffersSkeleton extends StatelessWidget {
  const _PurchaseOffersSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4),
      child: Column(
        children: [
          _PurchaseOfferSkeletonCard(),
          SizedBox(height: 12),
          _PurchaseOfferSkeletonCard(),
          SizedBox(height: 12),
          _PurchaseOfferSkeletonCard(),
          SizedBox(height: 12),
          _PurchaseOfferSkeletonCard(),
          SizedBox(height: 12),
          _PurchaseOfferSkeletonCard(),
        ],
      ),
    );
  }
}

class _PurchaseOfferSkeletonCard extends StatelessWidget {
  const _PurchaseOfferSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAECEF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            spreadRadius: -8,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.topRight,
            child: _SkeletonLine(width: 72, height: 12),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonLine(width: 132, height: 14),
                    SizedBox(height: 20),
                    _SkeletonLine(width: 104, height: 11),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Container(height: 1, color: const Color(0xFFEAECEF)),
              const SizedBox(height: 1),
              Row(
                children: [
                  const _SkeletonLine(width: 56, height: 11),
                  const Spacer(),
                  _SkeletonButton(),
                  const SizedBox(width: 4),
                  const _SkeletonLine(width: 30, height: 13),
                  const SizedBox(width: 4),
                  _SkeletonButton(dark: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonButton extends StatelessWidget {
  const _SkeletonButton({this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF101522) : const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(13),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EBF0),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _CarnetCard extends StatelessWidget {
  const _CarnetCard({
    required this.type,
    required this.quantity,
    required this.maxAllowed,
    required this.selected,
    required this.onMinus,
    required this.onPlus,
    required this.onTap,
  });

  final CarnetType type;
  final int quantity;
  final int maxAllowed;
  final bool selected;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = quantity > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isSelected
                  ? AppColors.leaderGreen
                  : const Color(0xFFEAECEF),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 18,
                      spreadRadius: -8,
                      offset: Offset(0, 7),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  '${Formatters.numberFr(type.totalAmount)} ${type.displayCurrency}',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 112),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.name,
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Validité ${type.validityDays} jours',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF667085),
                                  height: 1.08,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                      _StepperPair(
                        value: quantity,
                        onMinus: onMinus,
                        onPlus: onPlus,
                        canDecrement: quantity > 0,
                        canIncrement: quantity < maxAllowed,
                      ),
                    ],
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

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.currency,
    required this.hasSelection,
    required this.submitting,
    required this.onSubmit,
  });

  final int totalAmount;
  final String currency;
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
                  'TOTAL PANIER',
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        Formatters.numberFr(totalAmount),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currency,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
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
                  ? const AppInlineLoading(size: 20)
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

class _StepperPair extends StatelessWidget {
  const _StepperPair({
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.canDecrement,
    required this.canIncrement,
  });

  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool canDecrement;
  final bool canIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepCapsule(
          icon: Icons.remove,
          enabled: canDecrement,
          onTap: onMinus,
          isPositive: false,
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
        _StepCapsule(
          icon: Icons.add,
          enabled: canIncrement,
          onTap: onPlus,
          isPositive: true,
        ),
      ],
    );
  }
}

class _StepCapsule extends StatelessWidget {
  const _StepCapsule({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.isPositive,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: enabled
            ? (isPositive ? const Color(0xFF43A047) : const Color(0xFFF2F4F7))
            : const Color(0xFFF3F4F6),
        foregroundColor: enabled
            ? (isPositive ? Colors.white : const Color(0xFF344054))
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

class _PurchaseLinesSummaryCard extends StatelessWidget {
  const _PurchaseLinesSummaryCard({required this.lines});

  final List<_PurchaseLinesSummaryLine> lines;

  @override
  Widget build(BuildContext context) {
    final currency = lines.isEmpty
        ? Formatters.fallbackCurrency
        : lines.first.currency;
    final totalAmount = lines.fold<int>(0, (sum, line) => sum + line.amount);

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
            _PurchaseLinesSummaryRow(
              label: lines[i].label,
              qty: lines[i].qty,
              amount: lines[i].amount,
              currency: lines[i].currency,
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
          _PurchaseLinesSummaryTotalRow(
            totalAmount: totalAmount,
            currency: currency,
          ),
        ],
      ),
    );
  }
}

class _PurchaseLinesSummaryLine {
  const _PurchaseLinesSummaryLine({
    required this.label,
    required this.qty,
    required this.amount,
    required this.currency,
  });

  final String label;
  final int qty;
  final int amount;
  final String currency;
}

class _PurchaseLinesSummaryRow extends StatelessWidget {
  const _PurchaseLinesSummaryRow({
    required this.label,
    required this.qty,
    required this.amount,
    required this.currency,
  });

  final String label;
  final int qty;
  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            Formatters.numberFr(qty),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            '${Formatters.numberFr(amount)} $currency',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseLinesSummaryTotalRow extends StatelessWidget {
  const _PurchaseLinesSummaryTotalRow({
    required this.totalAmount,
    required this.currency,
  });

  final int totalAmount;
  final String currency;

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
        Text(
          '${Formatters.numberFr(totalAmount)} $currency',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _ProofPicker extends StatelessWidget {
  const _ProofPicker({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasFile
                  ? AppColors.success.withValues(alpha: 0.28)
                  : AppColors.line,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: hasFile
                    ? AppColors.success.withValues(alpha: 0.08)
                    : const Color(0x08000000),
                blurRadius: 18,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasFile
                      ? AppColors.success.withValues(alpha: 0.10)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  hasFile ? Icons.verified_rounded : Icons.upload_file_outlined,
                  color: hasFile ? AppColors.success : AppColors.muted,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: hasFile
                            ? AppColors.success.withValues(alpha: 0.10)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        hasFile ? 'Prête' : 'Pièce requise',
                        style: TextStyle(
                          color: hasFile ? AppColors.success : AppColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFile
                          ? 'Preuve sélectionnée'
                          : 'Ajouter la preuve de paiement',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile
                          ? path!.split(RegExp(r'[/\\]')).last
                          : 'JPG, PNG ou PDF — taille maximale ${PurchasePaymentProofGuard.maxSizeLabel}.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                hasFile ? Icons.edit_outlined : Icons.chevron_right,
                color: hasFile ? AppColors.success : AppColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

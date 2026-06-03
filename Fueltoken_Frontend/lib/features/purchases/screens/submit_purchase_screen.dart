import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/purchase_submit_success_dialog.dart';
import '../../auth/bloc/auth_bloc.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plafond : $_kMaxTicketsPerPurchase tickets au total '
            '(${_otherTickets(typeId)} déjà sur d’autres tickets).',
          ),
        ),
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

  Future<void> _pickProof() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() => _proofPath = picked.path);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de charger l’image. Réessayez.'),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    if (_totalTickets() > _kMaxTicketsPerPurchase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum $_kMaxTicketsPerPurchase tickets par achat.'),
        ),
      );
      return;
    }
    if (!_hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez au moins un ticket.')),
      );
      return;
    }
    if (_proofPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La preuve de paiement est obligatoire.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      if (AppEnvironment.useAcpecLiveData) {
        if (kIsWeb) {
          throw Exception(
            'L’envoi de lot ACPEC avec preuve nécessite l’application mobile.',
          );
        }
        final proofPath = _proofPath!;
        final proofBytes = await File(proofPath).readAsBytes();
        final rpcLines = <Map<String, dynamic>>[];
        for (final t in _offerTypes) {
          final q = _qty[t.id] ?? 0;
          if (q <= 0) continue;
          final idOdoo = int.tryParse(t.id);
          if (idOdoo == null) {
            throw Exception(
              'Type Â« ${t.code} Â» : identifiant serveur inconnu. '
              'Rafraîchissez la liste des offres.',
            );
          }
          final cq = acpecOdooCarnetQtyFromTicketSelection(t, q);
          if (cq <= 0) continue;
          rpcLines.add({'carnet_type_id': idOdoo, 'carnet_qty': cq});
        }
        if (rpcLines.isEmpty) {
          throw Exception('Aucune ligne valide à envoyer.');
        }
        final slash = proofPath.lastIndexOf('/');
        final back = proofPath.lastIndexOf('\\');
        final cut = math.max(slash, back);
        final fileName = cut >= 0 ? proofPath.substring(cut + 1) : proofPath;
        final payRef = 'MOBL-${DateTime.now().millisecondsSinceEpoch}';
        final idem = const Uuid().v4();
        final raw = await OdooFueltokenFacade().purchasesCreate({
          'lines': rpcLines,
          'proof_filename': fileName,
          'proof_data': base64Encode(proofBytes),
          'payment_reference': payRef,
          'idempotency_key': idem,
        });
        if (!mounted) return;
        final parsed = AcpecPurchasesMapper.parseCreateResult(raw);
        await showPurchaseSubmitSuccessDialog(
          context,
          result: parsed,
          clientPaymentReference: payRef,
        );
        ClientHistoryRefreshBus.instance.bump();
        if (mounted) context.pop();
      } else {
        throw Exception(
          'Connexion serveur ACPEC requise pour soumettre un achat.',
        );
      }
    } on OdooJsonRpcException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              err.toString().replaceFirst('OdooJsonRpcException', 'Odoo'),
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            hasSelection: _hasSelection,
            submitting: _submitting,
            onSubmit: _submitting ? null : _submit,
          ),
        ),
      ),
      body: SafeArea(
        top: true,
        child: Column(
          children: [
            AppBarHeader(
              title: 'Nouvel achat',
              subtitle: 'Sélectionnez les carnets et indiquez la quantité',
              showBack: true,
              largeTitle: true,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                children: [
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
                                : 'Aucun type de ticket unitaire n’est disponible pour votre société.',
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
                                ? 'Lorsque des offres seront disponibles pour votre compte, elles s’afficheront ici.'
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
                            childAspectRatio: 3.8,
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
                    const SizedBox(height: 20),
                    Text(
                      'PREUVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: AppColors.muted.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProofPicker(path: _proofPath, onTap: _pickProof),
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
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _SkeletonLine(width: 120, height: 14),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const _SkeletonLine(width: 84, height: 11),
                    const SizedBox(width: 18),
                    const _SkeletonLine(width: 72, height: 10),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              const SizedBox(width: 8),
              const _SkeletonLine(width: 18, height: 16),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF101522),
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ],
          ),
        ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: const Color(0xFFEAECEF),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 18,
                spreadRadius: -8,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Carnet ${Formatters.numberFr(type.size)} × ${Formatters.numberFr(type.faceValue)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '${Formatters.numberFr(type.totalAmount)} MRU',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Text(
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'QTE (carnets)',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.35,
                    ),
                  ),
                  const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.hasSelection,
    required this.submitting,
    required this.onSubmit,
  });

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
                  'TOTAL DE LA COMMANDE',
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
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'MRU',
                        style: TextStyle(
                          fontSize: 11,
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
                disabledBackgroundColor:
                    const Color(0xFF43A047).withValues(alpha: 0.35),
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
                      'Soumettre',
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
          primary: false,
          onTap: onMinus,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 20,
          child: Center(
            child: Text(
              '$value',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _StepCapsule(
          icon: Icons.add,
          enabled: canIncrement,
          primary: true,
          onTap: onPlus,
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
    required this.primary,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.white
                : primary
                    ? const Color(0xFF43A047)
                    : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: !enabled
                  ? const Color(0xFFE3E6EA)
                  : primary
                    ? const Color(0xFF43A047)
                    : const Color(0xFFD9DEE4),
            ),
          ),
          child: Icon(
            icon,
            size: 12,
            color: !enabled
                ? const Color(0xFFB4B8C0)
                : primary
                    ? Colors.white
                    : const Color(0xFF344054),
          ),
        ),
      ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppColors.primary : AppColors.line,
            width: hasFile ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile ? Colors.white : AppColors.lineSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasFile ? Icons.check_circle : Icons.upload_file_outlined,
                color: hasFile ? AppColors.primary : AppColors.body,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasFile ? 'Preuve sélectionnée' : 'Choisir un fichier',
                    style: TextStyle(
                      color: hasFile ? AppColors.primaryDark : AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasFile
                        ? path!.split(RegExp(r'[/\\]')).last
                        : 'PDF ou image (virement, reçu, etc.)',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              hasFile ? Icons.refresh : Icons.chevron_right,
              color: hasFile ? AppColors.primaryDark : AppColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

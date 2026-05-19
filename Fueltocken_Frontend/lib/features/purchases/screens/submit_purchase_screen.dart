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
import '../../../core/utils/formatters.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/face_value_chip.dart';
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
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
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
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
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
          _ctrls.putIfAbsent(t.id, () => TextEditingController(text: '0'));
          _focus.putIfAbsent(t.id, () => FocusNode());
        }
        for (final id in List<String>.from(_ctrls.keys)) {
          if (!offers.any((t) => t.id == id)) {
            _ctrls[id]?.dispose();
            _focus[id]?.dispose();
            _ctrls.remove(id);
            _focus.remove(id);
            _qty.remove(id);
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

  List<CarnetType> get _selectedOfferTypes =>
      _offerTypes.where((t) => _selectedTypeIds.contains(t.id)).toList();

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
      s += (_qty[t.id] ?? 0) * t.faceValue;
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
    _ctrls[typeId]!.text = clamped.toString();
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
      }
    });
    _ctrls[id]!.text = '${_qty[id] ?? 0}';
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
              'Type « ${t.code} » : identifiant serveur inconnu. '
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
    final totalT = _totalTickets();
    final amt = _totalAmount();
    final selectedOfferTypes = _selectedOfferTypes;

    return Scaffold(
      bottomNavigationBar: Material(
        elevation: 12,
        color: AppColors.ink,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: _BottomBar(
            totalAmount: amt,
            totalTickets: totalT,
            maxTickets: _kMaxTicketsPerPurchase,
            hasSelection: _hasSelection,
            submitting: _submitting,
            onSubmit: _submitting ? null : _submit,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppBarHeader(title: 'Nouvel achat'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  if (_loadingOffers)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: AppLoadingLottie(size: 88)),
                    )
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
                                ? 'Lorsque des offres seront disponibles pour votre compte, '
                                      'elles s’afficheront ici.'
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
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.line),
                        boxShadow: AppColors.softShadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                            child: Text(
                              'VALEUR (MRU)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                                color: AppColors.muted.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.05,
                                  ),
                              itemCount: _offerTypes.length,
                              itemBuilder: (context, i) {
                                final t = _offerTypes[i];
                                final sel = _selectedTypeIds.contains(t.id);
                                return _DenomCell(
                                  faceValue: t.faceValue,
                                  selected: sel,
                                  onTap: () => _selectType(t.id),
                                );
                              },
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.lineSoft),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'QUANTITÉS PAR VALEUR',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.9,
                                        color: AppColors.muted.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.lineSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        selectedOfferTypes.length == 1
                                            ? '1 valeur sélectionnée'
                                            : '${selectedOfferTypes.length} valeurs sélectionnées',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (selectedOfferTypes.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.line),
                                    ),
                                    child: const Text(
                                      'Sélectionnez une ou plusieurs valeurs ci-dessus, puis ajustez la quantité de chacune.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                        height: 1.35,
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < selectedOfferTypes.length;
                                        index++
                                      ) ...[
                                        Builder(
                                          builder: (context) {
                                            final t = selectedOfferTypes[index];
                                            final q = _qty[t.id] ?? 0;
                                            final maxAllowed = _maxAllowedFor(
                                              t.id,
                                            );
                                            return _SelectedOfferLine(
                                              type: t,
                                              quantity: q,
                                              maxAllowed: maxAllowed,
                                              onMinus: () =>
                                                  _setQty(t.id, q - 1),
                                              onPlus: () =>
                                                  _setQty(t.id, q + 1),
                                            );
                                          },
                                        ),
                                        if (index <
                                            selectedOfferTypes.length - 1)
                                          const SizedBox(height: 10),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _DenomCell extends StatelessWidget {
  const _DenomCell({
    required this.faceValue,
    required this.selected,
    required this.onTap,
  });

  final int faceValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                Formatters.numberFr(faceValue),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.primaryDark : AppColors.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'MRU',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.85)
                      : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedOfferLine extends StatelessWidget {
  const _SelectedOfferLine({
    required this.type,
    required this.quantity,
    required this.maxAllowed,
    required this.onMinus,
    required this.onPlus,
  });

  final CarnetType type;
  final int quantity;
  final int maxAllowed;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final remaining = math.max(0, maxAllowed);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          FaceValueChip(value: type.faceValue, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${Formatters.numberFr(type.faceValue)} MRU',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Disponible : ${Formatters.numberFr(remaining)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StepperPair(
            value: quantity,
            onMinus: onMinus,
            onPlus: onPlus,
            canDecrement: quantity > 0,
            canIncrement: quantity < maxAllowed,
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.totalTickets,
    required this.maxTickets,
    required this.hasSelection,
    required this.submitting,
    required this.onSubmit,
  });
  final int totalAmount;
  final int totalTickets;
  final int maxTickets;
  final bool hasSelection;
  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onSubmit == null || !hasSelection;
    return Container(
      width: double.infinity,
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
                  'TOTAL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
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
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'MRU',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !hasSelection
                      ? 'Aucun ticket'
                      : '$totalTickets / $maxTickets tickets',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: disabled ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                elevation: 0,
              ),
              icon: submitting
                  ? const AppInlineLoading(size: 20)
                  : Icon(
                      Icons.send_outlined,
                      size: 18,
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.white,
                    ),
              label: const Text(
                'Soumettre le lot',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lineSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SqBtn(
            icon: Icons.remove,
            enabled: canDecrement,
            primary: false,
            onTap: onMinus,
          ),
          SizedBox(
            width: 30,
            child: Center(
              child: Text(
                '$value',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          _SqBtn(
            icon: Icons.add,
            enabled: canIncrement,
            primary: true,
            onTap: onPlus,
          ),
        ],
      ),
    );
  }
}

class _SqBtn extends StatelessWidget {
  const _SqBtn({
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 48,
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.transparent
                : primary
                ? AppColors.ink
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: !enabled
                ? AppColors.hint
                : primary
                ? Colors.white
                : AppColors.ink,
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
          color: hasFile ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppColors.primary : AppColors.line,
            width: hasFile ? 1.5 : 1,
          ),
          boxShadow: AppColors.softShadow,
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

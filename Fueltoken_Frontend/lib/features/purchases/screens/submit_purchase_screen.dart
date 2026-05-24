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
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
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
    final totalT = _totalTickets();
    final amt = _totalAmount();
    final selectedOffers =
        _offerTypes.where((t) => (_qty[t.id] ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8FBFA),
                Color(0xFFF4F7F5),
                Color(0xFFEFF4F1),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F7A5A), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F7A5A).withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$selectedOffers sélectionné(s)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Nouvel achat',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.02,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Composez votre commande, joignez la preuve de paiement et envoyez le tout au serveur.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    if (_loadingOffers)
                      const Padding(
                        padding: EdgeInsets.only(top: 12, bottom: 24),
                        child: AppLoadingSkeleton(
                          style: AppLoadingSkeletonStyle.purchaseOffers,
                          itemCount: 6,
                        ),
                      )
                    else if (_offerLoadError != null)
                      _EmptyStatePanel(
                        icon: Icons.cloud_off_outlined,
                        title: 'Offres indisponibles',
                        message: _offerLoadError!,
                        buttonLabel: 'Actualiser',
                        onTap: _reloadOffers,
                      )
                    else if (_offerTypes.isEmpty)
                      _EmptyStatePanel(
                        icon: Icons.inventory_2_outlined,
                        title: 'Aucune offre',
                        message: AppEnvironment.useAcpecLiveData
                            ? 'Aucun type de carnet unitaire n’a été trouvé pour le moment.'
                            : 'Aucun type de carnet n’est disponible hors connexion ACPEC.',
                        buttonLabel: 'Actualiser',
                        onTap: _reloadOffers,
                      )
                    else ...[
                      const SizedBox(height: 6),
                      Text(
                        'Choisissez les carnets à acheter',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chaque carte présente le carnet, son montant total et le niveau de sélection.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Column(
                        children: [
                          for (var index = 0; index < _offerTypes.length; index++) ...[
                            Builder(
                              builder: (context) {
                                final t = _offerTypes[index];
                                final q = _qty[t.id] ?? 0;
                                final maxAllowed = _maxAllowedFor(t.id);
                                return _SelectedOfferLine(
                                  type: t,
                                  quantity: q,
                                  maxAllowed: maxAllowed,
                                  onMinus: () => _setQty(t.id, q - 1),
                                  onPlus: () => _setQty(t.id, q + 1),
                                );
                              },
                            ),
                            if (index < _offerTypes.length - 1)
                              const SizedBox(height: 12),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Preuve de paiement',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ProofPicker(path: _proofPath, onTap: _pickProof),
                    ],
                  ],
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

  String get _carnetLabel =>
      'Carnet ${Formatters.numberFr(type.size)} x ${Formatters.numberFr(type.faceValue)}';

  String get _amountLabel => '${Formatters.numberFr(type.totalAmount)} MRU';

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? const Color(0xFF0F7A5A) : const Color(0xFFE6EAE8),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [const Color(0xFF0F7A5A), const Color(0xFF1D4ED8)]
                    : [const Color(0xFFF3F6F5), const Color(0xFFE9EFEC)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Icon(
              selected ? Icons.check_rounded : Icons.inventory_2_outlined,
              size: 24,
              color: selected ? Colors.white : const Color(0xFF4B5563),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _carnetLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _amountLabel,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F7A5A),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$quantity sur $maxAllowed max',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final button = SizedBox(
          height: 52,
          width: narrow ? double.infinity : 150,
          child: ElevatedButton.icon(
            onPressed: disabled ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F7A5A),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF0F7A5A).withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            icon: submitting
                ? const AppInlineLoading(size: 20)
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              'Envoyer',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        );

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF8FAF9)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE5EAE7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TotalPanel(totalAmount: totalAmount, totalTickets: totalTickets),
                    const SizedBox(height: 12),
                    button,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _TotalPanel(
                        totalAmount: totalAmount,
                        totalTickets: totalTickets,
                      ),
                    ),
                    const SizedBox(width: 12),
                    button,
                  ],
                ),
        );
      },
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EAE8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SqBtn(
            icon: Icons.remove_rounded,
            enabled: canDecrement,
            primary: false,
            onTap: onMinus,
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '$value',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          ),
          _SqBtn(
            icon: Icons.add_rounded,
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: !enabled
                ? const Color(0xFFF0F2F2)
                : primary
                    ? const Color(0xFF0F7A5A)
                    : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary
                  ? const Color(0xFF0F7A5A)
                  : const Color(0xFFD8DEDB),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: !enabled
                ? const Color(0xFFB6BCC8)
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasFile
                ? [const Color(0xFFEAF7EE), const Color(0xFFF6FBF7)]
                : [Colors.white, const Color(0xFFF8FAF9)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasFile ? const Color(0xFF0F7A5A) : const Color(0xFFE5EAE7),
            width: hasFile ? 1.3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile ? Colors.white : const Color(0xFFF0F2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasFile ? Icons.check_circle : Icons.upload_file_outlined,
                color: hasFile ? const Color(0xFF0F7A5A) : const Color(0xFF4B5563),
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
                    style: GoogleFonts.inter(
                      color: const Color(0xFF111827),
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
                      color: Color(0xFF6B7280),
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
              color: hasFile ? const Color(0xFF0F7A5A) : const Color(0xFF6B7280),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalPanel extends StatelessWidget {
  const _TotalPanel({
    required this.totalAmount,
    required this.totalTickets,
  });

  final int totalAmount;
  final int totalTickets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EAE8)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F7A5A), Color(0xFF1D4ED8)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Résumé',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.numberFr(totalAmount)} MRU',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalTickets ticket(s) sélectionné(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStatePanel extends StatelessWidget {
  const _EmptyStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5EAE7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF7EE), Color(0xFFDFF3EA)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: const Color(0xFF0F7A5A), size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F7A5A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

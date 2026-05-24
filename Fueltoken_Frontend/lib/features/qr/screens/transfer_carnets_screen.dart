import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/face_value_chip.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/bloc/auth_bloc.dart';

class TransferCarnetsScreen extends StatefulWidget {
  const TransferCarnetsScreen({super.key});

  @override
  State<TransferCarnetsScreen> createState() => _TransferCarnetsScreenState();
}

class _TransferCarnetsScreenState extends State<TransferCarnetsScreen> {
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final Map<String, int> _selectedQtyByLineId = <String, int>{};

  Map<String, int> _carnetSizeById = <String, int>{};
  Map<String, int> _carnetSizeByCode = <String, int>{};
  List<FaceLine> _faces = [];
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = AppEnvironment.useAcpecLiveData;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int _carnetSizeFor(FaceLine line) {
    final byId = _carnetSizeById[line.carnetTypeId.trim()];
    if (byId != null && byId > 0) return byId;
    final byCode = _carnetSizeByCode[line.carnetTypeCode.trim().toUpperCase()];
    if (byCode != null && byCode > 0) return byCode;
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
      if (size <= 0 || line.isExpired) continue;
      if (line.availableQty ~/ size <= 0) continue;
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
        const <String, dynamic>{},
      );
      final catalogResult = await AcpecCarnetCatalogService.instance
          .loadAdminCatalog(companyId: companyId);

      final faces = AcpecFacesMapper.fromRpcResult(facesRaw, ownerId: user.id);
      final byId = <String, int>{};
      final byCode = <String, int>{};
      for (final type in catalogResult.types) {
        if (type.id.trim().isNotEmpty) {
          byId[type.id.trim()] = type.size;
        }
        if (type.code.trim().isNotEmpty) {
          byCode[type.code.trim().toUpperCase()] = type.size;
        }
      }

      if (!mounted) return;
      setState(() {
        _faces = faces;
        _carnetSizeById = byId;
        _carnetSizeByCode = byCode;
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

  int _selectedCarnetsFor(FaceLine line) => _selectedQtyByLineId[line.id] ?? 0;

  int _selectedTickets() {
    var total = 0;
    for (final line in _transferableFaces) {
      total += _selectedCarnetsFor(line) * _carnetSizeFor(line);
    }
    return total;
  }

  int _selectedAmount() {
    var total = 0;
    for (final line in _transferableFaces) {
      final qty = _selectedCarnetsFor(line);
      final size = _carnetSizeFor(line);
      total += qty * size * line.faceValue;
    }
    return total;
  }

  void _changeQty(FaceLine line, int delta) {
    final size = _carnetSizeFor(line);
    final maxCarnets = line.availableQty ~/ size;
    final current = _selectedCarnetsFor(line);
    final next = (current + delta).clamp(0, maxCarnets).toInt();
    setState(() => _selectedQtyByLineId[line.id] = next);
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saisissez le téléphone du destinataire.'),
        ),
      );
      return;
    }

    final lines = <Map<String, dynamic>>[];
    for (final line in _transferableFaces) {
      final qty = _selectedCarnetsFor(line);
      if (qty <= 0) continue;
      final faceLineId = int.tryParse(line.id);
      if (faceLineId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identifiant de face manquant. Rechargez les faces.'),
          ),
        );
        return;
      }
      lines.add({'face_line_id': faceLineId, 'carnet_qty': qty});
    }

    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez au moins un carnet à transférer.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final raw = await OdooFueltokenFacade().carnetsTransfer({
        'recipient_phone': phone,
        'lines': lines,
        'note': _noteController.text.trim(),
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

      final transferName = data['name']?.toString().trim();
      final totalAmount = data['amount_total'];
      final totalFaces = data['face_qty_total'];

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            transferName != null && transferName.isNotEmpty
                ? 'Transfert confirmé: $transferName'
                : 'Transfert confirmé.',
          ),
        ),
      );
      if (totalFaces != null || totalAmount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Total: ${Formatters.numberFr(totalFaces is num ? totalFaces.round() : int.tryParse('$totalFaces') ?? 0)} tickets · ${Formatters.numberFr(totalAmount is num ? totalAmount.round() : int.tryParse('$totalAmount') ?? 0)} MRU',
            ),
          ),
        );
      }

      setState(() => _selectedQtyByLineId.clear());
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.isOdooSessionExpired
                ? 'Session expirée. Reconnectez-vous.'
                : e.message,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const AppBarHeader(
                title: 'Transférer',
                showBack: true,
                largeTitle: true,
              ),
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
      );
    }

    final transferable = _transferableFaces;
    final selectedTickets = _selectedTickets();
    final selectedAmount = _selectedAmount();

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
            color: AppColors.surface,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppBarHeader(
              title: 'Transférer',
              showBack: true,
              largeTitle: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'Destinataire',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8F9FB),
                      hintText: 'Numéro de téléphone / login',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Note',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8F9FB),
                      hintText: 'Optionnel',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sélection',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        Text(
                          '$selectedTickets ticket${selectedTickets > 1 ? 's' : ''} · ${Formatters.numberFr(selectedAmount)} MRU',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Carnets transférables'),
                  const SizedBox(height: 8),
                  if (transferable.isEmpty)
                    AppCard(
                      child: Text(
                        'Aucun carnet complet disponible pour transfert.',
                        style: TextStyle(color: AppColors.body, height: 1.35),
                      ),
                    )
                  else
                    for (var i = 0; i < transferable.length; i++) ...[
                      _TransferLineCard(
                        line: transferable[i],
                        carnetSize: _carnetSizeFor(transferable[i]),
                        selected: _selectedCarnetsFor(transferable[i]),
                        onDecrement: () => _changeQty(transferable[i], -1),
                        onIncrement: () => _changeQty(transferable[i], 1),
                      ),
                      if (i < transferable.length - 1)
                        const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_submitting ? 'Transfert...' : 'Transférer'),
                    ),
                  ),
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
        context.go('/home');
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
    required this.carnetSize,
    required this.selected,
    required this.onDecrement,
    required this.onIncrement,
  });

  final FaceLine line;
  final int carnetSize;
  final int selected;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final maxCarnets = line.availableQty ~/ carnetSize;
    final transferableValue = maxCarnets * carnetSize * line.faceValue;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaceValueChip(value: line.faceValue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carnet ${Formatters.numberFr(carnetSize)}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.numberFr(line.availableQty)} tickets disponibles · ${Formatters.numberFr(maxCarnets)} carnet${maxCarnets > 1 ? 's' : ''} transférable${maxCarnets > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${Formatters.numberFr(transferableValue)} MRU',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Carnets à transférer',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: selected > 0 ? onDecrement : null,
                icon: const Icon(Icons.remove, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 34,
                child: Text(
                  '$selected',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: selected < maxCarnets ? onIncrement : null,
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

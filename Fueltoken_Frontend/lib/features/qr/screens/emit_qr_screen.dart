import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/models/face_line.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../data/services/acpec_faces_mapper.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../auth/bloc/auth_bloc.dart';

class EmitQrScreen extends StatefulWidget {
  const EmitQrScreen({super.key});
  @override
  State<EmitQrScreen> createState() => _EmitQrScreenState();
}

class _EmitQrScreenState extends State<EmitQrScreen> {
  final Map<int, int> _request = {};
  bool _emitting = false;
  bool _liveLoading = false;
  String? _liveError;
  List<CarnetType> _offerTypes = [];
  List<FaceLine> _liveFaceLines = [];

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLiveFaces());
    }
  }

  Future<void> _loadLiveFaces() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() {
      _liveLoading = true;
      _liveError = null;
    });
    try {
      final facesFuture = OdooFueltokenFacade().faces(const {});
      final typesFuture = AcpecCarnetCatalogService.instance
          .listPurchaseOfferTypes(
            companyId: AppEnvironment.companyIdForUser(user),
          )
          .catchError((_) => <CarnetType>[]);
      final raw = await facesFuture;
      final offerTypes = await typesFuture;
      final lines = AcpecFacesMapper.fromRpcResult(raw, ownerId: user.id);
      if (!mounted) return;
      setState(() {
        _liveFaceLines = lines;
        _offerTypes = offerTypes;
        _liveLoading = false;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.isOdooSessionExpired
            ? 'Session expirÃ©e. Reconnectez-vous.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Corps de requÃªte d'Ã©mission : privilÃ©gie `carnet_type_id` (FIFO) sinon `face_value`.
  List<Map<String, dynamic>> _acpecIssueLinePayload(String ownerId) {
    final acc = <String, int>{};
    void bump(String key, int delta) {
      if (delta <= 0) return;
      acc[key] = (acc[key] ?? 0) + delta;
    }

    for (final e in _request.entries) {
      if (e.value <= 0) continue;
      var rem = e.value;
      final pool =
          _liveFaceLines
              .where(
                (l) =>
                    l.faceValue == e.key && l.availableQty > 0 && !l.isExpired,
              )
              .toList()
            ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
      for (final l in pool) {
        if (rem <= 0) break;
        final take = rem < l.availableQty ? rem : l.availableQty;
        if (take <= 0) continue;
        final cid = int.tryParse(l.carnetTypeId.trim());
        if (cid != null && cid > 0) {
          bump('c:$cid', take);
        } else {
          bump('f:${l.faceValue}', take);
        }
        rem -= take;
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final e in acc.entries) {
      if (e.key.startsWith('c:')) {
        out.add({
          'carnet_type_id': int.parse(e.key.substring(2)),
          'qty': e.value,
        });
      } else if (e.key.startsWith('f:')) {
        out.add({'face_value': int.parse(e.key.substring(2)), 'qty': e.value});
      }
    }
    return out;
  }

  Map<int, int> _availableByFace(String ownerId) {
    final map = <int, int>{};
    for (final f in _liveFaceLines) {
      if (f.ownerId != ownerId || f.isExpired) continue;
      map[f.faceValue] = (map[f.faceValue] ?? 0) + f.availableQty;
    }
    return map;
  }

  Map<int, DateTime> _expiryByFace(String ownerId) {
    final map = <int, DateTime>{};
    for (final f in _liveFaceLines) {
      if (f.ownerId != ownerId || f.isExpired || f.availableQty <= 0) continue;
      final current = map[f.faceValue];
      if (current == null || f.expirationDate.isBefore(current)) {
        map[f.faceValue] = f.expirationDate;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarHeader(
                title: 'GÃ©nÃ©rer un QR',
                showBack: true,
                largeTitle: true,
              ),
              Expanded(
                child: ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 120),
                  children: [
                    AppLoadingSkeleton(
                      style: AppLoadingSkeletonStyle.qrGeneration,
                      itemCount: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarHeader(
                title: 'GÃ©nÃ©rer un QR',
                showBack: true,
                largeTitle: true,
                onBack: () => popOrGoClientHome(context),
              ),
              const Expanded(child: ApiRequiredView()),
            ],
          ),
        ),
      );
    }
    if (_liveLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarHeader(
                title: 'GÃ©nÃ©rer un QR',
                showBack: true,
                largeTitle: true,
              ),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  children: [
                    AppLoadingSkeleton(
                      style: AppLoadingSkeletonStyle.qrGeneration,
                      itemCount: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (AppEnvironment.useAcpecLiveData && _liveError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarHeader(
                title: 'GÃ©nÃ©rer un QR',
                showBack: true,
                largeTitle: true,
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _liveError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.body),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadLiveFaces,
                          child: const Text('RÃ©essayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final available = _availableByFace(user.id);
    final expiryByFace = _expiryByFace(user.id);
    final offerTypes =
        _offerTypes
            .where((type) => (available[type.faceValue] ?? 0) > 0)
            .toList()
          ..sort((a, b) => a.faceValue.compareTo(b.faceValue));
    final legacyEntries = available.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final useOfferTypes = _offerTypes.isNotEmpty;
    final hasEntries = useOfferTypes
        ? offerTypes.isNotEmpty
        : legacyEntries.isNotEmpty;

    final totalQty = _request.values.fold(0, (s, v) => s + v);
    final totalAmount = _request.entries.fold(0, (s, e) => s + e.key * e.value);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: _BottomBar(
          totalAmount: totalAmount,
          emitting: _emitting,
          onEmit: totalQty == 0 || _emitting ? null : () => _emit(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBarHeader(
              title: 'GÃ©nÃ©rer un QR',
              showBack: true,
              largeTitle: true,
            ),
            Expanded(
              child: hasEntries
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
                      children: [
                        const SizedBox(height: 18),
                        const _SectionTitle('CARNETS DISPONIBLES'),
                        const SizedBox(height: 12),
                        ...(useOfferTypes
                            ? offerTypes.map((type) {
                                final selected = _request[type.faceValue] ?? 0;
                                return _CompositionRow(
                                  type: type,
                                  available: available[type.faceValue] ?? 0,
                                  expirationDate: expiryByFace[type.faceValue],
                                  selected: selected,
                                  onChange: (n) => setState(() {
                                    if (n <= 0) {
                                      _request.remove(type.faceValue);
                                    } else {
                                      _request[type.faceValue] = n;
                                    }
                                  }),
                                );
                              })
                            : legacyEntries.map((e) {
                                final selected = _request[e.key] ?? 0;
                                return _CompositionRow(
                                  type: CarnetType(
                                    id: '',
                                    code: '',
                                    name:
                                        'Carnet ${Formatters.numberFr(e.key)}',
                                    size: 1,
                                    faceValue: e.key,
                                    companyId: '',
                                  ),
                                  available: e.value,
                                  expirationDate: expiryByFace[e.key],
                                  selected: selected,
                                  onChange: (n) => setState(() {
                                    if (n <= 0) {
                                      _request.remove(e.key);
                                    } else {
                                      _request[e.key] = n;
                                    }
                                  }),
                                );
                              })),
                        const SizedBox(height: 8),
                      ],
                    )
                  : const _EmptyAvailable(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _emit(BuildContext context) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final navigator = GoRouter.of(context);
    setState(() => _emitting = true);
    try {
      if (AppEnvironment.useAcpecLiveData) {
        final linesPayload = _acpecIssueLinePayload(user.id);
        if (linesPayload.isEmpty) {
          throw Exception(
            'Aucune ligne Ã  Ã©mettre (stock ou sÃ©lection vide).',
          );
        }
        final raw = await OdooFueltokenFacade().qrIssue({
          'lines': linesPayload,
          'idempotency_key': 'ft-qr-${const Uuid().v4()}',
        });
        final qr = AcpecQrMapper.fromRpcIssueEnvelope(
          raw,
          ownerId: user.id,
          ownerName: user.name,
          companyId: AppEnvironment.companyIdForUser(user),
        );
        if (!context.mounted) return;
        navigator.pushReplacement(
          '/qr/${Uri.encodeComponent(qr.publicCode)}?emitted=1',
        );
      } else {
        throw Exception(
          'Connexion serveur ACPEC requise pour gÃ©nÃ©rer un QR.',
        );
      }
    } on OdooJsonRpcException catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.isOdooSessionExpired
                ? 'Session expirÃ©e. Reconnectez-vous.'
                : err.message,
          ),
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _emitting = false);
    }
  }
}

// --------------------------------------------------------------------------
// Bottom bar: white summary card + green action button
// --------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.emitting,
    required this.onEmit,
  });

  final int totalAmount;
  final bool emitting;
  final VoidCallback? onEmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onEmit == null;
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
                  'MONTANT TOTAL QR',
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
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: disabled ? null : onEmit,
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
              child: emitting
                  ? const AppInlineLoading(size: 20)
                  : const Text(
                      'GÃ©nÃ©rer',
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

// --------------------------------------------------------------------------
// Composition row & stepper
// --------------------------------------------------------------------------

class _CompositionRow extends StatelessWidget {
  final CarnetType type;
  final int available;
  final DateTime? expirationDate;
  final int selected;
  final ValueChanged<int> onChange;
  const _CompositionRow({
    required this.type,
    required this.available,
    required this.expirationDate,
    required this.selected,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Carnet ${Formatters.numberFr(type.size)} × ${Formatters.numberFr(type.faceValue)}',
                    style: GoogleFonts.inter(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      '${Formatters.numberFr(available)} tickets disponibles',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted.withValues(alpha: 0.95),
                        height: 1.08,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Expire le ${expirationDate != null ? Formatters.dateTimeDash(expirationDate!) : '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
                height: 1,
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFEAECEF)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Quantité',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                const Spacer(),
                _Stepper(value: selected, max: available, onChange: onChange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChange;
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove,
          enabled: value > 0,
          onTap: () => onChange(value - 1),
          primary: false,
        ),
        SizedBox(
          width: 24,
          child: Center(
            child: Text(
              '$value',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                height: 1,
              ),
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChange(value + 1),
          primary: true,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 41,
        height: 41,
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0xFFF4F5F7)
              : primary
              ? const Color(0xFF101522)
              : const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !enabled
                ? const Color(0xFFE5E7EB)
                : primary
                ? const Color(0xFF101522)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Icon(
          icon,
          size: 17,
          color: !enabled
              ? const Color(0xFF9CA3AF)
              : primary
              ? Colors.white
              : const Color(0xFF334155),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppColors.muted,
        letterSpacing: 0.8,
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Empty state
// --------------------------------------------------------------------------

class _EmptyAvailable extends StatelessWidget {
  const _EmptyAvailable();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.layers_clear_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucun ticket disponible',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Soumettez un achat de tickets et attendez la validation pour gÃ©nÃ©rer un QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.body),
            ),
          ],
        ),
      ),
    );
  }
}

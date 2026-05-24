import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/face_line.dart';
import '../../../shared/widgets/api_required_view.dart';
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
      final raw = await OdooFueltokenFacade().faces(const {});
      final lines = AcpecFacesMapper.fromRpcResult(raw, ownerId: user.id);
      if (!mounted) return;
      setState(() {
        _liveFaceLines = lines;
        _liveLoading = false;
      });
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _liveError = e.isOdooSessionExpired
            ? 'Session expirée. Reconnectez-vous.'
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

  /// Corps de requête d'émission : privilégie `carnet_type_id` (FIFO) sinon `face_value`.
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
                title: 'Générer un QR',
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
                title: 'Générer un QR',
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
                title: 'Générer un QR',
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
                title: 'Générer un QR',
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
                          child: const Text('Réessayer'),
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
    final entries = available.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

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
              title: 'Générer un QR',
              showBack: true,
              largeTitle: true,
            ),
            Expanded(
              child: entries.isEmpty
                  ? const _EmptyAvailable()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
                      children: [
                        const SizedBox(height: 18),
                        const _SectionTitle('COMPOSITION'),
                        const SizedBox(height: 12),
                        ...entries.map((e) {
                          final selected = _request[e.key] ?? 0;
                          return _CompositionRow(
                            faceValue: e.key,
                            available: e.value,
                            selected: selected,
                            onChange: (n) => setState(() {
                              if (n <= 0) {
                                _request.remove(e.key);
                              } else {
                                _request[e.key] = n;
                              }
                            }),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ),
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
            'Aucune ligne à émettre (stock ou sélection vide).',
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
        throw Exception('Connexion serveur ACPEC requise pour générer un QR.');
      }
    } on OdooJsonRpcException catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.isOdooSessionExpired
                ? 'Session expirée. Reconnectez-vous.'
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
            height: 50,
            child: ElevatedButton.icon(
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
                padding: const EdgeInsets.symmetric(horizontal: 18),
                elevation: 0,
              ),
              icon: emitting
                  ? const AppInlineLoading(size: 20)
                  : Icon(
                      Icons.qr_code_2,
                      size: 18,
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.white,
                    ),
                label: const Text(
                  'Générer',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
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
  final int faceValue;
  final int available;
  final int selected;
  final ValueChanged<int> onChange;
  const _CompositionRow({
    required this.faceValue,
    required this.available,
    required this.selected,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.line.withValues(alpha: 0.9),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x100D2040),
              blurRadius: 12,
              spreadRadius: -4,
              offset: Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _FaceValueBadge(faceValue: faceValue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ticket ${Formatters.numberFr(faceValue)} MRU',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.leaderGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$available dispo',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Stepper(value: selected, max: available, onChange: onChange),
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(
            icon: Icons.remove_rounded,
            enabled: value > 0,
            onTap: () => onChange(value - 1),
            primary: false,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
          ),
          _StepBtn(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChange(value + 1),
            primary: true,
          ),
        ],
      ),
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.transparent
              : primary
              ? AppColors.ink
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 16,
          color: !enabled
              ? AppColors.hint
              : primary
              ? Colors.white
              : AppColors.ink,
        ),
      ),
    );
  }
}

class _FaceValueBadge extends StatelessWidget {
  const _FaceValueBadge({required this.faceValue});

  final int faceValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34D399), Color(0xFF16A34A)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x334ADE80),
            blurRadius: 12,
            spreadRadius: -3,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Formatters.numberFr(faceValue),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'MRU',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
        ],
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
              'Soumettez un achat de tickets et attendez la validation pour générer un QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.body),
            ),
          ],
        ),
      ),
    );
  }
}

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
import '../../../shared/widgets/app_status_lottie.dart';
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

  /// Corps de requête d’émission : privilégie `carnet_type_id` (FIFO) sinon `face_value`.
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

  /// FIFO preview: pick face lines (by faceValue) sorted by expiration ASC.
  List<({String lotRef, int faceValue, int qty, DateTime expiry})> _fifoPreview(
    String ownerId,
  ) {
    final lines = _liveFaceLines.where((f) => f.ownerId == ownerId).toList();
    final result =
        <({String lotRef, int faceValue, int qty, DateTime expiry})>[];
    for (final entry in _request.entries) {
      if (entry.value <= 0) continue;
      final fv = entry.key;
      var remaining = entry.value;
      final pool =
          lines.where((l) => l.faceValue == fv && l.availableQty > 0).toList()
            ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
      for (final l in pool) {
        if (remaining <= 0) break;
        final take = remaining < l.availableQty ? remaining : l.availableQty;
        if (take > 0) {
          result.add((
            lotRef: l.lotInternalRef,
            faceValue: fv,
            qty: take,
            expiry: l.expirationDate,
          ));
          remaining -= take;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    if (!AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmissionHeader(
                title: 'Émettre un QR',
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
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmissionHeader(
                title: 'Émettre un QR',
                onBack: () => context.pop(),
              ),
              const Expanded(child: Center(child: AppLoadingLottie(size: 100))),
            ],
          ),
        ),
      );
    }
    if (AppEnvironment.useAcpecLiveData && _liveError != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmissionHeader(
                title: 'Émettre un QR',
                onBack: () => context.pop(),
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
    final preview = _fifoPreview(user.id);
    final lotsCount = preview.map((p) => p.lotRef).toSet().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: SafeArea(
        child: _BottomBar(
          totalAmount: totalAmount,
          totalQty: totalQty,
          lotsCount: lotsCount,
          emitting: _emitting,
          onEmit: totalQty == 0 || _emitting ? null : () => _emit(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmissionHeader(
              title: 'Émettre un QR',
              onBack: () => context.pop(),
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
                        if (preview.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const _SectionTitle('RÉPARTITION PAR LOT'),
                          const SizedBox(height: 8),
                          _LotsPreview(preview: preview),
                        ],
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
          throw Exception('Aucune ligne à émettre (stock ou sélection vide).');
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
        throw Exception('Connexion serveur ACPEC requise pour émettre un QR.');
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

// ──────────────────────────────────────────────────────────────────────────
// Bottom bar: dark ink summary + green emit button
// ──────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalAmount,
    required this.totalQty,
    required this.lotsCount,
    required this.emitting,
    required this.onEmit,
  });

  final int totalAmount;
  final int totalQty;
  final int lotsCount;
  final bool emitting;
  final VoidCallback? onEmit;

  @override
  Widget build(BuildContext context) {
    final disabled = onEmit == null;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14233A), Color(0xFF112338)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2A0F172A),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'TOTAL DU QR',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.numberFr(totalAmount),
                      style: const TextStyle(
                        fontSize: 39,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'MRU',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.6),
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  totalQty == 0
                      ? 'Aucun ticket sélectionné'
                      : '$totalQty ticket${totalQty > 1 ? 's' : ''}${lotsCount > 0 ? ' · $lotsCount lot${lotsCount > 1 ? 's' : ''}' : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 78,
            child: InkWell(
              onTap: onEmit,
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: disabled
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF34D399), Color(0xFF16A34A)],
                        ),
                  color: disabled ? Colors.white.withValues(alpha: 0.08) : null,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      emitting
                          ? const AppInlineLoading(size: 22)
                          : Icon(
                              Icons.qr_code_2,
                              size: 22,
                              color: disabled
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.white,
                            ),
                      const SizedBox(width: 12),
                      Text(
                        'Émettre',
                        style: TextStyle(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w800,
                          color: disabled
                              ? Colors.white.withValues(alpha: 0.3)
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Composition row & stepper
// ──────────────────────────────────────────────────────────────────────────

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

class _EmissionHeader extends StatelessWidget {
  const _EmissionHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EmissionBackButton(onTap: onBack),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: AppColors.ink,
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

class _EmissionBackButton extends StatelessWidget {
  const _EmissionBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120D2040),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 24,
            color: AppColors.ink,
          ),
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

// ──────────────────────────────────────────────────────────────────────────
// Lots preview
// ──────────────────────────────────────────────────────────────────────────

class _LotsPreview extends StatelessWidget {
  const _LotsPreview({required this.preview});
  final List<({String lotRef, int faceValue, int qty, DateTime expiry})>
  preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.lineSoft),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview[i].lotRef,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'expire ${Formatters.date(preview[i].expiry)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${preview[i].qty} ticket${preview[i].qty > 1 ? 's' : ''} · ${Formatters.numberFr(preview[i].faceValue)} MRU',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Empty state
// ──────────────────────────────────────────────────────────────────────────

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
              'Soumettez un achat de tickets et attendez la validation pour émettre un QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.body),
            ),
          ],
        ),
      ),
    );
  }
}

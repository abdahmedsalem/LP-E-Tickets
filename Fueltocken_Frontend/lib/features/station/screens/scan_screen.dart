import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/models/station_qr_check_result.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/mini_qr.dart';
import '../../auth/bloc/auth_bloc.dart';

const _scanBackground = Color(0xFFF7F7F4);
const _scanInk = Color(0xFF1F2430);
const _scanMuted = Color(0xFF6B7280);
const _scanAccent = Color(0xFFC9901E);
const _scanHintBg = Color(0xFFF4FAF7);
const _scanHintIconBg = Color(0xFFE5F5EE);
const _scanHintIcon = Color(0xFF58B08D);
const _scanFlashBg = Color(0xFF1B2030);
const _scanScrim = Color(0xA6000000);
const _scanOverlay = Color(0x55000000);
const _scanTopAreaHeight = 324.0;
const _scanBottomReserved = 210.0;
const _scanFrameVerticalNudge = 10.0;

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _processing = false;
  bool _consuming = false;
  bool _torchOn = false;
  bool _manualMode = false;
  final TextEditingController _manual = TextEditingController();
  late final AnimationController _scanLineCtrl;

  /// Codes consommés pendant cette session (évite un second scan avant refresh serveur).
  final Set<String> _consumedThisSession = {};

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _handleIncomingCode(String code) async {
    if (_processing || _consuming) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    if (AppEnvironment.useAcpecLiveData) {
      await _checkQrAcpec(trimmed);
    } else {
      await _consume(trimmed);
    }
  }

  Future<void> _checkQrAcpec(String publicCode) async {
    final codeKey = publicCode.trim().toLowerCase();
    if (_consumedThisSession.contains(codeKey)) {
      if (!mounted) return;
      await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _StationQrCheckSheet(
          publicCode: publicCode,
          result: const StationQrCheckResult(
            canConsume: false,
            reason:
                'Ce QR vient d’être consommé sur cette session et ne peut plus être scanné.',
          ),
        ),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      final raw = await OdooFueltokenFacade().stationQrCheck({
        'public_code': publicCode,
      });
      final result = StationQrCheckResult.fromRpc(raw);
      if (!mounted) return;
      setState(() => _processing = false);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        isDismissible: !_consuming,
        enableDrag: !_consuming,
        builder: (ctx) => _StationQrCheckSheet(
          publicCode: publicCode,
          result: result,
          onConfirmConsume: result.canConsume
              ? () async {
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (mounted) await _consume(publicCode);
                }
              : null,
        ),
      );
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        await _showError(
          e.isOdooSessionExpired
              ? 'Session expirée. Reconnectez-vous.'
              : e.message,
        );
      }
    } catch (e) {
      if (mounted) {
        await _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _consume(String code) async {
    if (_consuming) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    setState(() => _consuming = true);
    final user = context.read<AuthBloc>().state.user!;
    try {
      if (!AppEnvironment.useAcpecLiveData) {
        throw Exception(
          'Connexion serveur ACPEC requise pour consommer un QR.',
        );
      }
      final raw = await OdooFueltokenFacade().stationQrUse({
        'public_code': trimmed,
        'idempotency_key': const Uuid().v4(),
      });
      final qr = AcpecQrMapper.fromStationUseResult(
        raw,
        scannedPublicCode: trimmed,
        stationUserId: user.id,
        stationUserName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      final detailParams = AcpecQrMapper.detailParamsForRouteId(trimmed);
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        detailParams,
      );
      for (final params in [
        const <String, dynamic>{},
        const <String, dynamic>{'state': 'active'},
        const <String, dynamic>{'state': 'blocked'},
        const <String, dynamic>{'state': 'consumed'},
      ]) {
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.qrList,
          params,
        );
      }
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.transactions,
        null,
      );
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.stationTransactions,
        null,
      );
      _consumedThisSession.add(trimmed.toLowerCase());
      if (mounted) {
        await _showSuccess(qr);
        if (mounted) context.pop();
      }
    } catch (err) {
      if (mounted) {
        await _showError(err.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _consuming = false);
    }
  }

  Future<void> _showSuccess(QrToken qr) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Consommation validée',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.shortPublicCode(qr.publicCode),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: MiniQR(
                    data: qr.publicCode,
                    state: qr.state,
                    size: 132,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primarySoft),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            Formatters.numberFr(qr.totalAmount),
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDeep,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'MRU',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${qr.totalQty} face${qr.totalQty > 1 ? 's' : ''} consommée${qr.totalQty > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showError(String msg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scanBackground,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null) _handleIncomingCode(code);
            },
          ),

          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: _scanTopAreaHeight,
              color: _scanBackground,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paiement station',
                        style: GoogleFonts.inter(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: _scanInk,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scannez le QR code affiché sur la pompe ou la borne',
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: _scanMuted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ModeToggle(
                        isScanMode: !_manualMode,
                        onScanTap: () => setState(() => _manualMode = false),
                        onManualTap: () => setState(() => _manualMode = true),
                      ),
                      const SizedBox(height: 12),
                      const _StationHintBanner(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Scrim with cut-out reticle
          IgnorePointer(
            child: CustomPaint(size: Size.infinite, painter: _ScrimPainter()),
          ),

          // Reticle with corner brackets + scan line
          IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final frameSize = (constraints.maxWidth * 0.79)
                    .clamp(282.0, 312.0)
                    .toDouble();
                final cameraTop = _scanTopAreaHeight;
                final cameraBottom =
                    constraints.maxHeight - _scanBottomReserved;
                final cameraHeight = (cameraBottom - cameraTop).clamp(
                  0.0,
                  constraints.maxHeight,
                );
                final centeredTop =
                    cameraTop +
                    ((cameraHeight - frameSize) / 2) +
                    _scanFrameVerticalNudge;
                final maxTop = constraints.maxHeight - frameSize;
                final frameTop = centeredTop.clamp(cameraTop, maxTop);
                return Stack(
                  children: [
                    Positioned(
                      top: frameTop,
                      left: (constraints.maxWidth - frameSize) / 2,
                      width: frameSize,
                      height: frameSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ...const [
                            _Corner(alignment: Alignment.topLeft),
                            _Corner(alignment: Alignment.topRight),
                            _Corner(alignment: Alignment.bottomLeft),
                            _Corner(alignment: Alignment.bottomRight),
                          ],
                          AnimatedBuilder(
                            animation: _scanLineCtrl,
                            builder: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 124,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: _scanFlashBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    _controller.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _torchOn
                            ? Icons.lightbulb_rounded
                            : Icons.lightbulb_outline_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Activer le flash',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom panel: scan hints
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: _scanBackground,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9ECE8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _scanHintBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _scanHintIconBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.description_outlined,
                                color: _scanHintIcon,
                                size: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Conseil',
                                  style: TextStyle(
                                    color: _scanInk,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Placez le QR code au centre du cadre pour une meilleure détection.',
                                  style: TextStyle(
                                    color: _scanMuted,
                                    fontSize: 14,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_processing || _consuming)
            Positioned.fill(
              child: ColoredBox(
                color: _scanOverlay,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppLoadingLottie(
                        size: MediaQuery.sizeOf(context).shortestSide * 0.22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _consuming
                            ? 'Validation de la consommation…'
                            : 'Vérification du QR…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StationQrCheckSheet extends StatefulWidget {
  const _StationQrCheckSheet({
    required this.publicCode,
    required this.result,
    this.onConfirmConsume,
  });

  final String publicCode;
  final StationQrCheckResult result;
  final Future<void> Function()? onConfirmConsume;

  @override
  State<_StationQrCheckSheet> createState() => _StationQrCheckSheetState();
}

class _StationQrCheckSheetState extends State<_StationQrCheckSheet> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final publicCode = widget.publicCode;
    final result = widget.result;
    final onConfirmConsume = widget.onConfirmConsume;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final ok = result.canConsume;
    final accent = ok ? AppColors.success : AppColors.danger;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom + 8),
      child: Center(
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: scheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Vérification QR',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Contrôle serveur avant consommation',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: MiniQR(
                      data: publicCode,
                      state: ok ? QrState.active : QrState.blocked,
                      size: 128,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.42,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          Formatters.shortPublicCode(publicCode),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _QrStatePill(
                              label: ok ? 'Autorisé' : 'Bloqué',
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            _QrStatePill(
                              label: ok
                                  ? 'Prêt à consommer'
                                  : 'Consommation impossible',
                              color: accent,
                              soft: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          ok ? Icons.check_circle_outline : Icons.block_rounded,
                          color: accent,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ok
                                    ? 'Consommation autorisée'
                                    : 'Consommation bloquée',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ok
                                    ? 'Vous pouvez enregistrer la consommation sur ce QR.'
                                    : 'Ce QR ne peut pas être consommé dans son état actuel.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!ok && result.reason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Motif',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            result.reason!.trim(),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Fermer'),
                        ),
                      ),
                      if (onConfirmConsume != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _confirming
                                ? null
                                : () async {
                                    setState(() => _confirming = true);
                                    try {
                                      await onConfirmConsume();
                                    } finally {
                                      if (mounted) {
                                        setState(() => _confirming = false);
                                      }
                                    }
                                  },
                            icon: _confirming
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: AppInlineLoading(
                                      size: 20,
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              _confirming ? 'Validation…' : 'Consommer',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Reticle pieces
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _QrStatePill extends StatelessWidget {
  const _QrStatePill({
    required this.label,
    required this.color,
    this.soft = false,
  });

  final String label;
  final Color color;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: soft
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.alignment});
  final Alignment alignment;
  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? const BorderSide(color: Colors.white, width: 7)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: Colors.white, width: 7)
                : BorderSide.none,
            left: isLeft
                ? const BorderSide(color: Colors.white, width: 7)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: Colors.white, width: 7)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = _scanScrim;
    final frameSize = (size.width * 0.79).clamp(282.0, 312.0).toDouble();
    final cameraTop = _scanTopAreaHeight;
    final cameraBottom = size.height - _scanBottomReserved;
    final cameraHeight = (cameraBottom - cameraTop).clamp(0.0, size.height);
    final centeredTop =
        cameraTop + ((cameraHeight - frameSize) / 2) + _scanFrameVerticalNudge;
    final maxTop = size.height - frameSize;
    final frameTop = centeredTop.clamp(cameraTop, maxTop);
    final hole = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (size.width - frameSize) / 2,
        frameTop,
        frameSize,
        frameSize,
      ),
      const Radius.circular(22),
    );
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, scrim);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.isScanMode,
    required this.onScanTap,
    required this.onManualTap,
  });

  final bool isScanMode;
  final VoidCallback onScanTap;
  final VoidCallback onManualTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECE8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeToggleButton(
              label: 'Scanner',
              icon: Icons.qr_code_scanner_rounded,
              selected: isScanMode,
              onTap: onScanTap,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeToggleButton(
              label: 'Saisir manuellement',
              icon: Icons.keyboard_alt_outlined,
              selected: !isScanMode,
              onTap: onManualTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  const _ModeToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surface : const Color(0xFFF5F5F3),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? _scanAccent : _scanMuted),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? _scanAccent : _scanMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationHintBanner extends StatelessWidget {
  const _StationHintBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F1E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3E5C5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFF4DDAA),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.info_rounded,
              size: 17,
              color: Color(0xFFB88413),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Assurez-vous que le QR code provient d’une station de confiance avant de continuer.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B5563),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

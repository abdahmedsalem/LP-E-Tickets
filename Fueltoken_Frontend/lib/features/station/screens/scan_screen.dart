import 'dart:async';

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
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/models/station_qr_check_result.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/mini_qr.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/auth_action_code_dialog.dart';

const _scanBackground = Colors.white;
const _scanInk = Color(0xFF1F2430);
const _scanMuted = Color(0xFF6B7280);
const _scanBorder = Color(0xFFE2E6DD);

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    torchEnabled: false,
  );

  bool _processing = false;
  bool _consuming = false;
  final Set<String> _consumedThisSession = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    unawaited(_handleDetect(capture));
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_processing || _consuming) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;
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
      await showModalBottomSheet<void>(
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
        isDismissible: true,
        enableDrag: true,
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
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: 'Vérification du PIN',
        description: 'Saisissez votre PIN pour confirmer cette opération.',
      );
      if (actionCode == null || actionCode.isEmpty || !mounted) return;
      final raw = await OdooFueltokenFacade().stationQrUse({
        'public_code': trimmed,
        'action_code': actionCode,
        'idempotency_key': const Uuid().v4(),
      });
      final guarded = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Consommation QR refusée par le serveur.',
        publicErrorMessage:
            'La consommation du QR a échoué. Réessayez ou contactez l’administrateur.',
      );
      final qr = AcpecQrMapper.fromStationUseResult(
        guarded,
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
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.walletCurrent,
        Map<String, dynamic>.from(
          OdooFueltokenRpcConfig.walletCurrentDefaultParams,
        ),
      );
      WalletRefreshBus.instance.bump();
      ClientHistoryRefreshBus.instance.bump();
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
    await showDialog<void>(
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
                  style: GoogleFonts.poppins(
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
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDeep,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            Formatters.defaultCurrency,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
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
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: _scanBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ScanHeader(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: (size.height * 0.40).clamp(260.0, 380.0),
                    child: _ScanCameraCard(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scanner QR Client',
            style: GoogleFonts.poppins(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.04,
              letterSpacing: -0.9,
              color: _scanInk,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Text(
              'Scannez n\'importe quel code QR compatible et payez plus rapidement et facilement',
              style: GoogleFonts.poppins(
                fontSize: 13.8,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: _scanMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCameraCard extends StatelessWidget {
  const _ScanCameraCard({required this.controller, required this.onDetect});

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white,
        border: Border.all(color: _scanBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              onDetect: onDetect,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.04),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.06),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: _CornerFrame()),
          ],
        ),
      ),
    );
  }
}

class _CornerFrame extends StatelessWidget {
  const _CornerFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: CustomPaint(
          painter: _CornerFramePainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    const corner = 34.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawCorner(Offset start, List<Offset> points) {
      final path = Path()..moveTo(start.dx, start.dy);
      for (final p in points) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    drawCorner(const Offset(0, corner), [
      const Offset(0, 0),
      const Offset(corner, 0),
    ]);
    drawCorner(Offset(size.width - corner, 0), [
      Offset(size.width, 0),
      Offset(size.width, corner),
    ]);
    drawCorner(Offset(0, size.height - corner), [
      Offset(0, size.height),
      Offset(corner, size.height),
    ]);
    drawCorner(Offset(size.width - corner, size.height), [
      Offset(size.width, size.height),
      Offset(size.width, size.height - corner),
    ]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final result = widget.result;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom + 8),
      child: Center(
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: scheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
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
                    style: GoogleFonts.poppins(
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
                  Center(
                    child: MiniQR(
                      data: widget.publicCode,
                      state: result.canConsume
                          ? QrState.active
                          : QrState.blocked,
                      size: 128,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoLine(
                    label: 'Montant total',
                    value: result.totalAmount != null
                        ? Formatters.money(result.totalAmount!)
                        : 'Non renseigné',
                    highlighted: true,
                  ),
                  const SizedBox(height: 8),
                  _InfoLine(
                    label: 'Client',
                    value: result.clientName ?? 'Non renseigné',
                  ),
                  const SizedBox(height: 12),
                  _QrStatePill(
                    label: result.canConsume
                        ? 'Consommation autorisée'
                        : 'Consommation bloquée',
                    color: result.canConsume
                        ? AppColors.success
                        : AppColors.danger,
                    subtitle: result.canConsume
                        ? 'Vous pouvez enregistrer la consommation sur ce QR.'
                        : 'Ce QR ne peut pas être consommé dans son état actuel.',
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _confirming
                          ? null
                          : () async {
                              if (widget.onConfirmConsume == null) {
                                Navigator.pop(context);
                                return;
                              }
                              setState(() => _confirming = true);
                              try {
                                await widget.onConfirmConsume!.call();
                              } finally {
                                if (mounted) {
                                  setState(() => _confirming = false);
                                }
                              }
                            },
                      child: Text(
                        _confirming
                            ? 'Validation…'
                            : (widget.onConfirmConsume == null
                                  ? 'Fermer'
                                  : 'Envoyer'),
                      ),
                    ),
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

class _QrStatePill extends StatelessWidget {
  const _QrStatePill({
    required this.label,
    required this.color,
    required this.subtitle,
  });

  final String label;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.8,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.88),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primaryTint
            : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? AppColors.primarySoft
              : scheme.outline.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: highlighted
                    ? AppColors.primaryDark
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? AppColors.primaryDeep : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

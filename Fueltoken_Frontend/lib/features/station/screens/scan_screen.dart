import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/auth/auth_session_host.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/client_history_refresh_bus.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/wallet_refresh_bus.dart';
import '../../../data/models/qr_token.dart';
import '../../../data/models/station_qr_check_result.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/acpec_rpc_result_guard.dart';
import '../../../data/services/sensitive_action_intent.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/mini_qr.dart';
import '../../../shared/widgets/station_qr_failure_dialog.dart';
import '../../../shared/widgets/station_qr_success_dialog.dart';
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

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    torchEnabled: false,
    autoStart: false,
  );

  bool _processing = false;
  bool _consuming = false;
  bool _leavingAfterSuccess = false;
  bool _startingScanner = false;
  bool _qrCheckLoadingVisible = false;
  Future<void>? _qrCheckLoadingRoute;
  String? _cameraError;
  String? _lastHandledCode;
  DateTime? _lastHandledAt;
  static const Duration _sameCodeCooldown = Duration(seconds: 3);
  final Set<String> _consumedThisSession = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScanner());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ne pas toucher à la caméra tant qu'une modale/consommation est en cours :
    // le flux _restartScannerAfterModal s'en charge lui-même.
    if (_processing || _consuming) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_restartScannerAfterModal());
      case AppLifecycleState.inactive:
        unawaited(_stopScannerForModal());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _startingScanner) return;

    _startingScanner = true;
    try {
      await _controller.start();
      if (mounted && _cameraError != null) {
        setState(() => _cameraError = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraError = AppLocalizations.of(context).stationCameraUnavailable;
        });
      }
    } finally {
      _startingScanner = false;
    }
  }

  Future<void> _stopScannerForModal() async {
    if (!mounted) return;
    try {
      await _controller.stop();
    } catch (_) {
      // Scanner may already be stopped or not fully initialized.
    }
  }

  Future<void> _restartScannerAfterModal() async {
    if (!mounted) return;

    try {
      await _controller.stop();
    } catch (_) {
      // Scanner may already be stopped or not fully initialized.
    }

    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;

    await _startScanner();
  }

  void _goStationHome() {
    if (!mounted) return;

    setState(() {
      _processing = false;
      _consuming = false;
      _leavingAfterSuccess = false;
    });
    unawaited(_stopScannerForModal());
    context.go('/station/home');
  }

  void _scheduleScannerStartWhenVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_processing || _consuming || _leavingAfterSuccess) return;

      final path = GoRouterState.of(context).uri.path;
      if (path == '/station/scan') {
        unawaited(_startScanner());
      }
    });
  }

  void _showQrCheckLoadingSheet() {
    if (!mounted || _qrCheckLoadingVisible) return;
    _qrCheckLoadingVisible = true;
    final route = showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => const _StationQrCheckLoadingSheet(),
    );
    _qrCheckLoadingRoute = route;
    unawaited(
      route.whenComplete(() {
        if (identical(_qrCheckLoadingRoute, route)) {
          _qrCheckLoadingVisible = false;
          _qrCheckLoadingRoute = null;
        }
      }),
    );
  }

  Future<void> _dismissQrCheckLoadingSheet() async {
    if (!mounted || !_qrCheckLoadingVisible) return;
    final route = _qrCheckLoadingRoute;
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      if (route != null) await route;
    } else {
      _qrCheckLoadingVisible = false;
      _qrCheckLoadingRoute = null;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    unawaited(_handleDetect(capture));
  }

  Barcode? _firstQrBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      if (barcode.format == BarcodeFormat.qrCode) return barcode;
    }
    return null;
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_leavingAfterSuccess || _processing || _consuming) return;

    final barcode = _firstQrBarcode(capture);
    if (barcode == null) return;

    final code = barcode.rawValue;
    if (code == null) return;

    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    final codeKey = trimmed.toLowerCase();
    if (_lastHandledCode == codeKey &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _sameCodeCooldown) {
      return;
    }
    _lastHandledCode = codeKey;
    _lastHandledAt = now;

    if (AppEnvironment.useAcpecLiveData) {
      await _checkQrAcpec(trimmed);
    } else {
      await _consume(trimmed);
    }
  }

  Future<void> _checkQrAcpec(String publicCode) async {
    final l10n = AppLocalizations.of(context);
    final codeKey = publicCode.trim().toLowerCase();

    if (_consumedThisSession.contains(codeKey)) {
      if (!mounted) return;
      setState(() => _processing = true);
      await _stopScannerForModal();
      if (!mounted) return;

      try {
        await _showFailureDialog(
          title: l10n.stationQrNotConsumable,
          message: l10n.stationQrAlreadyConsumed,
          actionLabel: l10n.stationBackHome,
        );
        if (mounted) _goStationHome();
      } finally {
        if (mounted && _processing) {
          setState(() => _processing = false);
        }
      }
      return;
    }

    setState(() => _processing = true);
    await _stopScannerForModal();
    if (!mounted) return;

    var consumeRequested = false;
    try {
      _showQrCheckLoadingSheet();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final raw = await OdooFueltokenFacade().stationQrCheck({
        'public_code': publicCode,
      });
      if (!mounted) return;
      final result = StationQrCheckResult.fromRpc(raw);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      await _dismissQrCheckLoadingSheet();
      if (!mounted) return;

      if (!result.canConsume) {
        await _showFailureDialog(
          title: l10n.stationQrNotConsumable,
          message: l10n.stationQrNotConsumableMessage,
          actionLabel: l10n.stationBackHome,
        );
        if (mounted) _goStationHome();
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.ink.withValues(alpha: 0.58),
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        builder: (ctx) => _StationQrCheckSheet(
          publicCode: publicCode,
          result: result,
          onConfirmConsume: () async {
            if (!ctx.mounted) return;
            consumeRequested = true;
            Navigator.pop(ctx);
            if (mounted) {
              await _consume(publicCode);
            }
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted && !consumeRequested && !_consuming) {
        _lastHandledCode = null;
        _lastHandledAt = null;
        setState(() => _processing = false);
        await _restartScannerAfterModal();
      }
    } catch (e) {
      if (mounted) {
        if (e is OdooJsonRpcException && e.requiresReLogin) {
          await _dismissQrCheckLoadingSheet();
          AuthSessionHost.instance.notifySessionExpired();
          return;
        }
        await _dismissQrCheckLoadingSheet();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        if (!mounted) return;
        // Une panne réseau/serveur ne signifie pas que le QR est non
        // consommable : ne pas induire l’opérateur en erreur.
        final technical = ErrorPresenter.isBackendUnavailable(e);
        await _showFailureDialog(
          title: technical
              ? l10n.stationVerificationImpossible
              : l10n.stationQrNotConsumable,
          message: ErrorPresenter.localizedMessage(context, e),
          actionLabel: technical
              ? l10n.stationBackToScan
              : l10n.stationBackHome,
        );
        if (mounted) {
          if (technical) {
            setState(() => _processing = false);
            await _restartScannerAfterModal();
          } else {
            _goStationHome();
          }
        }
      }
    } finally {
      if (mounted && _processing) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _consume(String code) async {
    final l10n = AppLocalizations.of(context);
    if (_consuming) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    setState(() => _consuming = true);
    await _stopScannerForModal();
    if (!mounted) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      if (mounted) setState(() => _consuming = false);
      AuthSessionHost.instance.notifySessionExpired();
      return;
    }
    try {
      if (!AppEnvironment.useAcpecLiveData) {
        throw Exception(l10n.commonServerUnavailable);
      }
      final actionCode = await showSensitiveActionCodeDialog(
        context,
        title: l10n.stationPinVerification,
        description: l10n.stationPinScanDescription,
      );
      if (actionCode == null || actionCode.isEmpty) {
        if (mounted) await _restartScannerAfterModal();
        return;
      }
      if (!mounted) return;
      final intent = SensitiveActionIntent.create('station-qr-use');
      final raw = await OdooFueltokenFacade().stationQrUse(
        intent.withAuthParams({'public_code': trimmed}, actionCode: actionCode),
      );
      final guarded = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: l10n.stationConsumptionRejected,
        publicErrorMessage: l10n.stationConsumptionFailed,
      );
      final qr = AcpecQrMapper.fromStationUseResult(
        guarded,
        scannedPublicCode: trimmed,
        stationUserId: user.id,
        stationUserName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      final transactionName =
          _payloadString(guarded, const [
            'transaction_name',
            'transactionName',
          ]) ??
          l10n.commonNotProvided;
      final consumedAt =
          _payloadDateTime(guarded, const [
            'consumed_at',
            'consumedAt',
            'transaction_created_at',
            'transactionCreatedAt',
            'created_at',
            'createdAt',
          ]) ??
          DateTime.now();
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
        setState(() => _leavingAfterSuccess = true);
        await _showSuccess(
          qr,
          transactionName: transactionName,
          consumedAt: consumedAt,
        );
        if (mounted) _goStationHome();
      }
    } catch (err) {
      if (mounted) {
        final technical = ErrorPresenter.isBackendUnavailable(err);
        await _showFailureDialog(
          title: technical
              ? l10n.stationConsumptionUnconfirmed
              : l10n.stationOperationRejected,
          message: technical
              ? l10n.stationConsumptionUnconfirmedMessage
              : ErrorPresenter.localizedMessage(context, err),
          actionLabel: l10n.stationBackToScan,
        );
        if (mounted) await _restartScannerAfterModal();
      }
    } finally {
      if (mounted && !_leavingAfterSuccess) {
        setState(() => _consuming = false);
      }
    }
  }

  String? _payloadString(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  DateTime? _payloadDateTime(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _formatStationDateTime(DateTime value) {
    return Formatters.dateTimeDash(value);
  }

  Future<void> _showSuccess(
    QrToken qr, {
    required String transactionName,
    required DateTime consumedAt,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      builder: (ctx) {
        return StationQrSuccessDialog(
          amount: Formatters.money(qr.totalAmount),
          consumedAt: _formatStationDateTime(consumedAt),
          transactionName: transactionName,
          onClose: () => Navigator.pop(ctx),
        );
      },
    );
  }

  Future<void> _showFailureDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      builder: (ctx) {
        return StationQrFailureDialog(
          title: title,
          message: message,
          actionLabel: actionLabel,
          onClose: () => Navigator.pop(ctx),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleScannerStartWhenVisible();
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: !_consuming,
      child: Scaffold(
        backgroundColor: _scanBackground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScanHeader(onBack: _consuming ? null : _goStationHome),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                    child: SizedBox(
                      width: double.infinity,
                      height: (size.height * 0.40).clamp(260.0, 380.0),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ScanCameraCard(
                            controller: _controller,
                            onDetect: _onDetect,
                          ),
                          if (_cameraError != null)
                            _CameraErrorCard(
                              message: _cameraError!,
                              onRetry: () => unawaited(_startScanner()),
                            ),
                        ],
                      ),
                    ),
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

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.stationBackHome,
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: _scanInk,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.stationScannerTitle,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.04,
                    letterSpacing: -0.9,
                    color: _scanInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Text(
              l10n.stationScannerSubtitle,
              style: TextStyle(
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

class _CameraErrorCard extends StatelessWidget {
  const _CameraErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white,
        border: Border.all(color: _scanBorder),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_outlined, size: 44, color: _scanMuted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: _scanMuted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.stationReactivateCamera),
          ),
        ],
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

class _StationQrCheckLoadingSheet extends StatelessWidget {
  const _StationQrCheckLoadingSheet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.leaderGreen.withValues(alpha: 0.28),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.leaderGreen,
            ),
          ),
        ),
      ),
    );
  }
}

class _StationQrCheckSheet extends StatefulWidget {
  const _StationQrCheckSheet({
    required this.publicCode,
    required this.result,
    required this.onConfirmConsume,
  });

  final String publicCode;
  final StationQrCheckResult result;
  final Future<void> Function() onConfirmConsume;

  @override
  State<_StationQrCheckSheet> createState() => _StationQrCheckSheetState();
}

class _StationQrCheckSheetState extends State<_StationQrCheckSheet> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = widget.result;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom + 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.16),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(27),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 7,
                    decoration: const BoxDecoration(
                      gradient: AppColors.validGradient,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.line,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.stationQrVerificationTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.stationQrVerificationSubtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                        Center(
                          child: MiniQR(
                            data: widget.publicCode,
                            state: QrState.active,
                            size: 128,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoLine(
                          label: l10n.stationTotalAmount,
                          value: result.totalAmount != null
                              ? Formatters.money(result.totalAmount!)
                              : l10n.commonNotProvided,
                          highlighted: true,
                        ),
                        const SizedBox(height: 8),
                        _InfoLine(
                          label: l10n.stationClient,
                          value: result.clientName ?? l10n.commonNotProvided,
                        ),
                        const SizedBox(height: 12),
                        _QrStatePill(
                          label: l10n.stationConsumptionAllowed,
                          color: AppColors.success,
                          icon: Icons.check_circle_outline,
                          subtitle: l10n.stationConsumptionAllowedMessage,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: _confirming
                                      ? null
                                      : () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.ink,
                                    side: const BorderSide(
                                      color: AppColors.line,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: Text(l10n.commonCancel),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: _confirming
                                      ? null
                                      : () async {
                                          setState(() => _confirming = true);
                                          try {
                                            await widget.onConfirmConsume
                                                .call();
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => _confirming = false,
                                              );
                                            }
                                          }
                                        },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.leaderGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: Text(
                                    _confirming
                                        ? l10n.stationValidating
                                        : l10n.commonContinue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
    this.icon = Icons.check_circle_outline,
  });

  final String label;
  final Color color;
  final String subtitle;
  final IconData icon;

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
          Icon(icon, size: 22, color: color),
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
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                textAlign: TextAlign.end,
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

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/purchase_lot.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/payment_proof_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_message.dart';
import '../../../shared/widgets/backend_unavailable_banner.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/screen_header.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<PurchaseLot> _purchases = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).commonSessionRequired;
        _purchases = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!AppEnvironment.useAcpecLiveData) {
        throw StateError(AppLocalizations.of(context).commonServerUnavailable);
      }
      final companyId = AppEnvironment.companyIdForUser(user);
      final facade = OdooFueltokenFacade();
      final raw = await facade.purchasesList(const <String, dynamic>{});
      var purchases = AcpecPurchasesMapper.fromRpcResult(
        raw,
        clientId: user.id,
        clientName: user.name,
        companyId: companyId,
      )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      purchases = await _loadMissingProofs(
        purchases,
        facade: facade,
        clientId: user.id,
        clientName: user.name,
        companyId: companyId,
      );
      if (!mounted) return;
      setState(() {
        _purchases = purchases;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorPresenter.localizedMessage(context, error);
      });
    }
  }

  Future<List<PurchaseLot>> _loadMissingProofs(
    List<PurchaseLot> purchases, {
    required OdooFueltokenFacade facade,
    required String clientId,
    required String clientName,
    required String companyId,
  }) async {
    return Future.wait(
      purchases.map((purchase) async {
        if (_hasLoadableProof(purchase)) return purchase;
        final purchaseId = AcpecPurchasesMapper.resolvePurchaseId(purchase.id);
        if (purchaseId == null) return purchase;
        try {
          final rawDetail = await facade.purchasesDetail(<String, dynamic>{
            'purchase_id': purchaseId,
          });
          final detail = AcpecPurchasesMapper.parsePurchaseDetail(
            rawDetail,
            clientId: clientId,
            clientName: clientName,
            companyId: companyId,
            requestedPurchaseId: purchaseId,
          );
          return _hasLoadableProof(detail) ? detail : purchase;
        } catch (_) {
          // L'historique reste utilisable même si un détail est indisponible.
          return purchase;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: l10n.settingsPaymentHistory,
              subtitle: l10n.paymentHistoryScreenSubtitle,
              onBack: () => context.pop(),
            ),
            Expanded(child: _buildContent(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading && _purchases.isEmpty) {
      return const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: AppLoadingSkeleton(
          style: AppLoadingSkeletonStyle.qrCards,
          itemCount: 4,
        ),
      );
    }
    if (_purchases.isEmpty) {
      return RefreshIndicator(
        color: AppColors.leaderGreen,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            if (_error != null)
              BackendUnavailableBanner(message: _error!, onRetry: _refresh)
            else
              EmptyState(
                icon: Icons.payments_outlined,
                title: l10n.paymentHistoryEmptyTitle,
                message: l10n.paymentHistoryEmptyMessage,
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.leaderGreen,
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _purchases.length + (_error == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (_error != null && index == 0) {
            return BackendUnavailableBanner(
              message: _error!,
              onRetry: _refresh,
            );
          }
          final purchase = _purchases[_error == null ? index : index - 1];
          return _PaymentPurchaseCard(purchase: purchase);
        },
      ),
    );
  }
}

class _PaymentPurchaseCard extends StatelessWidget {
  const _PaymentPurchaseCard({required this.purchase});

  final PurchaseLot purchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final proof = _primaryProof(purchase);
    final accent = _stateColor(purchase.state);
    final purchaseDate = purchase.submittedAt ?? purchase.createdAt;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.lineSoft),
        boxShadow: AppColors.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaymentProofPreview(proof: proof),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: StatusBadge.lot(
                          purchase.state,
                          label: _stateLabel(l10n, purchase.state),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Formatters.money(purchase.totalAmount),
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        Formatters.dateTime(purchaseDate),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionPanelList.radio(
                elevation: 0,
                expandedHeaderPadding: EdgeInsets.zero,
                expansionCallback: (_, _) {},
                children: [
                  ExpansionPanelRadio(
                    value: purchase.id,
                    canTapOnHeader: true,
                    backgroundColor: AppColors.brandBlueTint,
                    headerBuilder: (_, isExpanded) => Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        2,
                        8,
                        2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 20,
                            color: isExpanded
                                ? AppColors.brandBlue
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.paymentHistoryPurchaseDetails,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    body: _PurchaseDetails(purchase: purchase),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseDetails extends StatelessWidget {
  const _PurchaseDetails({required this.purchase});

  final PurchaseLot purchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <({String label, String value})>[
      (
        label: l10n.paymentHistoryPurchaseReference,
        value: purchase.internalRef,
      ),
      (label: l10n.referenceCode, value: purchase.publicCode),
      if (purchase.paymentReference?.trim().isNotEmpty == true)
        (
          label: l10n.paymentReference,
          value: purchase.paymentReference!.trim(),
        ),
      (label: l10n.status, value: _stateLabel(l10n, purchase.state)),
      (
        label: l10n.purchaseTotal,
        value: Formatters.money(purchase.totalAmount),
      ),
      (
        label: l10n.submittedOn,
        value: Formatters.dateTime(purchase.submittedAt ?? purchase.createdAt),
      ),
      if (purchase.validationDate != null)
        (
          label: l10n.purchasesValidationDate,
          value: Formatters.dateTime(purchase.validationDate!),
        ),
      if (purchase.validatorName?.trim().isNotEmpty == true)
        (label: l10n.validatedBy, value: purchase.validatorName!.trim()),
      if (purchase.rejectionReason?.trim().isNotEmpty == true)
        (label: l10n.rejectionReason, value: purchase.rejectionReason!.trim()),
      (
        label: l10n.paymentHistoryCarnetsCount,
        value:
            '${purchase.lines.fold<int>(0, (sum, line) => sum + line.carnetCount)}',
      ),
      (label: l10n.paymentHistoryTicketsCount, value: '${purchase.totalFaces}'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      color: AppColors.brandBlueTint,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _DetailRow(label: rows[i].label, value: rows[i].value),
                if (i != rows.length - 1)
                  const Divider(height: 18, color: AppColors.lineSoft),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: SelectableText(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentProofPreview extends StatefulWidget {
  const _PaymentProofPreview({required this.proof});

  final PurchaseProofSummary? proof;

  @override
  State<_PaymentProofPreview> createState() => _PaymentProofPreviewState();
}

class _PaymentProofPreviewState extends State<_PaymentProofPreview> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  Future<Uint8List?> _loadBytes() async {
    final proof = widget.proof;
    if (proof == null) return null;
    if (proof.bytes?.isNotEmpty == true) return proof.bytes;
    return PaymentProofLoader.fetchBytes(proof.url);
  }

  String _filename() {
    final raw = widget.proof?.filename?.trim();
    if (raw != null && raw.isNotEmpty && raw != 'false') return raw;
    return 'preuve_paiement.jpg';
  }

  Future<void> _download(BuildContext context, Uint8List? knownBytes) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = knownBytes ?? await _bytesFuture;
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) {
          AppMessage.error(context, l10n.purchaseDownloadUnavailable);
        }
        return;
      }
      final path = await FilePicker.saveFile(
        dialogTitle: l10n.commonDownload,
        fileName: _filename(),
        bytes: bytes,
      );
      if (context.mounted && path != null) {
        AppMessage.success(context, l10n.paymentHistoryProofDownloaded);
      }
    } catch (_) {
      if (context.mounted) {
        AppMessage.error(context, l10n.purchaseProofDownloadFailed);
      }
    }
  }

  Future<void> _openFullScreen(BuildContext context, Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(AppLocalizations.of(pageContext).purchaseProofTitle),
            actions: [
              IconButton(
                tooltip: AppLocalizations.of(pageContext).commonDownload,
                onPressed: () => _download(pageContext, bytes),
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: InteractiveViewer(
              minScale: 0.7,
              maxScale: 5,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        final hasImage =
            bytes != null &&
            bytes.isNotEmpty &&
            (widget.proof?.hasImagePreview ?? true);
        return SizedBox(
          height: 185,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Material(
                color: AppColors.surfaceAlt,
                child: InkWell(
                  onTap: hasImage
                      ? () => _openFullScreen(context, bytes)
                      : null,
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.leaderGreen,
                            strokeWidth: 2.4,
                          ),
                        )
                      : hasImage
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : _NoProofPlaceholder(
                          label: l10n.paymentHistoryProofUnavailable,
                        ),
                ),
              ),
              if (hasImage)
                PositionedDirectional(
                  end: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      _ProofAction(
                        icon: Icons.fullscreen_rounded,
                        label: l10n.paymentHistoryOpenProof,
                        onTap: () => _openFullScreen(context, bytes),
                      ),
                      const SizedBox(width: 8),
                      _ProofAction(
                        icon: Icons.download_rounded,
                        label: l10n.commonDownload,
                        filled: true,
                        onTap: () => _download(context, bytes),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NoProofPlaceholder extends StatelessWidget {
  const _NoProofPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.hint,
            size: 38,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ProofAction extends StatelessWidget {
  const _ProofAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled
          ? AppColors.leaderGreen
          : Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: filled ? Colors.white : AppColors.brandBlueDeep,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : AppColors.brandBlueDeep,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

PurchaseProofSummary? _primaryProof(PurchaseLot purchase) {
  // 1. Prefer proofs that contain binary bytes
  for (final proof in purchase.proofs) {
    if (proof.bytes?.isNotEmpty == true) return proof;
  }
  // 2. Prefer proofs with fetchable URLs
  for (final proof in purchase.proofs) {
    if (_isFetchableProofUrl(proof.url)) return proof;
  }
  // 3. Fallback to any displayable proof
  for (final proof in purchase.proofs) {
    if (proof.isDisplayable) return proof;
  }
  // 4. Fallback to paymentProofPath if it's a fetchable URL
  final path = purchase.paymentProofPath?.trim();
  if (!_isFetchableProofUrl(path)) return null;
  return PurchaseProofSummary(
    label: 'Preuve de paiement',
    filename: path!.split('/').last,
    url: path,
  );
}

bool _hasLoadableProof(PurchaseLot purchase) {
  for (final proof in purchase.proofs) {
    if (proof.bytes?.isNotEmpty == true || _isFetchableProofUrl(proof.url)) {
      return true;
    }
  }
  return _isFetchableProofUrl(purchase.paymentProofPath);
}

bool _isFetchableProofUrl(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw == 'false') return false;
  return raw.startsWith('http://') ||
      raw.startsWith('https://') ||
      raw.startsWith('/');
}

Color _stateColor(PurchaseLotState state) => switch (state) {
  PurchaseLotState.approved => AppColors.success,
  PurchaseLotState.submitted => AppColors.info,
  PurchaseLotState.rejected => AppColors.danger,
  PurchaseLotState.draft => AppColors.textMuted,
};

String _stateLabel(AppLocalizations l10n, PurchaseLotState state) =>
    switch (state) {
      PurchaseLotState.draft => l10n.statusDraft,
      PurchaseLotState.submitted => l10n.statusSubmitted,
      PurchaseLotState.approved => l10n.statusApproved,
      PurchaseLotState.rejected => l10n.statusRejected,
    };

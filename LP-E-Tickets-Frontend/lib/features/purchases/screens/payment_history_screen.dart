import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/auth/payment_proof_http_headers.dart';
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
import '../../../shared/widgets/amount_inline.dart';
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
      final raw = await facade.purchasesList(const <String, dynamic>{
        'include_proof_data': true,
      });
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
        if (_hasInlineProofBytes(purchase)) return purchase;
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
          if (_hasInlineProofBytes(detail)) return detail;
          return !_hasLoadableProof(purchase) && _hasLoadableProof(detail)
              ? detail
              : purchase;
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
      backgroundColor: Colors.white,
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
        padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _purchases.length + (_error == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    final scheme = Theme.of(context).colorScheme;
    final proof = _primaryProof(purchase);
    final purchaseDate = purchase.submittedAt ?? purchase.createdAt;
    final rejectionReason = purchase.rejectionReason?.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PaymentProofThumbnail(proof: proof, purchase: purchase),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: StatusBadge.lot(
                            purchase.state,
                            label: _stateLabel(l10n, purchase.state),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AmountInline(
                            amount: purchase.totalAmount,
                            semanticsLabel: Formatters.money(purchase.totalAmount),
                            textAlign: TextAlign.end,
                            valueStyle: const TextStyle(
                              fontSize: 14.2,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDeep,
                            ),
                            unitStyle: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      Formatters.dateTime(purchaseDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                        height: 1.2,
                      ),
                    ),
                    if (purchase.state == PurchaseLotState.rejected &&
                        rejectionReason != null &&
                        rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.report_gmailerrorred_outlined,
                              color: scheme.error,
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.rejectionReason,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.error,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    rejectionReason,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: scheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _PaymentProofThumbnail extends StatefulWidget {
  const _PaymentProofThumbnail({required this.proof, required this.purchase});

  final PurchaseProofSummary? proof;
  final PurchaseLot purchase;

  @override
  State<_PaymentProofThumbnail> createState() => _PaymentProofThumbnailState();
}

class _PaymentProofThumbnailState extends State<_PaymentProofThumbnail> {
  Future<Uint8List?>? _bytesFuture;
  Future<Map<String, String>>? _headersFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
    _headersFuture = paymentProofHttpHeaders();
  }

  @override
  void didUpdateWidget(covariant _PaymentProofThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proof != widget.proof) {
      _bytesFuture = _loadBytes();
      _headersFuture = paymentProofHttpHeaders();
    }
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

  Future<void> _openFullScreen(
    BuildContext context, {
    Uint8List? bytes,
    String? url,
    Map<String, String>? headers,
  }) async {
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasUrl = url != null && url.isNotEmpty;
    if (!hasBytes && !hasUrl) return;
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
              child: Center(
                child: hasBytes
                    ? Image.memory(bytes, fit: BoxFit.contain)
                    : Image.network(
                        url!,
                        headers: headers?.isEmpty == true ? null : headers,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Text(
                          AppLocalizations.of(
                            pageContext,
                          ).paymentHistoryProofUnavailable,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
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
        final hasBytes = bytes != null && bytes.isNotEmpty;
        final isWaiting = snapshot.connectionState == ConnectionState.waiting;
        final resolvedUrl = PaymentProofLoader.resolveProofUrl(
          widget.proof?.url,
        );
        final hasUrl = resolvedUrl != null && resolvedUrl.isNotEmpty;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasBytes || hasUrl
                ? () async {
                    final headers = hasBytes
                        ? null
                        : await (_headersFuture ??= paymentProofHttpHeaders());
                    if (!context.mounted) return;
                    await _openFullScreen(
                      context,
                      bytes: bytes,
                      url: resolvedUrl,
                      headers: headers,
                    );
                  }
                : null,
            child: Ink(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.lineSoft),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasBytes)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => _ProofThumbnailPlaceholder(
                          label: l10n.paymentHistoryProofUnavailable,
                        ),
                      ),
                    )
                  else if (isWaiting)
                    const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.leaderGreen,
                        ),
                      ),
                    )
                  else if (hasUrl)
                    FutureBuilder<Map<String, String>>(
                      future: _headersFuture,
                      builder: (context, headerSnapshot) {
                        final headers = headerSnapshot.data;
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.network(
                            resolvedUrl,
                            headers: headers?.isEmpty == true ? null : headers,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                _ProofThumbnailPlaceholder(
                                  label: l10n.paymentHistoryProofUnavailable,
                                ),
                          ),
                        );
                      },
                    )
                  else
                    _ProofThumbnailPlaceholder(
                      label: l10n.paymentHistoryProofUnavailable,
                    ),
                  if (hasBytes || hasUrl)
                    PositionedDirectional(
                      end: 4,
                      bottom: 4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.48),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProofThumbnailPlaceholder extends StatelessWidget {
  const _ProofThumbnailPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            height: 1.05,
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

bool _hasInlineProofBytes(PurchaseLot purchase) {
  for (final proof in purchase.proofs) {
    if (proof.bytes?.isNotEmpty == true) return true;
  }
  return false;
}

bool _isFetchableProofUrl(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw == 'false') return false;
  return raw.startsWith('http://') ||
      raw.startsWith('https://') ||
      raw.startsWith('/');
}

String _stateLabel(AppLocalizations l10n, PurchaseLotState state) =>
    switch (state) {
      PurchaseLotState.draft => l10n.statusDraft,
      PurchaseLotState.submitted => l10n.statusSubmitted,
      PurchaseLotState.approved => l10n.statusApproved,
      PurchaseLotState.rejected => l10n.statusRejected,
    };

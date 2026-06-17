import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/notifications/purchase_validation_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/qr_token.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/mini_qr.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../data/notifications_store.dart';
import '../models/notification_item.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _store = NotificationsStore.instance;
  final Set<String> _expandedIds = <String>{};

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user;
    if (user != null) {
      _store.loadForUser(user.id).then((_) {
        if (mounted) _store.initCounts();
        if (mounted) _store.migrateLegacyContent();
      });
    }
    unawaited(_syncPurchaseNotifications());
  }

  Future<void> _syncPurchaseNotifications() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    await PurchaseValidationNotificationService.instance.syncForUser(user);
  }

  Future<void> _markAllRead() async => _store.markAllRead();

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final notifications = _store.items
            .map(_store.displayItem)
            .toList(growable: false);
        final unreadItems = notifications
            .where((item) => !item.read)
            .toList(growable: false);
        final readItems = notifications
            .where((item) => item.read)
            .toList(growable: false);
        final hasUnread = _store.unreadCount.value > 0;

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBarHeader(
                  title: 'Notifications',
                    action: hasUnread
                      ? TextButton(
                          onPressed: _markAllRead,
                          child: Text(
                            'Tout lu',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                  leadingOnlyWhenNavigatorCanPop: true,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: notifications.isEmpty
                      ? const EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Aucune notification',
                          message:
                              'Les achats validés, QR et transferts apparaîtront ici.',
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            if (unreadItems.isNotEmpty) ...[
                              SectionLabel(
                                'Non lues',
                                trailing: Text(
                                  '${unreadItems.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              for (final item in unreadItems) ...[
                                _NotificationCard(
                                  item: item,
                                  expanded: _expandedIds.contains(item.id),
                                  onToggleDetails: () =>
                                      _toggleExpanded(item.id),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                            if (readItems.isNotEmpty) ...[
                              SectionLabel(
                                'Lues',
                                trailing: Text(
                                  '${readItems.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                              for (final item in readItems) ...[
                                _NotificationCard(
                                  item: item,
                                  expanded: _expandedIds.contains(item.id),
                                  onToggleDetails: () =>
                                      _toggleExpanded(item.id),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.expanded,
    required this.onToggleDetails,
  });

  final NotificationItem item;
  final bool expanded;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final isQrExpiration = _isQrExpiration(item);
    final isPurchase = item.id.startsWith('purchase-');
    final isTransfer = _isReceiptNotification(item);
    final isRejected = item.purchaseStatus == 'rejected';
    final accent = isPurchase
        ? (isRejected ? AppColors.brandRed : AppColors.leaderGreen)
        : isTransfer
            ? AppColors.leaderGreen
            : isQrExpiration
            ? const Color(0xFFF59E0B)
            : const Color(0xFFF59E0B);
    final dateLabel = item.notificationDateLabel?.trim() ?? '';
    final titleLabel = item.title;

    return AppCard(
      onTap: onToggleDetails,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      borderColor: item.read ? AppColors.line : accent.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted,
                size: 24,
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isPurchase && item.purchaseLines.isNotEmpty) ...[
                    for (final line in item.purchaseLines) ...[
                      _PurchaseLineTile(line: line),
                      if (line != item.purchaseLines.last)
                        const SizedBox(height: 12),
                    ],
                  ] else if (isTransfer) ...[
                    if ((item.transferPartyPhone ?? '').trim().isNotEmpty) ...[
                      _NotificationMetaTile(
                        label: 'Téléphone de l’envoyeur',
                        value: item.transferPartyPhone!.trim(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final line in item.transferLines) ...[
                      _ReceiptLineTile(line: line),
                      if (line != item.transferLines.last)
                        const SizedBox(height: 12),
                    ],
                  ] else if (isQrExpiration) ...[
                    _QrExpirationTile(item: item),
                  ] else ...[
                    Text(
                      item.body,
                      style: GoogleFonts.poppins(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w500,
                        color: AppColors.body,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PurchaseLineTile extends StatelessWidget {
  const _PurchaseLineTile({required this.line});

  final NotificationPurchaseLineItem line;

  @override
  Widget build(BuildContext context) {
    final carnet = line.label.trim().isEmpty ? 'Carnet' : line.label.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              carnet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: Formatters.numberFr(line.totalAmount),
                  style: GoogleFonts.poppins(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.leaderGreen,
                    height: 1.1,
                  ),
                ),
                TextSpan(
                  text: ' MRU',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.leaderGreen.withValues(alpha: 0.72),
                    height: 1.1,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ReceiptLineTile extends StatelessWidget {
  const _ReceiptLineTile({required this.line});

  final NotificationPurchaseLineItem line;

  @override
  Widget build(BuildContext context) {
    final carnet = line.label.trim().isEmpty ? 'Carnet' : line.label.trim();
    final amount = _displayAmount(line.amountLabel, fallback: line.totalAmount);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      carnet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: amount,
                      style: GoogleFonts.poppins(
                        fontSize: 13.2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.leaderGreen,
                        height: 1.1,
                      ),
                    ),
                    TextSpan(
                      text: ' MRU',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: AppColors.leaderGreen.withValues(alpha: 0.72),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayAmount(String value, {required int fallback}) {
    final raw = value.trim();
    if (raw.isEmpty) return Formatters.numberFr(fallback);
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.toUpperCase().endsWith(' MRU')) {
      return normalized.substring(0, normalized.length - 4).trim();
    }
    return normalized;
  }
}

class _NotificationMetaTile extends StatelessWidget {
  const _NotificationMetaTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isQrExpiration(NotificationItem item) {
  final text = '${item.category ?? ''} ${item.id} ${item.title} ${item.body}'
      .toLowerCase();
  return text.contains('expiration') || text.contains('expire');
}

bool _isReceiptNotification(NotificationItem item) {
  final text = '${item.category ?? ''} ${item.id} ${item.title} ${item.body}'
      .toLowerCase();
  return item.transferLines.isNotEmpty ||
      text.contains('transfer') ||
      text.contains('recu') ||
      text.contains('reçu') ||
      text.contains('reception') ||
      text.contains('réception');
}

String _qrExpirationAmountLabel(NotificationItem item) {
  final direct = item.amountLabel?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final parsed = _valueAfterLabel(item.body, const ['montant', 'amount']);
  if (parsed != null && parsed.isNotEmpty) return parsed;
  return 'Montant indisponible';
}

String? _valueAfterLabel(String body, List<String> labels) {
  final normalized = body.toLowerCase();
  for (final rawLine in body.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    for (final label in labels) {
      if (!lower.contains(label)) continue;
      final idx = line.indexOf(':');
      if (idx >= 0 && idx + 1 < line.length) {
        return line.substring(idx + 1).trim();
      }
      final dashIdx = line.indexOf('-');
      if (dashIdx >= 0 && dashIdx + 1 < line.length) {
        return line.substring(dashIdx + 1).trim();
      }
      final labelIdx = normalized.indexOf(label);
      if (labelIdx >= 0) {
        return body.substring(labelIdx + label.length).trim();
      }
    }
  }
  return null;
}

class _QrExpirationTile extends StatelessWidget {
  const _QrExpirationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final qrCode = item.qrPublicCode?.trim() ?? '';
    final amount = _qrExpirationAmountLabel(item);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
                children: [
                  Center(
                    child: MiniQR(
                      data: qrCode.isEmpty ? 'QR indisponible' : qrCode,
                      state: QrState.expired,
                      size: 104,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    qrCode.isEmpty ? 'Code QR indisponible' : qrCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Montant',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  amount,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.leaderGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: qrCode.isEmpty
                  ? null
                  : () => context.push('/qr/${Uri.encodeComponent(qrCode)}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B8F3A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(
                  0xFF1B8F3A,
                ).withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('Voir le QR'),
            ),
          ),
        ],
      ),
    );
  }
}




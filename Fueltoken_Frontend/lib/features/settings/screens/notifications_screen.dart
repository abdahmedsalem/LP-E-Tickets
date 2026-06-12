import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/notifications/purchase_validation_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_state.dart';
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

  void _openItem(NotificationItem item) {
    _store.markRead(item.id);
    final route = item.actionRoute;
    if (route != null && route.isNotEmpty) {
      context.push(route);
    }
  }

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
          backgroundColor: const Color(0xFFF7F8FA),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBarHeader(
                  title: 'Notifications',
                  subtitle: 'Validation de vos achats, QR et transferts',
                  action: hasUnread
                      ? TextButton(
                          onPressed: _markAllRead,
                          child: Text(
                            'Tout lu',
                            style: GoogleFonts.inter(
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
                                  style: GoogleFonts.inter(
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
                                  onTap: () => _openItem(item),
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
                                  style: GoogleFonts.inter(
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
                                  onTap: () => _openItem(item),
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
    required this.onTap,
    required this.onToggleDetails,
  });

  final NotificationItem item;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final isQrExpiration = _isQrExpiration(item);
    final isPurchase = item.id.startsWith('purchase-');
    final isRejected = item.purchaseStatus == 'rejected';
    final accent = isPurchase
        ? (isRejected ? AppColors.brandRed : AppColors.leaderGreen)
        : isQrExpiration
            ? const Color(0xFFF59E0B)
        : AppColors.primary;
    final dateLabel = isQrExpiration
        ? (_qrExpirationDateLabel(item) ?? item.timeLabel)
        : (item.validationDateLabel ?? item.timeLabel);
    final statusLabel = isPurchase
        ? (isRejected ? 'Rejetée' : 'Validée')
        : isQrExpiration
            ? 'Expiration'
        : (item.actionLabel ?? 'Disponible');
    final titleLabel = isQrExpiration
        ? 'QR expire dans 7 jours'
        : item.title;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      borderColor: item.read ? AppColors.line : accent.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleLabel,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Détails',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onToggleDetails,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        expanded ? 'Masquer' : 'Voir',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isQrExpiration
                        ? _qrExpirationDetailText(item)
                        : item.body,
                    style: GoogleFonts.inter(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w500,
                      color: AppColors.body,
                      height: 1.35,
                    ),
                  ),
                  if (isQrExpiration) ...[
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Montant',
                      value: _qrExpirationAmountLabel(item),
                      valueColor: AppColors.leaderGreen,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Date d\'expiration',
                      value: dateLabel,
                      valueColor: accent,
                    ),
                  ],
                  if (isPurchase && item.amountLabel != null) ...[
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Montant',
                      value: item.amountLabel!,
                      valueColor: AppColors.leaderGreen,
                    ),
                  ],
                  if (isPurchase && item.purchaseLines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final line in item.purchaseLines) ...[
                      _PurchaseLineTile(line: line),
                      const SizedBox(height: 8),
                    ],
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

bool _isQrExpiration(NotificationItem item) {
  final text = '${item.category ?? ''} ${item.id} ${item.title} ${item.body}'
      .toLowerCase();
  return text.contains('expiration') || text.contains('expire');
}

String _qrExpirationAmountLabel(NotificationItem item) {
  final direct = item.amountLabel?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final body = item.body;
  final amountMatch = RegExp(
    r'(?i)(?:montant|amount)\s*[:\-]?\s*([^\n•·]+)',
  ).firstMatch(body);
  final value = amountMatch?.group(1)?.trim();
  if (value != null && value.isNotEmpty) return value;
  return 'Montant indisponible';
}

String? _qrExpirationDateLabel(NotificationItem item) {
  final direct = item.validationDateLabel?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final body = item.body;
  final dateMatch = RegExp(
    r'(?i)(?:date d\'expiration|expiration(?:\s*le)?)\s*[:\-]?\s*([^\n•·]+)',
  ).firstMatch(body);
  final value = dateMatch?.group(1)?.trim();
  if (value != null && value.isNotEmpty) return value;
  return null;
}

String _qrExpirationDetailText(NotificationItem item) {
  final body = item.body.trim();
  if (body.isNotEmpty) return body;
  return 'QR bientôt expiré.';
}

class _PurchaseLineTile extends StatelessWidget {
  const _PurchaseLineTile({required this.line});

  final NotificationPurchaseLineItem line;

  @override
  Widget build(BuildContext context) {
    final carnet = line.label.trim().isEmpty ? 'Carnet' : line.label.trim();
    final quantity = line.quantityLabel.trim().isEmpty
        ? '${Formatters.numberFr(line.carnetCount)} carnet${line.carnetCount > 1 ? 's' : ''}'
        : line.quantityLabel.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  carnet,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quantity,
                  style: GoogleFonts.inter(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            line.amountLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.leaderGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label :',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

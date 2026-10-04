import 'package:flutter/material.dart';

import '../../features/transfer/screens/transfer_carnets_success_screen.dart';
import '../../features/transfer/models/transfer_confirmation.dart';
import '../../features/transfer/screens/transfer_tickets_success_screen.dart';

export '../../features/purchases/screens/purchase_success_screen.dart';
export '../../features/qr/generation/screens/qr_generation_success_screen.dart';
export '../../features/transfer/screens/transfer_carnets_success_screen.dart';
export '../../features/transfer/screens/transfer_tickets_success_screen.dart';

/// Compatibility entry point for existing callers. New code should call the
/// operation-specific success presenter.
Future<void> showTransferSuccessDialog(
  BuildContext context, {
  required int totalAmount,
  required DateTime confirmedAt,
  required String recipientName,
  List<TransferConfirmationLine> lines = const [],
  String? linesTitle,
  bool showQuantity = false,
}) {
  if (showQuantity) {
    return showTransferTicketsSuccessDialog(
      context,
      totalAmount: totalAmount,
      confirmedAt: confirmedAt,
      recipientName: recipientName,
      lines: lines,
      linesTitle: linesTitle,
    );
  }
  return showTransferCarnetsSuccessDialog(
    context,
    totalAmount: totalAmount,
    confirmedAt: confirmedAt,
    recipientName: recipientName,
    lines: lines,
    linesTitle: linesTitle,
  );
}

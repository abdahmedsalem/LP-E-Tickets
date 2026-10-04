import 'package:flutter/material.dart';

import '../../../core/models/sensitive_action_intent.dart';
import 'transfer_inventory.dart';

/// Arguments partagés par les confirmations de transfert.
class TransferConfirmationArgs {
  const TransferConfirmationArgs({
    required this.recipientName,
    required this.lines,
    required this.title,
    required this.introText,
    required this.confirmLabel,
    required this.sectionLabel,
    required this.intentOperation,
    required this.unconfirmedActionMessage,
    this.showQuantity = false,
    this.confirmIcon = Icons.send_rounded,
    required this.onConfirm,
  });

  /// Nom résolu du destinataire (retourné par le backend lors de la vérification).
  final String recipientName;

  /// Lignes de transfert sélectionnées.
  final List<TransferConfirmationLine> lines;
  final bool showQuantity;

  final String title;
  final String introText;
  final String confirmLabel;
  final IconData confirmIcon;
  final String sectionLabel;
  final String intentOperation;
  final String unconfirmedActionMessage;

  /// Callback appelé quand l'utilisateur confirme sans motif éditable.
  final Future<void> Function(String actionCode, SensitiveActionIntent intent)
  onConfirm;
}

class TransferConfirmationLine {
  const TransferConfirmationLine({
    required this.item,
    required this.quantity,
    required this.unitSize,
  });

  final TransferInventoryItem item;
  final int quantity;
  final int unitSize;

  int get totalFaces => quantity * unitSize;
  int get totalAmount => totalFaces * item.faceValue;
}

// -----------------------------------------------------------------------------

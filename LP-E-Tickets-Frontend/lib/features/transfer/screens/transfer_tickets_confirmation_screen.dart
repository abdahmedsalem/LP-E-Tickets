import 'package:flutter/material.dart';

import '../widgets/transfer_confirmation_content.dart';
import '../models/transfer_confirmation.dart';

/// Confirmation entry point dedicated to transferring tickets.
class TransferTicketsConfirmationScreen extends StatelessWidget {
  const TransferTicketsConfirmationScreen({super.key, required this.args});

  final TransferConfirmationArgs args;

  @override
  Widget build(BuildContext context) => TransferConfirmationContent(args: args);
}

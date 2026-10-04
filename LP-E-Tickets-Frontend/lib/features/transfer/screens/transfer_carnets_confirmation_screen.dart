import 'package:flutter/material.dart';

import '../widgets/transfer_confirmation_content.dart';
import '../models/transfer_confirmation.dart';

/// Confirmation entry point dedicated to transferring carnets.
class TransferCarnetsConfirmationScreen extends StatelessWidget {
  const TransferCarnetsConfirmationScreen({super.key, required this.args});

  final TransferConfirmationArgs args;

  @override
  Widget build(BuildContext context) => TransferConfirmationContent(args: args);
}

import 'package:flutter/material.dart';

import '../../shared/screens/qr_action_confirmation_screen.dart';

/// Confirmation entry point dedicated to generating QR codes.
class QrGenerationConfirmationScreen extends StatelessWidget {
  const QrGenerationConfirmationScreen({super.key, required this.args});

  final QrActionConfirmationArgs args;

  @override
  Widget build(BuildContext context) => QrActionConfirmationScreen(args: args);
}

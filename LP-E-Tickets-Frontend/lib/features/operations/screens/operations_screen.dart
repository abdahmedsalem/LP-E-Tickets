import 'package:flutter/material.dart';

import '../../../core/models/client_session.dart';
import '../../../domain/models/user_role.dart';
import '../../history/screens/transactions_screen.dart';
import '../../history/controllers/history_controller.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({
    super.key,
    required this.session,
    required this.role,
    required this.controller,
  });

  final ClientSession session;
  final UserRole role;
  final HistoryController controller;

  @override
  Widget build(BuildContext context) {
    return TransactionsScreen(
      session: session,
      role: role,
      controller: controller,
      mode: TransactionsScreenMode.wallet,
    );
  }
}

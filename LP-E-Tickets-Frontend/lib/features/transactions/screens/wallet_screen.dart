import 'package:flutter/material.dart';

import 'transactions_screen.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TransactionsScreen(mode: TransactionsScreenMode.wallet);
  }
}

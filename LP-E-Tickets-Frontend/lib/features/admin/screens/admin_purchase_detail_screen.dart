import 'package:flutter/material.dart';

import '../../purchases/screens/purchase_detail_screen.dart';

/// Détail admin d’un achat (`POST …/admin/purchases/detail`).
class AdminPurchaseDetailScreen extends StatelessWidget {
  const AdminPurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context) {
    return PurchaseDetailScreen(lotId: purchaseId, adminMode: true);
  }
}

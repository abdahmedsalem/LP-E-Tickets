import 'face_line.dart';
import 'wallet_breakdown_extras.dart';

class WalletSnapshot {
  const WalletSnapshot({
    required this.amount,
    required this.byFaceValue,
    required this.faceLines,
    required this.breakdownExtras,
  });

  final int amount;
  final Map<int, int> byFaceValue;
  final List<FaceLine> faceLines;
  final WalletBreakdownExtras? breakdownExtras;
}

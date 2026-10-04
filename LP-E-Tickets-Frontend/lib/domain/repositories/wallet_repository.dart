import '../models/portfolio/wallet_snapshot.dart';

abstract interface class WalletRepositoryContract {
  Future<WalletSnapshot> current({
    required String ownerId,
    required String companyId,
  });
}

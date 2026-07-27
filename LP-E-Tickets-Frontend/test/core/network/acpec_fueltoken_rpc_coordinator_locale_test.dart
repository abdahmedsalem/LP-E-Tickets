import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/core/network/acpec_fueltoken_rpc_coordinator.dart';

void main() {
  test(
    'RPC cache separates locales and invalidates every locale variant',
    () async {
      final coordinator = AcpecFueltokenRpcCoordinator(
        cacheTtl: const Duration(minutes: 1),
      );
      var calls = 0;

      Future<dynamic> load(String locale) => coordinator.execute(
        route: '/mobile/carnet-types',
        params: const {'active': true},
        cacheVariant: 'locale=$locale',
        request: () async => ++calls,
      );

      expect(await load('fr'), 1);
      expect(await load('fr'), 1);
      expect(await load('ar'), 2);
      expect(await load('ar'), 2);

      coordinator.invalidate('/mobile/carnet-types', const {'active': true});

      expect(await load('fr'), 3);
      expect(await load('ar'), 4);
    },
  );
}

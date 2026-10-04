import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';
import 'package:fueltoken_app/data/repositories/history_repository.dart';
import 'package:fueltoken_app/data/repositories/portfolio_repository.dart';
import 'package:fueltoken_app/features/history/controllers/history_controller.dart';
import 'package:fueltoken_app/features/portfolio/controllers/portfolio_controller.dart';
import 'package:fueltoken_app/domain/models/purchase/carnet_catalog_load_result.dart';

class FakeApi implements OdooFueltokenFacade {
  String? route;
  Map<String, dynamic>? params;
  Object? failure;
  Future<dynamic> response(String name, Map<String, dynamic>? p) async {
    route = name;
    params = p;
    if (failure != null) throw failure!;
    return {
      'ok': true,
      'data': {'items': [], 'has_more': false},
    };
  }

  @override
  Future<dynamic> transactions([Map<String, dynamic>? p]) =>
      response('client', p);
  @override
  Future<dynamic> stationTransactions([Map<String, dynamic>? p]) =>
      response('station', p);
  @override
  Future<dynamic> qrList([Map<String, dynamic>? p]) => response('qrs', p);
  @override
  Future<dynamic> faces([Map<String, dynamic>? p]) => response('faces', p);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class TestPortfolioRepository extends PortfolioRepository {
  TestPortfolioRepository({required super.api});
  @override
  Future<AcpecCarnetCatalogLoadResult> optionalCatalog({
    required String companyId,
    String? languageCode,
  }) async => const AcpecCarnetCatalogLoadResult(types: []);
}

void main() {
  test('tab screens have no API or repository access', () {
    for (final path in [
      'history/screens/transactions_screen.dart',
      'portfolio/screens/faces_detail_screen.dart',
      'portfolio/screens/qr_list_screen.dart',
    ]) {
      final source = File('lib/features/$path').readAsStringSync();
      for (final forbidden in [
        'OdooFueltokenFacade',
        'AcpecCarnetCatalogService.instance',
        'AcpecFueltokenRpcCoordinator',
        'data/repositories/',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: path);
      }
      expect(source, contains('_controller.'));
      expect(source, contains('_controller.dispose()'));
    }
    expect(
      File(
        'lib/features/operations/screens/operations_screen.dart',
      ).readAsStringSync(),
      contains('mode: TransactionsScreenMode.wallet'),
    );
  });
  for (final station in [true, false]) {
    test(
      'history preserves page parameters and routes for station=$station',
      () async {
        final api = FakeApi();
        final c = HistoryController(repository: HistoryRepository(api: api));
        final params = <String, dynamic>{
          'offset': 20,
          'limit': 10,
          'date_from': '2026-01-01',
        };
        final page = await c.page(
          params,
          station: station,
          userId: '1',
          userName: 'Client',
          limit: 10,
          offset: 20,
        );
        expect(api.route, station ? 'station' : 'client');
        expect(api.params, params);
        expect(page.items, isEmpty);
        expect(page.hasMore, false);
        expect(c.isRunning('page:20'), false);
        c.dispose();
      },
    );
  }
  test('portfolio retains QR filters and retrieves inventory', () async {
    final api = FakeApi();
    final c = PortfolioController(
      repository: TestPortfolioRepository(api: api),
    );
    expect(
      await c.qrs(
        {'state': 'blocked'},
        ownerId: '1',
        ownerName: 'Client',
        companyId: '1',
      ),
      isEmpty,
    );
    expect(api.route, 'qrs');
    expect(api.params, {
      'state': 'blocked',
      'limit': 100,
      'offset': 0,
      'include_pagination_meta': true,
    });
    expect(await c.faces(ownerId: '1', companyId: '1'), isEmpty);
    expect(api.route, 'faces');
    expect(api.params, isEmpty);
    c.dispose();
  });
  test('history propagates errors and clears loading state', () async {
    final error = StateError('offline');
    final api = FakeApi()..failure = error;
    final c = HistoryController(repository: HistoryRepository(api: api));
    await expectLater(
      c.page(
        {},
        station: false,
        userId: '1',
        userName: 'Client',
        limit: 10,
        offset: 0,
      ),
      throwsA(same(error)),
    );
    expect(c.errorFor('page:0'), same(error));
    expect(c.isRunning('page:0'), false);
    c.dispose();
  });
}

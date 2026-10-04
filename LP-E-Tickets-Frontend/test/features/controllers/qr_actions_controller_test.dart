import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';
import 'package:fueltoken_app/data/repositories/qr_actions_repository.dart';
import 'package:fueltoken_app/features/qr/shared/controllers/qr_actions_controller.dart';
import 'package:fueltoken_app/features/qr/separation/controllers/qr_separation_controller.dart';

class FakeApi implements OdooFueltokenFacade {
  final pending = Completer<dynamic>();
  final calls = <String>[];
  Map<String, dynamic>? payload;
  Future<dynamic> call(String method, Map<String, dynamic> p) {
    calls.add(method);
    payload = p;
    return pending.future;
  }

  @override
  Future<dynamic> qrSeparer(Map<String, dynamic> p) => call('separation', p);
  @override
  Future<dynamic> qrRetirer(Map<String, dynamic> p) => call('withdrawal', p);
  @override
  Future<dynamic> qrRevealCode(Map<String, dynamic> p) => call('reveal', p);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'dedicated separation controller preserves the protected RPC payload',
    () async {
      final api = FakeApi();
      final controller = QrSeparationController(
        repository: QrActionsRepository(api: api),
      );
      final params = <String, dynamic>{
        'public_code': 'QR1',
        'action_code': '1234',
        'idempotency_key': 'one-intent',
      };

      final pending = controller.separate(
        params,
        fallbackMessage: 'Refus',
        publicErrorMessage: 'Échec',
      );

      expect(controller.isRunning('separate'), isTrue);
      await expectLater(
        controller.separate(
          params,
          fallbackMessage: 'Refus',
          publicErrorMessage: 'Échec',
        ),
        throwsStateError,
      );
      expect(api.calls, ['separation']);
      expect(api.payload, params);

      api.pending.complete({
        'ok': true,
        'data': {'source': {}, 'new_qr': {}},
      });
      expect((await pending)['source'], isA<Map>());
      expect(controller.isRunning('separate'), isFalse);
      controller.dispose();
    },
  );

  test('QR screens use controller rather than API or repository', () {
    for (final path in [
      'detail/screens/qr_detail_screen.dart',
      'separation/screens/separer_qr_screen.dart',
      'retirer/screens/retirer_qr_screen.dart',
    ]) {
      final source = File('lib/features/qr/$path').readAsStringSync();
      for (final forbidden in [
        'OdooFueltokenFacade',
        'AcpecCarnetCatalogService',
        'AcpecFueltokenRpcCoordinator',
        'data/repositories/',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: path);
      }
      expect(source, contains('_controller.dispose()'));
      if (path.startsWith('separation/')) {
        expect(source, contains('QrSeparationController'));
        expect(
          source,
          contains("../controllers/qr_separation_controller.dart"),
        );
      }
    }
  });
  for (final operation in ['withdrawal', 'reveal']) {
    for (final success in [true, false]) {
      test(
        '$operation retains PIN/intent, prevents duplicate and propagates result: $success',
        () async {
          final api = FakeApi();
          final controller = QrActionsController(
            repository: QrActionsRepository(api: api),
          );
          final params = <String, dynamic>{
            'public_code': 'QR1',
            'action_code': '1234',
            'idempotency_key': 'one-intent',
          };
          Future<Map<String, dynamic>> send() {
            switch (operation) {
              case 'withdrawal':
                return controller.qrRetirer(
                  params,
                  fallbackMessage: 'Refus',
                  publicErrorMessage: 'Échec',
                );
              default:
                return controller.qrRevealCode(
                  params,
                  fallbackMessage: 'Refus',
                  publicErrorMessage: 'Échec',
                );
            }
          }

          final pending = send();
          expect(controller.isRunning('mutation'), true);
          await expectLater(send(), throwsStateError);
          expect(api.calls, [operation]);
          expect(api.payload, params);
          if (success) {
            api.pending.complete({
              'ok': true,
              'data': {'public_code': 'QR2'},
            });
            expect((await pending)['public_code'], 'QR2');
          } else {
            final check = expectLater(pending, throwsException);
            api.pending.complete({
              'ok': false,
              'error': {'code': 'INVALID_ACTION_CODE', 'message': 'Refus'},
            });
            await check;
            expect(controller.errorFor('mutation'), isNotNull);
          }
          expect(controller.isRunning('mutation'), false);
          controller.dispose();
        },
      );
    }
  }
}

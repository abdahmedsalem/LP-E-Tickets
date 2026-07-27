import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/core/utils/error_presenter.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';

void main() {
  group('Odoo JSON-RPC HTTP status mapping', () {
    test('2xx responses are not HTTP failures', () {
      for (final status in <int>[200, 201, 204, 299]) {
        expect(odooJsonRpcHttpFailure(status), isNull);
      }
    });

    test('401 keeps the existing authentication recovery contract', () {
      final error = odooJsonRpcHttpFailure(401);

      expect(error, isNotNull);
      expect(error!.code, 401);
      expect(error.message, 'AUTH_REQUIRED');
      expect(error.requiresReLogin, isTrue);
    });

    test('403 is forbidden without forcing logout or refresh', () {
      final error = odooJsonRpcHttpFailure(403)!;

      expect(error.code, 403);
      expect(error.requiresReLogin, isFalse);
      expect(error.requiresLogout, isFalse);
      expect(
        ErrorPresenter.message(error),
        'Vous n’êtes pas autorisé à effectuer cette action.',
      );
    });

    test('404 and 405 are classified before JSON-RPC parsing', () {
      final notFound = odooJsonRpcHttpFailure(404)!;
      final methodNotAllowed = odooJsonRpcHttpFailure(405)!;

      expect(notFound.code, 404);
      expect(notFound.message, 'Le service demandé est introuvable.');
      expect(notFound.toString(), isNot(contains('private')));
      expect(methodNotAllowed.code, 405);
      expect(
        methodNotAllowed.message,
        'Cette opération n’est pas autorisée par le serveur.',
      );
    });

    test('500 to 504 are presented as backend unavailable', () {
      for (final status in <int>[500, 502, 503, 504]) {
        final error = odooJsonRpcHttpFailure(status)!;

        expect(error.code, status);
        expect(ErrorPresenter.isBackendUnavailable(error), isTrue);
        expect(error.message, isNot(contains('traceback')));
        expect(error.message, isNot(contains('<html>')));
      }
    });

    test('known request status codes get safe local messages', () {
      final expected = <int, String>{
        400: 'La requête envoyée au serveur est invalide.',
        408: 'Serveur momentanément indisponible. Réessayez plus tard.',
        413: 'La requête envoyée est trop volumineuse.',
        415: 'Le format de la requête n’est pas accepté par le serveur.',
        422: 'La requête envoyée au serveur est invalide.',
        429: 'Trop de requêtes. Réessayez plus tard.',
      };

      for (final entry in expected.entries) {
        final error = odooJsonRpcHttpFailure(entry.key)!;
        expect(error.code, entry.key);
        expect(error.message, entry.value);
      }
    });

    test('unexpected HTTP status remains classified and safe', () {
      final error = odooJsonRpcHttpFailure(418)!;

      expect(error.code, 418);
      expect(error.message, 'Le serveur a refusé la requête (HTTP 418).');
      expect(error.toString(), isNot(contains('debug_reason')));
      expect(error.toString(), isNot(contains('private')));
    });
  });

  group('Dio transport mapping', () {
    test('badResponse delegates to the HTTP status classifier', () {
      final error = odooJsonRpcExceptionFromDio(
        DioException(
          requestOptions: RequestOptions(path: '/api/acpec/test'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/acpec/test'),
            statusCode: 503,
            data: '<html>private</html>',
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(error.code, 503);
      expect(ErrorPresenter.isBackendUnavailable(error), isTrue);
    });

    test('connection errors use the existing network message', () {
      final error = odooJsonRpcExceptionFromDio(
        DioException(
          requestOptions: RequestOptions(path: '/api/acpec/test'),
          type: DioExceptionType.connectionError,
          message: 'SocketException: failed host lookup private.example',
        ),
      );

      expect(error.code, isNull);
      expect(
        error.message,
        'Impossible de joindre le serveur. Vérifiez votre connexion.',
      );
      expect(error.toString(), isNot(contains('private.example')));
    });

    test('timeouts are classified as backend unavailable', () {
      for (final type in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final error = odooJsonRpcExceptionFromDio(
          DioException(
            requestOptions: RequestOptions(path: '/api/acpec/test'),
            type: type,
          ),
        );

        expect(ErrorPresenter.isBackendUnavailable(error), isTrue);
      }
    });

    test('unknown Dio errors do not expose their technical message', () {
      final error = odooJsonRpcExceptionFromDio(
        DioException(
          requestOptions: RequestOptions(path: '/api/acpec/test'),
          type: DioExceptionType.unknown,
          message: 'Traceback debug_reason private',
        ),
      );

      expect(error.message, 'Une erreur réseau est survenue. Réessayez.');
      expect(error.toString(), isNot(contains('Traceback')));
      expect(error.toString(), isNot(contains('debug_reason')));
    });
  });
}

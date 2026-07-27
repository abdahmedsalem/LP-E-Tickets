# -*- coding: utf-8 -*-
from types import SimpleNamespace
from unittest.mock import patch

from psycopg2 import errors as pg_errors

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import (
    AcpecMobileAuthApiCommon,
)
from odoo.addons.base.models import ir_http as base_ir_http_module
from odoo.addons.http_routing.models import (
    ir_http as http_routing_ir_http_module,
)
from odoo.addons.acpec_mobile_auth.models import (
    mobile_web_session_guard as guard_module,
)


class _FakeJsonRpcDispatcher:
    routing_type = 'jsonrpc'

    def __init__(self, request_id=43):
        self.request_id = request_id
        self.handled_exception = False

    def _response(self, result=None, error=None):
        response = {
            'jsonrpc': '2.0',
            'id': self.request_id,
        }
        if result is not None:
            response['result'] = result
        if error is not None:
            response['error'] = error
        return response

    def handle_error(self, exception):
        self.handled_exception = exception
        return {'odoo_fallback': type(exception).__name__}


class _FakeHttpDispatcher(_FakeJsonRpcDispatcher):
    routing_type = 'http'


@tagged('post_install', '-at_install')
class TestMobileApiFinalErrorBoundary(TransactionCase):

    def _make_request(
        self,
        *,
        path='/api/acpec/fueltoken/v1/station/qr/use',
        dispatcher=None,
        matched=True,
        operation='station_qr_use',
        params=None,
    ):
        return SimpleNamespace(
            httprequest=SimpleNamespace(path=path),
            dispatcher=dispatcher or _FakeJsonRpcDispatcher(),
            params=params or {'idempotency_key': 'test-key'},
            _acpec_mobile_api_route_matched=matched,
            _acpec_mobile_api_operation=operation,
        )

    def _endpoint(self, *, route_type='jsonrpc', name='station_qr_use'):
        def endpoint():
            return None

        endpoint.__name__ = name
        endpoint.routing = {'type': route_type}
        return endpoint

    def test_only_matched_acpec_jsonrpc_route_is_marked(self):
        fake_request = self._make_request(matched=False)
        endpoint = self._endpoint()

        with patch.object(guard_module, 'request', fake_request):
            result = self.env['ir.http']._acpec_mark_mobile_api_route(endpoint)

        self.assertTrue(result)
        self.assertTrue(fake_request._acpec_mobile_api_route_matched)
        self.assertEqual(
            fake_request._acpec_mobile_api_operation,
            'station_qr_use',
        )

    def test_route_marker_rejects_non_acpec_and_non_jsonrpc_routes(self):
        cases = (
            ('/web', self._endpoint()),
            (
                '/api/acpec/mobile_auth/v1/version-check',
                self._endpoint(route_type='http'),
            ),
        )

        for path, endpoint in cases:
            fake_request = self._make_request(
                path=path,
                matched=True,
                operation='stale_operation',
            )
            with patch.object(guard_module, 'request', fake_request):
                result = self.env['ir.http']._acpec_mark_mobile_api_route(
                    endpoint
                )

            self.assertFalse(result)
            self.assertFalse(fake_request._acpec_mobile_api_route_matched)
            self.assertFalse(fake_request._acpec_mobile_api_operation)

    def test_unknown_acpec_path_is_not_guessed_without_matched_route(self):
        fake_request = self._make_request(
            path='/api/acpec/unknown',
            matched=False,
        )
        dispatcher = fake_request.dispatcher
        exception = RuntimeError('unknown route')

        with (
            patch.object(guard_module, 'request', fake_request),
            patch.object(base_ir_http_module, 'request', fake_request),
            patch.object(
                http_routing_ir_http_module,
                'request',
                fake_request,
            ),
        ):
            response = self.env['ir.http']._handle_error(exception)

        self.assertEqual(response, {'odoo_fallback': 'RuntimeError'})
        self.assertIs(dispatcher.handled_exception, exception)

    def test_non_jsonrpc_route_keeps_odoo_error_handler(self):
        fake_request = self._make_request(
            dispatcher=_FakeHttpDispatcher(),
            matched=True,
        )
        dispatcher = fake_request.dispatcher
        exception = RuntimeError('http route failure')

        with (
            patch.object(guard_module, 'request', fake_request),
            patch.object(base_ir_http_module, 'request', fake_request),
            patch.object(
                http_routing_ir_http_module,
                'request',
                fake_request,
            ),
        ):
            response = self.env['ir.http']._handle_error(exception)

        self.assertEqual(response, {'odoo_fallback': 'RuntimeError'})
        self.assertIs(dispatcher.handled_exception, exception)

    def test_unhandled_runtime_error_uses_standard_acpec_payload(self):
        fake_request = self._make_request()
        exception = RuntimeError('unexpected failure')

        with (
            patch.object(guard_module, 'request', fake_request),
            patch.object(
                AcpecMobileAuthApiCommon,
                '_log_unhandled_mobile_api_exception',
                return_value='ERR-20260713-TEST',
            ) as log_unhandled,
        ):
            response = self.env['ir.http']._handle_error(exception)

        self.assertEqual(response['jsonrpc'], '2.0')
        self.assertEqual(response['id'], 43)
        self.assertFalse(response['result']['ok'])
        self.assertFalse(response['result']['success'])
        self.assertEqual(
            response['result']['error']['code'],
            'SERVER_ERROR',
        )
        self.assertEqual(
            response['result']['error']['reference'],
            'ERR-20260713-TEST',
        )
        log_unhandled.assert_called_once_with(
            exception,
            params={'idempotency_key': 'test-key'},
            operation='station_qr_use',
            endpoint='/api/acpec/fueltoken/v1/station/qr/use',
        )

    def test_exhausted_retryable_error_is_converted_not_raised_again(self):
        fake_request = self._make_request()
        exception = pg_errors.SerializationFailure(
            'could not serialize access due to concurrent update'
        )

        with (
            patch.object(guard_module, 'request', fake_request),
            patch.object(
                AcpecMobileAuthApiCommon,
                '_log_unhandled_mobile_api_exception',
                return_value='ERR-20260713-RETRY',
            ) as log_unhandled,
        ):
            response = self.env['ir.http']._handle_error(exception)

        self.assertEqual(
            response['result']['error']['code'],
            'SERVER_ERROR',
        )
        self.assertEqual(
            response['result']['error']['reference'],
            'ERR-20260713-RETRY',
        )
        log_unhandled.assert_called_once()

    def test_boundary_failure_falls_back_to_odoo_handler(self):
        fake_request = self._make_request()
        dispatcher = fake_request.dispatcher
        exception = RuntimeError('original failure')

        with (
            patch.object(guard_module, 'request', fake_request),
            patch.object(base_ir_http_module, 'request', fake_request),
            patch.object(
                http_routing_ir_http_module,
                'request',
                fake_request,
            ),
            patch.object(
                self.env['ir.http'].__class__,
                '_acpec_handle_final_mobile_api_error',
                side_effect=RuntimeError('boundary failure'),
            ),
            patch.object(guard_module._logger, 'exception') as log_failure,
        ):
            response = self.env['ir.http']._handle_error(exception)

        self.assertEqual(response, {'odoo_fallback': 'RuntimeError'})
        self.assertIs(dispatcher.handled_exception, exception)
        log_failure.assert_called_once()

import ast
import inspect
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase

from odoo.addons.acpec_mobile_auth.controllers import api_common


class _RequestWithoutHttpContext:

    @property
    def httprequest(self):
        raise RuntimeError('No HTTP request bound')


class TestRequestIpContractM23C8A(TransactionCase):

    def test_m23c8a_request_ip_has_single_class_definition(self):
        source_path = Path(
            inspect.getsourcefile(
                api_common.AcpecMobileAuthApiCommon
            )
        )
        tree = ast.parse(
            source_path.read_text(encoding='utf-8'),
            filename=str(source_path),
        )

        controller_classes = [
            node
            for node in tree.body
            if (
                isinstance(node, ast.ClassDef)
                and node.name == 'AcpecMobileAuthApiCommon'
            )
        ]
        self.assertEqual(len(controller_classes), 1)

        definitions = [
            node
            for node in controller_classes[0].body
            if (
                isinstance(node, ast.FunctionDef)
                and node.name == '_request_ip'
            )
        ]
        self.assertEqual(
            len(definitions),
            1,
            'AcpecMobileAuthApiCommon doit définir _request_ip une seule fois.',
        )

    def test_m23c8a_test_request_ip_override_has_priority(self):
        controller = api_common.AcpecMobileAuthApiCommon()
        controller._test_request_ip = '10.43.23.81'

        with patch.object(
            api_common,
            'request',
            _RequestWithoutHttpContext(),
        ):
            self.assertEqual(
                controller._request_ip(),
                '10.43.23.81',
            )

    def test_m23c8a_request_ip_returns_empty_without_http_context(self):
        controller = api_common.AcpecMobileAuthApiCommon()

        with patch.object(
            api_common,
            'request',
            _RequestWithoutHttpContext(),
        ):
            self.assertEqual(controller._request_ip(), '')

    def test_m23c8a_request_ip_strips_http_remote_address(self):
        controller = api_common.AcpecMobileAuthApiCommon()
        fake_request = SimpleNamespace(
            httprequest=SimpleNamespace(
                remote_addr='  203.0.113.43  ',
            ),
        )

        with patch.object(api_common, 'request', fake_request):
            self.assertEqual(
                controller._request_ip(),
                '203.0.113.43',
            )

# -*- coding: utf-8 -*-

import inspect

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth_otp.controllers.api_otp import (
    AcpecMobileAuthOtpApi,
)


@tagged('post_install', '-at_install')
class TestOtpConcurrencyRetryBoundary(TransactionCase):

    def test_request_otp_explicitly_disables_retry_around_sms_effect(self):
        source = inspect.getsource(AcpecMobileAuthOtpApi.request_otp)

        self.assertIn(
            'allow_odoo_concurrency_retry=False',
            source,
        )

# -*- coding: utf-8 -*-
import base64

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


def _acpec_test_mobile_phone(label):
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value


@tagged("post_install", "-at_install")
class TestPurchasePaymentProofGuard(TransactionCase):

    def _group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        )
        return [
            self.env.ref(xmlid).id
            for xmlid in xmlids
            if self.env.ref(xmlid, raise_if_not_found=False)
        ]

    def _create_mobile_user(self, login='purchase-proof-guard-43k1b@example.com'):
        phone = _acpec_test_mobile_phone(login)
        user_model = self.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
        )
        user = user_model.create({
            'name': login,
            'login': phone,
            'mobile_phone': phone,
            'email': login,
            'active': True,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })
        user.set_mobile_pin('1234')
        return user

    def _trusted_session(self, login='purchase-proof-guard-43k1b@example.com'):
        user = self._create_mobile_user(login)
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': login.replace('@', '-'),
            'platform': 'android',
        })
        session = token_data['session']
        session.action_trust_device()
        return user, session

    def _controller_for_session(self, session):
        controller = AcpecFuelTokenMobileApi()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _payload(self, proof_filename, proof_data, key='purchase-proof-guard-key-43k1b'):
        return {
            'lines': [{'carnet_type_id': 999999, 'carnet_qty': 1}],
            'proof_filename': proof_filename,
            'proof_data': proof_data,
            'payment_reference': 'PAY-PROOF-GUARD-43K1B',
            # Mauvais action_code volontaire : le guard preuve doit refuser avant
            # la validation PIN et ne doit donc pas incrémenter le compteur.
            'action_code': '9999',
            'idempotency_key': key,
        }

    def _assert_payment_proof_invalid(self, response):
        self.assertIsInstance(response, dict)
        self.assertFalse(response.get('success'))
        self.assertFalse(response.get('ok'))
        error = response.get('error') or {}
        self.assertEqual(error.get('code'), 'PAYMENT_PROOF_INVALID')
        self.assertIn('JPG', error.get('message') or '')
        self.assertIn('PNG', error.get('message') or '')
        self.assertIn('PDF', error.get('message') or '')

    def _assert_pin_not_consumed(self, user, key):
        user.invalidate_recordset(['acpec_mobile_pin_failed_count'])
        self.assertEqual(user.acpec_mobile_pin_failed_count, 0)

        audit = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', key),
            ('code', '=', 'INVALID_ACTION_CODE'),
        ])
        self.assertFalse(audit)

    def test_purchase_proof_too_large_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-too-large-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-too-large-key-43k1b'

        too_large = 'A' * (
            controller._purchase_payment_proof_max_base64_chars()
            + controller.PURCHASE_PAYMENT_PROOF_BASE64_MARGIN_CHARS
            + 1
        )

        response = controller.create_purchase(**self._payload(
            'preuve.pdf',
            too_large,
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_extension_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-extension-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-extension-key-43k1b'

        response = controller.create_purchase(**self._payload(
            'preuve.exe',
            base64.b64encode(b'%PDF-1.4\nnot allowed extension\n').decode('ascii'),
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_invalid_base64_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-base64-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-base64-key-43k1b'

        response = controller.create_purchase(**self._payload(
            'preuve.pdf',
            'not-valid-base64@@@',
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_data_url_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-data-url-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-data-url-key-43k1b'

        response = controller.create_purchase(**self._payload(
            'preuve.pdf',
            'data:application/pdf;base64,' + base64.b64encode(b'%PDF-1.4\n').decode('ascii'),
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_missing_filename_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-missing-filename-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-missing-filename-key-43k1b'

        response = controller.create_purchase(**self._payload(
            False,
            base64.b64encode(b'%PDF-1.4\nvalid pdf bytes\n').decode('ascii'),
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_signature_mismatch_is_rejected_before_action_code(self):
        user, session = self._trusted_session('purchase-proof-signature-43k1b@example.com')
        controller = self._controller_for_session(session)
        key = 'purchase-proof-signature-key-43k1b'

        response = controller.create_purchase(**self._payload(
            'preuve.jpg',
            base64.b64encode(b'%PDF-1.4\nthis is a pdf not jpeg\n').decode('ascii'),
            key=key,
        ))

        self._assert_payment_proof_invalid(response)
        self._assert_pin_not_consumed(user, key)

    def test_purchase_proof_minimal_allowed_signatures_pass_guard(self):
        controller = AcpecFuelTokenMobileApi()
        samples = (
            ('preuve.pdf', b'%PDF-1.4\nminimal pdf\n'),
            ('preuve.jpg', bytes.fromhex('ffd8ffe0') + b'minimal jpeg'),
            ('preuve.jpeg', bytes.fromhex('ffd8ffe1') + b'minimal jpeg'),
            ('preuve.png', bytes.fromhex('89504e470d0a1a0a') + b'minimal png'),
        )

        for filename, raw in samples:
            clean_name, clean_data, error = controller._validate_purchase_payment_proof(
                filename,
                base64.b64encode(raw).decode('ascii'),
            )
            self.assertFalse(error)
            self.assertEqual(clean_name, filename)
            self.assertTrue(clean_data)

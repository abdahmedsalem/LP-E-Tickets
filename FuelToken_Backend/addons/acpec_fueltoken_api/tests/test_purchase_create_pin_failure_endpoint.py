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
class TestPurchaseCreatePinFailureEndpoint(TransactionCase):

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

    def _create_mobile_user(self, login='purchase-wrong-pin-endpoint-43k1@example.com'):
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
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids())],
        })
        user.set_mobile_pin('1234')
        return user

    def _trusted_session(self):
        user = self._create_mobile_user()
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': 'purchase-wrong-pin-endpoint-device-43k1',
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

    def test_purchase_create_wrong_pin_persists_counter_and_audit(self):
        user, session = self._trusted_session()
        controller = self._controller_for_session(session)
        key = 'purchase-create-wrong-pin-key-43k1'

        # Endpoint-level call: create_purchase catches the sensitive-action
        # refusal and converts it to a JSON response. The wrong PIN must still
        # be committed as security state: failed_count=1 + INVALID_ACTION_CODE audit.
        response = controller.create_purchase(
            lines=[{'carnet_type_id': 999999, 'carnet_qty': 1}],
            proof_filename='tiny-proof.pdf',
            proof_data=base64.b64encode(b'%PDF-1.4\\ntiny proof\\n').decode('ascii'),
            payment_reference='PIN-FAIL-43K1',
            action_code='9999',
            idempotency_key=key,
        )

        self.assertIsInstance(response, dict)
        self.assertFalse(response.get('success'))
        self.assertFalse(response.get('ok'))
        self.assertIn('error', response)
        self.assertEqual(response['error'].get('code'), 'ACTION_REFUSED')
        self.assertTrue(response['error'].get('reference'))

        # Le code interne précis doit rester dans l'audit sécurité, pas dans le
        # contrat public mobile.
        self.assertNotIn('9999', str(response))

        self.env.flush_all()
        self.env.invalidate_all()

        user = self.env['res.users'].sudo().browse(user.id)
        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 1)

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', key),
            ('code', '=', 'INVALID_ACTION_CODE'),
        ], limit=1)

        self.assertTrue(log)
        self.assertEqual(log.event_type, 'invalid_action_code')
        self.assertEqual(log.operation, 'purchase_create')
        self.assertTrue(log.action_code_present)
        self.assertEqual(log.failed_count_before, 0)
        self.assertEqual(log.failed_count_after, 1)

        exported = str(log.read()[0])
        self.assertNotIn('9999', exported)

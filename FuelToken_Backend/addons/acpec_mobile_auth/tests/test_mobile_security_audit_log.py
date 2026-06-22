# -*- coding: utf-8 -*-

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged("post_install", "-at_install")
class TestMobileSecurityAuditLog(TransactionCase):

    def _existing_partner(self):
        partner = self.env['res.partner'].sudo().search([], limit=1)
        self.assertTrue(partner, "Aucun partenaire existant disponible pour le test.")
        return partner

    def _create_mobile_user(self, login):
        partner = self._existing_partner()
        user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': login,
            'login': login,
            'email': login,
            'partner_id': partner.id,
            'mobile_only': True,
            'mobile_state': 'approved',
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [
                self.env.ref('base.group_portal').id,
                self.env.ref('acpec_mobile_auth.group_mobile_auth_user').id,
            ])],
        })
        user.set_mobile_pin('1234')
        return user

    def _session_for_user(self, user, trusted=True, device_uid='audit-device-32a'):
        token_data = self.env['acpec.mobile.session'].sudo().create_for_user(user, {
            'device_uid': device_uid,
            'device_name': 'Device test audit',
            'platform': 'test',
            'user_agent': 'odoo-test',
        })
        session = token_data['session'].sudo()

        if trusted:
            session.write({
                'device_trust_state': 'trusted',
                'device_trusted_at': fields.Datetime.now(),
                'device_blocked_at': False,
            })
        else:
            session.write({
                'device_trust_state': 'pending_trust',
                'device_trusted_at': False,
                'device_blocked_at': False,
            })

        return session

    def _controller_for_session(self, session):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._get_mobile_session = lambda required=True: session
        return controller

    def _expect_access_error(self, controller, params, purpose):
        try:
            controller._require_sensitive_action_pin(params, purpose=purpose)
        except AccessError as exc:
            self.env.flush_all()
            self.env.invalidate_all()
            return exc
        self.fail('AccessError attendu.')

    def test_wrong_action_code_creates_audit_without_raw_pin(self):
        user = self._create_mobile_user('audit-wrong-pin-32a@example.com')
        session = self._session_for_user(user, trusted=True)
        controller = self._controller_for_session(session)

        self._expect_access_error(controller, {
            'action_code': '9999',
            'idempotency_key': 'audit-wrong-pin-key-32a',
        }, purpose='carnet_transfer')

        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 1)

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', 'audit-wrong-pin-key-32a'),
            ('code', '=', 'INVALID_ACTION_CODE'),
        ], limit=1)

        self.assertTrue(log)
        self.assertEqual(log.event_type, 'invalid_action_code')
        self.assertEqual(log.operation, 'carnet_transfer')
        self.assertTrue(log.action_code_present)
        self.assertTrue(log.action_code_format_valid)
        self.assertEqual(log.failed_count_before, 0)
        self.assertEqual(log.failed_count_after, 1)

        exported = str(log.read()[0])
        self.assertNotIn('9999', exported)

    def test_pending_device_creates_audit_without_incrementing_pin_counter(self):
        user = self._create_mobile_user('audit-pending-device-32a@example.com')
        session = self._session_for_user(
            user,
            trusted=False,
            device_uid='audit-pending-device-32a',
        )
        controller = self._controller_for_session(session)

        self._expect_access_error(controller, {
            'action_code': '9999',
            'idempotency_key': 'audit-pending-device-key-32a',
        }, purpose='carnet_transfer')

        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 0)

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', 'audit-pending-device-key-32a'),
            ('code', '=', 'DEVICE_PENDING_TRUST'),
        ], limit=1)

        self.assertTrue(log)
        self.assertEqual(log.event_type, 'device_pending_trust')
        self.assertEqual(log.device_trust_state, 'pending_trust')
        self.assertTrue(log.blocked)
        self.assertFalse(log.success)

    def test_valid_action_code_creates_allowed_audit_and_resets_counter(self):
        user = self._create_mobile_user('audit-valid-pin-32a@example.com')
        session = self._session_for_user(
            user,
            trusted=True,
            device_uid='audit-valid-device-32a',
        )
        controller = self._controller_for_session(session)

        self._expect_access_error(controller, {
            'action_code': '9999',
            'idempotency_key': 'audit-valid-before-wrong-key-32a',
        }, purpose='carnet_transfer')

        user.invalidate_recordset(['mobile_pin_failed_count'])
        self.assertEqual(user.mobile_pin_failed_count, 1)

        allowed_user = controller._require_sensitive_action_pin({
            'action_code': '1234',
            'idempotency_key': 'audit-valid-pin-key-32a',
        }, purpose='carnet_transfer')

        self.env.flush_all()
        self.env.invalidate_all()

        self.assertEqual(allowed_user, user)

        user.invalidate_recordset([
            'mobile_pin_failed_count',
            'mobile_pin_locked_until',
        ])
        self.assertEqual(user.mobile_pin_failed_count, 0)
        self.assertFalse(user.mobile_pin_locked_until)

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', 'audit-valid-pin-key-32a'),
            ('code', '=', 'ACTION_CODE_VALID'),
        ], limit=1)

        self.assertTrue(log)
        self.assertEqual(log.event_type, 'sensitive_action_allowed')
        self.assertEqual(log.operation, 'carnet_transfer')
        self.assertTrue(log.success)
        self.assertFalse(log.blocked)
        self.assertFalse(log.public_message)
        self.assertEqual(log.failed_count_before, 1)
        self.assertEqual(log.failed_count_after, 0)

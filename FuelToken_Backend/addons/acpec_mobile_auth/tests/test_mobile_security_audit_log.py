# -*- coding: utf-8 -*-

from odoo import api, fields, SUPERUSER_ID
from odoo.exceptions import AccessError, ValidationError
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

    def test_sensitive_action_transaction_logs_allowed_after_success(self):
        user = self._create_mobile_user('audit-transaction-success-43d@example.com')
        session = self._session_for_user(
            user,
            trusted=True,
            device_uid='audit-transaction-success-43d',
        )
        controller = self._controller_for_session(session)

        with controller._sensitive_action_transaction({
            'action_code': '1234',
            'idempotency_key': 'audit-transaction-success-key-43d',
        }, purpose='carnet_transfer') as allowed_user:
            self.assertEqual(allowed_user, user)

        self.env.flush_all()
        self.env.invalidate_all()

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', 'audit-transaction-success-key-43d'),
            ('code', '=', 'ACTION_CODE_VALID'),
        ], limit=1)
        self.assertTrue(log)
        self.assertEqual(log.event_type, 'sensitive_action_allowed')
        self.assertTrue(log.success)
        self.assertFalse(log.blocked)

    def test_authorized_business_failure_does_not_create_allowed_audit(self):
        user = self._create_mobile_user('audit-business-failure-43d@example.com')
        session = self._session_for_user(
            user,
            trusted=True,
            device_uid='audit-business-failure-43d',
        )
        controller = self._controller_for_session(session)

        with self.assertRaises(ValidationError):
            with controller._sensitive_action_transaction({
                'action_code': '1234',
                'idempotency_key': 'audit-business-failure-key-43d',
            }, purpose='carnet_transfer'):
                raise ValidationError('business failure after authorization')

        self.env.flush_all()
        self.env.invalidate_all()

        log = self.env['acpec.mobile.security.audit.log'].sudo().search([
            ('idempotency_key', '=', 'audit-business-failure-key-43d'),
            ('code', '=', 'ACTION_CODE_VALID'),
        ], limit=1)
        self.assertFalse(log)

    def test_allowed_audit_failure_rolls_back_business_action(self):
        user = self._create_mobile_user('audit-fail-rollback-43d@example.com')
        session = self._session_for_user(
            user,
            trusted=True,
            device_uid='audit-fail-rollback-43d',
        )
        controller = self._controller_for_session(session)
        marker_ids = []

        def _fail_allowed_audit(vals):
            raise ValidationError('forced audit failure')

        controller._audit_in_transaction = _fail_allowed_audit

        with self.assertRaises(ValidationError):
            with controller._sensitive_action_transaction({
                'action_code': '1234',
                'idempotency_key': 'audit-fail-rollback-key-43d',
            }, purpose='carnet_transfer'):
                marker = self.env['res.partner'].sudo().create({
                    'name': 'Patch43D marker must rollback',
                })
                marker_ids.append(marker.id)

        self.env.flush_all()
        self.env.invalidate_all()

        self.assertTrue(marker_ids)
        self.assertFalse(self.env['res.partner'].sudo().browse(marker_ids[0]).exists())

    def test_security_denial_uses_committed_audit_helper(self):
        user = self._create_mobile_user('audit-denial-committed-43d@example.com')
        session = self._session_for_user(
            user,
            trusted=True,
            device_uid='audit-denial-committed-43d',
        )
        controller = self._controller_for_session(session)
        captured = []

        def _capture_committed(vals):
            captured.append(dict(vals or {}))
            controller._audit_in_transaction(vals)

        controller._audit_committed = _capture_committed

        self._expect_access_error(controller, {
            'idempotency_key': 'audit-denial-committed-key-43d',
        }, purpose='carnet_transfer')

        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0]['code'], 'MISSING_ACTION_CODE')
        self.assertFalse(captured[0]['success'])
        self.assertTrue(captured[0]['blocked'])

    def test_committed_refusal_audit_survives_caller_savepoint_rollback(self):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._force_independent_audit_cursor = True
        key = 'audit-independent-cursor-survives-rollback-43d'

        vals = {
            'event_type': 'missing_action_code',
            'severity': 'warning',
            'code': 'MISSING_ACTION_CODE',
            'operation': 'carnet_transfer',
            'idempotency_key': key,
            'success': False,
            'blocked': True,
            'action_code_present': False,
            'action_code_format_valid': False,
        }

        with self.assertRaises(ValidationError):
            with self.env.cr.savepoint():
                controller._audit_committed(vals)
                raise ValidationError('force rollback of caller savepoint')

        with self.env.registry.cursor() as cr:
            check_env = api.Environment(cr, SUPERUSER_ID, dict(self.env.context))
            log = check_env['acpec.mobile.security.audit.log'].sudo().search([
                ('idempotency_key', '=', key),
                ('code', '=', 'MISSING_ACTION_CODE'),
            ], limit=1)
            self.assertTrue(log)
            self.assertEqual(log.event_type, 'missing_action_code')
            self.assertFalse(log.success)
            self.assertTrue(log.blocked)

        with self.env.registry.cursor() as cr:
            cr.execute(
                "DELETE FROM acpec_mobile_security_audit_log WHERE idempotency_key = %s",
                [key],
            )

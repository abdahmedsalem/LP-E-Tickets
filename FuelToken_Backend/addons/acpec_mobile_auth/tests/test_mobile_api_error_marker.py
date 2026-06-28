# -*- coding: utf-8 -*-

import uuid

from dateutil.relativedelta import relativedelta

from odoo import api, fields, SUPERUSER_ID
from odoo.exceptions import AccessError, ValidationError
from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


@tagged('post_install', '-at_install')
class TestMobileApiErrorMarker(TransactionCase):

    def _controller(self, path='/api/acpec/test/server-error'):
        controller = AcpecMobileAuthApiCommon()
        controller._test_env = self.env
        controller._test_request_path = path
        controller._test_request_ip = '10.0.0.9'
        controller._test_user_agent = 'odoo-test-mobile-api-error-marker'
        return controller

    def _raise_and_handle(self, controller, message, operation='test_server_error', params=None):
        try:
            raise RuntimeError(message)
        except Exception as exc:
            return controller._handle_exception_response(
                exc,
                params=params or {},
                operation=operation,
            )

    def test_unexpected_exception_returns_server_error_reference_and_marker(self):
        controller = self._controller('/api/acpec/test/server-error/payload')
        response = self._raise_and_handle(
            controller,
            'boom action_code=1234',
            params={'action_code': '1234'},
        )

        self.assertFalse(response['ok'])
        self.assertFalse(response['success'])
        self.assertEqual(response['error']['code'], 'SERVER_ERROR')
        self.assertEqual(
            response['error']['message'],
            'Une erreur technique est survenue. Veuillez contacter le support.',
        )
        reference = response['error']['reference']
        self.assertTrue(reference.startswith('ERR-'))
        self.assertNotIn('Traceback', repr(response))
        self.assertNotIn('1234', repr(response))

        marker = self.env['acpec.mobile.api.error.marker'].sudo().search([
            ('last_seen_reference', '=', reference),
        ], limit=1)
        self.assertTrue(marker)
        self.assertEqual(marker.code, 'SERVER_ERROR')
        self.assertEqual(marker.exception_type, 'RuntimeError')
        self.assertEqual(marker.occurrence_count, 1)
        self.assertNotIn('1234', marker.exception_summary or '')
        self.assertIn('***REDACTED***', marker.exception_summary or '')

    def test_error_marker_aggregates_repeated_exception(self):
        controller = self._controller('/api/acpec/test/server-error/aggregate')
        response1 = self._raise_and_handle(controller, 'same aggregate failure')
        response2 = self._raise_and_handle(controller, 'same aggregate failure')

        marker = self.env['acpec.mobile.api.error.marker'].sudo().search([
            ('last_seen_reference', '=', response2['error']['reference']),
        ], limit=1)
        self.assertTrue(marker)
        self.assertEqual(marker.occurrence_count, 2)
        self.assertEqual(marker.first_seen_reference, response1['error']['reference'])
        self.assertEqual(marker.last_seen_reference, response2['error']['reference'])

        markers = self.env['acpec.mobile.api.error.marker'].sudo().search([
            ('fingerprint', '=', marker.fingerprint),
        ])
        self.assertEqual(len(markers), 1)

    def test_error_marker_survives_rollback_with_independent_cursor(self):
        unique = uuid.uuid4().hex
        controller = self._controller('/api/acpec/test/server-error/rollback/%s' % unique)
        controller._force_independent_error_marker_cursor = True
        reference = False
        try:
            with self.env.cr.savepoint():
                response = self._raise_and_handle(
                    controller,
                    'rollback surviving marker %s' % unique,
                )
                reference = response['error']['reference']
                raise ValidationError('rollback caller transaction')
        except ValidationError:
            pass

        with self.env.registry.cursor() as cr:
            committed_env = api.Environment(cr, SUPERUSER_ID, dict(self.env.context))
            marker = committed_env['acpec.mobile.api.error.marker'].sudo().search([
                ('last_seen_reference', '=', reference),
            ], limit=1)
            self.assertTrue(marker)
            self.assertEqual(marker.occurrence_count, 1)

    def test_redact_text_for_log_masks_common_secret_shapes(self):
        controller = self._controller('/api/acpec/test/server-error/redaction')
        message = (
            'Authorization: Bearer AUTH_SECRET '
            'action_code=1234 '
            '"otp": "999999" '
            "'qr_numeric_code': '654321' "
            'public_code=PUBSECRET '
            'request_hash=HASHSECRET'
        )
        redacted = controller._redact_text_for_log(message)

        for secret in ('AUTH_SECRET', '1234', '999999', '654321', 'PUBSECRET', 'HASHSECRET'):
            self.assertNotIn(secret, redacted)
        self.assertIn('***REDACTED***', redacted)

    def test_error_marker_access_is_restricted_to_security_auditor(self):
        marker = self.env['acpec.mobile.api.error.marker'].sudo().log_marker(
            name='ERR-TEST-ACL-000001',
            fingerprint='acl-test-fingerprint-000001',
            endpoint='/api/acpec/test/server-error/acl',
            exception_type='RuntimeError',
            exception_summary='acl test',
        )
        group_user = self.env.ref('base.group_user')
        group_auditor = self.env.ref('acpec_mobile_auth.group_mobile_security_auditor')
        regular = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Utilisateur sans audit API mobile',
            'login': 'mobile.api.marker.regular@example.com',
            'email': 'mobile.api.marker.regular@example.com',
            'group_ids': [(6, 0, [group_user.id])],
        })
        auditor = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Auditeur incidents API mobile',
            'login': 'mobile.api.marker.auditor@example.com',
            'email': 'mobile.api.marker.auditor@example.com',
            'group_ids': [(6, 0, [group_user.id, group_auditor.id])],
        })

        with self.assertRaises(AccessError):
            marker.with_user(regular).read(['name'])

        data = marker.with_user(auditor).read(['name', 'state'])[0]
        self.assertEqual(data['name'], 'ERR-TEST-ACL-000001')
        marker.with_user(auditor).write({
            'state': 'reviewed',
            'resolution_note': 'Vu par le support',
        })
        marker.invalidate_recordset(['state', 'resolution_note', 'reviewed_by_id'])
        self.assertEqual(marker.state, 'reviewed')
        self.assertEqual(marker.reviewed_by_id, auditor)

    def test_error_marker_purge_removes_old_markers_only(self):
        Marker = self.env['acpec.mobile.api.error.marker'].sudo()
        old_date = fields.Datetime.now() - relativedelta(days=400)
        recent_date = fields.Datetime.now()
        old = Marker.create({
            'name': 'ERR-TEST-PURGE-OLD',
            'fingerprint': 'purge-old-fingerprint',
            'code': 'SERVER_ERROR',
            'exception_type': 'RuntimeError',
            'exception_summary': 'old marker',
            'first_seen_reference': 'ERR-TEST-PURGE-OLD',
            'last_seen_reference': 'ERR-TEST-PURGE-OLD',
            'first_seen_date': old_date,
            'last_seen_date': old_date,
            'occurrence_count': 1,
            'state': 'resolved',
        })
        recent = Marker.create({
            'name': 'ERR-TEST-PURGE-RECENT',
            'fingerprint': 'purge-recent-fingerprint',
            'code': 'SERVER_ERROR',
            'exception_type': 'RuntimeError',
            'exception_summary': 'recent marker',
            'first_seen_reference': 'ERR-TEST-PURGE-RECENT',
            'last_seen_reference': 'ERR-TEST-PURGE-RECENT',
            'first_seen_date': recent_date,
            'last_seen_date': recent_date,
            'occurrence_count': 1,
            'state': 'resolved',
        })

        removed = Marker._cron_purge_old_markers()
        self.assertGreaterEqual(removed, 1)
        self.assertFalse(old.exists())
        self.assertTrue(recent.exists())

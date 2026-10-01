from datetime import timedelta
from odoo import fields

from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestDeletionRequests(TransactionCase):
    def setUp(self):
        super().setUp()
        self.model = self.env['acpec.mobile.account.deletion']
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.processing_days', '7')

    def test_repeated_submission_keeps_receipt_and_deadline(self):
        first = self.model._request_for_user(self.env.user)
        again = self.model._request_for_user(self.env.user)
        self.assertEqual(first.id, again.id)
        self.assertEqual(first._payload(), again._payload())
        self.assertEqual(first.state, 'pending')

    def test_invalid_policy_is_rejected(self):
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.processing_days', 'invalid')
        with self.assertRaises(ValidationError):
            self.model._processing_days()

    def test_portal_cannot_create_or_change_requests_directly(self):
        portal = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Deletion test portal', 'login': 'deletion-test-portal',
            'group_ids': [(6, 0, [self.env.ref('base.group_portal').id])],
        })
        record = self.model._request_for_user(portal)
        with self.assertRaises(AccessError):
            record.with_user(portal).write({'state': 'completed'})
        with self.assertRaises(AccessError):
            record.with_user(portal).action_start()
        with self.assertRaises(AccessError):
            self.model.with_user(portal).create({'user_id': portal.id})

    def test_completion_requires_processing_and_notification_evidence(self):
        manager = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Deletion manager', 'login': 'deletion-test-manager',
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [self.env.ref('base.group_user').id,
                self.env.ref('acpec_mobile_auth.group_mobile_auth_admin').id])],
        })
        requester = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Deletion requester', 'login': 'deletion-requester-complete',
            'group_ids': [(6, 0, [self.env.ref('base.group_portal').id])],
        })
        record = self.model._request_for_user(requester).with_user(manager)
        with self.assertRaises(ValidationError):
            record.action_complete()
        record.action_start()
        with self.assertRaises(ValidationError):
            record.action_complete()
        record.write({'processing_notes': 'Traitement effectué selon procédure',
                      'notification_reference': 'SMS-test'})
        with self.assertRaises(ValidationError):
            record.action_complete()
        self.assertEqual(record.state, 'in_progress')
        requester.write({'active': False})
        with self.assertRaises(ValidationError):
            record.action_complete()
        record.write({'erasure_evidence': 'Rapport de suppression de test',
                      'retention_details': 'Justification et durée documentées dans la procédure de test'})
        with self.assertRaises(ValidationError):
            record.action_complete()
        record.write({'settlement_notes': 'Aucun ticket ni solde dans cette fixture',
                      'notification_channel': 'email',
                      'notification_sent_at': fields.Datetime.now()})
        record.action_complete()
        self.assertEqual(record.state, 'completed')
        self.assertEqual(record.completed_by, manager)
        self.assertEqual(record.assigned_to, manager)
        with self.assertRaises(AccessError):
            record.write({'erasure_evidence': 'Modification après clôture'})

    def test_default_processing_days_is_seven(self):
        self.env['ir.config_parameter'].sudo().search([
            ('key', '=', 'acpec_mobile_account_deletion.processing_days')
        ]).unlink()
        days = self.model._processing_days()
        self.assertEqual(days, 7)

    def test_preparation_revokes_without_claiming_deletion(self):
        manager = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Deletion Manager Auto', 'login': 'deletion-manager-auto',
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [self.env.ref('base.group_user').id,
                self.env.ref('acpec_mobile_auth.group_mobile_auth_admin').id])],
        })
        requester = self.env['res.users'].with_context(
            no_reset_password=True, acpec_mobile_allow_password_write=True
        ).create({
            'name': 'Deletion Requester Auto', 'login': '27999999',
            'mobile_phone': '27999999', 'acpec_mobile_phone': '27999999',
            'email': 'client-deletion@test.local',
            'acpec_mobile_only': True, 'acpec_mobile_state': 'approved',
            'group_ids': [(6, 0, [self.env.ref('base.group_portal').id,
                self.env.ref('acpec_mobile_auth.group_mobile_auth_user').id])],
        })
        requester.set_mobile_pin('1234')
        session_data = self.env['acpec.mobile.session'].sudo().create_for_user(requester, {
            'device_uid': 'device-auto-del', 'platform': 'ios',
        })
        session = session_data['session']
        self.assertEqual(session.state, 'active')
        self.assertTrue(requester.active)

        record = self.model._request_for_user(requester).with_user(manager)
        self.assertEqual(record.state, 'pending')

        # Execute automated deletion
        record.action_execute_and_complete()

        self.assertEqual(record.state, 'in_progress')
        self.assertEqual(session.state, 'revoked')
        self.assertFalse(requester.active)
        self.assertEqual(requester.acpec_mobile_state, 'blocked')
        self.assertFalse(requester.acpec_mobile_pin_set)
        self.assertFalse(record.notification_reference)
        self.assertFalse(record.completed_at)
        self.assertTrue(record.processing_notes)


    def test_overdue_cron_does_not_claim_deletion(self):
        requester = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Overdue requester', 'login': 'overdue-requester', 'active': True,
            'group_ids': [(6, 0, [self.env.ref('base.group_portal').id])],
        })
        record = self.model._request_for_user(requester)
        record.sudo().write({'due_at': fields.Datetime.now() - timedelta(days=1)})
        self.model._cron_process_due_deletion_requests()
        self.assertEqual(record.state, 'pending')
        self.assertFalse(record.completed_at)
        self.assertTrue(requester.active)

    def test_notification_is_queued_not_assumed_delivered(self):
        mail = self.model._send_mail_safe('support@example.test', 'Test', '<p>Test</p>')
        self.assertEqual(mail.state, 'outgoing')

    def _manual_case(self):
        manager = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Manual manager', 'login': 'manual-deletion-manager',
            'company_id': self.env.company.id,
            'company_ids': [(6, 0, [self.env.company.id])],
            'group_ids': [(6, 0, [self.env.ref('base.group_user').id,
                self.env.ref('acpec_mobile_auth.group_mobile_auth_admin').id])],
        })
        requester = self.env['res.users'].with_context(no_reset_password=True).create({
            'name': 'Manual requester', 'login': 'manual-deletion-requester',
            'group_ids': [(6, 0, [self.env.ref('base.group_portal').id])],
        })
        record = self.model._request_for_user(requester).with_user(manager)
        record.action_start()
        record.write({
            'settlement_notes': 'Aucun ticket ni solde',
            'processing_notes': 'Procédure manuelle de test',
            'erasure_evidence': 'Rapport de vérification de test',
            'retention_details': 'Aucune donnée financière pour ce compte de test',
            'notification_channel': 'sms',
            'notification_reference': 'SMS de test confirmé',
            'notification_sent_at': fields.Datetime.now(),
        })
        return record, requester

    def test_manual_completion_requires_all_steps(self):
        record, requester = self._manual_case()
        with self.assertRaises(ValidationError):
            record.action_complete()
        requester.write({'active': False})
        for field in ('settlement_notes', 'erasure_evidence', 'retention_details',
                      'notification_channel', 'notification_reference', 'notification_sent_at'):
            original = record[field]
            record.write({field: False})
            with self.assertRaises(ValidationError):
                record.action_complete()
            self.assertEqual(record.state, 'in_progress')
            record.write({field: original})
        record.action_complete()
        self.assertEqual(record.state, 'completed')

    def test_manual_confirmation_cannot_be_in_future(self):
        record, requester = self._manual_case()
        requester.write({'active': False})
        record.write({'notification_sent_at': fields.Datetime.now() + timedelta(days=1)})
        with self.assertRaises(ValidationError):
            record.action_complete()
        self.assertEqual(record.state, 'in_progress')

    def test_manual_completion_after_real_test_account_removal(self):
        record, requester = self._manual_case()
        partner = requester.partner_id
        requester.unlink()
        partner.unlink()
        self.env.invalidate_all()
        self.assertFalse(record.user_id)
        self.assertFalse(requester.exists())
        self.assertFalse(partner.exists())
        record.write({'retention_details': False})
        with self.assertRaises(ValidationError):
            record.action_complete()
        record.write({'retention_details': 'Aucune donnée financière à conserver pour ce compte vide'})
        record.action_complete()
        self.assertEqual(record.state, 'completed')

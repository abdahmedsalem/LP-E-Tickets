import base64
import uuid

from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged
from odoo.addons.acpec_fueltoken_core.tests.qr_action_test_utils import create_mobile_test_user


@tagged('post_install', '-at_install')
class TestImmediateDeletion(TransactionCase):
    def setUp(self):
        super().setUp()
        self.model = self.env['acpec.mobile.account.deletion'].sudo()
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.retention_notice', 'Test: preserved until fixture rollback.')
        self.user = create_mobile_test_user(self.env, self.env.company, uuid.uuid4().hex, 'client')
        self.user.set_mobile_pin('1234')
        self.wallet = self.env['acpec.fuel.wallet'].sudo().get_or_create(self.user.partner_id, self.env.company)

    def _fund(self):
        ct = self.env['acpec.fuel.carnet.type'].sudo().search([
            ('company_id', '=', self.env.company.id)], limit=1)
        if not ct:
            ct = self.env['acpec.fuel.carnet.type'].sudo().create({
                'face_count': 10, 'face_value': 100, 'validity_days': 365,
                'company_id': self.env.company.id})
        purchase = self.env['acpec.fuel.purchase'].sudo()._create_internal({
            'partner_id': self.user.partner_id.id, 'company_id': self.env.company.id})
        self.env['acpec.fuel.purchase.line'].sudo()._create_internal({
            'purchase_id': purchase.id, 'carnet_type_id': ct.id, 'carnet_qty': 1})
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'payment-proof.pdf', 'datas': base64.b64encode(b'%PDF-1.4 fixture'),
            'res_model': purchase._name, 'res_id': purchase.id, 'mimetype': 'application/pdf'})
        purchase._write_proof_internal({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()
        face = self.env['acpec.fuel.face.line'].sudo().search([('wallet_id', '=', self.wallet.id)], limit=1)
        qr = self.env['acpec.fuel.qr'].sudo()._issue_from_available_internal(
            self.user, self.wallet, [{'face_line_id': face.id, 'qty': 1}],
            idempotency_key=uuid.uuid4().hex, request_hash=uuid.uuid4().hex)
        return purchase, face, qr, attachment

    def test_value_requires_explicit_waiver_and_preserves_financial_rows(self):
        purchase, face, qr, proof = self._fund()
        report = self.model._wallet_report(self.user)
        self.assertTrue(report['has_value'])
        with self.assertRaises(ValidationError):
            self.model._delete_immediately(self.user, report['snapshot'], False, str(uuid.uuid4()))
        self.assertTrue(self.user.active)
        txs = self.env['acpec.fuel.transaction'].sudo().search([('wallet_id', '=', self.wallet.id)])
        initial = face.qty_initial
        old_wallet_label = self.wallet.name
        result = self.model._delete_immediately(self.user, report['snapshot'], True, str(uuid.uuid4()))
        self.assertTrue(result['completed'])
        self.assertEqual(qr.state, 'blocked')
        self.assertEqual(face.qty_qr_active, 0)
        self.assertEqual(face.qty_qr_blocked, 1)
        self.assertEqual(face.qty_initial, initial)
        self.assertEqual(txs.exists(), txs)
        self.assertTrue(purchase.exists())
        self.assertTrue(proof.exists())
        self.assertNotEqual(old_wallet_label, self.wallet.name)
        self.assertFalse(self.user.acpec_mobile_phone)
        self.assertFalse(self.user.acpec_mobile_pin_set)

    def test_station_reservation_blocks_deletion(self):
        purchase, face, qr, proof = self._fund()
        qr._write_state_internal({'station_lock_user_id': self.env.user.id})
        report = self.model._wallet_report(self.user)
        self.assertIn('station_operation', report['blockers'])
        with self.assertRaises(ValidationError):
            self.model._delete_immediately(self.user, report['snapshot'], True, str(uuid.uuid4()))
        self.assertTrue(self.user.active)
        self.assertEqual(qr.state, 'active')

    def test_personal_copies_are_purged_and_audit_events_preserved(self):
        phone = self.user.acpec_mobile_phone
        session = self.env['acpec.mobile.session'].sudo().create_for_user(self.user, {
            'device_uid': 'deletion-private-device', 'platform': 'ios'})['session']
        device = session.device_id
        otp = self.env['acpec.mobile.auth.otp'].sudo()._create_internal({
            'identifier': phone, 'user_id': self.user.id, 'otp_hash': 'fixture',
            'salt': 'fixture', 'expires_at': '2099-01-01 00:00:00'})
        picture = self.env['ir.attachment'].sudo().create({
            'name': 'avatar.jpg', 'datas': base64.b64encode(b'private'),
            'res_model': 'res.partner', 'res_id': self.user.partner_id.id})
        message = self.user.partner_id.message_post(body='Private profile note')
        log = self.env['acpec.mobile.security.audit.log'].sudo().log_event(
            event_type='sensitive_action_allowed', user_id=self.user.id,
            partner_id=self.user.partner_id.id, device_uid='private-device',
            ip_address='192.0.2.1', success=True)
        report = self.model._wallet_report(self.user)
        self.model._delete_immediately(self.user, report['snapshot'], False, str(uuid.uuid4()))
        self.model._scrub_deletion_audit(self.user)
        self.assertFalse(otp.exists())
        self.assertFalse(session.exists())
        self.assertFalse(device.exists())
        self.assertFalse(picture.exists())
        self.assertFalse(message.exists())
        self.assertTrue(log.exists())
        self.assertFalse(log.device_uid)
        self.assertFalse(log.ip_address)
        with self.assertRaises(AccessError):
            log.write({'success': False})
        with self.assertRaises(AccessError):
            self.env['acpec.mobile.auth.otp'].sudo()._find_user(phone)

    def test_recovery_expiry_and_token_scope(self):
        from datetime import timedelta
        from odoo import fields
        key = str(uuid.uuid4())
        report = self.model._wallet_report(self.user)
        result = self.model._delete_immediately(self.user, report['snapshot'], False, key)
        self.assertEqual(result, self.model._recover_immediate(key))
        self.assertEqual(self.model._recover_immediate(str(uuid.uuid4())), {'completed': False})
        record = self.model.search([('user_id', '=', self.user.id)])
        record.write({'recovery_expires_at': fields.Datetime.now() - timedelta(seconds=1)})
        self.assertEqual(self.model._recover_immediate(key), {'completed': False, 'expired': True})

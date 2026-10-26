"""Immediate client deletion. Financial rows remain; personal copies are purged."""
import hashlib
import hmac
import json
import re
import secrets
from datetime import timedelta

from odoo import api, fields, models, _
from odoo.exceptions import AccessError, ValidationError


class ImmediateAccountDeletion(models.Model):
    _inherit = 'acpec.mobile.account.deletion'

    recovery_hash = fields.Char(readonly=True, copy=False, index=True, groups='base.group_system')
    recovery_expires_at = fields.Datetime(readonly=True, copy=False, groups='base.group_system')
    history_expires_at = fields.Datetime(
        readonly=True, copy=False, index=True,
        string='Échéance de l’historique des mouvements',
    )
    history_purged_at = fields.Datetime(
        readonly=True, copy=False,
        string='Purge de l’historique des mouvements',
    )
    _unique_recovery_hash = models.Constraint('UNIQUE(recovery_hash)', 'Recovery key must be unique.')

    @api.model
    def _recovery_digest(self, key):
        if not isinstance(key, str) or not re.fullmatch(r'[0-9a-fA-F-]{36}', key):
            raise ValidationError(_('Invalid deletion recovery key.'))
        return hashlib.sha256(key.encode()).hexdigest()

    @api.model
    def _recover_immediate(self, key):
        digest = self._recovery_digest(key)
        record = self.sudo().search([
            ('recovery_hash', '=', digest), ('state', '=', 'completed'),
        ], limit=1)
        if record and (not record.recovery_expires_at or record.recovery_expires_at <= fields.Datetime.now()):
            return {'completed': False, 'expired': True}
        return {'completed': bool(record), **({'reference': record.reference} if record else {})}

    @api.model
    def _retention_notice(self):
        notice = self.env['ir.config_parameter'].sudo().get_param(
            'acpec_mobile_account_deletion.retention_notice', '')
        if not notice.strip():
            raise ValidationError(_('Account deletion is temporarily unavailable: retention policy is not configured.'))
        return notice.strip()

    @api.model
    def _retention_notice_ar(self):
        notice = self.env['ir.config_parameter'].sudo().get_param(
            'acpec_mobile_account_deletion.retention_notice_ar', '')
        return notice.strip() or self._retention_notice()

    @api.model
    def _client_wallets(self, user):
        user.ensure_one()
        if not user.active or not user.acpec_mobile_only:
            raise AccessError(_('This operation requires an active mobile account.'))
        # Never erase a shared identity or an operational/company identity.
        for xmlid in ('base.group_user', 'acpec_fueltoken_base.group_fuel_station',
                      'acpec_fueltoken_base.group_fuel_manager', 'acpec_fueltoken_base.group_fuel_admin'):
            if user.has_group(xmlid):
                raise AccessError(_('This operation is reserved for client accounts.'))
        if user.partner_id.is_company or self.env['res.users'].sudo().with_context(active_test=False).search_count([
            ('partner_id', '=', user.partner_id.id), ('id', '!=', user.id),
        ]):
            raise ValidationError(_('A shared identity must be separated before deletion.'))
        return self.env['acpec.fuel.wallet'].sudo().search([('partner_id', '=', user.partner_id.id)], order='id')

    @api.model
    def _wallet_report(self, user, lock=False):
        wallets = self._client_wallets(user)
        qrs = self.env['acpec.fuel.qr'].sudo().search([('wallet_id', 'in', wallets.ids)], order='id')
        faces = self.env['acpec.fuel.face.line'].sudo().search([('wallet_id', 'in', wallets.ids)], order='id')
        purchases = self.env['acpec.fuel.purchase'].sudo().search([('partner_id', '=', user.partner_id.id)], order='id')
        if lock:
            # Match wallet/face locking used by transfers and QR issuance.
            for table, records in (('res_users', user), ('acpec_fuel_wallet', wallets),
                                   ('acpec_fuel_qr', qrs), ('acpec_fuel_face_line', faces),
                                   ('acpec_fuel_purchase', purchases)):
                if records:
                    self.env.cr.execute('SELECT id FROM ' + table + ' WHERE id IN %s ORDER BY id FOR UPDATE',
                                        [tuple(records.ids)])
                    records.invalidate_recordset()
        blockers = []
        if any(qr.station_lock_user_id or qr.station_lock_station_id for qr in qrs):
            blockers.append('station_operation')
        # An unsettled purchase must not disappear together with its owner.
        if any(p.state not in ('approved', 'rejected', 'cancelled') for p in purchases):
            blockers.append('pending_purchase')
        report = {
            'wallets': [{
                'reference': w.name, 'currency': w.currency_id.name,
                'balance': w.balance, 'available_tickets': w.qty_available,
            } for w in wallets],
            'carnets': [{
                'reference': f.carnet_short_code or f.name, 'value': f.face_value,
                'available': f.qty_available, 'qr_active': f.qty_qr_active,
                'qr_blocked': f.qty_qr_blocked, 'consumed': f.qty_consumed,
                'expired': f.qty_expired, 'transferred': f.qty_transferred_out,
                'expires_at': fields.Datetime.to_string(f.expires_at) if f.expires_at else None,
            } for f in faces],
            # Public QR references only: never export bearer redemption secrets.
            'qrs': [{'reference': q.name, 'state': q.state,
                     'tickets': sum(q.line_ids.mapped('qty'))} for q in qrs],
            'has_value': any(f.qty_available or f.qty_qr_active or f.qty_qr_blocked for f in faces),
            'blockers': blockers,
            'retention_notice': self._retention_notice_ar()
            if (self.env.context.get('lang') or '').startswith('ar')
            else self._retention_notice(),
        }
        txs = self.env['acpec.fuel.transaction'].sudo().search([
            ('wallet_id', 'in', wallets.ids)], order='id')
        fingerprint_data = {
            'user': user.id, 'report': report, 'transactions': txs.ids,
            'purchases': [(p.id, p.state, str(p.write_date)) for p in purchases],
            'faces': [(f.id, str(f.write_date)) for f in faces],
            'qrs': [(q.id, str(q.write_date)) for q in qrs],
        }
        report['snapshot'] = hashlib.sha256(json.dumps(
            fingerprint_data, sort_keys=True, default=str).encode()).hexdigest()
        return report

    def _neutralize_qrs(self, wallets):
        for qr in self.env['acpec.fuel.qr'].sudo().search([
            ('wallet_id', 'in', wallets.ids), ('state', '=', 'active'),
        ], order='id'):
            tx_lines = []
            for line in qr.line_ids.filtered(lambda item: item.state == 'active'):
                face = line.face_line_id
                face._write_state_internal({
                    'qty_qr_active': face.qty_qr_active - line.qty,
                    'qty_qr_blocked': face.qty_qr_blocked + line.qty,
                })
                line._write_state_internal({'state': 'blocked'})
                tx_lines.append(line._transaction_line_vals())
            qr._write_state_internal({'state': 'blocked'})
            self.env['acpec.fuel.transaction'].sudo().log(
                'blocage_qr', qr.company_id, wallet=qr.wallet_id, qr=qr, lines=tx_lines,
                note='Account deletion: QR disabled after explicit waiver; financial quantities preserved.')

    def _purge_personal_copies(self, user, identifiers):
        """Purge nonfinancial account material, leaving financial foreign keys intact."""
        self.ensure_one()
        partner = user.partner_id
        for model, domain, context_key in (
            ('acpec.mobile.auth.otp',
             ['|', ('user_id', '=', user.id), ('identifier', 'in', identifiers)],
             'acpec_mobile_otp_internal_purge'),
            ('acpec.mobile.session', [('user_id', '=', user.id)], 'acpec_mobile_session_internal_purge'),
            ('acpec.mobile.auth.account.request', [('user_id', '=', user.id)], 'acpec_mobile_auth_account_request_internal_purge'),
            ('acpec.mobile.device', [('user_id', '=', user.id)], 'acpec_mobile_device_internal_purge'),
        ):
            self.env[model].sudo().with_context(**{context_key: True}).search(domain).unlink()
        self.env['acpec.mobile.auth.otp.verify.bucket'].sudo().with_context(
            acpec_mobile_otp_bucket_internal_purge=True).search([
                ('scope', '=', 'identifier'), ('key', 'in', identifiers),
            ]).unlink()
        # The initial request emails may contain the old name/login.
        mails = self.env['mail.mail'].sudo().search([('subject', 'ilike', self.reference)])
        mails.mapped('mail_message_id').unlink()
        profile_domain = ['|', '&', ('model', '=', 'res.users'), ('res_id', '=', user.id),
                          '&', ('model', '=', 'res.partner'), ('res_id', '=', partner.id)]
        self.env['mail.message'].sudo().search(profile_domain).unlink()
        self.env['ir.attachment'].sudo().search([
            '|', '&', ('res_model', '=', 'res.users'), ('res_id', '=', user.id),
            '&', ('res_model', '=', 'res.partner'), ('res_id', '=', partner.id),
        ]).unlink()
        self.env['mail.activity'].sudo().search([
            '|', '&', ('res_model', '=', 'res.users'), ('res_id', '=', user.id),
            '&', ('res_model', '=', 'res.partner'), ('res_id', '=', partner.id),
        ]).unlink()
        # Purchase screenshots and payment proofs are personal data. They are
        # erased immediately with the account, while the movement ledger is
        # retained for the configured three-day traceability window.
        purchases = self.env['acpec.fuel.purchase'].sudo().search([
            ('partner_id', '=', partner.id),
        ])
        proof_attachments = purchases.mapped('proof_attachment_ids')
        if proof_attachments:
            models.Model.write(purchases, {'proof_attachment_ids': [(5, 0, 0)]})
            proof_attachments.unlink()
        if purchases:
            models.Model.write(purchases, {
                'payment_reference': False,
                'rejection_reason': False,
                'idempotency_key': False,
                'request_hash': False,
                'approval_idempotency_key': False,
                'approval_request_hash': False,
                'rejection_idempotency_key': False,
                'rejection_request_hash': False,
            })
        for model, ids in (('res.users', user), ('res.partner', partner)):
            values = {name: False for name in ('image_1920', 'signature', 'function', 'birthdate',
                                               'website', 'tz')
                      if name in ids._fields and not ids._fields[name].related}
            if values:
                ids.sudo().write(values)

    @api.model
    def _scrub_deletion_audit(self, user):
        # Called AFTER the sensitive-action audit is written as well.
        if not self.env.su or user.active or user.acpec_mobile_phone:
            raise AccessError(_('Audit privacy erasure requires an erased account.'))
        records = self.env['acpec.mobile.security.audit.log'].sudo().search([
            '|', ('user_id', '=', user.id), ('partner_id', '=', user.partner_id.id),
        ])
        # Public write/unlink stay immutable. This private, state-checked ORM
        # erasure clears only personal metadata, preserving every audit event.
        models.Model.write(records, {
            'device_uid': False, 'device_name': False, 'ip_address': False,
            'user_agent': False, 'debug_reason': False, 'idempotency_key': False,
        })

    @api.model
    def _delete_immediately(self, user, snapshot, waive_value, recovery_key):
        """Private entry point: controller must verify PIN before calling it."""
        if not self.env.su:
            raise AccessError(_('Privileged execution required.'))
        digest = self._recovery_digest(recovery_key)
        report = self._wallet_report(user, lock=True)
        if not isinstance(snapshot, str) or not hmac.compare_digest(snapshot, report['snapshot']):
            raise ValidationError(_('The wallet changed. Reopen the deletion report before confirming.'))
        if report['blockers']:
            raise ValidationError(_('An operation is still in progress. Complete it before deleting the account.'))
        if report['has_value'] and waive_value is not True:
            raise ValidationError(_('Explicit consent to abandon the remaining tickets and balance is required.'))
        record = self.sudo().search([('user_id', '=', user.id)], limit=1)
        if record and record.state == 'completed':
            raise ValidationError(_('Account already deleted.'))
        if not record:
            record = self.sudo().create({
                'reference': 'DEL-' + secrets.token_hex(16).upper(), 'user_id': user.id,
                'company_id': user.company_id.id, 'due_at': fields.Datetime.now(),
            })
        wallets = self._client_wallets(user)
        phone = user.acpec_mobile_phone
        identifiers = list(filter(None, [phone, user.login, user.email,
                                        '+222' + phone if phone else None,
                                        '222' + phone if phone else None]))
        # Disable access first, in the SAME transaction as all erasure.
        sessions = self.env['acpec.mobile.session'].sudo().search([('user_id', '=', user.id)])
        sessions._write_internal({'state': 'revoked', 'revoked_at': fields.Datetime.now()})
        user.sudo().write({'active': False, 'acpec_mobile_state': 'blocked'})
        record._neutralize_qrs(wallets)
        record._erase_personal_data()
        # Refresh the stored wallet label and update its locked row. Waiters
        # using an older repeatable-read snapshot must retry against revoked auth.
        wallets.with_context(acpec_fueltoken_wallet_internal_operation='write')._compute_name()
        wallets.flush_recordset(['name'])
        record._purge_personal_copies(user, identifiers)
        # Do not attest a delivered notification. The response/receipt is the confirmation.
        record.sudo().write({
            'state': 'completed', 'completed_at': fields.Datetime.now(),
            'completed_by': user.id, 'due_at': fields.Datetime.now(),
            'notification_channel': False, 'notification_sent_at': False,
            'notification_reference': False,
            'recovery_hash': digest,
            'recovery_expires_at': fields.Datetime.now() + timedelta(days=7),
            'history_expires_at': fields.Datetime.now() + timedelta(days=3),
            'settlement_notes': 'Explicit in-app waiver of residual value.' if report['has_value'] else 'No residual value.',
            'processing_notes': 'Immediate authenticated deletion; completion receipt available for seven days.',
            'erasure_evidence': 'Profile and contact cleared; personal attachments/messages, OTPs, sessions and devices purged.',
            'retention_details': report['retention_notice'],
        })
        return {'completed': True, 'reference': record.reference}

    @api.model
    def _purge_expired_movement_history(self):
        """Purge only the deleted client's anonymous movement ledger."""
        now = fields.Datetime.now()
        records = self.sudo().search([
            ('state', '=', 'completed'),
            ('history_expires_at', '!=', False),
            ('history_expires_at', '<=', now),
            '|', ('history_purged_at', '=', False),
                 ('history_purged_at', '<', fields.Datetime.to_string(now - timedelta(minutes=1))),
        ], limit=100, order='history_expires_at,id')
        count = 0
        for record in records:
            user = record.user_id.with_context(active_test=False)
            if not user or user.active or user.acpec_mobile_phone:
                continue
            wallets = self.env['acpec.fuel.wallet'].sudo().search([
                ('partner_id', '=', user.partner_id.id),
            ])
            purchases = self.env['acpec.fuel.purchase'].sudo().search([
                ('partner_id', '=', user.partner_id.id),
            ])
            movements = self.env['acpec.fuel.transaction'].sudo().search([
                '|', ('wallet_id', 'in', wallets.ids),
                '&', ('wallet_id', '=', False), ('purchase_id', 'in', purchases.ids),
            ])
            if movements:
                movements.with_context(allow_fuel_transaction_unlink=True).unlink()
                count += len(movements)
            record.sudo().write({'history_purged_at': now})
        return count



import uuid
from datetime import timedelta

from odoo import api, fields, models, _
from markupsafe import escape
from odoo.exceptions import AccessError, ValidationError


class AccountDeletionRequest(models.Model):
    _name = 'acpec.mobile.account.deletion'
    _description = 'Demande de suppression de compte mobile'
    _order = 'create_date desc'
    _rec_name = 'reference'

    reference = fields.Char(required=True, readonly=True, copy=False)
    user_id = fields.Many2one('res.users', readonly=True, ondelete='set null')
    company_id = fields.Many2one('res.company', required=True, readonly=True)
    due_at = fields.Datetime(required=True, readonly=True)
    state = fields.Selection([('pending', 'À traiter'), ('in_progress', 'En traitement'),
                              ('completed', 'Traitée')], default='pending', required=True, readonly=True)
    assigned_to = fields.Many2one('res.users', string='Responsable du traitement', readonly=True)
    settlement_notes = fields.Text(string='Traitement des tickets, QR et solde')
    notification_channel = fields.Selection([
        ('email', 'E-mail au client'), ('sms', 'SMS au client'),
        ('other', 'Autre canal convenu avec le client'),
    ], string='Canal de confirmation au client')
    notification_sent_at = fields.Datetime(string='Confirmation adressée au client le')
    processing_notes = fields.Text(string='Compte rendu du traitement')
    erasure_evidence = fields.Text(string='Preuve de suppression des données personnelles')
    retention_details = fields.Text(string='Données conservées, justification et durée')
    notification_reference = fields.Char(string='Preuve de confirmation envoyée au demandeur')
    completed_at = fields.Datetime(readonly=True)
    completed_by = fields.Many2one('res.users', readonly=True)

    _unique_user = models.Constraint('UNIQUE(user_id)', 'Une demande existe déjà pour ce compte.')
    _unique_reference = models.Constraint('UNIQUE(reference)', 'La référence doit être unique.')

    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.su:
            raise AccessError(_('La création est réservée au parcours mobile authentifié.'))
        return super().create(vals_list)

    def write(self, vals):
        if not self.env.su and any(rec.state == 'completed' for rec in self):
            raise AccessError(_('Une demande clôturée ne peut plus être modifiée.'))
        if not self.env.su and set(vals) - {
            'processing_notes', 'notification_reference', 'erasure_evidence',
            'retention_details', 'settlement_notes', 'notification_channel', 'notification_sent_at',
        }:
            raise AccessError(_('Utilisez les actions de traitement.'))
        return super().write(vals)

    @api.model
    def _processing_days(self):
        param = self.env['ir.config_parameter'].sudo().search([
            ('key', '=', 'acpec_mobile_account_deletion.processing_days')
        ], limit=1)
        raw = param.value if param else '7'
        try:
            days = int(raw)
        except (ValueError, TypeError):
            days = 0
        if not 1 <= days <= 90:
            raise ValidationError(_('Le délai de traitement des suppressions doit être configuré (1 à 90 jours).'))
        return days

    @api.model
    def _get_support_email(self):
        return self.env['ir.config_parameter'].sudo().get_param(
            'acpec_mobile_account_deletion.support_email', 'support@acpec.mr') or 'support@acpec.mr'

    @api.model
    def _send_mail_safe(self, email_to, subject, body_html):
        if not email_to:
            return self.env['mail.mail']
        # Queue within the request transaction: never send an irreversible email
        # before the deletion request commits, and never claim it was delivered.
        return self.env['mail.mail'].sudo().create({
            'subject': subject,
            'body_html': body_html,
            'email_to': email_to,
            'email_from': self.env.company.email or 'support@acpec.mr',
            'auto_delete': False,
        })

    def _send_request_notification_emails(self):
        self.ensure_one()
        support_email = self._get_support_email()
        user = self.user_id
        if not user:
            return
        user_name = escape(user.name or 'Demandeur')
        user_login = escape(user.login or '')
        user_email = user.email or (user.partner_id.email if user.partner_id else '')
        due_str = self.due_at.strftime('%d/%m/%Y') if self.due_at else ''

        support_subject = f"[Suppression Compte] Demande {self.reference} - {user_name}"
        support_body = f"""<p>Bonjour,</p>
<p>Une demande de suppression de compte mobile a été soumise sur l'application :</p>
<ul>
    <li><strong>Référence :</strong> {self.reference}</li>
    <li><strong>Utilisateur :</strong> {user_name} ({user_login})</li>
    <li><strong>Date de la demande :</strong> {fields.Datetime.to_string(self.create_date or fields.Datetime.now())}</li>
    <li><strong>Échéance de traitement :</strong> {due_str}</li>
</ul>
<p>Vérifiez les données à supprimer et documentez la justification et la durée de conservation des transactions, factures et pièces justificatives.</p>
"""
        self._send_mail_safe(support_email, support_subject, support_body)

        if user_email:
            user_subject = f"Prise en compte de votre demande de suppression - {self.reference}"
            user_body = f"""<p>Bonjour {user_name},</p>
<p>Nous avons bien reçu votre demande de suppression de compte (référence : <strong>{self.reference}</strong>).</p>
<p>Votre demande sera traitée au plus tard le <strong>{due_str}</strong>.</p>
<p>Seules les données soumises à une obligation de conservation seront conservées, selon la politique applicable.</p>
<p>Une confirmation vous sera adressée dès clôture définitive du compte.</p>
<p>Cordialement,<br/>L'équipe Support ACPEC</p>
"""
            self._send_mail_safe(user_email, user_subject, user_body)

    @api.model
    def _request_for_user(self, user):
        # Serialize requests for this user. The unique constraint remains the
        # final protection under PostgreSQL repeatable-read concurrency.
        self.env.cr.execute('SELECT id FROM res_users WHERE id = %s FOR UPDATE', [user.id])
        existing = self.sudo().search([('user_id', '=', user.id)], limit=1)
        if existing:
            return existing
        record = self.sudo().create({
            'reference': 'DEL-' + uuid.uuid4().hex.upper(),
            'user_id': user.id,
            'company_id': user.company_id.id,
            'due_at': fields.Datetime.now() + timedelta(days=self._processing_days()),
        })
        record._send_request_notification_emails()
        return record

    def _payload(self):
        self.ensure_one()
        return {'reference': self.reference, 'state': self.state,
                'due_at': self.due_at.isoformat() + 'Z'}

    def _check_manager(self):
        if not self.env.user.has_group('acpec_mobile_auth.group_mobile_auth_admin'):
            raise AccessError(_('Accès réservé aux responsables Mobile Auth.'))
        self.check_access('write')

    def action_start(self):
        self._check_manager()
        for rec in self:
            if rec.state == 'pending':
                rec.sudo().write({'state': 'in_progress', 'assigned_to': self.env.user.id})

    def action_prepare_deletion(self):
        """Revoke access only; actual erasure remains a separate manual step."""
        self._check_manager()
        for rec in self:
            with self.env.cr.savepoint():
                self.env.cr.execute('SELECT id FROM acpec_mobile_account_deletion WHERE id = %s FOR UPDATE', [rec.id])
                rec.invalidate_recordset()
                if rec.state not in ('pending', 'in_progress'):
                    raise ValidationError(_('Cette demande ne peut plus être préparée.'))
                user = rec.user_id.with_context(active_test=False)
                if not user or not user.acpec_mobile_only:
                    raise ValidationError(_('Cette action est réservée à un compte mobile.'))
                self.env.cr.execute('SELECT id FROM res_users WHERE id = %s FOR UPDATE', [user.id])
                sessions = self.env['acpec.mobile.session'].sudo().search([
                    ('user_id', '=', user.id), ('state', 'in', ('active', 'rotated')),
                ])
                sessions._write_internal({'state': 'revoked', 'revoked_at': fields.Datetime.now()})
                user.sudo().action_reset_mobile_pin()
                user.sudo().write({'active': False, 'acpec_mobile_state': 'blocked'})
                rec.sudo().write({
                    'state': 'in_progress',
                    'assigned_to': rec.assigned_to.id or self.env.user.id,
                    'processing_notes': rec.processing_notes or _('Accès révoqués. Suppression des données personnelles et confirmation au demandeur restant à effectuer.'),
                })
        return True

    def action_execute_and_complete(self):
        # Old callers must not mistake account deactivation for data deletion.
        return self.action_prepare_deletion()

    def action_complete(self):
        """Record an operator's completed manual procedure, not automatic erasure."""
        self._check_manager()
        with self.env.cr.savepoint():
            for rec in self.sorted('id'):
                self.env.cr.execute('SELECT id FROM acpec_mobile_account_deletion WHERE id = %s FOR UPDATE', [rec.id])
                rec.invalidate_recordset()
                if rec.state != 'in_progress':
                    raise ValidationError(_('Commencez le traitement avant de clôturer la demande.'))
                if not (rec.settlement_notes or '').strip():
                    raise ValidationError(_('Documentez le traitement des tickets, QR et du solde, ou leur absence.'))
                if not (rec.processing_notes or '').strip() or not (rec.erasure_evidence or '').strip():
                    raise ValidationError(_('Documentez la suppression effective des données personnelles et le compte rendu.'))
                # Records may remain even when res.users has been deleted.
                if not (rec.retention_details or '').strip():
                    raise ValidationError(_('Documentez les données conservées, leur justification et leur durée, ou leur absence.'))
                if not rec.notification_channel or not rec.notification_sent_at or not (rec.notification_reference or '').strip():
                    raise ValidationError(_('Renseignez le canal, la date et la preuve de confirmation adressée au client. Un message au support ne suffit pas.'))
                now = fields.Datetime.now()
                if rec.notification_sent_at > now or rec.notification_sent_at < rec.create_date.replace(microsecond=0):
                    raise ValidationError(_('La date de confirmation doit être comprise entre la demande et maintenant.'))
                user = rec.user_id.with_context(active_test=False)
                if user:
                    self.env.cr.execute('SELECT id FROM res_users WHERE id = %s FOR UPDATE', [user.id])
                    user.invalidate_recordset()
                    if user.active:
                        raise ValidationError(_('Le compte est encore actif. Effectuez la suppression et la révocation des accès avant de clôturer.'))
                    if self.env['acpec.mobile.session'].sudo().search_count([
                        ('user_id', '=', user.id), ('state', 'in', ('active', 'rotated')),
                    ]):
                        raise ValidationError(_('Des sessions mobiles sont encore actives. Révoquez-les avant de clôturer.'))
                rec.sudo().write({'state': 'completed', 'completed_at': now,
                                  'completed_by': self.env.user.id,
                                  'assigned_to': rec.assigned_to.id or self.env.user.id})
        return True

    @api.model
    def _cron_process_due_deletion_requests(self):
        """Escalate overdue requests; never claim automatic data erasure."""
        due_requests = self.sudo().search([
            ('state', 'in', ('pending', 'in_progress')),
            ('due_at', '<=', fields.Datetime.now()),
        ])
        if due_requests:
            references = ', '.join(escape(rec.reference) for rec in due_requests)
            self._send_mail_safe(self._get_support_email(),
                'ACPEC : demandes de suppression en retard',
                '<p>Demandes à traiter et à confirmer au demandeur : %s</p>' % references)

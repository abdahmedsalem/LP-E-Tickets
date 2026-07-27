# -*- coding: utf-8 -*-

from odoo import api, fields, models, _
from odoo.exceptions import AccessError


class AcpecMobileSecurityAuditLog(models.Model):
    _name = 'acpec.mobile.security.audit.log'
    _description = 'Journal d’audit sécurité mobile'
    _order = 'create_date desc, id desc'

    name = fields.Char(
        string='Référence',
        required=True,
        readonly=True,
        copy=False,
        default=lambda self: _('Nouveau'),
        index=True,
    )

    event_type = fields.Selection([
        ('sensitive_action_denied', 'Action sensible refusée'),
        ('sensitive_action_allowed', 'Action sensible autorisée'),
        ('mobile_signup_not_allowed', 'Inscription mobile refusée'),
        ('invalid_action_code', 'Code d’action invalide'),
        ('missing_action_code', 'Code d’action manquant'),
        ('invalid_action_code_key', 'Clé de code d’action invalide'),
        ('device_pending_trust', 'Device en attente de validation'),
        ('device_blocked', 'Device bloqué'),
        ('device_not_trusted', 'Device non approuvé'),
        ('device_missing_uid', 'Device sans identifiant'),
        ('pin_locked', 'PIN verrouillé'),
        ('pin_hard_blocked', 'PIN bloqué définitivement'),
        ('pin_reset_required', 'Réinitialisation PIN requise'),
        ('sensitive_action_busy', 'Action sensible déjà en cours'),
    ], string='Type d’événement', required=True, index=True)

    severity = fields.Selection([
        ('info', 'Information'),
        ('warning', 'Avertissement'),
        ('error', 'Erreur'),
        ('critical', 'Critique'),
    ], string='Sévérité', required=True, default='warning', index=True)

    code = fields.Char(string='Code', index=True)
    reference = fields.Char(string='Référence publique', index=True, copy=False, readonly=True)
    public_message = fields.Text(string='Message public')
    debug_reason = fields.Text(string='Raison technique')

    user_id = fields.Many2one('res.users', string='Utilisateur mobile', index=True, ondelete='set null')
    partner_id = fields.Many2one('res.partner', string='Partenaire', index=True, ondelete='set null')
    company_id = fields.Many2one('res.company', string='Société', index=True, ondelete='set null')
    session_id = fields.Many2one('acpec.mobile.session', string='Session mobile', index=True, ondelete='set null')

    device_uid = fields.Char(string='Identifiant device', index=True)
    device_name = fields.Char(string='Nom device')
    device_trust_state = fields.Char(string='État de confiance device', index=True)

    endpoint = fields.Char(string='Endpoint', index=True)
    operation = fields.Char(string='Opération', index=True)
    idempotency_key = fields.Char(string='Clé d’idempotence', index=True)

    target_model = fields.Char(string='Modèle cible', index=True)
    target_res_id = fields.Integer(string='ID cible', index=True)
    business_ref = fields.Char(string='Référence métier', index=True)

    ip_address = fields.Char(string='Adresse IP')
    user_agent = fields.Text(string='User-Agent')

    success = fields.Boolean(string='Succès', default=False, index=True)
    blocked = fields.Boolean(string='Bloqué', default=False, index=True)

    action_code_present = fields.Boolean(string='Code d’action présent')
    action_code_format_valid = fields.Boolean(string='Format code d’action valide')
    failed_count_before = fields.Integer(string='Échecs PIN avant')
    failed_count_after = fields.Integer(string='Échecs PIN après')

    @api.model_create_multi
    def create(self, vals_list):
        sequence = self.env['ir.sequence'].sudo()
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('Nouveau'):
                vals['name'] = (
                    sequence.next_by_code('acpec.mobile.security.audit.log')
                    or _('Nouveau')
                )
        return super().create(vals_list)

    @api.model
    def log_event(self, **kwargs):
        """Créer un événement d’audit structuré.

        Les secrets bruts ne doivent jamais être stockés ici.
        """
        allowed = {
            'event_type',
            'severity',
            'code',
            'reference',
            'public_message',
            'debug_reason',
            'user_id',
            'partner_id',
            'company_id',
            'session_id',
            'device_uid',
            'device_name',
            'device_trust_state',
            'endpoint',
            'operation',
            'idempotency_key',
            'target_model',
            'target_res_id',
            'business_ref',
            'ip_address',
            'user_agent',
            'success',
            'blocked',
            'action_code_present',
            'action_code_format_valid',
            'failed_count_before',
            'failed_count_after',
        }
        vals = {key: value for key, value in kwargs.items() if key in allowed}

        for forbidden in (
            'action_code',
            'action_pin',
            'pin',
            'secret_code',
            'otp',
            'otp_code',
            'acpec_mobile_pin_hash',
            'acpec_mobile_pin_salt',
        ):
            vals.pop(forbidden, None)

        return self.sudo().create(vals)

    def write(self, vals):
        raise AccessError(_('Les journaux d’audit sécurité mobile sont immuables.'))

    def unlink(self):
        raise AccessError(_('Les journaux d’audit sécurité mobile ne peuvent pas être supprimés.'))

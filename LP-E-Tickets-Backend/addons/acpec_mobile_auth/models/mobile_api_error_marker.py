# -*- coding: utf-8 -*-

from dateutil.relativedelta import relativedelta
from psycopg2 import IntegrityError

from odoo import api, fields, models, _
from odoo.exceptions import AccessError, UserError


class AcpecMobileApiErrorMarker(models.Model):
    _name = 'acpec.mobile.api.error.marker'
    _description = 'Incident API mobile'
    _order = 'last_seen_date desc, id desc'

    name = fields.Char(string='Référence', required=True, readonly=True, copy=False, index=True)
    fingerprint = fields.Char(string='Empreinte', required=True, readonly=True, copy=False, index=True)
    code = fields.Char(string='Code erreur', required=True, readonly=True, default='SERVER_ERROR', index=True)
    endpoint = fields.Char(string='Point d’accès', readonly=True, index=True)
    operation = fields.Char(string='Opération', readonly=True, index=True)
    exception_type = fields.Char(string='Type d’exception', readonly=True, index=True)
    exception_summary = fields.Text(string='Résumé de l’erreur', readonly=True)

    first_seen_reference = fields.Char(string='Première référence', readonly=True, index=True)
    last_seen_reference = fields.Char(string='Dernière référence', readonly=True, index=True)
    first_seen_date = fields.Datetime(string='Première apparition', readonly=True, index=True)
    last_seen_date = fields.Datetime(string='Dernière apparition', readonly=True, index=True)
    occurrence_count = fields.Integer(string='Nombre d’occurrences', readonly=True, default=1, index=True)

    last_user_id = fields.Many2one('res.users', string='Dernier utilisateur', readonly=True, index=True, ondelete='set null')
    last_company_id = fields.Many2one('res.company', string='Dernière société', readonly=True, index=True, ondelete='set null')

    state = fields.Selection([
        ('new', 'Nouveau'),
        ('reviewed', 'Vu'),
        ('resolved', 'Résolu'),
        ('ignored', 'Ignoré'),
    ], string='État', required=True, default='new', index=True)
    reviewed_by_id = fields.Many2one('res.users', string='Vu par', readonly=True, ondelete='set null')
    reviewed_date = fields.Datetime(string='Date de revue', readonly=True)
    resolution_note = fields.Text(string='Note de résolution')

    _fingerprint_unique = models.Constraint(
        'unique(fingerprint)',
        'L’empreinte de l’incident API mobile doit être unique.',
    )

    _name_unique = models.Constraint(
        'unique(name)',
        'La référence de l’incident API mobile doit être unique.',
    )

    @api.model
    def _retention_days(self, key, default):
        value = self.env['ir.config_parameter'].sudo().get_param(key)
        try:
            value = int(value)
        except Exception:
            value = default
        return max(value, 1)

    @api.model
    def log_marker(self, **kwargs):
        """Create or aggregate a technical mobile API incident marker.

        This marker deliberately stores no traceback and no request payload.
        The full traceback stays in the Odoo server log and is searched by
        the last_seen_reference returned to Flutter.
        """
        allowed = {
            'name',
            'fingerprint',
            'code',
            'endpoint',
            'operation',
            'exception_type',
            'exception_summary',
            'last_user_id',
            'last_company_id',
        }
        vals = {key: value for key, value in kwargs.items() if key in allowed}
        reference = vals.get('name')
        fingerprint = vals.get('fingerprint')
        if not reference or not fingerprint:
            raise UserError(_('Référence et empreinte obligatoires pour l’incident API mobile.'))

        now = fields.Datetime.now()
        marker = self.sudo().search([('fingerprint', '=', fingerprint)], limit=1)
        update_vals = {
            'last_seen_reference': reference,
            'last_seen_date': now,
            'occurrence_count': (marker.occurrence_count + 1) if marker else 1,
            'last_user_id': vals.get('last_user_id') or False,
            'last_company_id': vals.get('last_company_id') or False,
        }
        if marker:
            marker.sudo().write(update_vals)
            return marker

        create_vals = dict(vals)
        create_vals.update({
            'code': vals.get('code') or 'SERVER_ERROR',
            'first_seen_reference': reference,
            'last_seen_reference': reference,
            'first_seen_date': now,
            'last_seen_date': now,
            'occurrence_count': 1,
            'state': 'new',
        })
        try:
            with self.env.cr.savepoint():
                return self.sudo().create(create_vals)
        except IntegrityError:
            marker = self.sudo().search([('fingerprint', '=', fingerprint)], limit=1)
            if marker:
                marker.sudo().write({
                    'last_seen_reference': reference,
                    'last_seen_date': now,
                    'occurrence_count': marker.occurrence_count + 1,
                    'last_user_id': vals.get('last_user_id') or False,
                    'last_company_id': vals.get('last_company_id') or False,
                })
                return marker
            raise

    def write(self, vals):
        vals = dict(vals or {})
        if not self.env.su:
            allowed = {'state', 'resolution_note'}
            forbidden = set(vals) - allowed
            if forbidden:
                raise AccessError(_('Seuls l’état et la note de résolution peuvent être modifiés.'))
            if 'state' in vals:
                vals['reviewed_by_id'] = self.env.user.id
                vals['reviewed_date'] = fields.Datetime.now()
        return super().write(vals)

    def unlink(self):
        if not self.env.su:
            raise AccessError(_('Les incidents API mobile sont supprimés uniquement par la purge automatique.'))
        return super().unlink()

    @api.model
    def _cron_purge_old_markers(self):
        resolved_days = self._retention_days(
            'acpec_mobile_auth.api_error_marker_resolved_retention_days',
            90,
        )
        general_days = self._retention_days(
            'acpec_mobile_auth.api_error_marker_retention_days',
            365,
        )
        now = fields.Datetime.now()
        resolved_cutoff = now - relativedelta(days=resolved_days)
        general_cutoff = now - relativedelta(days=general_days)

        Marker = self.sudo()
        old_resolved = Marker.search([
            ('state', 'in', ('resolved', 'ignored')),
            ('last_seen_date', '<', resolved_cutoff),
        ])
        old_reviewed = Marker.search([
            ('state', '=', 'reviewed'),
            ('last_seen_date', '<', general_cutoff),
        ])
        old_new = Marker.search([
            ('state', '=', 'new'),
            ('last_seen_date', '<', general_cutoff),
        ])
        records = old_resolved | old_reviewed | old_new
        count = len(records)
        records.unlink()
        return count

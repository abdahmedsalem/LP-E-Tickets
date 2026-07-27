import secrets

from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class AcpecFueltokenSecuritySettings(models.Model):
    _name = 'acpec.fueltoken.security.settings'
    _description = 'Paramètres sécurité Tickets Carburant'
    _rec_name = 'company_id'

    QR_NUMERIC_SECRET_MIN_LENGTH = 32
    QR_NUMERIC_SECRET_RECOVERY_CONTEXT_KEY = 'allow_qr_numeric_secret_recovery'

    company_id = fields.Many2one(
        'res.company',
        string='Société Tickets Carburant',
        required=True,
        readonly=True,
        copy=False,
        index=True,
        ondelete='restrict',
        default=lambda self: self._default_company_id(),
    )
    qr_numeric_secret = fields.Char(
        string='Secret code manuel QR',
        copy=False,
        groups='base.group_system',
    )

    _company_unique = models.Constraint(
        'UNIQUE(company_id)',
        'Un seul paramétrage sécurité Tickets Carburant est autorisé par société.',
    )

    @api.model
    def _fueltoken_company(self):
        Company = self.env['res.company'].sudo()
        helper = getattr(Company, '_fueltoken_company', None)
        if helper:
            company = helper()
            if company:
                return company.sudo()
        if 'acpec_fueltoken_enabled' in Company._fields:
            company = Company.search([('acpec_fueltoken_enabled', '=', True)], limit=1)
            if company:
                return company.sudo()
        return self.env.company.sudo()

    @api.model
    def _default_company_id(self):
        return self._fueltoken_company().id

    @api.model
    def _get_for_fueltoken_company(self):
        company = self._fueltoken_company()
        return self.sudo().search([('company_id', '=', company.id)], limit=1)

    @api.model
    def _get_or_create_for_fueltoken_company(self):
        company = self._fueltoken_company()
        settings = self.sudo().search([('company_id', '=', company.id)], limit=1)
        if settings:
            return settings
        return self.sudo().create({'company_id': company.id})

    @api.model
    def _is_qr_numeric_secret_strong(self, secret):
        secret = str(secret or '').strip()
        if len(secret) < self.QR_NUMERIC_SECRET_MIN_LENGTH:
            return False
        if secret.casefold() in ('acpec-fueltoken', 'fueltoken', 'secret'):
            return False
        if len(set(secret)) < 4:
            return False
        return True

    @api.model
    def _new_qr_numeric_secret(self):
        return secrets.token_urlsafe(48)

    @api.model
    def _qr_numeric_code_hash_count(self, company=False):
        domain = [('qr_numeric_code_hash', 'not in', [False, ''])]
        if company:
            domain.append(('company_id', '=', company.id))
        return self.env['acpec.fuel.qr'].sudo().search_count(domain)

    def _hashed_qr_count(self):
        self.ensure_one()
        return self._qr_numeric_code_hash_count(company=self.company_id)

    def _secret_change_guard_enabled(self):
        return not self.env.context.get(self.QR_NUMERIC_SECRET_RECOVERY_CONTEXT_KEY)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            secret = str(vals.get('qr_numeric_secret') or '').strip()
            if secret and not self._is_qr_numeric_secret_strong(secret):
                raise ValidationError(_(
                    'Le secret du code manuel QR doit être fort : au moins %s caractères.'
                ) % self.QR_NUMERIC_SECRET_MIN_LENGTH)
        return super().create(vals_list)

    def write(self, vals):
        if 'qr_numeric_secret' in vals:
            new_secret = str(vals.get('qr_numeric_secret') or '').strip()
            if new_secret and not self._is_qr_numeric_secret_strong(new_secret):
                raise ValidationError(_(
                    'Le secret du code manuel QR doit être fort : au moins %s caractères.'
                ) % self.QR_NUMERIC_SECRET_MIN_LENGTH)
            if self._secret_change_guard_enabled():
                for rec in self:
                    current_secret = str(rec.qr_numeric_secret or '').strip()
                    if new_secret != current_secret and rec._hashed_qr_count():
                        raise UserError(_(
                            'Modification du secret QR manuel interdite : des QR '
                            'avec empreinte numérique existent déjà pour cette société. '
                            'Utiliser une procédure de récupération/migration contrôlée.'
                        ))
        return super().write(vals)

    def unlink(self):
        if self._secret_change_guard_enabled():
            for rec in self:
                if rec._hashed_qr_count():
                    raise UserError(_(
                        'Suppression du paramétrage sécurité interdite : des QR '
                        'avec empreinte numérique existent déjà pour cette société.'
                    ))
        return super().unlink()

    @api.model
    def _qr_numeric_secret_status(self):
        company = self._fueltoken_company()
        settings = self.sudo().search([('company_id', '=', company.id)], limit=1)
        secret = settings.qr_numeric_secret if settings else ''
        hashed_count = self._qr_numeric_code_hash_count(company=company)
        strong = self._is_qr_numeric_secret_strong(secret)
        return {
            'installed': True,
            'ok': bool(strong),
            'missing': not bool(secret),
            'weak': bool(secret) and not strong,
            'hashed_count': hashed_count,
            'company_id': company.id,
            'settings_id': settings.id if settings else False,
            'model': self._name,
            'field': 'qr_numeric_secret',
            'min_length': self.QR_NUMERIC_SECRET_MIN_LENGTH,
        }

    def _ensure_qr_numeric_secret(self):
        self.ensure_one()
        secret = str(self.qr_numeric_secret or '').strip()
        if self._is_qr_numeric_secret_strong(secret):
            return secret

        if self._hashed_qr_count():
            raise UserError(_(
                'Configuration sécurité QR incomplète : le secret dédié du code '
                'manuel QR est absent ou faible alors que des QR numériques '
                'existent déjà.'
            ))

        secret = self._new_qr_numeric_secret()
        self.with_context(**{
            self.QR_NUMERIC_SECRET_RECOVERY_CONTEXT_KEY: True,
        }).write({'qr_numeric_secret': secret})
        return secret

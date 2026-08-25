from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelPaymentMethod(models.Model):
    _name = 'acpec.fuel.payment.method'
    _description = 'Moyen de paiement FuelToken'
    _order = 'sequence, name, id'

    name = fields.Char(string='Nom', required=True, translate=True)
    code = fields.Char(string='Code technique', required=True, index=True)
    merchant_code = fields.Char(string='Code commerçant', required=True)
    image_1920 = fields.Image(string='Logo', max_width=1024, max_height=1024)
    image_128 = fields.Image(
        string='Logo mobile',
        related='image_1920',
        max_width=128,
        max_height=128,
        store=True,
        readonly=False,
    )
    instructions = fields.Text(string='Instructions', translate=True)
    color_hex = fields.Char(string='Couleur', default='#43A047')
    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', string='Société')

    _code_company_unique = models.Constraint(
        'UNIQUE(code, company_id)',
        'Le code du moyen de paiement doit être unique par société.',
    )

    @api.model
    def _normalize_code(self, code):
        return (code or '').strip().lower()

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if 'code' in vals:
                vals['code'] = self._normalize_code(vals.get('code'))
            if 'color_hex' in vals and vals.get('color_hex'):
                vals['color_hex'] = vals['color_hex'].strip()
        return super().create(vals_list)

    def write(self, vals):
        vals = dict(vals)
        if 'code' in vals:
            vals['code'] = self._normalize_code(vals.get('code'))
        if 'color_hex' in vals and vals.get('color_hex'):
            vals['color_hex'] = vals['color_hex'].strip()
        return super().write(vals)

    @api.constrains('code')
    def _check_code(self):
        for rec in self:
            if not rec.code:
                raise ValidationError(_('Le code technique est obligatoire.'))
            if not rec.code.replace('_', '').replace('-', '').isalnum():
                raise ValidationError(
                    _('Le code technique ne doit contenir que lettres, chiffres, tirets ou underscores.')
                )

    @api.constrains('code', 'company_id')
    def _check_code_unique_by_scope(self):
        for rec in self:
            domain = [
                ('id', '!=', rec.id),
                ('code', '=', rec.code),
                ('company_id', '=', rec.company_id.id if rec.company_id else False),
            ]
            if self.sudo().search_count(domain):
                raise ValidationError(_('Le code du moyen de paiement doit être unique.'))

    @api.constrains('merchant_code')
    def _check_merchant_code(self):
        for rec in self:
            if not (rec.merchant_code or '').strip():
                raise ValidationError(_('Le code commerçant est obligatoire.'))

    @api.constrains('color_hex')
    def _check_color_hex(self):
        for rec in self:
            color = (rec.color_hex or '').strip()
            if not color:
                continue
            if len(color) != 7 or not color.startswith('#'):
                raise ValidationError(_('La couleur doit être au format #RRGGBB.'))
            try:
                int(color[1:], 16)
            except ValueError:
                raise ValidationError(_('La couleur doit être au format #RRGGBB.'))

    @api.model
    def available_for_company(self, company):
        domain = [('active', '=', True)]
        if company:
            domain = [
                ('active', '=', True),
                '|',
                ('company_id', '=', False),
                ('company_id', '=', company.id),
            ]
        records = self.sudo().search(domain, order='sequence, id')
        by_code = {}
        for record in records:
            current = by_code.get(record.code)
            if not current or (record.company_id and record.company_id == company):
                by_code[record.code] = record
        return self.browse([
            record.id
            for record in sorted(by_code.values(), key=lambda item: (item.sequence, item.id))
        ])

    @api.model
    def find_available_for_company(self, company, payment_method_id=False, payment_method_code=False):
        records = self.available_for_company(company)
        if payment_method_id:
            try:
                payment_method_id = int(payment_method_id)
            except (TypeError, ValueError):
                return self.browse()
            method = records.filtered(lambda item: item.id == payment_method_id)[:1]
            if method:
                return method
        code = self._normalize_code(payment_method_code)
        if code:
            method = records.filtered(lambda item: item.code == code)[:1]
            if method:
                return method
        return self.browse()

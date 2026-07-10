from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class AcpecFuelCarnetType(models.Model):
    _name = 'acpec.fuel.carnet.type'
    _description = 'Type de carnet FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'face_value, face_count, code'

    name = fields.Char(string='Nom', compute='_compute_name', store=True, readonly=True)
    code = fields.Char(string='Code', compute='_compute_code', store=True, readonly=True, index=True)
    
    face_count = fields.Integer(string='Nombre de tickets par carnet', required=True, default=10, tracking=True)
    face_value = fields.Monetary(string='Valeur du ticket', required=True, tracking=True)
    carnet_amount = fields.Monetary(string='Montant du carnet', compute='_compute_carnet_amount', store=True)
    validity_days = fields.Integer(string='Validité en jours', default=365)
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', string='Société', default=lambda self: self.env.company, required=True)
    currency_id = fields.Many2one('res.currency', related='company_id.currency_id', store=True, readonly=True)
    purchase_line_count = fields.Integer(string='Lignes d’achat', compute='_compute_purchase_line_count')

    _code_company_unique = models.Constraint(
        'UNIQUE(code, company_id)',
        'Le code du type de carnet doit être unique par société.',
    )
    _positive_face_count = models.Constraint(
        'CHECK(face_count > 0)',
        'Le nombre de tickets par carnet doit être positif.',
    )
    _positive_face_value = models.Constraint(
        'CHECK(face_value > 0)',
        'La valeur du ticket doit être positive.',
    )
    _validity_days = models.Constraint(
        'CHECK(validity_days >= 0)',
        'La validité en jours doit être un entier positif.',
    )


    def _format_carnet_number(self, value):
        value = value or 0
        number = float(value)
        if number.is_integer():
            return str(int(number))
        return ('%.6f' % number).rstrip('0').rstrip('.')

    @api.depends('face_count', 'face_value')
    def _compute_code(self):
        for rec in self:
            count = rec._format_carnet_number(rec.face_count)
            value = rec._format_carnet_number(rec.face_value)
            rec.code = 'C%sT-%s' % (count, value)

    def _human_carnet_type_label(self):
        self.ensure_one()
        count = self._format_carnet_number(self.face_count)
        value = self._format_carnet_number(self.face_value)
        currency = (self.currency_id.name or '').strip()
        ticket_word = 'ticket' if int(self.face_count or 0) == 1 else 'tickets'
        label = 'Carnet - %s %s x %s' % (count, ticket_word, value)
        return '%s %s' % (label, currency) if currency else label

    @api.depends('face_count', 'face_value', 'currency_id')
    def _compute_name(self):
        for rec in self:
            rec.name = rec._human_carnet_type_label()

    @api.model
    def _refresh_human_carnet_type_names(self):
        records = self.sudo().search([])
        for rec in records:
            expected_name = rec._human_carnet_type_label()
            self.env.cr.execute(
                """
                SELECT name
                  FROM acpec_fuel_carnet_type
                 WHERE id = %s
                """,
                [rec.id],
            )
            current_name = self.env.cr.fetchone()[0]
            if current_name != expected_name:
                self.env.cr.execute(
                    """
                    UPDATE acpec_fuel_carnet_type
                       SET name = %s
                     WHERE id = %s
                    """,
                    [expected_name, rec.id],
                )
        records.invalidate_recordset(['name'])
        return True

    @api.depends('face_count', 'face_value')
    def _compute_carnet_amount(self):
        for rec in self:
            rec.carnet_amount = rec.face_count * rec.face_value

    def _compute_purchase_line_count(self):
        has_purchase_line = 'acpec.fuel.purchase.line' in self.env.registry
        line_model = self.env['acpec.fuel.purchase.line'].sudo() if has_purchase_line else False
        for rec in self:
            rec.purchase_line_count = line_model.search_count([('carnet_type_id', '=', rec.id)]) if line_model else 0

    @api.constrains('face_count', 'face_value', 'validity_days')
    def _check_values(self):
        for rec in self:
            if rec.validity_days < 0:
                raise ValidationError(_('La validité en jours ne peut pas être négative.'))
            
    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            vals.pop('name', None)
            vals.pop('code', None)
        return super().create(vals_list)


    def _has_economic_usage(self):
        self.ensure_one()
        usage_checks = (
            ('acpec.fuel.purchase.line', [('carnet_type_id', '=', self.id)]),
            ('acpec.fuel.face.line', [('carnet_type_id', '=', self.id)]),
        )
        for model_name, domain in usage_checks:
            if model_name not in self.env.registry:
                continue
            model = self.env[model_name].sudo().with_context(active_test=False)
            if 'carnet_type_id' not in model._fields:
                continue
            if model.search_count(domain):
                return True
        return False

    def write(self, vals):
        vals = dict(vals)
        vals.pop('name', None)
        vals.pop('code', None)

        protected = {'face_count', 'face_value', 'validity_days', 'company_id'}
        if protected.intersection(vals):
            for rec in self:
                if rec._has_economic_usage():
                    raise ValidationError(_(
                        'Un type de carnet déjà utilisé ne peut pas être modifié sur ses paramètres structurants. '
                        'Archivez-le et créez un nouveau type.'
                    ))
        return super().write(vals)

    def unlink(self):
        raise UserError(_(
            'Les types de carnet ne doivent pas être supprimés. '
            'Archivez le type pour conserver la traçabilité.'
        ))

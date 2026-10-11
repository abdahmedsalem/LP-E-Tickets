from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class FormationCarnetType(models.Model):
    _name = 'formation.lp.carnet.type'
    _description = 'Type de carnet pédagogique'

    name = fields.Char(string='Nom', required=True)
    face_count = fields.Integer(string='Tickets par carnet', required=True)
    face_value = fields.Float(string='Valeur faciale', required=True)
    active = fields.Boolean(default=True)

    _face_count_positive = models.Constraint(
        'CHECK(face_count > 0)',
        'Le carnet doit contenir au moins un ticket.',
    )
    _face_value_positive = models.Constraint(
        'CHECK(face_value > 0)',
        'La valeur faciale doit être positive.',
    )


class FormationAchat(models.Model):
    _name = 'formation.lp.achat'
    _description = 'Achat pédagogique de carnets'
    _order = 'id desc'

    name = fields.Char(string='Référence', required=True, default='Nouvel achat')
    partner_id = fields.Many2one('res.partner', string='Client', required=True)
    company_id = fields.Many2one(
        'res.company', string='Société', required=True,
        default=lambda self: self.env.company,
    )
    state = fields.Selection(
        [('draft', 'Brouillon'), ('submitted', 'Soumis'),
         ('approved', 'Approuvé'), ('rejected', 'Rejeté')],
        default='draft', required=True,
    )
    line_ids = fields.One2many(
        'formation.lp.achat.line', 'achat_id', string='Lignes d’achat',
    )
    amount_total = fields.Float(
        string='Montant total', compute='_compute_totals', store=True,
    )
    ticket_total = fields.Integer(
        string='Nombre total de tickets', compute='_compute_totals', store=True,
    )

    @api.depends('line_ids.amount_total', 'line_ids.ticket_qty')
    def _compute_totals(self):
        for achat in self:
            achat.amount_total = sum(achat.line_ids.mapped('amount_total'))
            achat.ticket_total = sum(achat.line_ids.mapped('ticket_qty'))

    def action_submit(self):
        for achat in self:
            if achat.state != 'draft':
                raise UserError(_('Seul un brouillon peut être soumis.'))
            if not achat.line_ids:
                raise ValidationError(_('Ajoute au moins une ligne d’achat.'))
            achat.write({'state': 'submitted'})

    def action_approve(self):
        for achat in self:
            if achat.state != 'submitted':
                raise UserError(_('Seul un achat soumis peut être approuvé.'))
            achat.write({'state': 'approved'})

    def action_reject(self):
        for achat in self:
            if achat.state != 'submitted':
                raise UserError(_('Seul un achat soumis peut être rejeté.'))
            achat.write({'state': 'rejected'})


class FormationAchatLine(models.Model):
    _name = 'formation.lp.achat.line'
    _description = 'Ligne d’achat pédagogique'

    achat_id = fields.Many2one(
        'formation.lp.achat', string='Achat', required=True, ondelete='cascade',
    )
    carnet_type_id = fields.Many2one(
        'formation.lp.carnet.type', string='Type de carnet', required=True,
    )
    carnet_qty = fields.Integer(
        string='Nombre de carnets', required=True, default=1,
    )
    face_count = fields.Integer(string='Tickets par carnet', required=True)
    face_value = fields.Float(string='Valeur faciale', required=True)
    ticket_qty = fields.Integer(
        string='Nombre de tickets', compute='_compute_amounts', store=True,
    )
    amount_total = fields.Float(
        string='Montant de la ligne', compute='_compute_amounts', store=True,
    )

    _one_type_per_purchase = models.Constraint(
        'UNIQUE(achat_id, carnet_type_id)',
        'Un type de carnet ne peut apparaître qu’une fois par achat.',
    )

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            achat = self.env['formation.lp.achat'].browse(vals.get('achat_id'))
            if achat and achat.state != 'draft':
                raise UserError(
                    _('Une ligne ne peut être ajoutée que sur un achat brouillon.')
                )
        return super().create(vals_list)

    @api.onchange('carnet_type_id')
    def _onchange_carnet_type_id(self):
        for ligne in self:
            if ligne.carnet_type_id:
                ligne.face_count = ligne.carnet_type_id.face_count
                ligne.face_value = ligne.carnet_type_id.face_value
            else:
                ligne.face_count = 0
                ligne.face_value = 0

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_amounts(self):
        for ligne in self:
            ligne.ticket_qty = ligne.carnet_qty * ligne.face_count
            ligne.amount_total = ligne.ticket_qty * ligne.face_value

    @api.constrains('carnet_qty', 'face_count', 'face_value')
    def _check_values(self):
        for ligne in self:
            if ligne.carnet_qty <= 0:
                raise ValidationError(
                    _('Le nombre de carnets doit être supérieur à zéro.')
                )
            if ligne.face_count <= 0 or ligne.face_value <= 0:
                raise ValidationError(
                    _('Le nombre de tickets et leur valeur doivent être positifs.')
                )

    def write(self, vals):
        for ligne in self:
            if ligne.achat_id.state != 'draft':
                raise UserError(
                    _('Une ligne ne peut être modifiée que sur un achat brouillon.')
                )
        return super().write(vals)

    def unlink(self):
        for ligne in self:
            if ligne.achat_id.state != 'draft':
                raise UserError(
                    _('Une ligne ne peut être supprimée que sur un achat brouillon.')
                )
        return super().unlink()

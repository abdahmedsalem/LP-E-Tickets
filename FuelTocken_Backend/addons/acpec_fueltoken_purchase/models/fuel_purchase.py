from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError


class AcpecFuelPurchase(models.Model):
    _name = 'acpec.fuel.purchase'
    _description = 'Lot achat FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Reference interne', default='New', readonly=True, copy=False)
    partner_id = fields.Many2one('res.partner', string='Client', required=True, index=True, tracking=True)
    company_id = fields.Many2one('res.company', string='Societe', default=lambda self: self.env.company, required=True, index=True)
    currency_id = fields.Many2one('res.currency', related='company_id.currency_id', store=True, readonly=True)
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('submitted', 'Soumis'),
        ('approved', 'Valide'),
        ('rejected', 'Rejete'),
    ], string='Etat', default='draft', required=True, tracking=True, index=True)
    line_ids = fields.One2many('acpec.fuel.purchase.line', 'purchase_id', string='Lignes')
    amount_total = fields.Monetary(string='Montant total', compute='_compute_totals', store=True)
    face_qty_total = fields.Integer(string='Nombre de faces', compute='_compute_totals', store=True)
    proof_attachment_ids = fields.Many2many(
        'ir.attachment',
        'acpec_fuel_purchase_attachment_rel',
        'purchase_id',
        'attachment_id',
        string='Preuves de paiement',
    )
    payment_reference = fields.Char(string='Reference paiement')
    idempotency_key = fields.Char(string='Cle idempotence', index=True, copy=False)
    submitted_at = fields.Datetime(string='Date soumission', readonly=True)
    approved_at = fields.Datetime(string='Date validation', readonly=True)
    approved_by = fields.Many2one('res.users', string='Valide par', readonly=True)
    rejected_at = fields.Datetime(string='Date rejet', readonly=True)
    rejected_by = fields.Many2one('res.users', string='Rejete par', readonly=True)
    rejection_reason = fields.Text(string='Motif de rejet')
    fuel_value_created = fields.Boolean(string='Valeur carburant creee', readonly=True, copy=False)

    _public_code_unique = models.Constraint(
        'UNIQUE(public_code)',
        'Le code public du lot doit etre unique.',
    )
    _idempotency_partner_unique = models.Constraint(
        'UNIQUE(partner_id, idempotency_key)',
        "Cette demande d'achat existe deja pour ce client.",
    )

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('acpec.fuel.purchase') or 'New'
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='LOT', size=16)
        return super().create(vals_list)

    @api.depends('line_ids.amount_total', 'line_ids.generated_face_qty')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount_total'))
            rec.face_qty_total = sum(rec.line_ids.mapped('generated_face_qty'))

    def _check_before_submit(self):
        for rec in self:
            if not rec.line_ids:
                raise ValidationError(_('Le lot achat doit contenir au moins une ligne.'))
            if not rec.proof_attachment_ids:
                raise ValidationError(_('La preuve de paiement est obligatoire.'))
            for line in rec.line_ids:
                line._check_line_values()

    def action_submit(self):
        self._check_before_submit()
        for rec in self:
            if rec.state != 'draft':
                raise UserError(_('Seuls les lots en brouillon peuvent etre soumis.'))
            rec.write({'state': 'submitted', 'submitted_at': fields.Datetime.now()})

    def action_approve(self):
        with self.env.cr.savepoint():
            self._check_before_submit()
            for rec in self:
                if rec.state not in ('draft', 'submitted'):
                    raise UserError(_('Seuls les lots brouillon ou soumis peuvent etre valides.'))
                rec.write({
                    'state': 'approved',
                    'approved_at': fields.Datetime.now(),
                    'approved_by': self.env.user.id,
                    'rejection_reason': False,
                })
            self._create_face_lines_after_approval()

    def action_reject(self):
        for rec in self:
            if rec.state == 'approved':
                raise UserError(_('Un lot valide ne peut pas etre rejete.'))
            rec.write({
                'state': 'rejected',
                'rejected_at': fields.Datetime.now(),
                'rejected_by': self.env.user.id,
            })

    def _create_face_lines_after_approval(self):
        return True

    def write(self, vals):
        protected = {'line_ids', 'partner_id', 'company_id', 'proof_attachment_ids', 'payment_reference'}
        if protected.intersection(vals):
            for rec in self:
                if rec.state == 'approved':
                    raise UserError(_('Un lot valide ne peut pas etre modifie sur ses champs sensibles.'))
        return super().write(vals)

    @api.model
    def create_from_api(self, partner, company, lines, proof_filename, proof_data, payment_reference=False, idempotency_key=False):
        if idempotency_key:
            existing = self.sudo().search([
                ('partner_id', '=', partner.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing:
                return existing
        with self.env.cr.savepoint():
            purchase = self.sudo().create({
                'partner_id': partner.id,
                'company_id': company.id,
                'payment_reference': payment_reference or False,
                'idempotency_key': idempotency_key or False,
            })
            for item in lines:
                carnet_type = self.env['acpec.fuel.carnet.type'].sudo().browse(int(item.get('carnet_type_id') or 0)).exists()
                if not carnet_type:
                    raise ValidationError(_('Type de carnet introuvable.'))
                if not carnet_type.active:
                    raise ValidationError(_("Type de carnet '%s' desactive.") % carnet_type.display_name)
                if carnet_type.company_id and carnet_type.company_id != company:
                    raise ValidationError(_("Type de carnet '%s' indisponible pour cette societe.") % carnet_type.display_name)
                purchase.line_ids.create({
                    'purchase_id': purchase.id,
                    'carnet_type_id': carnet_type.id,
                    'carnet_qty': int(item.get('carnet_qty') or 0),
                })
            if proof_data:
                attachment = self.env['ir.attachment'].sudo().create({
                    'name': proof_filename or _('Preuve de paiement'),
                    'datas': proof_data,
                    'res_model': self._name,
                    'res_id': purchase.id,
                    'type': 'binary',
                })
                purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
            purchase.action_submit()
            return purchase


class AcpecFuelPurchaseLine(models.Model):
    _name = 'acpec.fuel.purchase.line'
    _description = 'Ligne achat FuelToken'
    _order = 'purchase_id, id'

    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot achat', required=True, ondelete='cascade', index=True)
    company_id = fields.Many2one('res.company', related='purchase_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='purchase_id.currency_id', store=True, readonly=True)
    carnet_type_id = fields.Many2one('acpec.fuel.carnet.type', string='Type de carnet', required=True)
    carnet_qty = fields.Integer(string='Nombre de carnets', required=True, default=1)
    face_count = fields.Integer(string='Taille carnet', related='carnet_type_id.face_count', store=True, readonly=True)
    face_value = fields.Monetary(string='Valeur de face', related='carnet_type_id.face_value', store=True, readonly=True)
    generated_face_qty = fields.Integer(string='Faces generees', compute='_compute_amounts', store=True)
    amount_total = fields.Monetary(string='Montant total', compute='_compute_amounts', store=True)

    _positive_carnet_qty = models.Constraint(
        'CHECK(carnet_qty > 0)',
        'Le nombre de carnets doit etre positif.',
    )

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_amounts(self):
        for rec in self:
            rec.generated_face_qty = rec.carnet_qty * rec.face_count
            rec.amount_total = rec.generated_face_qty * rec.face_value

    @api.constrains('carnet_type_id', 'purchase_id')
    def _check_carnet_type_company(self):
        for rec in self:
            if (
                rec.carnet_type_id.company_id
                and rec.purchase_id.company_id
                and rec.carnet_type_id.company_id != rec.purchase_id.company_id
            ):
                raise ValidationError(_(
                    "Le type de carnet '%s' n'appartient pas a la societe du lot d'achat."
                ) % rec.carnet_type_id.display_name)

    def _check_line_values(self):
        for rec in self:
            if rec.carnet_qty <= 0:
                raise ValidationError(_('Le nombre de carnets doit etre positif.'))
            if not rec.carnet_type_id:
                raise ValidationError(_('Le type de carnet est obligatoire.'))

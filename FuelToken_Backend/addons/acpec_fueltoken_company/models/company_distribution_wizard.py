from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError


class AcpecFuelDistributorDistributionWizard(models.TransientModel):
    _name = 'acpec.fuel.distributor.distribution.wizard'
    _description = 'Assistant distribution Compte Société'

    distributor_id = fields.Many2one(
        'acpec.fuel.distributor',
        string='Compte Société',
        required=True,
        readonly=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Société Odoo',
        related='distributor_id.company_id',
        readonly=True,
    )
    source_wallet_id = fields.Many2one(
        'acpec.fuel.wallet',
        string='Wallet société',
        compute='_compute_source_wallet',
        readonly=True,
    )
    member_partner_id = fields.Many2one(
        'res.partner',
        string='Membre destinataire',
        required=True,
        domain="[('id', 'in', allowed_member_partner_ids)]",
    )
    allowed_member_partner_ids = fields.Many2many(
        'res.partner',
        compute='_compute_allowed_member_partner_ids',
        string='Membres autorisés',
    )
    note = fields.Text(string='Note')
    confirm_transfer = fields.Boolean(
        string='Confirmer immédiatement',
        default=True,
        help='Si coché, le transfert est confirmé immédiatement et les carnets sont déplacés vers le wallet du membre.',
    )
    line_ids = fields.One2many(
        'acpec.fuel.distributor.distribution.wizard.line',
        'wizard_id',
        string='Carnets à distribuer',
    )

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        distributor_id = self.env.context.get('default_distributor_id') or self.env.context.get('active_id')
        distributor = self.env['acpec.fuel.distributor'].browse(distributor_id).exists() if distributor_id else False

        if distributor and 'distributor_id' in fields_list:
            res['distributor_id'] = distributor.id

        # Do not prefill distribution lines. The operator must explicitly add
        # the carnet types and quantities to distribute. Available balances remain
        # selectable/visible through the carnet type and audit columns.
        return res

    @api.depends('distributor_id')
    def _compute_source_wallet(self):
        for wizard in self:
            wallet = self.env['acpec.fuel.wallet']
            if wizard.distributor_id:
                wallet = wizard.distributor_id._get_company_wallet(create=False)
            wizard.source_wallet_id = wallet

    @api.depends('distributor_id', 'distributor_id.member_partner_ids')
    def _compute_allowed_member_partner_ids(self):
        for wizard in self:
            wizard.allowed_member_partner_ids = wizard.distributor_id.member_partner_ids.filtered(
                lambda partner: not partner.is_company
            )

    @api.depends('source_wallet_id')
    def _compute_available_carnet_type_ids(self):
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        for wizard in self:
            carnet_types = self.env['acpec.fuel.carnet.type']
            if wizard.source_wallet_id:
                face_lines = FaceLine.search([
                    ('wallet_id', '=', wizard.source_wallet_id.id),
                    ('qty_available', '>', 0),
                ], order='expires_at, id')
                for face_line in face_lines:
                    if face_line.is_transferable_carnet_line():
                        carnet_types |= face_line.carnet_type_id
            wizard.available_carnet_type_ids = carnet_types

    available_carnet_type_ids = fields.Many2many(
        'acpec.fuel.carnet.type',
        compute='_compute_available_carnet_type_ids',
        string='Types de carnets disponibles',
    )

    @api.onchange('distributor_id')
    def _onchange_distributor_id(self):
        for wizard in self:
            wizard.member_partner_id = False
            wizard.line_ids = [(5, 0, 0)]

    def _allocate_carnets_from_company_wallet(self, carnet_type, carnet_qty):
        self.ensure_one()
        if not self.source_wallet_id:
            raise ValidationError(_('Le Compte Société ne dispose d’aucun wallet source.'))

        remaining = int(carnet_qty or 0)
        if remaining <= 0:
            return []

        allocations = []
        face_lines = self.env['acpec.fuel.face.line'].sudo().search([
            ('wallet_id', '=', self.source_wallet_id.id),
            ('carnet_type_id', '=', carnet_type.id),
            ('qty_available', '>', 0),
        ], order='expires_at, id')
        for face_line in face_lines:
            if not face_line.is_transferable_carnet_line():
                continue
            available = face_line.transferable_carnet_count()
            if available <= 0:
                continue
            to_take = min(available, remaining)
            if to_take:
                allocations.append({
                    'face_line_id': face_line.id,
                    'carnet_qty': to_take,
                })
                remaining -= to_take
            if remaining <= 0:
                break

        if remaining > 0:
            allocated = int(carnet_qty or 0) - remaining
            raise ValidationError(_(
                'Carnets insuffisants pour %(type)s : %(available)s disponibles, %(asked)s demandés.'
            ) % {
                'type': carnet_type.display_name,
                'available': allocated,
                'asked': int(carnet_qty or 0),
            })
        return allocations

    def action_distribute(self):
        self.ensure_one()
        distributor = self.distributor_id
        if not distributor:
            raise UserError(_('Aucun Compte Société sélectionné.'))

        carnet_qty_by_type = {}
        for line in self.line_ids:
            if line.carnet_qty <= 0:
                continue
            if not line.carnet_type_id:
                raise ValidationError(_(
                    'Une ligne avec quantité doit obligatoirement référencer un type de carnet.'
                ))
            item = carnet_qty_by_type.setdefault(line.carnet_type_id.id, {
                'carnet_type': line.carnet_type_id,
                'carnet_qty': 0,
            })
            item['carnet_qty'] += line.carnet_qty

        if not carnet_qty_by_type:
            raise ValidationError(_('Vous devez saisir au moins une quantité de carnets à distribuer.'))

        selected_lines = []
        for item in carnet_qty_by_type.values():
            selected_lines.extend(
                self._allocate_carnets_from_company_wallet(
                    item['carnet_type'],
                    item['carnet_qty'],
                )
            )

        transfer = distributor.action_distribute_to_member(
            self.member_partner_id,
            selected_lines,
            note=self.note or False,
            confirm=self.confirm_transfer,
        )

        form_view = self.env.ref(
            'acpec_fueltoken_core.view_fuel_carnet_transfer_form',
            raise_if_not_found=False,
        )
        action = {
            'type': 'ir.actions.act_window',
            'name': _('Distribution société'),
            'res_model': 'acpec.fuel.carnet.transfer',
            'res_id': transfer.id,
            'view_mode': 'form',
            'target': 'current',
        }
        if form_view:
            action['views'] = [(form_view.id, 'form')]
        return action


class AcpecFuelDistributorDistributionWizardLine(models.TransientModel):
    _name = 'acpec.fuel.distributor.distribution.wizard.line'
    _description = 'Ligne assistant distribution Compte Société'
    _order = 'id'

    wizard_id = fields.Many2one(
        'acpec.fuel.distributor.distribution.wizard',
        required=True,
        ondelete='cascade',
    )
    distributor_id = fields.Many2one(
        related='wizard_id.distributor_id',
        readonly=True,
    )
    source_wallet_id = fields.Many2one(
        related='wizard_id.source_wallet_id',
        readonly=True,
    )
    available_carnet_type_ids = fields.Many2many(
        'acpec.fuel.carnet.type',
        related='wizard_id.available_carnet_type_ids',
        readonly=True,
    )
    carnet_type_id = fields.Many2one(
        'acpec.fuel.carnet.type',
        string='Type de carnet',
        domain="[('id', 'in', available_carnet_type_ids)]",
        required=True,
    )
    face_line_id = fields.Many2one(
        'acpec.fuel.face.line',
        string='Ligne de tickets source',
        compute='_compute_source_face_line',
        readonly=True,
        help='Première ligne technique disponible pour ce type de carnet. Champ d’audit uniquement.',
    )
    face_value = fields.Monetary(
        related='carnet_type_id.face_value',
        readonly=True,
    )
    currency_id = fields.Many2one(
        related='carnet_type_id.currency_id',
        readonly=True,
    )
    face_count = fields.Integer(
        related='carnet_type_id.face_count',
        readonly=True,
    )
    qty_available = fields.Integer(
        string='Tickets disponibles',
        compute='_compute_available_quantities',
    )
    transferable_carnet_count = fields.Integer(
        string='Carnets disponibles',
        compute='_compute_available_quantities',
    )
    carnet_qty = fields.Integer(string='Carnets à distribuer')
    qty_faces = fields.Integer(
        string='Tickets à distribuer',
        compute='_compute_totals',
    )
    amount_total = fields.Monetary(
        string='Montant',
        compute='_compute_totals',
    )

    def _get_transferable_face_lines(self):
        self.ensure_one()
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        if not self.source_wallet_id or not self.carnet_type_id:
            return FaceLine
        face_lines = FaceLine.search([
            ('wallet_id', '=', self.source_wallet_id.id),
            ('carnet_type_id', '=', self.carnet_type_id.id),
            ('qty_available', '>', 0),
        ], order='expires_at, id')
        return face_lines.filtered(lambda face_line: face_line.is_transferable_carnet_line())

    @api.depends('source_wallet_id', 'carnet_type_id')
    def _compute_source_face_line(self):
        for line in self:
            face_lines = line._get_transferable_face_lines()
            line.face_line_id = face_lines[:1]

    @api.depends('source_wallet_id', 'carnet_type_id')
    def _compute_available_quantities(self):
        for line in self:
            face_lines = line._get_transferable_face_lines()
            line.qty_available = sum(face_lines.mapped('qty_available'))
            line.transferable_carnet_count = sum(
                face_line.transferable_carnet_count() for face_line in face_lines
            )

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_totals(self):
        for line in self:
            line.qty_faces = max(line.carnet_qty or 0, 0) * (line.face_count or 0)
            line.amount_total = line.qty_faces * (line.face_value or 0)

    @api.constrains('carnet_type_id', 'carnet_qty')
    def _check_line_qty(self):
        for line in self:
            if line.carnet_qty < 0:
                raise ValidationError(_('La quantité de carnets ne peut pas être négative.'))
            if line.carnet_qty and not line.carnet_type_id:
                raise ValidationError(_(
                    'Une ligne avec quantité doit référencer un type de carnet.'
                ))
            if line.carnet_qty and line.carnet_qty > line.transferable_carnet_count:
                raise ValidationError(_(
                    'Quantité trop élevée pour %(type)s : %(available)s carnets disponibles, %(asked)s demandés.'
                ) % {
                    'type': line.carnet_type_id.display_name or line.face_line_id.display_name,
                    'available': line.transferable_carnet_count,
                    'asked': line.carnet_qty,
                })

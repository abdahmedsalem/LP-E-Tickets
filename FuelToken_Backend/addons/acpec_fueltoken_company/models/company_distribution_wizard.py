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

        if distributor and 'line_ids' in fields_list:
            res['line_ids'] = self._prepare_default_line_commands(distributor)

        return res

    @api.model
    def _prepare_default_line_commands(self, distributor):
        wallet = distributor._get_company_wallet(create=False)
        if not wallet:
            return []

        commands = []
        face_lines = self.env['acpec.fuel.face.line'].sudo().search([
            ('wallet_id', '=', wallet.id),
            ('qty_available', '>', 0),
        ], order='expires_at, id')
        for face_line in face_lines:
            if not face_line.is_transferable_carnet_line():
                continue
            commands.append((0, 0, {
                'face_line_id': face_line.id,
                'carnet_qty': 0,
            }))
        return commands

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

    @api.onchange('distributor_id')
    def _onchange_distributor_id(self):
        for wizard in self:
            wizard.member_partner_id = False
            wizard.line_ids = [(5, 0, 0)]
            if not wizard.distributor_id:
                continue
            if not wizard.distributor_id.has_wallet:
                continue

            wizard.line_ids = wizard._prepare_default_line_commands(wizard.distributor_id)

    def action_distribute(self):
        self.ensure_one()
        distributor = self.distributor_id
        if not distributor:
            raise UserError(_('Aucun Compte Société sélectionné.'))

        selected_lines = []
        for line in self.line_ids:
            if line.carnet_qty <= 0:
                continue
            if not line.face_line_id:
                raise ValidationError(_(
                    'Une ligne de distribution avec quantité doit obligatoirement référencer '
                    'une ligne de tickets source.'
                ))
            selected_lines.append({
                'face_line_id': line.face_line_id.id,
                'carnet_qty': line.carnet_qty,
            })

        if not selected_lines:
            raise ValidationError(_('Vous devez saisir au moins une quantité de carnets à distribuer.'))

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
    face_line_id = fields.Many2one(
        'acpec.fuel.face.line',
        string='Ligne de tickets source',
        domain="[('wallet_id', '=', source_wallet_id), ('qty_available', '>', 0)]",
        help=(
            'Ligne de tickets source proposée par l’assistant. '
            'Le champ n’est volontairement pas required au niveau ORM car le client web '
            'peut sauvegarder des lignes transitoires incomplètes dans un assistant editable.'
        ),
    )
    carnet_type_id = fields.Many2one(
        'acpec.fuel.carnet.type',
        string='Type de carnet',
        related='face_line_id.carnet_type_id',
        readonly=True,
    )
    face_value = fields.Monetary(
        related='face_line_id.face_value',
        readonly=True,
    )
    currency_id = fields.Many2one(
        related='face_line_id.currency_id',
        readonly=True,
    )
    face_count = fields.Integer(
        related='face_line_id.carnet_type_id.face_count',
        readonly=True,
    )
    qty_available = fields.Integer(
        string='Tickets disponibles',
        related='face_line_id.qty_available',
        readonly=True,
    )
    transferable_carnet_count = fields.Integer(
        string='Carnets disponibles',
        compute='_compute_transferable_carnet_count',
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

    @api.depends('face_line_id')
    def _compute_transferable_carnet_count(self):
        for line in self:
            if line.face_line_id:
                line.transferable_carnet_count = line.face_line_id.transferable_carnet_count()
            else:
                line.transferable_carnet_count = 0

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_totals(self):
        for line in self:
            line.qty_faces = max(line.carnet_qty or 0, 0) * (line.face_count or 0)
            line.amount_total = line.qty_faces * (line.face_value or 0)

    @api.constrains('face_line_id', 'carnet_qty')
    def _check_line_qty(self):
        for line in self:
            if line.carnet_qty < 0:
                raise ValidationError(_('La quantité de carnets ne peut pas être négative.'))
            if line.carnet_qty and not line.face_line_id:
                raise ValidationError(_(
                    'Une ligne avec quantité doit référencer une ligne de tickets source.'
                ))
            if line.carnet_qty and line.carnet_qty > line.transferable_carnet_count:
                raise ValidationError(_(
                    'Quantité trop élevée pour %(type)s : %(available)s carnets disponibles, %(asked)s demandés.'
                ) % {
                    'type': line.carnet_type_id.display_name or line.face_line_id.display_name,
                    'available': line.transferable_carnet_count,
                    'asked': line.carnet_qty,
                })

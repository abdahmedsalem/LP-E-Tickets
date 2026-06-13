from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError


class AcpecFuelDistributor(models.Model):
    _name = 'acpec.fuel.distributor'
    _description = 'Compte Société FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'name, id'

    name = fields.Char(
        string='Compte Société',
        required=True,
        tracking=True,
    )
    code = fields.Char(
        string='Code',
        required=True,
        index=True,
        tracking=True,
    )
    active = fields.Boolean(
        default=True,
        tracking=True,
    )
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('active', 'Actif'),
        ('suspended', 'Suspendu'),
        ('closed', 'Clôturé'),
    ], string='État', default='draft', required=True, tracking=True, index=True)

    partner_id = fields.Many2one(
        'res.partner',
        string='Société partenaire',
        required=True,
        index=True,
        tracking=True,
        domain="[('is_company', '=', True)]",
        ondelete='restrict',
        help='Partenaire entreprise représentant le Compte Société.',
    )
    company_id = fields.Many2one(
        'res.company',
        string='Société Odoo',
        required=True,
        default=lambda self: self.env.company,
        index=True,
        tracking=True,
    )

    member_partner_ids = fields.Many2many(
        'res.partner',
        'acpec_fuel_distributor_member_rel',
        'distributor_id',
        'partner_id',
        string='Membres',
        domain="[('is_company', '=', False)]",
        help=(
            'Membres rattachés au Compte Société. '
            'Ces partenaires représentent les utilisateurs/employés qui pourront recevoir des carnets via le futur portail société.'
        ),
        tracking=True,
    )
    member_count = fields.Integer(
        string='Nombre de membres',
        compute='_compute_member_count',
    )

    contact_name = fields.Char(string='Contact principal')
    contact_phone = fields.Char(string='Téléphone de contact')
    contact_email = fields.Char(string='Email de contact')
    notes = fields.Text(string='Notes internes')

    _code_company_unique = models.Constraint(
        'UNIQUE(code, company_id)',
        'Le code du compte société doit être unique par société Odoo.',
    )
    _partner_company_unique = models.Constraint(
        'UNIQUE(partner_id, company_id)',
        'Ce partenaire est déjà défini comme Compte Société pour cette société Odoo.',
    )

    @api.depends('member_partner_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_partner_ids)

    @api.onchange('partner_id')
    def _onchange_partner_id(self):
        for rec in self:
            partner = rec.partner_id
            if not partner:
                continue
            if not rec.name:
                rec.name = partner.name
            if not rec.contact_phone:
                rec.contact_phone = partner.phone
            if not rec.contact_email:
                rec.contact_email = partner.email

    @api.constrains('partner_id')
    def _check_partner_is_company(self):
        for rec in self:
            partner = rec.partner_id
            if partner and not partner.is_company:
                raise ValidationError(_(
                    'Un Compte Société doit être lié à un partenaire de type entreprise.'
                ))

    @api.constrains('partner_id')
    def _check_partner_is_not_mobile_user(self):
        """Un utilisateur mobile existant ne doit pas devenir Compte Société.

        Doctrine v3.3:
        - ne pas modifier le signup mobile ;
        - ne pas spécialiser les réponses API mobile pour les sociétés ;
        - empêcher seulement côté back-office qu'un compte mobile existant
          soit requalifié en Compte Société.
        """
        fuel_user_xmlid = 'acpec_fueltoken_base.group_fuel_user'
        for rec in self:
            partner = rec.partner_id
            if not partner:
                continue
            users = self.env['res.users'].sudo().with_context(active_test=False).search([
                ('partner_id', '=', partner.id),
            ])
            for user in users:
                if user.has_group(fuel_user_xmlid):
                    raise ValidationError(_(
                        'Ce partenaire est déjà lié à un utilisateur mobile FuelToken. '
                        'Un utilisateur mobile existant ne peut pas devenir Compte Société.'
                    ))

    @api.constrains('partner_id', 'member_partner_ids')
    def _check_members_are_valid_partners(self):
        for rec in self:
            if not rec.member_partner_ids:
                continue
            if rec.partner_id and rec.partner_id in rec.member_partner_ids:
                raise ValidationError(_(
                    'La société partenaire ne peut pas être listée comme membre de son propre Compte Société.'
                ))
            company_members = rec.member_partner_ids.filtered('is_company')
            if company_members:
                raise ValidationError(_(
                    'Les membres d’un Compte Société doivent être des partenaires individuels, pas des sociétés.'
                ))

    def action_activate(self):
        self.write({'state': 'active', 'active': True})
        return True

    def action_suspend(self):
        self.write({'state': 'suspended'})
        return True

    def action_close(self):
        self.write({'state': 'closed', 'active': False})
        return True

    def action_reset_to_draft(self):
        self.write({'state': 'draft', 'active': True})
        return True

    def unlink(self):
        raise UserError(_(
            'Les Comptes Sociétés ne doivent pas être supprimés. '
            'Archivez ou clôturez le compte pour conserver la traçabilité.'
        ))

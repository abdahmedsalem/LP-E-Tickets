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
        help=(
            'Partenaire entreprise représentant le Compte Société. '
            'Ce partenaire doit déjà avoir un accès portail Odoo standard.'
        ),
    )
    company_id = fields.Many2one(
        'res.company',
        string='Société Odoo',
        required=True,
        default=lambda self: self.env.company,
        index=True,
        tracking=True,
    )
    wallet_id = fields.Many2one(
        'acpec.fuel.wallet',
        string='Wallet société',
        compute='_compute_wallet_state',
        readonly=True,
        help='Wallet FuelToken technique du Compte Société, créé à la demande.',
    )
    has_wallet = fields.Boolean(
        string='Wallet société existant',
        compute='_compute_wallet_state',
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
    member_wallet_count = fields.Integer(
        string='Wallets membres existants',
        compute='_compute_member_wallet_state',
    )
    member_mobile_ready_count = fields.Integer(
        string='Membres mobile actifs',
        compute='_compute_member_wallet_state',
    )
    member_mobile_missing_count = fields.Integer(
        string='Membres mobile non prêts',
        compute='_compute_member_wallet_state',
    )

    portal_user_ids = fields.Many2many(
        'res.users',
        string='Utilisateurs portail actifs',
        compute='_compute_partner_user_state',
        readonly=True,
        help='Utilisateurs portail Odoo actifs liés à la société partenaire.',
    )
    portal_user_count = fields.Integer(
        string='Nombre utilisateurs portail',
        compute='_compute_partner_user_state',
    )
    has_portal_user = fields.Boolean(
        string='Accès portail actif',
        compute='_compute_partner_user_state',
    )
    blocked_user_ids = fields.Many2many(
        'res.users',
        string='Utilisateurs incompatibles',
        compute='_compute_partner_user_state',
        readonly=True,
        help=(
            'Utilisateurs liés à la société partenaire avec des groupes incompatibles '
            '(interne Odoo, mobile FuelToken, station ou back-office FuelToken).'
        ),
    )
    blocked_user_count = fields.Integer(
        string='Nombre utilisateurs incompatibles',
        compute='_compute_partner_user_state',
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

    def _get_group(self, xmlid):
        return self.env.ref(xmlid, raise_if_not_found=False)

    def _user_has_group_id(self, user, group_id):
        """Return True if the given user belongs to group_id.

        Odoo 19 no longer exposes groups_id as a searchable ORM field on
        res.users in this environment. We therefore check the standard relation
        table directly instead of using domains such as ('groups_id', 'in', ...).
        """
        if not user or not group_id:
            return False
        self.env.cr.execute(
            """
            SELECT 1
              FROM res_groups_users_rel
             WHERE uid = %s
               AND gid = %s
             LIMIT 1
            """,
            (user.id, group_id),
        )
        return bool(self.env.cr.fetchone())

    def _user_has_any_group_ids(self, user, group_ids):
        if not user or not group_ids:
            return False
        self.env.cr.execute(
            """
            SELECT 1
              FROM res_groups_users_rel
             WHERE uid = %s
               AND gid = ANY(%s)
             LIMIT 1
            """,
            (user.id, list(group_ids)),
        )
        return bool(self.env.cr.fetchone())

    def _get_disallowed_company_partner_groups(self):
        """Groups that make a partner incompatible with Compte Société.

        A Compte Société partner must be a portal partner only. It must not be
        a mobile user, station user, FuelToken back-office user, or internal
        Odoo user. This keeps the company portal flow separate from mobile and
        ACPEC back-office flows.
        """
        xmlids = [
            'base.group_user',
            'acpec_fueltoken_base.group_fuel_user',
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
            'acpec_fueltoken_base.group_fuel_admin',
        ]
        return self.env['res.groups'].browse([
            group.id
            for group in (self._get_group(xmlid) for xmlid in xmlids)
            if group
        ])

    def _get_partner_users(self, partner):
        if not partner:
            return self.env['res.users']
        return self.env['res.users'].sudo().with_context(active_test=False).search([
            ('partner_id', '=', partner.id),
        ])

    def _split_partner_users(self, partner):
        users = self._get_partner_users(partner)
        portal_group = self._get_group('base.group_portal')
        disallowed_groups = self._get_disallowed_company_partner_groups()

        if portal_group:
            portal_users = users.filtered(
                lambda user: user.active and self._user_has_group_id(user, portal_group.id)
            )
        else:
            portal_users = self.env['res.users']

        blocked_users = users.filtered(
            lambda user: self._user_has_any_group_ids(user, disallowed_groups.ids)
        )
        return portal_users, blocked_users

    @api.depends('partner_id', 'company_id')
    def _compute_wallet_state(self):
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        for rec in self:
            wallet = self.env['acpec.fuel.wallet']
            if rec.partner_id and rec.company_id:
                wallet = Wallet.search([
                    ('partner_id', '=', rec.partner_id.id),
                    ('company_id', '=', rec.company_id.id),
                ], limit=1)
            rec.wallet_id = wallet
            rec.has_wallet = bool(wallet)

    @api.depends('member_partner_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_partner_ids)

    @api.depends('member_partner_ids', 'company_id')
    def _compute_member_wallet_state(self):
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        for rec in self:
            wallet_count = 0
            mobile_ready_count = 0
            if rec.member_partner_ids and rec.company_id:
                wallet_count = Wallet.search_count([
                    ('partner_id', 'in', rec.member_partner_ids.ids),
                    ('company_id', '=', rec.company_id.id),
                ])
                for member in rec.member_partner_ids:
                    if rec._get_active_mobile_user_for_member(member):
                        mobile_ready_count += 1
            rec.member_wallet_count = wallet_count
            rec.member_mobile_ready_count = mobile_ready_count
            rec.member_mobile_missing_count = max(len(rec.member_partner_ids) - mobile_ready_count, 0)

    @api.depends('partner_id')
    def _compute_partner_user_state(self):
        for rec in self:
            portal_users, blocked_users = rec._split_partner_users(rec.partner_id)
            rec.portal_user_ids = portal_users
            rec.portal_user_count = len(portal_users)
            rec.has_portal_user = bool(portal_users)
            rec.blocked_user_ids = blocked_users
            rec.blocked_user_count = len(blocked_users)

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
    def _check_partner_is_company_portal_only(self):
        for rec in self:
            partner = rec.partner_id
            if not partner:
                continue

            if not partner.is_company:
                raise ValidationError(_(
                    'Un Compte Société doit être lié à un partenaire de type entreprise.'
                ))

            portal_users, blocked_users = rec._split_partner_users(partner)

            if blocked_users:
                raise ValidationError(_(
                    'La société partenaire est déjà liée à un utilisateur interne, mobile, station ou back-office FuelToken. '
                    'Un Compte Société doit être lié uniquement à un partenaire société avec accès portail Odoo standard.'
                ))

            if not portal_users:
                raise ValidationError(_(
                    'La société partenaire doit d’abord avoir un accès portail Odoo standard. '
                    'Depuis la fiche Contact de la société, utilisez : Donner accès au portail.'
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

    # -------------------------------------------------------------------------
    # Backend distribution API — called later by FuelToken_WebClient / portal
    # -------------------------------------------------------------------------

    def _get_company_wallet(self, create=False):
        self.ensure_one()
        if not self.partner_id or not self.company_id:
            return self.env['acpec.fuel.wallet']
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        if create:
            return Wallet.get_or_create(self.partner_id, self.company_id)
        return Wallet.search([
            ('partner_id', '=', self.partner_id.id),
            ('company_id', '=', self.company_id.id),
        ], limit=1)

    def _get_member_wallet(self, member_partner, create=False):
        self.ensure_one()
        if not member_partner or not self.company_id:
            return self.env['acpec.fuel.wallet']
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        if create:
            return Wallet.get_or_create(member_partner, self.company_id)
        return Wallet.search([
            ('partner_id', '=', member_partner.id),
            ('company_id', '=', self.company_id.id),
        ], limit=1)

    def _get_active_mobile_user_for_member(self, member_partner):
        """Return a validated mobile FuelToken user for a member partner.

        The method deliberately does not approve or modify the mobile account.
        It only checks the existing mobile state used by the mobile flow.
        """
        self.ensure_one()
        if not member_partner or not self.company_id:
            return self.env['res.users']

        fuel_user_group = self._get_group('acpec_fueltoken_base.group_fuel_user')
        if not fuel_user_group:
            return self.env['res.users']

        users = self.env['res.users'].sudo().search([
            ('partner_id', '=', member_partner.id),
            ('active', '=', True),
            ('company_ids', 'in', [self.company_id.id]),
        ])
        return users.filtered(
            lambda user: self._user_has_group_id(user, fuel_user_group.id)
            and getattr(user, 'mobile_state', False) == 'approved'
        )[:1]

    def _check_can_distribute_to_member(self, member_partner):
        self.ensure_one()

        if not self.active or self.state != 'active':
            raise ValidationError(_(
                'Le Compte Société doit être actif pour distribuer des carnets.'
            ))

        # Recheck portal-only contract at distribution time, not only at creation.
        self._check_partner_is_company_portal_only()

        if not member_partner:
            raise ValidationError(_('Le membre destinataire est obligatoire.'))

        if member_partner not in self.member_partner_ids:
            raise ValidationError(_(
                'Le destinataire du transfert doit être un membre du Compte Société source.'
            ))

        if member_partner.is_company:
            raise ValidationError(_(
                'La distribution société est autorisée uniquement vers des membres individuels.'
            ))

        mobile_user = self._get_active_mobile_user_for_member(member_partner)
        if not mobile_user:
            raise ValidationError(_(
                'Le membre destinataire doit avoir un compte mobile FuelToken actif et approuvé '
                'avant de recevoir une distribution société.'
            ))

        return mobile_user

    def _prepare_distribution_line_vals(self, lines):
        """Normalize lines for acpec.fuel.carnet.transfer.line.

        Expected input from backend/webclient:
        [{'face_line_id': 10, 'carnet_qty': 2}, ...]
        """
        self.ensure_one()
        if not lines:
            raise ValidationError(_('Au moins une ligne de distribution est requise.'))

        line_vals = []
        seen_face_line_ids = set()
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        company_wallet = self._get_company_wallet(create=True)

        for item in lines:
            face_line_id = int(item.get('face_line_id') or 0)
            carnet_qty = int(item.get('carnet_qty') or 0)
            if face_line_id <= 0:
                raise ValidationError(_("Paramètre 'face_line_id' invalide ou manquant."))
            if carnet_qty <= 0:
                raise ValidationError(_("Paramètre 'carnet_qty' doit être un entier positif."))
            if face_line_id in seen_face_line_ids:
                raise ValidationError(_(
                    'Une même ligne de tickets ne peut pas apparaître plusieurs fois dans une distribution.'
                ))
            seen_face_line_ids.add(face_line_id)

            face_line = FaceLine.browse(face_line_id).exists()
            if not face_line:
                raise ValidationError(_('Ligne de tickets introuvable: %s.') % face_line_id)
            if face_line.wallet_id != company_wallet:
                raise ValidationError(_(
                    "La ligne de tickets '%s' n’appartient pas au wallet du Compte Société."
                ) % (face_line.carnet_type_id.code or face_line.id))
            if not face_line.is_transferable_carnet_line():
                raise ValidationError(_(
                    "La ligne de tickets '%s' n’est pas transférable en carnets intacts."
                ) % (face_line.carnet_type_id.code or face_line.id))
            if carnet_qty > face_line.transferable_carnet_count():
                raise ValidationError(_(
                    "Carnets insuffisants pour '%s' : %d disponibles, %d demandés."
                ) % (
                    face_line.carnet_type_id.code or face_line.id,
                    face_line.transferable_carnet_count(),
                    carnet_qty,
                ))

            line_vals.append({
                'face_line_id': face_line.id,
                'carnet_qty': carnet_qty,
            })

        return line_vals

    def action_prepare_member_wallets(self):
        """Create technical wallets for members that already have approved mobile accounts.

        This action never approves mobile users and never changes mobile_state.
        """
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        messages = []

        for distributor in self:
            if not distributor.active or distributor.state != 'active':
                raise ValidationError(_(
                    'Le Compte Société doit être actif pour préparer les wallets membres.'
                ))

            created = 0
            already_existing = 0
            not_mobile_ready = []

            for member in distributor.member_partner_ids:
                if not distributor._get_active_mobile_user_for_member(member):
                    not_mobile_ready.append(member.display_name)
                    continue

                before = Wallet.search([
                    ('partner_id', '=', member.id),
                    ('company_id', '=', distributor.company_id.id),
                ], limit=1)
                Wallet.get_or_create(member, distributor.company_id)
                if before:
                    already_existing += 1
                else:
                    created += 1

            message = _(
                'Préparation des wallets membres terminée. Créés: %(created)s. Déjà existants: %(existing)s. Membres mobile non prêts: %(missing)s.'
            ) % {
                'created': created,
                'existing': already_existing,
                'missing': len(not_mobile_ready),
            }
            if not_mobile_ready:
                message += '<br/>' + _('Membres mobile non prêts: %s') % ', '.join(not_mobile_ready)
            distributor.message_post(body=message)
            messages.append(message)

        if len(self) == 1:
            return {
                'type': 'ir.actions.client',
                'tag': 'display_notification',
                'params': {
                    'title': _('Wallets membres'),
                    'message': messages[0],
                    'sticky': False,
                    'type': 'success',
                },
            }
        return True

    def action_distribute_to_member(self, member_partner, lines, note=False, idempotency_key=False, confirm=True):
        """Backend method for controlled company distribution to one member.

        This is the method that FuelToken_WebClient / portal should call later.
        It uses the existing acpec.fuel.carnet.transfer engine and does not
        duplicate transfer accounting logic.
        """
        self.ensure_one()
        member_partner = self.env['res.partner'].sudo().browse(
            member_partner.id if hasattr(member_partner, 'id') else int(member_partner or 0)
        ).exists()
        if not member_partner:
            raise ValidationError(_('Membre destinataire introuvable.'))

        self._check_can_distribute_to_member(member_partner)
        company_wallet = self._get_company_wallet(create=True)
        member_wallet = self._get_member_wallet(member_partner, create=True)

        if idempotency_key:
            existing = self.env['acpec.fuel.carnet.transfer'].sudo().search([
                ('source_wallet_id', '=', company_wallet.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing:
                if confirm and existing.state == 'draft':
                    existing.action_confirm()
                return existing

        transfer_line_vals = self._prepare_distribution_line_vals(lines)
        transfer_vals = {
            'source_wallet_id': company_wallet.id,
            'dest_wallet_id': member_wallet.id,
            'company_id': self.company_id.id,
            'note': note or _('Distribution société %s vers %s') % (
                self.display_name,
                member_partner.display_name,
            ),
            'idempotency_key': idempotency_key or False,
            'line_ids': [(0, 0, vals) for vals in transfer_line_vals],
        }
        transfer = self.env['acpec.fuel.carnet.transfer'].sudo().create(transfer_vals)
        if confirm:
            transfer.action_confirm()

        self.message_post(body=_(
            'Distribution société vers %(member)s: %(transfer)s, %(qty)s tickets.'
        ) % {
            'member': member_partner.display_name,
            'transfer': transfer.name,
            'qty': transfer.face_qty_total,
        })
        return transfer

    def action_distribute_bulk(self, distribution_lines, idempotency_key=False):
        """Backend helper for later bulk distribution from the webclient.

        Expected input:
        [
            {'member_partner_id': 10, 'lines': [{'face_line_id': 20, 'carnet_qty': 1}], 'note': '...'},
            ...
        ]
        """
        self.ensure_one()
        if not distribution_lines:
            raise ValidationError(_('Au moins une distribution est requise.'))

        transfers = self.env['acpec.fuel.carnet.transfer']
        with self.env.cr.savepoint():
            for index, item in enumerate(distribution_lines, start=1):
                member_partner_id = int(item.get('member_partner_id') or 0)
                member_partner = self.env['res.partner'].sudo().browse(member_partner_id).exists()
                if not member_partner:
                    raise ValidationError(_('Membre destinataire introuvable sur la ligne %s.') % index)
                line_key = item.get('idempotency_key') or (
                    '%s-%s' % (idempotency_key, index) if idempotency_key else False
                )
                transfer = self.action_distribute_to_member(
                    member_partner,
                    item.get('lines') or [],
                    note=item.get('note') or False,
                    idempotency_key=line_key,
                    confirm=True,
                )
                transfers |= transfer
        return transfers


    def action_open_distribution_wizard(self):
        """Open the controlled back-office distribution wizard.

        The wizard is an ACPEC back-office surface. It calls the backend
        distribution method and does not bypass company/member/mobile guards.
        """
        self.ensure_one()

        if not self.active or self.state != 'active':
            raise UserError(_(
                'Le Compte Société doit être actif pour distribuer des carnets.'
            ))

        if not self.member_partner_ids:
            raise UserError(_(
                'Ajoutez au moins un membre avant de distribuer des carnets.'
            ))

        wallet = self._get_company_wallet(create=False)
        if not wallet:
            raise UserError(_(
                'Le Compte Société ne dispose pas encore de wallet alimenté. Créez et validez d’abord un achat société.'
            ))

        transferable_lines = self.env['acpec.fuel.face.line'].sudo().search([
            ('wallet_id', '=', wallet.id),
            ('qty_available', '>', 0),
        ])
        if not any(line.is_transferable_carnet_line() for line in transferable_lines):
            raise UserError(_(
                'Aucun carnet intact disponible pour distribution sur le wallet société.'
            ))

        action = {
            'type': 'ir.actions.act_window',
            'name': _('Distribuer des carnets'),
            'res_model': 'acpec.fuel.distributor.distribution.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_distributor_id': self.id,
                'active_model': self._name,
                'active_id': self.id,
            },
        }
        wizard_view = self.env.ref(
            'acpec_fueltoken_company.view_fuel_distributor_distribution_wizard_form',
            raise_if_not_found=False,
        )
        if wizard_view:
            action['views'] = [(wizard_view.id, 'form')]
        return action


    def action_create_company_purchase(self):
        """Create a controlled draft purchase for this Compte Société.

        The generic back-office lists keep create disabled by doctrine. This
        explicit button is the controlled entry point for ACPEC operators to
        open a company purchase request prefilled with the distributor partner.
        The purchase is only a draft: lines, proof of payment, submit and
        approval stay in the standard acpec.fuel.purchase workflow.
        """
        self.ensure_one()

        if not self.active or self.state != 'active':
            raise UserError(_(
                'Le Compte Société doit être actif pour créer une demande d’achat.'
            ))

        # Recheck the portal-only contract before creating an operational record.
        self._check_partner_is_company_portal_only()

        purchase = self.env['acpec.fuel.purchase'].create({
            'partner_id': self.partner_id.id,
            'company_id': self.company_id.id,
        })

        self.message_post(body=_(
            'Demande d’achat société créée: %s.'
        ) % purchase.display_name)

        form_view = self.env.ref(
            'acpec_fueltoken_purchase.view_fuel_purchase_form',
            raise_if_not_found=False,
        )
        action = {
            'type': 'ir.actions.act_window',
            'name': _('Demande d’achat société'),
            'res_model': 'acpec.fuel.purchase',
            'res_id': purchase.id,
            'view_mode': 'form',
            'target': 'current',
            'context': {
                'default_partner_id': self.partner_id.id,
                'default_company_id': self.company_id.id,
            },
        }
        if form_view:
            action['views'] = [(form_view.id, 'form')]
        return action

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

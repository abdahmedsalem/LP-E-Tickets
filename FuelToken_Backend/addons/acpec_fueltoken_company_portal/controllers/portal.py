import base64
import uuid

from werkzeug.exceptions import NotFound

from odoo import http, _
from odoo.exceptions import ValidationError, UserError
from odoo.http import request
from odoo.addons.portal.controllers.portal import CustomerPortal


class AcpecFuelTokenCompanyPortal(CustomerPortal):
    """Portal surface for Tickets Carburant company accounts.

    Access doctrine:
    - a classic Odoo portal user may see Tickets Carburant and submit a company
      purchase request for its commercial partner;
    - distribution/member/wallet functions require an active
      acpec.fuel.distributor linked to the same commercial partner;
    - member management is limited to exact phone lookup of already approved
      mobile users; no autocomplete or partial search is exposed;
    - portal access is model-backed through read ACLs and record rules, like
      standard Odoo portal documents;
    - write operations are intentionally narrow controller actions that always
      start from the current portal user context.
    """

    def _user_has_group(self, user, xmlid):
        group = request.env.ref(xmlid, raise_if_not_found=False)
        if not group:
            return False
        return user.has_group(xmlid)

    def _portal_render(self, template, values):
        qcontext = self._prepare_portal_layout_values()
        qcontext.update(values or {})
        return request.render(template, qcontext)

    def _get_portal_company(self):
        website = getattr(request, 'website', False)
        return (website and website.company_id) or request.env.company

    def _get_portal_commercial_partner(self, user):
        partner = user.sudo().partner_id
        return partner.commercial_partner_id or partner

    def _get_portal_context(self, require_distributor=False):
        user = request.env.user
        if not user or user._is_public():
            raise NotFound()

        # A Tickets Carburant company portal user is a classic Odoo portal user, not an
        # internal back-office user and not a mobile Tickets Carburant user.
        if self._user_has_group(user, 'base.group_user'):
            raise NotFound()
        if not self._user_has_group(user, 'base.group_portal'):
            raise NotFound()

        forbidden_group_xmlids = [
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_user',
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
            'acpec_fueltoken_base.group_fuel_admin',
        ]
        if any(self._user_has_group(user, xmlid) for xmlid in forbidden_group_xmlids):
            raise NotFound()

        commercial_partner = self._get_portal_commercial_partner(user).sudo()
        company = self._get_portal_company().sudo()
        distributor = request.env['acpec.fuel.distributor'].sudo().search([
            ('partner_id', '=', commercial_partner.id),
            ('active', '=', True),
            ('state', '=', 'active'),
        ], limit=1)
        if require_distributor and not distributor:
            raise NotFound()
        return {
            'user': user,
            'commercial_partner': commercial_partner,
            'company': company,
            'distributor': distributor.sudo() if distributor else False,
            'portal_company_name': company.name,
        }

    def _get_portal_distributor(self):
        return self._get_portal_context(require_distributor=True)['distributor']

    def _prepare_home_portal_values(self, counters=None):
        # Keep standard portal counters untouched. The Tickets Carburant card is
        # rendered statically in the portal template, so it must not participate
        # in the async counter mechanism that may leave a residual spinner.
        return super()._prepare_home_portal_values(counters or [])

    def _get_company_wallet(self, distributor):
        wallet = distributor._get_company_wallet(create=False)
        return wallet.sudo() if wallet else request.env['acpec.fuel.wallet'].sudo().browse()

    def _get_ticket_lines(self, wallet):
        if not wallet:
            return request.env['acpec.fuel.face.line'].sudo().browse()
        return request.env['acpec.fuel.face.line'].sudo().search([
            ('wallet_id', '=', wallet.id),
            ('qty_available', '>', 0),
        ], order='expires_at NULLS LAST, id')

    def _get_available_carnet_types(self, company):
        return request.env['acpec.fuel.carnet.type'].sudo().search([
            ('active', '=', True),
            ('company_id', '=', company.id),
        ], order='face_value, face_count, code, id')

    def _get_purchases(self, partner, company, limit=None):
        return request.env['acpec.fuel.purchase'].sudo().search([
            ('partner_id', '=', partner.id),
            ('company_id', '=', company.id),
        ], order='id desc', limit=limit)

    def _get_distributions(self, wallet, limit=None):
        if not wallet:
            return request.env['acpec.fuel.carnet.transfer'].sudo().browse()
        return request.env['acpec.fuel.carnet.transfer'].sudo().search([
            ('source_wallet_id', '=', wallet.id),
        ], order='id desc', limit=limit)

    def _normalize_phone_digits(self, value):
        return ''.join(ch for ch in (value or '') if ch.isdigit())

    def _phone_variants(self, phone):
        raw = (phone or '').strip()
        digits = self._normalize_phone_digits(raw)
        variants = {raw} if raw else set()
        if digits:
            variants.add(digits)
            variants.add('+' + digits)
            if len(digits) == 8:
                variants.add('222' + digits)
                variants.add('+222' + digits)
            if digits.startswith('222') and len(digits) > 3:
                variants.add(digits[3:])
                variants.add('+222' + digits[3:])
        return [variant for variant in variants if variant]

    def _user_has_group_id(self, user, group):
        if not user or not group:
            return False
        request.env.cr.execute(
            """
            SELECT 1
              FROM res_groups_users_rel
             WHERE uid = %s
               AND gid = %s
             LIMIT 1
            """,
            (user.id, group.id),
        )
        return bool(request.env.cr.fetchone())

    def _find_mobile_member_by_phone(self, distributor, phone):
        """Return an approved mobile user matching an exact phone.

        This is intentionally not an autocomplete and not a partial search.  The
        company portal user must know the member phone number.  This avoids
        turning the portal into a public directory of mobile users.
        """
        self._get_portal_context(require_distributor=True)
        variants = self._phone_variants(phone)
        if not variants:
            raise ValidationError(_('Saisissez un numéro de téléphone.'))

        fuel_user_group = request.env.ref('acpec_fueltoken_base.group_fuel_user', raise_if_not_found=False)
        if not fuel_user_group:
            raise ValidationError(_('Configuration mobile Tickets Carburant incomplète.'))

        Users = request.env['res.users'].sudo().with_context(active_test=False)
        candidates = Users.search([
            '|',
            ('mobile_phone', 'in', variants),
            ('login', 'in', variants),
        ], limit=20)
        target_digits = self._normalize_phone_digits(phone)
        for user in candidates:
            user_digits = self._normalize_phone_digits(user.mobile_phone or user.login)
            if user_digits != target_digits and not (user_digits.endswith(target_digits) or target_digits.endswith(user_digits)):
                continue
            if not user.active or getattr(user, 'mobile_state', False) != 'approved':
                continue
            if not self._user_has_group_id(user, fuel_user_group):
                continue
            if distributor.company_id and distributor.company_id.id not in user.company_ids.ids:
                continue
            partner = user.partner_id.sudo()
            if not partner or partner.is_company or partner == distributor.partner_id:
                continue
            return user

        raise ValidationError(_(
            'Aucun utilisateur mobile prêt trouvé pour ce numéro. Vérifiez que le membre a finalisé son inscription mobile.'
        ))

    def _build_member_rows(self, distributor):
        rows = []
        if not distributor:
            return rows
        for member in distributor.member_partner_ids.sudo().sorted(lambda p: (p.name or '', p.id)):
            mobile_user = distributor._get_active_mobile_user_for_member(member)
            rows.append({
                'partner': member,
                'name': member.display_name,
                'phone': member.phone or '',
                'email': member.email or '',
                'mobile_ready': bool(mobile_user),
                'mobile_login': mobile_user.login if mobile_user else '',
            })
        return rows

    def _build_members_page_values(self, context, error=None, success=None, phone=''):
        distributor = context['distributor']
        return {
            'page_name': 'fueltoken_company_members',
            'distributor': distributor,
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'member_rows': self._build_member_rows(distributor),
            'member_count': len(distributor.member_partner_ids) if distributor else 0,
            'error': error,
            'success': success,
            'phone': phone or '',
        }

    def _build_dashboard_values(self, context):
        distributor = context['distributor']
        commercial_partner = context['commercial_partner']
        company = context['company']
        wallet = self._get_company_wallet(distributor) if distributor else request.env['acpec.fuel.wallet'].sudo().browse()
        ticket_lines = self._get_ticket_lines(wallet)
        purchases = self._get_purchases(commercial_partner, company, limit=10)
        distributions = self._get_distributions(wallet, limit=10)

        member_rows = self._build_member_rows(distributor) if distributor else []

        ticket_rows = []
        for line in ticket_lines:
            ticket_rows.append({
                'line': line,
                'transferable_carnet_count': line.transferable_carnet_count(),
            })

        return {
            'page_name': 'fueltoken_company',
            'distributor': distributor,
            'commercial_partner': commercial_partner,
            'portal_company': company,
            'portal_company_name': context['portal_company_name'],
            'wallet': wallet,
            'ticket_lines': ticket_lines,
            'ticket_rows': ticket_rows,
            'member_rows': member_rows,
            'purchases': purchases,
            'distributions': distributions,
            'purchase_count': request.env['acpec.fuel.purchase'].sudo().search_count([
                ('partner_id', '=', commercial_partner.id),
                ('company_id', '=', company.id),
            ]),
            'distribution_count': request.env['acpec.fuel.carnet.transfer'].sudo().search_count([
                ('source_wallet_id', '=', wallet.id),
            ]) if wallet else 0,
            'member_count': len(member_rows),
            'total_tickets_available': sum(ticket_lines.mapped('qty_available')),
            'total_amount_available': sum(ticket_lines.mapped('amount_available')),
            'total_transferable_carnets': sum(row['transferable_carnet_count'] for row in ticket_rows),
        }

    def _build_purchase_form_values(self, context, error=None, form_data=None):
        form_data = form_data or {}
        carnet_types = self._get_available_carnet_types(context['company'])
        carnet_rows = []
        for carnet_type in carnet_types:
            qty = form_data.get('qty_%s' % carnet_type.id, '')
            carnet_rows.append({
                'carnet_type': carnet_type,
                'qty': qty,
            })
        return {
            'page_name': 'fueltoken_company_purchase_new',
            'distributor': context['distributor'],
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'carnet_rows': carnet_rows,
            'payment_reference': form_data.get('payment_reference', ''),
            'idempotency_key': form_data.get('idempotency_key') or str(uuid.uuid4()),
            'error': error,
        }

    def _prepare_purchase_lines_from_post(self, company, post):
        lines = []
        carnet_types = self._get_available_carnet_types(company)
        available_ids = set(carnet_types.ids)
        for carnet_type in carnet_types:
            raw_qty = post.get('qty_%s' % carnet_type.id)
            if raw_qty in (None, ''):
                continue
            try:
                carnet_qty = int(raw_qty)
            except (TypeError, ValueError):
                raise ValidationError(_('Les quantités de carnets doivent être des entiers.'))
            if carnet_qty < 0:
                raise ValidationError(_('Les quantités de carnets ne peuvent pas être négatives.'))
            if carnet_qty == 0:
                continue
            if carnet_type.id not in available_ids:
                raise ValidationError(_('Type de carnet indisponible.'))
            lines.append({
                'carnet_type_id': carnet_type.id,
                'carnet_qty': carnet_qty,
            })
        if not lines:
            raise ValidationError(_('Veuillez saisir au moins une quantité de carnets à acheter.'))
        return lines

    def _read_purchase_proof_from_post(self, post):
        upload = post.get('proof_file')
        if not upload:
            raise ValidationError(_('La preuve de paiement est obligatoire.'))
        filename = getattr(upload, 'filename', '') or _('Preuve de paiement')
        content = upload.read()
        if not content:
            raise ValidationError(_('La preuve de paiement est obligatoire.'))
        return filename, base64.b64encode(content).decode('ascii')

    @http.route(['/my/fueltoken'], type='http', auth='user', website=True)
    def portal_fueltoken_company_dashboard(self, **kwargs):
        context = self._get_portal_context(require_distributor=False)
        values = self._build_dashboard_values(context)
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_dashboard', values)

    @http.route(['/my/fueltoken/members'], type='http', auth='user', website=True)
    def portal_fueltoken_company_members(self, added=False, removed=False, **kwargs):
        context = self._get_portal_context(require_distributor=True)
        success = False
        if added:
            success = _('Membre ajouté au compte société.')
        elif removed:
            success = _('Membre retiré du compte société.')
        return self._portal_render(
            'acpec_fueltoken_company_portal.portal_fueltoken_company_members',
            self._build_members_page_values(context, success=success)
        )

    @http.route(['/my/fueltoken/members/add'], type='http', auth='user', website=True, methods=['POST'])
    def portal_fueltoken_company_member_add(self, **post):
        context = self._get_portal_context(require_distributor=True)
        distributor = context['distributor']
        phone = (post.get('phone') or '').strip()
        try:
            mobile_user = self._find_mobile_member_by_phone(distributor, phone)
            member = mobile_user.partner_id.sudo()
            if member in distributor.member_partner_ids.sudo():
                raise ValidationError(_('Ce membre est déjà rattaché au compte société.'))
            distributor.sudo().write({'member_partner_ids': [(4, member.id)]})
            distributor.sudo().message_post(body=_(
                'Membre ajouté depuis le portail: %(member)s (%(phone)s).'
            ) % {
                'member': member.display_name,
                'phone': mobile_user.mobile_phone or mobile_user.login,
            })
        except (ValidationError, UserError) as exc:
            values = self._build_members_page_values(context, error=exc.args[0], phone=phone)
            return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_members', values)
        return request.redirect('/my/fueltoken/members?added=1')

    @http.route(['/my/fueltoken/members/remove'], type='http', auth='user', website=True, methods=['POST'])
    def portal_fueltoken_company_member_remove(self, **post):
        context = self._get_portal_context(require_distributor=True)
        distributor = context['distributor']
        try:
            member_id = int(post.get('member_id') or 0)
        except (TypeError, ValueError):
            member_id = 0
        member = request.env['res.partner'].sudo().browse(member_id).exists()
        if not member or member not in distributor.member_partner_ids.sudo():
            raise NotFound()
        distributor.sudo().write({'member_partner_ids': [(3, member.id)]})
        distributor.sudo().message_post(body=_(
            'Membre retiré depuis le portail: %s.'
        ) % member.display_name)
        return request.redirect('/my/fueltoken/members?removed=1')

    @http.route(['/my/fueltoken/purchases'], type='http', auth='user', website=True)
    def portal_fueltoken_company_purchases(self, **kwargs):
        context = self._get_portal_context(require_distributor=False)
        purchases = self._get_purchases(context['commercial_partner'], context['company'])
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_purchases', {
            'page_name': 'fueltoken_company_purchases',
            'distributor': context['distributor'],
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'purchases': purchases,
        })

    @http.route(['/my/fueltoken/purchases/new'], type='http', auth='user', website=True, methods=['GET'])
    def portal_fueltoken_company_purchase_new(self, **kwargs):
        context = self._get_portal_context(require_distributor=False)
        return self._portal_render(
            'acpec_fueltoken_company_portal.portal_fueltoken_company_purchase_new',
            self._build_purchase_form_values(context)
        )

    @http.route(['/my/fueltoken/purchases/new'], type='http', auth='user', website=True, methods=['POST'])
    def portal_fueltoken_company_purchase_submit(self, **post):
        context = self._get_portal_context(require_distributor=False)
        try:
            lines = self._prepare_purchase_lines_from_post(context['company'], post)
            proof_filename, proof_data = self._read_purchase_proof_from_post(post)
            purchase = request.env['acpec.fuel.purchase'].sudo().create_from_api(
                partner=context['commercial_partner'],
                company=context['company'],
                lines=lines,
                proof_filename=proof_filename,
                proof_data=proof_data,
                payment_reference=(post.get('payment_reference') or '').strip() or False,
                idempotency_key=(post.get('idempotency_key') or '').strip() or False,
            )
        except (ValidationError, UserError) as exc:
            values = self._build_purchase_form_values(context, error=exc.args[0], form_data=post)
            return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_purchase_new', values)
        return request.redirect('/my/fueltoken/purchases/%s?created=1' % purchase.id)

    @http.route(['/my/fueltoken/purchases/<int:purchase_id>'], type='http', auth='user', website=True)
    def portal_fueltoken_company_purchase_detail(self, purchase_id, created=False, **kwargs):
        context = self._get_portal_context(require_distributor=False)
        purchase = request.env['acpec.fuel.purchase'].sudo().search([
            ('id', '=', purchase_id),
            ('partner_id', '=', context['commercial_partner'].id),
            ('company_id', '=', context['company'].id),
        ], limit=1)
        if not purchase:
            raise NotFound()
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_purchase_detail', {
            'page_name': 'fueltoken_company_purchases',
            'distributor': context['distributor'],
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'purchase': purchase,
            'created': bool(created),
        })

    @http.route(['/my/fueltoken/distributions'], type='http', auth='user', website=True)
    def portal_fueltoken_company_distributions(self, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        distributions = self._get_distributions(wallet)
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_distributions', {
            'page_name': 'fueltoken_company_distributions',
            'distributor': distributor,
            'commercial_partner': distributor.partner_id,
            'portal_company': distributor.company_id,
            'portal_company_name': distributor.company_id.name,
            'wallet': wallet,
            'distributions': distributions,
        })

    @http.route(['/my/fueltoken/distributions/<int:transfer_id>'], type='http', auth='user', website=True)
    def portal_fueltoken_company_distribution_detail(self, transfer_id, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        if not wallet:
            raise NotFound()
        transfer = request.env['acpec.fuel.carnet.transfer'].sudo().search([
            ('id', '=', transfer_id),
            ('source_wallet_id', '=', wallet.id),
        ], limit=1)
        if not transfer:
            raise NotFound()
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_distribution_detail', {
            'page_name': 'fueltoken_company_distributions',
            'distributor': distributor,
            'commercial_partner': distributor.partner_id,
            'portal_company': distributor.company_id,
            'portal_company_name': distributor.company_id.name,
            'wallet': wallet,
            'transfer': transfer,
        })

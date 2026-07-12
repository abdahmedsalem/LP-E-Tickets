import base64
import uuid

from werkzeug.exceptions import NotFound

from odoo import http, _, fields
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
      start from the current portal user context;
    - portal distributions call the company distribution engine and never
      reimplement wallet/accounting movements.
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
            ('company_id', '=', company.id),
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

    def _require_exact_company_portal_actor(
        self,
        context,
    ):
        user = context.get('user')
        distributor = context.get('distributor')

        if (
            not user
            or not distributor
            or user.partner_id.id
            != distributor.partner_id.id
        ):
            raise NotFound()

        return user

    def _get_company_wallet(self, distributor):
        wallet = distributor._get_company_wallet(create=False)
        return wallet.sudo() if wallet else request.env['acpec.fuel.wallet'].sudo().browse()

    def _get_ticket_lines(self, wallet):
        """Dashboard carnet rows.

        Patch34F: the Company Portal must not expose legacy consolidated
        face_lines as individual carnets. Only Patch34A individualized carnets
        are shown in the portal dashboard.
        """
        if not wallet:
            return request.env['acpec.fuel.face.line'].sudo().browse()
        return self._get_portal_individual_carnet_lines(wallet)

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

    def _get_ticket_transfers(self, wallet, limit=None):
        if not wallet:
            return request.env['acpec.fuel.ticket.transfer'].sudo().browse()
        return request.env['acpec.fuel.ticket.transfer'].sudo().search([
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
            if not user.active or getattr(user, 'acpec_mobile_state', False) not in ('approved', 'self_registered'):
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
            'Aucun utilisateur mobile éligible trouvé pour ce numéro. Vérifiez que le membre a finalisé son inscription mobile.'
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
        max_bytes = request.env['acpec.fuel.purchase'].sudo()._proof_upload_max_bytes()
        content = upload.read(max_bytes + 1)
        if not content:
            raise ValidationError(_('La preuve de paiement est obligatoire.'))
        if len(content) > max_bytes:
            raise ValidationError(_('La preuve de paiement depasse la taille maximale autorisee de 5 Mo.'))
        return filename, base64.b64encode(content).decode('ascii')

    def _get_transferable_face_lines(self, wallet, carnet_type=None):
        FaceLine = request.env['acpec.fuel.face.line'].sudo()
        if not wallet:
            return FaceLine.browse()
        domain = [
            ('wallet_id', '=', wallet.id),
            ('qty_available', '>', 0),
        ]
        if carnet_type:
            domain.append(('carnet_type_id', '=', carnet_type.id))
        face_lines = FaceLine.search(domain, order='expires_at NULLS LAST, lot_short_code, carnet_sequence, id')
        return face_lines.filtered(lambda line: line.is_transferable_carnet_line())

    def _get_portal_individual_carnet_lines(self, wallet):
        """Return only Patch34A individualized carnets for explicit portal selection.

        Legacy consolidated face_lines may still exist in test/old data. They can
        be technically transferable by count, but the Company Portal explicit
        contract must expose one row per real carnet only.
        """
        return self._get_transferable_face_lines(wallet).filtered(
            lambda line: bool(
                line.carnet_no
                and line.carnet_short_code
                and line.carnet_sequence
                and line.carnet_sequence > 0
                and line.transferable_carnet_count() == 1
            )
        )

    def _build_distribution_carnet_rows(self, wallet, form_data=None):
        """Return individual transferable carnets for the portal composer.

        Patch34F portal contract:
        - one row = one source carnet;
        - select by face_line_id;
        - submit carnet_qty = 1 implicitly.
        """
        form_data = form_data or {}
        selected_face_line_ids = set()
        for index in range(8):
            raw_face_line = form_data.get('line_%s_face_line_id' % index)
            try:
                face_line_id = int(raw_face_line or 0)
            except (TypeError, ValueError):
                face_line_id = 0
            if face_line_id:
                selected_face_line_ids.add(face_line_id)

        rows = []
        for face_line in self._get_transferable_face_lines(wallet):
            carnet_type = face_line.carnet_type_id
            qty_available = int(face_line.qty_available or 0)
            face_count = int(carnet_type.face_count or qty_available or 0)
            amount_available = float(face_line.amount_available or (qty_available * (face_line.face_value or 0.0)))
            carnet_label = face_line.carnet_short_code or face_line.carnet_no or str(face_line.id)
            type_label = carnet_type.display_name or carnet_type.code or ''
            label = '%s — %s' % (carnet_label, type_label) if type_label else carnet_label
            currency = face_line.currency_id or carnet_type.currency_id or wallet.currency_id
            rows.append({
                'face_line': face_line,
                'face_line_id': face_line.id,
                'carnet_label': carnet_label,
                'label': label,
                'carnet_type': carnet_type,
                'qty_available': qty_available,
                'transferable_carnet_count': 1,
                'amount_available': amount_available,
                'face_count': face_count,
                'amount_per_carnet': amount_available,
                'currency_name': currency.name if currency else '',
                'expires_at': face_line.expires_at.strftime('%Y-%m-%d %H:%M') if face_line.expires_at else '',
                'selected': face_line.id in selected_face_line_ids,
            })
        return rows

    def _build_distribution_line_slots(self, form_data=None, slot_count=8):
        """Return fixed UI slots for a carnet-by-carnet portal composer."""
        form_data = form_data or {}
        slots = []
        for index in range(slot_count):
            raw_face_line = form_data.get('line_%s_face_line_id' % index)
            try:
                face_line_id = int(raw_face_line or 0)
            except (TypeError, ValueError):
                face_line_id = 0
            slots.append({
                'index': index,
                'face_line_id': face_line_id,
                'visible': index == 0 or bool(face_line_id),
            })
        return slots

    def _distribution_carnet_catalog_by_id(self, carnet_rows):
        return {row['face_line_id']: row for row in carnet_rows}

    def _build_distribution_totals(self, carnet_rows, currency_name=False):
        return {
            'qty_available': sum(row.get('qty_available', 0) for row in carnet_rows),
            'transferable_carnet_count': sum(row.get('transferable_carnet_count', 0) for row in carnet_rows),
            'amount_available': sum(row.get('amount_available', 0) for row in carnet_rows),
            'selected_carnet_qty': 0,
            'selected_ticket_qty': 0,
            'selected_amount_total': 0,
            'currency_name': currency_name or '',
        }

    def _build_selected_distribution_totals(self, carnet_rows, line_slots, currency_name=False):
        catalog = self._distribution_carnet_catalog_by_id(carnet_rows)
        selected_carnet_qty = 0
        selected_ticket_qty = 0
        selected_amount_total = 0.0
        for slot in line_slots:
            row = catalog.get(slot.get('face_line_id'))
            if not row:
                continue
            selected_carnet_qty += 1
            selected_ticket_qty += int(row.get('qty_available') or row.get('face_count') or 0)
            selected_amount_total += float(row.get('amount_per_carnet') or 0.0)
        return {
            'selected_carnet_qty': selected_carnet_qty,
            'selected_ticket_qty': selected_ticket_qty,
            'selected_amount_total': selected_amount_total,
            'currency_name': currency_name or '',
        }

    def _build_transfer_totals(self, transfers, currency_name=False):
        return {
            'face_qty_total': sum(transfers.mapped('face_qty_total')),
            'amount_total': sum(transfers.mapped('amount_total')),
            'currency_name': currency_name or '',
        }

    def _build_distribution_form_values(self, context, error=None, form_data=None):
        form_data = form_data or {}
        distributor = context['distributor']
        wallet = self._get_company_wallet(distributor)
        member_rows = [row for row in self._build_member_rows(distributor) if row['mobile_ready']]
        carnet_rows = self._build_distribution_carnet_rows(wallet, form_data=form_data)
        line_slots = self._build_distribution_line_slots(form_data=form_data)
        currency = (wallet and wallet.currency_id) or context['company'].currency_id
        currency_name = currency.name if currency else ''
        return {
            'page_name': 'fueltoken_company_distribution_new',
            'distributor': distributor,
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'wallet': wallet,
            'member_rows': member_rows,
            'carnet_rows': carnet_rows,
            'distribution_line_slots': line_slots,
            'distribution_totals': self._build_distribution_totals(carnet_rows, currency_name),
            'selected_distribution_totals': self._build_selected_distribution_totals(carnet_rows, line_slots, currency_name),
            'member_partner_id': int(form_data.get('member_partner_id') or 0),
            'note': form_data.get('note', ''),
            'idempotency_key': form_data.get('idempotency_key') or str(uuid.uuid4()),
            'error': error,
        }

    def _get_transferable_ticket_lines(self, wallet):
        FaceLine = request.env['acpec.fuel.face.line'].sudo()
        if not wallet:
            return FaceLine.browse()
        now = fields.Datetime.now()
        return FaceLine.search([
            ('wallet_id', '=', wallet.id),
            ('qty_available', '>', 0),
            '|',
            ('expires_at', '=', False),
            ('expires_at', '>', now),
        ], order='expires_at NULLS LAST, lot_short_code, carnet_sequence, id')

    def _build_ticket_transfer_line_rows(self, wallet, form_data=None):
        form_data = form_data or {}
        selected_qty_by_face_line_id = {}
        for index in range(8):
            try:
                face_line_id = int(form_data.get('line_%s_face_line_id' % index) or 0)
            except (TypeError, ValueError):
                face_line_id = 0
            try:
                qty_tickets = int(form_data.get('line_%s_qty_tickets' % index) or 0)
            except (TypeError, ValueError):
                qty_tickets = 0
            if face_line_id:
                selected_qty_by_face_line_id[face_line_id] = qty_tickets

        rows = []
        for face_line in self._get_transferable_ticket_lines(wallet):
            carnet_type = face_line.carnet_type_id
            qty_available = int(face_line.qty_available or 0)
            face_value = float(face_line.face_value or 0.0)
            amount_available = float(face_line.amount_available or (qty_available * face_value))
            carnet_label = face_line.carnet_short_code or face_line.carnet_no or str(face_line.id)
            type_label = carnet_type.display_name or carnet_type.code or ''
            label = '%s — %s' % (carnet_label, type_label) if type_label else carnet_label
            currency = face_line.currency_id or carnet_type.currency_id or wallet.currency_id
            rows.append({
                'face_line': face_line,
                'face_line_id': face_line.id,
                'label': label,
                'carnet_label': carnet_label,
                'carnet_type': carnet_type,
                'qty_available': qty_available,
                'face_value': face_value,
                'amount_available': amount_available,
                'currency_name': currency.name if currency else '',
                'expires_at': face_line.expires_at.strftime('%Y-%m-%d %H:%M') if face_line.expires_at else '',
                'selected_qty': selected_qty_by_face_line_id.get(face_line.id, 0),
            })
        return rows

    def _build_ticket_transfer_line_slots(self, form_data=None, slot_count=8):
        form_data = form_data or {}
        slots = []
        for index in range(slot_count):
            try:
                face_line_id = int(form_data.get('line_%s_face_line_id' % index) or 0)
            except (TypeError, ValueError):
                face_line_id = 0
            qty_tickets = form_data.get('line_%s_qty_tickets' % index) or ''
            slots.append({
                'index': index,
                'face_line_id': face_line_id,
                'qty_tickets': qty_tickets,
                'visible': index == 0 or bool(face_line_id or qty_tickets),
            })
        return slots

    def _ticket_transfer_catalog_by_id(self, ticket_rows):
        return {row['face_line_id']: row for row in ticket_rows}

    def _build_ticket_transfer_totals(self, ticket_rows, currency_name=False):
        return {
            'qty_available': sum(row.get('qty_available', 0) for row in ticket_rows),
            'amount_available': sum(row.get('amount_available', 0) for row in ticket_rows),
            'selected_ticket_qty': 0,
            'selected_amount_total': 0,
            'currency_name': currency_name or '',
        }

    def _build_selected_ticket_transfer_totals(self, ticket_rows, line_slots, currency_name=False):
        catalog = self._ticket_transfer_catalog_by_id(ticket_rows)
        selected_ticket_qty = 0
        selected_amount_total = 0.0
        for slot in line_slots:
            row = catalog.get(slot.get('face_line_id'))
            if not row:
                continue
            try:
                qty_tickets = int(slot.get('qty_tickets') or 0)
            except (TypeError, ValueError):
                qty_tickets = 0
            if qty_tickets <= 0:
                continue
            selected_ticket_qty += qty_tickets
            selected_amount_total += float(row.get('face_value') or 0.0) * qty_tickets
        return {
            'selected_ticket_qty': selected_ticket_qty,
            'selected_amount_total': selected_amount_total,
            'currency_name': currency_name or '',
        }

    def _build_ticket_transfer_form_values(self, context, error=None, form_data=None):
        form_data = form_data or {}
        distributor = context['distributor']
        wallet = self._get_company_wallet(distributor)
        member_rows = [row for row in self._build_member_rows(distributor) if row['mobile_ready']]
        ticket_rows = self._build_ticket_transfer_line_rows(wallet, form_data=form_data)
        line_slots = self._build_ticket_transfer_line_slots(form_data=form_data)
        currency = (wallet and wallet.currency_id) or context['company'].currency_id
        currency_name = currency.name if currency else ''
        return {
            'page_name': 'fueltoken_company_ticket_transfer_new',
            'distributor': distributor,
            'commercial_partner': context['commercial_partner'],
            'portal_company': context['company'],
            'portal_company_name': context['portal_company_name'],
            'wallet': wallet,
            'member_rows': member_rows,
            'ticket_rows': ticket_rows,
            'ticket_transfer_line_slots': line_slots,
            'ticket_transfer_totals': self._build_ticket_transfer_totals(ticket_rows, currency_name),
            'selected_ticket_transfer_totals': self._build_selected_ticket_transfer_totals(ticket_rows, line_slots, currency_name),
            'member_partner_id': int(form_data.get('member_partner_id') or 0),
            'note': form_data.get('note', ''),
            'idempotency_key': form_data.get('idempotency_key') or str(uuid.uuid4()),
            'error': error,
        }

    def _parse_ticket_transfer_lines_from_post(self, wallet, post):
        if not wallet:
            raise ValidationError(_('Le Compte Société ne dispose d’aucun wallet source.'))

        allowed_lines = self._get_transferable_ticket_lines(wallet)
        allowed_by_id = {line.id: line for line in allowed_lines}
        selected_lines = []
        seen_face_line_ids = set()

        for index in range(8):
            raw_face_line = post.get('line_%s_face_line_id' % index)
            raw_qty = post.get('line_%s_qty_tickets' % index)
            if raw_face_line in (None, '') and raw_qty in (None, ''):
                continue
            try:
                face_line_id = int(raw_face_line or 0)
            except (TypeError, ValueError):
                raise ValidationError(_('Carnet source invalide sur une ligne de transfert tickets.'))
            try:
                qty_tickets = int(raw_qty or 0)
            except (TypeError, ValueError):
                raise ValidationError(_('Les quantités de tickets doivent être des entiers.'))
            if face_line_id <= 0:
                raise ValidationError(_('Sélectionnez un carnet source pour chaque ligne renseignée.'))
            if qty_tickets <= 0:
                raise ValidationError(_('La quantité de tickets doit être positive pour chaque ligne renseignée.'))
            if face_line_id in seen_face_line_ids:
                raise ValidationError(_('Un même carnet ne peut pas apparaître plusieurs fois dans un transfert de tickets.'))
            if face_line_id not in allowed_by_id:
                raise ValidationError(_('Carnet source indisponible pour transfert de tickets.'))
            face_line = allowed_by_id[face_line_id]
            if qty_tickets > int(face_line.qty_available or 0):
                raise ValidationError(_(
                    "Tickets disponibles insuffisants pour '%s' : %d disponibles, %d demandés."
                ) % (
                    face_line.carnet_short_code or face_line.carnet_no or face_line.id,
                    face_line.qty_available,
                    qty_tickets,
                ))
            seen_face_line_ids.add(face_line_id)
            selected_lines.append({
                'face_line_id': face_line_id,
                'qty_tickets': qty_tickets,
            })

        if not selected_lines:
            raise ValidationError(_('Veuillez sélectionner au moins une quantité de tickets à transférer.'))
        return selected_lines

    def _allocate_carnets_from_company_wallet(self, wallet, carnet_type, carnet_qty):
        """Legacy allocation by type kept for compatibility/back-office fallback."""
        if not wallet:
            raise ValidationError(_('Le Compte Société ne dispose d’aucun wallet source.'))
        remaining = int(carnet_qty or 0)
        if remaining <= 0:
            return []
        allocations = []
        for face_line in self._get_transferable_face_lines(wallet, carnet_type=carnet_type):
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

    def _parse_distribution_selected_face_lines(self, wallet, post):
        """Parse Patch34F explicit portal contract: one selected face_line_id = one carnet."""
        allowed_lines = self._get_portal_individual_carnet_lines(wallet)
        allowed_by_id = {line.id: line for line in allowed_lines}
        selected_lines = []
        seen_face_line_ids = set()

        for index in range(8):
            raw_face_line = post.get('line_%s_face_line_id' % index)
            if raw_face_line in (None, ''):
                continue
            try:
                face_line_id = int(raw_face_line or 0)
            except (TypeError, ValueError):
                raise ValidationError(_('Carnet source invalide sur une ligne de distribution.'))
            if face_line_id <= 0:
                continue
            if face_line_id in seen_face_line_ids:
                raise ValidationError(_('Un même carnet ne peut pas apparaître plusieurs fois dans une distribution.'))
            if face_line_id not in allowed_by_id:
                raise ValidationError(_('Carnet source indisponible ou non transférable.'))
            seen_face_line_ids.add(face_line_id)
            selected_lines.append({
                'face_line_id': face_line_id,
                'carnet_qty': 1,
            })

        return selected_lines

    def _parse_distribution_selected_by_type(self, wallet, post):
        """Legacy fallback for the previous type + quantity portal contract."""
        allowed_type_ids = set(self._get_transferable_face_lines(wallet).mapped('carnet_type_id').ids)
        selected_by_type = {}

        for index in range(8):
            raw_type = post.get('line_%s_carnet_type_id' % index)
            raw_qty = post.get('line_%s_qty' % index)
            if raw_type in (None, '') and raw_qty in (None, ''):
                continue
            try:
                carnet_type_id = int(raw_type or 0)
            except (TypeError, ValueError):
                raise ValidationError(_('Type de carnet invalide sur une ligne de distribution.'))
            try:
                carnet_qty = int(raw_qty or 0)
            except (TypeError, ValueError):
                raise ValidationError(_('Les quantités de carnets doivent être des entiers.'))
            if carnet_qty < 0:
                raise ValidationError(_('Les quantités de carnets ne peuvent pas être négatives.'))
            if carnet_qty == 0 and not carnet_type_id:
                continue
            if not carnet_type_id:
                raise ValidationError(_('Sélectionnez un type de carnet pour chaque ligne renseignée.'))
            if carnet_type_id not in allowed_type_ids:
                raise ValidationError(_('Type de carnet indisponible.'))
            if carnet_qty <= 0:
                raise ValidationError(_('Le nombre de carnets doit être positif pour chaque ligne renseignée.'))
            selected_by_type[carnet_type_id] = selected_by_type.get(carnet_type_id, 0) + carnet_qty

        if not selected_by_type:
            for carnet_type_id in allowed_type_ids:
                raw_qty = post.get('qty_%s' % carnet_type_id)
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
                selected_by_type[carnet_type_id] = selected_by_type.get(carnet_type_id, 0) + carnet_qty

        return selected_by_type

    def _prepare_distribution_lines_from_post(self, distributor, wallet, post):
        if not wallet:
            raise ValidationError(_('Le Compte Société ne dispose d’aucun wallet source.'))

        selected_lines = self._parse_distribution_selected_face_lines(wallet, post)
        if selected_lines:
            return selected_lines

        selected_by_type = self._parse_distribution_selected_by_type(wallet, post)
        if not selected_by_type:
            raise ValidationError(_('Veuillez sélectionner au moins un carnet à distribuer.'))

        selected_lines = []
        for carnet_type_id, carnet_qty in selected_by_type.items():
            carnet_type = request.env['acpec.fuel.carnet.type'].sudo().browse(carnet_type_id).exists()
            if not carnet_type:
                raise ValidationError(_('Type de carnet indisponible.'))
            selected_lines.extend(self._allocate_carnets_from_company_wallet(wallet, carnet_type, carnet_qty))
        return selected_lines

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
            purchase = request.env['acpec.fuel.purchase'].create_from_api(
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

    @http.route(['/my/fueltoken/distributions/new'], type='http', auth='user', website=True, methods=['GET'])
    def portal_fueltoken_company_distribution_new(self, **kwargs):
        context = self._get_portal_context(require_distributor=True)
        return self._portal_render(
            'acpec_fueltoken_company_portal.portal_fueltoken_company_distribution_new',
            self._build_distribution_form_values(context)
        )

    @http.route(['/my/fueltoken/distributions/new'], type='http', auth='user', website=True, methods=['POST'])
    def portal_fueltoken_company_distribution_submit(self, **post):
        context = self._get_portal_context(require_distributor=True)
        distributor = context['distributor']
        operator_user = self._require_exact_company_portal_actor(
            context
        )
        wallet = self._get_company_wallet(distributor)
        try:
            member_id = int(post.get('member_partner_id') or 0)
        except (TypeError, ValueError):
            member_id = 0
        try:
            member = request.env['res.partner'].sudo().browse(member_id).exists()
            if not member or member not in distributor.member_partner_ids.sudo():
                raise ValidationError(_('Sélectionnez un membre autorisé.'))
            if not distributor._get_active_mobile_user_for_member(member):
                raise ValidationError(_('Le membre sélectionné n’a pas de compte mobile actif et éligible.'))
            lines = self._prepare_distribution_lines_from_post(distributor, wallet, post)
            transfer = distributor.sudo().action_distribute_to_member(
                member,
                lines,
                note=(post.get('note') or '').strip() or False,
                idempotency_key=(post.get('idempotency_key') or '').strip() or False,
                confirm=True,
                operator_user=operator_user,
            )
        except (ValidationError, UserError) as exc:
            values = self._build_distribution_form_values(context, error=exc.args[0], form_data=post)
            return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_distribution_new', values)
        return request.redirect('/my/fueltoken/distributions/%s?created=1' % transfer.id)

    @http.route(['/my/fueltoken/distributions'], type='http', auth='user', website=True)
    def portal_fueltoken_company_distributions(self, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        distributions = self._get_distributions(wallet)
        currency = (wallet and wallet.currency_id) or distributor.company_id.currency_id
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_distributions', {
            'page_name': 'fueltoken_company_distributions',
            'distributor': distributor,
            'commercial_partner': distributor.partner_id,
            'portal_company': distributor.company_id,
            'portal_company_name': distributor.company_id.name,
            'wallet': wallet,
            'distributions': distributions,
            'distribution_totals': self._build_transfer_totals(distributions, currency.name if currency else ''),
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


    @http.route(['/my/fueltoken/ticket-transfers/new'], type='http', auth='user', website=True, methods=['GET'])
    def portal_fueltoken_company_ticket_transfer_new(self, **kwargs):
        context = self._get_portal_context(require_distributor=True)
        return self._portal_render(
            'acpec_fueltoken_company_portal.portal_fueltoken_company_ticket_transfer_new',
            self._build_ticket_transfer_form_values(context)
        )

    @http.route(['/my/fueltoken/ticket-transfers/new'], type='http', auth='user', website=True, methods=['POST'])
    def portal_fueltoken_company_ticket_transfer_submit(self, **post):
        context = self._get_portal_context(require_distributor=True)
        distributor = context['distributor']
        operator_user = self._require_exact_company_portal_actor(
            context
        )
        wallet = self._get_company_wallet(distributor)
        try:
            member_id = int(post.get('member_partner_id') or 0)
        except (TypeError, ValueError):
            member_id = 0
        try:
            member = request.env['res.partner'].sudo().browse(member_id).exists()
            if not member or member not in distributor.member_partner_ids.sudo():
                raise ValidationError(_('Sélectionnez un membre autorisé.'))
            if not distributor._get_active_mobile_user_for_member(member):
                raise ValidationError(_('Le membre sélectionné n’a pas de compte mobile actif et éligible.'))
            lines = self._parse_ticket_transfer_lines_from_post(wallet, post)
            transfer = distributor.sudo().action_transfer_tickets_to_member(
                member,
                lines,
                note=(post.get('note') or '').strip() or False,
                idempotency_key=(post.get('idempotency_key') or '').strip() or False,
                confirm=True,
                operator_user=operator_user,
            )
        except (ValidationError, UserError) as exc:
            values = self._build_ticket_transfer_form_values(context, error=exc.args[0], form_data=post)
            return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_ticket_transfer_new', values)
        return request.redirect('/my/fueltoken/ticket-transfers/%s?created=1' % transfer.id)

    @http.route(['/my/fueltoken/ticket-transfers'], type='http', auth='user', website=True)
    def portal_fueltoken_company_ticket_transfers(self, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        transfers = self._get_ticket_transfers(wallet)
        currency = (wallet and wallet.currency_id) or distributor.company_id.currency_id
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_ticket_transfers', {
            'page_name': 'fueltoken_company_ticket_transfers',
            'distributor': distributor,
            'commercial_partner': distributor.partner_id,
            'portal_company': distributor.company_id,
            'portal_company_name': distributor.company_id.name,
            'wallet': wallet,
            'ticket_transfers': transfers,
            'ticket_transfer_totals': self._build_transfer_totals(transfers, currency.name if currency else ''),
        })

    @http.route(['/my/fueltoken/ticket-transfers/<int:transfer_id>'], type='http', auth='user', website=True)
    def portal_fueltoken_company_ticket_transfer_detail(self, transfer_id, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        if not wallet:
            raise NotFound()
        transfer = request.env['acpec.fuel.ticket.transfer'].sudo().search([
            ('id', '=', transfer_id),
            ('source_wallet_id', '=', wallet.id),
        ], limit=1)
        if not transfer:
            raise NotFound()
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_ticket_transfer_detail', {
            'page_name': 'fueltoken_company_ticket_transfers',
            'distributor': distributor,
            'commercial_partner': distributor.partner_id,
            'portal_company': distributor.company_id,
            'portal_company_name': distributor.company_id.name,
            'wallet': wallet,
            'transfer': transfer,
        })

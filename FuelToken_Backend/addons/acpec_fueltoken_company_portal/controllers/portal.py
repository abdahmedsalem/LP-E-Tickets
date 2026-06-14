from werkzeug.exceptions import NotFound

from odoo import http
from odoo.http import request
from odoo.addons.portal.controllers.portal import CustomerPortal


class AcpecFuelTokenCompanyPortal(CustomerPortal):
    """Read-only portal surface for FuelToken company accounts.

    Access doctrine:
    - a normal Odoo portal user can access FuelToken company pages only when
      its commercial partner is linked to an active acpec.fuel.distributor;
    - portal access is model-backed through read ACLs and record rules, like
      standard Odoo portal documents;
    - controller checks remain the first gate; sudo is used only after that
      gate to build read-only display values that may include related contacts.
    """

    def _user_has_group(self, user, xmlid):
        group = request.env.ref(xmlid, raise_if_not_found=False)
        if not group:
            return False
        return user.has_group(xmlid)

    def _portal_render(self, template, values):
        # Use the same base qcontext as standard Odoo portal pages.  This is
        # preferable to trying to patch portal.portal_layout variables one by
        # one, and lets Odoo provide its usual sales_user/page values.
        qcontext = self._prepare_portal_layout_values()
        qcontext.update(values or {})
        return request.render(template, qcontext)

    def _get_portal_distributor(self):
        user = request.env.user
        if not user or user._is_public():
            raise NotFound()

        # A FuelToken company user is a classic Odoo portal user, not an
        # internal back-office user and not a mobile FuelToken user.
        if self._user_has_group(user, 'base.group_user'):
            raise NotFound()
        if not self._user_has_group(user, 'base.group_portal'):
            raise NotFound()

        forbidden_group_xmlids = [
            'acpec_fueltoken_base.group_fuel_user',
            'acpec_fueltoken_base.group_fuel_station',
            'acpec_fueltoken_base.group_fuel_manager',
            'acpec_fueltoken_base.group_fuel_admin',
        ]
        if any(self._user_has_group(user, xmlid) for xmlid in forbidden_group_xmlids):
            raise NotFound()

        partner = user.sudo().partner_id
        commercial_partner = partner.commercial_partner_id or partner
        distributor = request.env['acpec.fuel.distributor'].sudo().search([
            ('partner_id', '=', commercial_partner.id),
            ('active', '=', True),
            ('state', '=', 'active'),
        ], limit=1)
        if not distributor:
            raise NotFound()
        return distributor.sudo()

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

    def _get_purchases(self, distributor, limit=None):
        return request.env['acpec.fuel.purchase'].sudo().search([
            ('partner_id', '=', distributor.partner_id.id),
            ('company_id', '=', distributor.company_id.id),
        ], order='id desc', limit=limit)

    def _get_distributions(self, wallet, limit=None):
        if not wallet:
            return request.env['acpec.fuel.carnet.transfer'].sudo().browse()
        return request.env['acpec.fuel.carnet.transfer'].sudo().search([
            ('source_wallet_id', '=', wallet.id),
        ], order='id desc', limit=limit)

    def _build_dashboard_values(self, distributor):
        wallet = self._get_company_wallet(distributor)
        ticket_lines = self._get_ticket_lines(wallet)
        purchases = self._get_purchases(distributor, limit=10)
        distributions = self._get_distributions(wallet, limit=10)

        member_rows = []
        for member in distributor.member_partner_ids.sudo():
            mobile_ready = bool(distributor._get_active_mobile_user_for_member(member))
            member_rows.append({
                'name': member.display_name,
                'phone': member.phone or '',
                'email': member.email or '',
                'mobile_ready': mobile_ready,
            })

        ticket_rows = []
        for line in ticket_lines:
            ticket_rows.append({
                'line': line,
                'transferable_carnet_count': line.transferable_carnet_count(),
            })

        return {
            'page_name': 'fueltoken_company',
            'distributor': distributor,
            'wallet': wallet,
            'ticket_lines': ticket_lines,
            'ticket_rows': ticket_rows,
            'member_rows': member_rows,
            'purchases': purchases,
            'distributions': distributions,
            'purchase_count': request.env['acpec.fuel.purchase'].sudo().search_count([
                ('partner_id', '=', distributor.partner_id.id),
                ('company_id', '=', distributor.company_id.id),
            ]),
            'distribution_count': request.env['acpec.fuel.carnet.transfer'].sudo().search_count([
                ('source_wallet_id', '=', wallet.id),
            ]) if wallet else 0,
            'member_count': len(member_rows),
            'total_tickets_available': sum(ticket_lines.mapped('qty_available')),
            'total_amount_available': sum(ticket_lines.mapped('amount_available')),
            'total_transferable_carnets': sum(row['transferable_carnet_count'] for row in ticket_rows),
        }

    @http.route(['/my/fueltoken'], type='http', auth='user', website=True)
    def portal_fueltoken_company_dashboard(self, **kwargs):
        distributor = self._get_portal_distributor()
        values = self._build_dashboard_values(distributor)
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_dashboard', values)

    @http.route(['/my/fueltoken/purchases'], type='http', auth='user', website=True)
    def portal_fueltoken_company_purchases(self, **kwargs):
        distributor = self._get_portal_distributor()
        purchases = self._get_purchases(distributor)
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_purchases', {
            'page_name': 'fueltoken_company_purchases',
            'distributor': distributor,
            'purchases': purchases,
        })

    @http.route(['/my/fueltoken/purchases/<int:purchase_id>'], type='http', auth='user', website=True)
    def portal_fueltoken_company_purchase_detail(self, purchase_id, **kwargs):
        distributor = self._get_portal_distributor()
        purchase = request.env['acpec.fuel.purchase'].sudo().search([
            ('id', '=', purchase_id),
            ('partner_id', '=', distributor.partner_id.id),
            ('company_id', '=', distributor.company_id.id),
        ], limit=1)
        if not purchase:
            raise NotFound()
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_purchase_detail', {
            'page_name': 'fueltoken_company_purchases',
            'distributor': distributor,
            'purchase': purchase,
        })

    @http.route(['/my/fueltoken/distributions'], type='http', auth='user', website=True)
    def portal_fueltoken_company_distributions(self, **kwargs):
        distributor = self._get_portal_distributor()
        wallet = self._get_company_wallet(distributor)
        distributions = self._get_distributions(wallet)
        return self._portal_render('acpec_fueltoken_company_portal.portal_fueltoken_company_distributions', {
            'page_name': 'fueltoken_company_distributions',
            'distributor': distributor,
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
            'wallet': wallet,
            'transfer': transfer,
        })

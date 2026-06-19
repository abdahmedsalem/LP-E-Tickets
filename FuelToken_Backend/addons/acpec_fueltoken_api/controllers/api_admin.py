from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenAdminApi(AcpecFuelTokenApiCommon):

    def _admin_user(self):
        user = self._require_mobile_auth()
        self._require_fuel_group(user, 'manager')
        return user

    def _trusted_admin_user(self, params=None, purpose='admin_sensitive_action'):
        user = self._require_sensitive_action_pin(params or {}, purpose=purpose)
        self._require_fuel_group(user, 'manager')
        return user

    def _carnet_type_label(self, rec):
        if not rec:
            return False
        return rec.name or rec.code or _('Carnet de tickets')

    def _carnet_payload(self, rec):
        currency = rec.currency_id or rec.company_id.currency_id
        face_count = rec.face_count or 0
        face_value = rec.face_value or 0
        carnet_amount = rec.carnet_amount or (face_count * face_value)
        sequence = getattr(rec, 'sequence', 0)
        return {
            'id': rec.id,
            'code': rec.code or False,
            'name': self._carnet_type_label(rec),

            'face_count': face_count,
            'ticket_count': face_count,

            'face_value': face_value,
            'carnet_amount': carnet_amount,
            'total_amount': carnet_amount,
            'amount_total': carnet_amount,

            'validity_days': rec.validity_days or 0,
            'expiry_days': rec.validity_days or 0,

            'active': rec.active,
            'sequence': sequence,

            'company_id': rec.company_id.id if rec.company_id else False,
            'company_name': rec.company_id.name if rec.company_id else False,

            'currency_id': currency.id if currency else False,
            'currency_name': currency.name if currency else False,
            'currency_symbol': currency.symbol if currency else False,
        }

    def _purchase_payload(self, purchase, detail=False):
        data = {
            'id': purchase.id,
            'name': purchase.name,
            'public_code': purchase.public_code,
            'partner_id': purchase.partner_id.id,
            'partner_name': purchase.partner_id.name,
            'company_id': purchase.company_id.id,
            'company_name': purchase.company_id.name,
            'state': purchase.state,
            'amount_total': purchase.amount_total,
            'face_qty_total': purchase.face_qty_total,
            'payment_reference': purchase.payment_reference or False,
            'submitted_at': fields.Datetime.to_string(purchase.submitted_at) if purchase.submitted_at else False,
            'approved_at': fields.Datetime.to_string(purchase.approved_at) if purchase.approved_at else False,
            'approved_by': purchase.approved_by.name if purchase.approved_by else False,
            'rejected_at': fields.Datetime.to_string(purchase.rejected_at) if purchase.rejected_at else False,
            'rejected_by': purchase.rejected_by.name if purchase.rejected_by else False,
            'rejection_reason': purchase.rejection_reason or False,
        }
        if detail:
            data['lines'] = [{
                'id': line.id,
                'carnet_type_id': line.carnet_type_id.id,
                'carnet_type_code': line.carnet_type_id.code,
                'carnet_type_name': self._carnet_type_label(line.carnet_type_id),
                'carnet_qty': line.carnet_qty,
                'face_count': line.face_count,
                'face_value': line.face_value,
                'generated_face_qty': line.generated_face_qty,
                'amount_total': line.amount_total,
            } for line in purchase.line_ids]
            data['proof_attachments'] = [{
                'id': attachment.id,
                'name': attachment.name,
                'mimetype': attachment.mimetype or False,
                'file_size': attachment.file_size or 0,
            } for attachment in purchase.proof_attachment_ids]
        return data

    def _station_agent_payload(self, agent):
        return {
            'id': agent.id,
            'station_id': agent.station_id.id,
            'user_id': agent.user_id.id,
            'user_name': agent.user_id.name,
            'active': agent.active,
            'is_primary': agent.is_primary,
            'date_start': fields.Date.to_string(agent.date_start) if agent.date_start else False,
            'date_end': fields.Date.to_string(agent.date_end) if agent.date_end else False,
        }

    def _station_agents_payload(self, station):
        agents = station.active_agent_ids.sorted(lambda a: (not a.is_primary, a.id))
        if agents:
            return [self._station_agent_payload(agent) for agent in agents]
        if station.user_id:
            return [{
                'id': False,
                'station_id': station.id,
                'user_id': station.user_id.id,
                'user_name': station.user_id.name,
                'active': station.active,
                'is_primary': True,
                'date_start': False,
                'date_end': False,
                'source': 'legacy_user_id',
            }]
        return []

    def _station_payload(self, station):
        agents = self._station_agents_payload(station)
        return {
            'id': station.id,
            'name': station.name,
            'code': station.code or False,
            'user_id': station.user_id.id,
            'user_name': station.user_id.name,
            'company_id': station.company_id.id,
            'company_name': station.company_id.name,
            'active': station.active,
            'agents': agents,
            'agent_count': len(agents),
        }

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_list(self, **kwargs):
        try:
            user = self._admin_user()
            company_id = self._get_optional_int(kwargs, 'company_id', 0)
            if company_id:
                company = self._require_allowed_company(user, company_id)
                domain = [('company_id', '=', company.id)]
            else:
                domain = self._company_domain_for_user(user)
            active = kwargs.get('active')
            if active not in (None, False, ''):
                domain.append(('active', '=', self._get_bool_param(active)))
            records = request.env['acpec.fuel.carnet.type'].sudo().search(domain, order='face_value, face_count, code')
            return self._json_response({'items': [self._carnet_payload(rec) for rec in records], 'count': len(records)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_create(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='carnet_type_create')
            self._require_keys(kwargs, ['face_count', 'face_value'])
            company_id = self._get_optional_int(kwargs, 'company_id', user.company_id.id)
            company = self._require_allowed_company(user, company_id)
            rec = request.env['acpec.fuel.carnet.type'].sudo().create({
                'face_count': self._get_optional_int(kwargs, 'face_count', 0),
                'face_value': self._get_optional_float(kwargs, 'face_value', 0),
                'validity_days': self._get_optional_int(kwargs, 'validity_days', 365),
                'company_id': company.id,
                'active': self._get_bool_param(kwargs.get('active'), default=True),
            })
            if kwargs.get('name'):
                rec.write({'name': kwargs.get('name')})
            if kwargs.get('code'):
                rec.write({'code': kwargs.get('code')})
            return self._json_response(self._carnet_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_update(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='carnet_type_update')
            self._require_keys(kwargs, ['carnet_type_id'])
            rec = request.env['acpec.fuel.carnet.type'].sudo().browse(self._get_optional_int(kwargs, 'carnet_type_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Type de carnet introuvable.'))
            self._check_record_company_allowed(user, rec)
            vals = {}
            for key in ('name', 'code'):
                if key in kwargs:
                    vals[key] = kwargs.get(key) or False
            for key in ('face_count', 'validity_days'):
                if key in kwargs:
                    vals[key] = self._get_optional_int(kwargs, key, 0)
            if 'face_value' in kwargs:
                vals['face_value'] = self._get_optional_float(kwargs, 'face_value', 0)
            if 'active' in kwargs:
                vals['active'] = self._get_bool_param(kwargs.get('active'))
            if vals:
                rec.write(vals)
            return self._json_response(self._carnet_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/delete', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_delete(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='carnet_type_delete')
            self._require_keys(kwargs, ['carnet_type_id'])
            rec = request.env['acpec.fuel.carnet.type'].sudo().browse(self._get_optional_int(kwargs, 'carnet_type_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Type de carnet introuvable.'))
            self._check_record_company_allowed(user, rec)
            rec.write({'active': False})
            return self._json_response({'id': rec.id, 'active': rec.active})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/pending', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchases_pending(self, **kwargs):
        try:
            user = self._admin_user()
            limit, offset = self._pagination_params(kwargs, default_limit=100, max_limit=200)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            state = kwargs.get('state') or 'submitted'
            domain = self._company_domain_for_user(user)
            if state != 'all':
                domain.append(('state', '=', state))
            self._add_date_range_domain(domain, date_from, date_to, field_name='submitted_at')
            purchase_model = request.env['acpec.fuel.purchase'].sudo()
            total = purchase_model.search_count(domain)
            records = purchase_model.search(
                domain, order='id desc', limit=limit, offset=offset,
            )
            return self._json_response({
                'items': [self._purchase_payload(purchase) for purchase in records],
                **self._pagination_meta_count_only(total, limit, offset, len(records), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchase_detail(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            self._check_record_company_allowed(user, purchase)
            return self._json_response(self._purchase_payload(purchase, detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/approve', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchase_approve(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='purchase_approve')
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            self._check_record_company_allowed(user, purchase)
            purchase.with_user(user).action_approve()
            return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/reject', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchase_reject(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='purchase_reject')
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            self._check_record_company_allowed(user, purchase)
            purchase.with_user(user).action_reject()
            if kwargs.get('rejection_reason'):
                purchase.sudo().write({'rejection_reason': kwargs.get('rejection_reason')})
            return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def stations_list(self, **kwargs):
        try:
            user = self._admin_user()
            domain = self._company_domain_for_user(user)
            if kwargs.get('active') not in (None, False, ''):
                domain.append(('active', '=', self._get_bool_param(kwargs.get('active'))))
            records = request.env['acpec.fuel.station'].sudo().search(domain, order='name')
            return self._json_response({'items': [self._station_payload(station) for station in records], 'count': len(records)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_create(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='station_create')
            self._require_keys(kwargs, ['name', 'user_id'])
            company_id = self._get_optional_int(kwargs, 'company_id', user.company_id.id)
            company = self._require_allowed_company(user, company_id)
            station_user = request.env['res.users'].sudo().browse(self._get_optional_int(kwargs, 'user_id', 0)).exists()
            self._require_user_company_membership(station_user, company)
            rec = request.env['acpec.fuel.station'].sudo().create({
                'name': kwargs.get('name'),
                'code': kwargs.get('code') or False,
                'user_id': station_user.id,
                'company_id': company.id,
                'active': self._get_bool_param(kwargs.get('active'), default=True),
            })
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_update(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='station_update')
            self._require_keys(kwargs, ['station_id'])
            rec = request.env['acpec.fuel.station'].sudo().browse(self._get_optional_int(kwargs, 'station_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Station introuvable.'))
            self._check_record_company_allowed(user, rec)

            target_company = rec.company_id
            if 'company_id' in kwargs:
                target_company = self._require_allowed_company(user, self._get_optional_int(kwargs, 'company_id', 0))

            vals = {}
            for key in ('name', 'code'):
                if key in kwargs:
                    vals[key] = kwargs.get(key) or False
            if 'user_id' in kwargs:
                station_user = request.env['res.users'].sudo().browse(self._get_optional_int(kwargs, 'user_id', 0)).exists()
                self._require_user_company_membership(station_user, target_company)
                vals['user_id'] = station_user.id
            elif 'company_id' in kwargs:
                self._require_user_company_membership(rec.user_id, target_company)
            if 'company_id' in kwargs:
                vals['company_id'] = target_company.id
            if 'active' in kwargs:
                vals['active'] = self._get_bool_param(kwargs.get('active'))
            if vals:
                rec.write(vals)
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/disable', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_disable(self, **kwargs):
        try:
            user = self._trusted_admin_user(kwargs, purpose='station_disable')
            self._require_keys(kwargs, ['station_id'])
            rec = request.env['acpec.fuel.station'].sudo().browse(self._get_optional_int(kwargs, 'station_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Station introuvable.'))
            self._check_record_company_allowed(user, rec)
            rec.write({'active': False})
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/reports/summary', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def reports_summary(self, **kwargs):
        try:
            user = self._admin_user()
            company_domain = self._company_domain_for_user(user)
            Purchase = request.env['acpec.fuel.purchase'].sudo()
            Wallet = request.env['acpec.fuel.wallet'].sudo()
            Qr = request.env['acpec.fuel.qr'].sudo()
            Station = request.env['acpec.fuel.station'].sudo()
            Transaction = request.env['acpec.fuel.transaction'].sudo()
            return self._json_response({
                'purchases_submitted': Purchase.search_count(company_domain + [('state', '=', 'submitted')]),
                'purchases_approved': Purchase.search_count(company_domain + [('state', '=', 'approved')]),
                'wallets': Wallet.search_count(company_domain),
                'stations_active': Station.search_count(company_domain + [('active', '=', True)]),
                'qr_active': Qr.search_count(company_domain + [('state', '=', 'active')]),
                'qr_blocked': Qr.search_count(company_domain + [('state', '=', 'blocked')]),
                'qr_consumed': Qr.search_count(company_domain + [('state', '=', 'consumed')]),
                'qr_expired': Qr.search_count(company_domain + [('state', '=', 'expired')]),
                'transactions': Transaction.search_count(company_domain),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

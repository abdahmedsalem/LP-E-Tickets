from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AcpecFuelTokenAdminApi(AcpecMobileAuthApiCommon):

    def _admin_user(self):
        user = self._require_mobile_auth()
        self._require_fuel_group(user, 'manager')
        return user

    def _carnet_type_label(self, rec):
        face_count = int(rec.face_count or 0)
        face_value = int(rec.face_value or 0)
        if face_count > 0 and face_value > 0:
            return 'Carnet %s × %s' % (face_count, face_value)
        return rec.name or rec.code or 'Carnet'

    def _carnet_payload(self, rec):
        return {
            'id': rec.id,
            'code': rec.code,
            'name': self._carnet_type_label(rec),
            'face_count': rec.face_count,
            'face_value': rec.face_value,
            'carnet_amount': rec.carnet_amount,
            'validity_days': rec.validity_days,
            'active': rec.active,
            'company_id': rec.company_id.id,
            'company_name': rec.company_id.name,
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

    def _station_payload(self, station):
        return {
            'id': station.id,
            'name': station.name,
            'code': station.code or False,
            'user_id': station.user_id.id,
            'user_name': station.user_id.name,
            'company_id': station.company_id.id,
            'company_name': station.company_id.name,
            'active': station.active,
        }

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_type_list(self, **kwargs):
        try:
            user = self._admin_user()
            domain = []
            company_id = self._get_optional_int(kwargs, 'company_id', 0)
            if company_id:
                domain.append(('company_id', '=', company_id))
            active = kwargs.get('active')
            if active not in (None, False, ''):
                domain.append(('active', '=', self._get_bool_param(active)))
            records = request.env['acpec.fuel.carnet.type'].sudo().search(domain, order='face_value, face_count, code')
            return self._json_response({'items': [self._carnet_payload(rec) for rec in records], 'count': len(records)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_type_create(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['face_count', 'face_value'])
            company_id = self._get_optional_int(kwargs, 'company_id', user.company_id.id)
            company = request.env['res.company'].sudo().browse(company_id).exists()
            if not company:
                raise ValidationError(_('Société introuvable.'))
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

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_type_update(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['carnet_type_id'])
            rec = request.env['acpec.fuel.carnet.type'].sudo().browse(self._get_optional_int(kwargs, 'carnet_type_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Type de carnet introuvable.'))
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

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/delete', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_type_delete(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['carnet_type_id'])
            rec = request.env['acpec.fuel.carnet.type'].sudo().browse(self._get_optional_int(kwargs, 'carnet_type_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Type de carnet introuvable.'))
            rec.write({'active': False})
            return self._json_response({'id': rec.id, 'active': rec.active})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/pending', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchases_pending(self, **kwargs):
        try:
            user = self._admin_user()
            state = kwargs.get('state') or 'submitted'
            domain = [('state', '=', state)] if state != 'all' else []
            records = request.env['acpec.fuel.purchase'].sudo().search(domain, order='id desc', limit=100)
            return self._json_response({'items': [self._purchase_payload(purchase) for purchase in records], 'count': len(records)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchase_detail(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            return self._json_response(self._purchase_payload(purchase, detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/approve', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchase_approve(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            purchase.with_user(user).action_approve()
            return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/reject', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchase_reject(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['purchase_id'])
            purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            if kwargs.get('rejection_reason'):
                purchase.write({'rejection_reason': kwargs.get('rejection_reason')})
            purchase.with_user(user).action_reject()
            if kwargs.get('rejection_reason'):
                purchase.sudo().write({'rejection_reason': kwargs.get('rejection_reason')})
            return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def stations_list(self, **kwargs):
        try:
            user = self._admin_user()
            domain = []
            if kwargs.get('active') not in (None, False, ''):
                domain.append(('active', '=', self._get_bool_param(kwargs.get('active'))))
            records = request.env['acpec.fuel.station'].sudo().search(domain, order='name')
            return self._json_response({'items': [self._station_payload(station) for station in records], 'count': len(records)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def station_create(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['name', 'user_id'])
            company_id = self._get_optional_int(kwargs, 'company_id', user.company_id.id)
            rec = request.env['acpec.fuel.station'].sudo().create({
                'name': kwargs.get('name'),
                'code': kwargs.get('code') or False,
                'user_id': self._get_optional_int(kwargs, 'user_id', 0),
                'company_id': company_id,
                'active': self._get_bool_param(kwargs.get('active'), default=True),
            })
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def station_update(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['station_id'])
            rec = request.env['acpec.fuel.station'].sudo().browse(self._get_optional_int(kwargs, 'station_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Station introuvable.'))
            vals = {}
            for key in ('name', 'code'):
                if key in kwargs:
                    vals[key] = kwargs.get(key) or False
            if 'user_id' in kwargs:
                vals['user_id'] = self._get_optional_int(kwargs, 'user_id', 0)
            if 'company_id' in kwargs:
                vals['company_id'] = self._get_optional_int(kwargs, 'company_id', 0)
            if 'active' in kwargs:
                vals['active'] = self._get_bool_param(kwargs.get('active'))
            if vals:
                rec.write(vals)
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/disable', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def station_disable(self, **kwargs):
        try:
            user = self._admin_user()
            self._require_keys(kwargs, ['station_id'])
            rec = request.env['acpec.fuel.station'].sudo().browse(self._get_optional_int(kwargs, 'station_id', 0)).exists()
            if not rec:
                raise ValidationError(_('Station introuvable.'))
            rec.write({'active': False})
            return self._json_response(self._station_payload(rec))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/reports/summary', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def reports_summary(self, **kwargs):
        try:
            user = self._admin_user()
            Purchase = request.env['acpec.fuel.purchase'].sudo()
            Wallet = request.env['acpec.fuel.wallet'].sudo()
            Qr = request.env['acpec.fuel.qr'].sudo()
            Station = request.env['acpec.fuel.station'].sudo()
            Transaction = request.env['acpec.fuel.transaction'].sudo()
            return self._json_response({
                'purchases_submitted': Purchase.search_count([('state', '=', 'submitted')]),
                'purchases_approved': Purchase.search_count([('state', '=', 'approved')]),
                'wallets': Wallet.search_count([]),
                'stations_active': Station.search_count([('active', '=', True)]),
                'qr_active': Qr.search_count([('state', '=', 'active')]),
                'qr_blocked': Qr.search_count([('state', '=', 'blocked')]),
                'qr_consumed': Qr.search_count([('state', '=', 'consumed')]),
                'qr_expired': Qr.search_count([('state', '=', 'expired')]),
                'transactions': Transaction.search_count([]),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

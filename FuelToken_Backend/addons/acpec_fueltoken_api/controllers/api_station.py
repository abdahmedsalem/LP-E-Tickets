from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenStationApi(AcpecFuelTokenApiCommon):


    def _station_user(self):
        user = self._require_mobile_auth()
        self._require_fuel_group(user, 'station')
        station = request.env['acpec.fuel.station'].sudo().station_for_user(user)
        return station, user

    def _station_payload(self, station):
        return {
            'station_id': station.id,
            'name': station.name,
            'code': station.code or False,
            'company_id': station.company_id.id,
            'company_name': station.company_id.name,
            'active': station.active,
            'user_id': station.user_id.id,
            'user_name': station.user_id.name,
        }

    def _qr_check_payload(self, qr, station):
        can_consume = True
        reason = False
        if qr.state != 'active':
            can_consume = False
            reason = _('Le QR n’est pas actif.')
        elif qr.company_id != station.company_id:
            can_consume = False
            reason = _('Le QR n’appartient pas à la société de la station.')
        elif qr.expires_at and qr.expires_at <= fields.Datetime.now():
            can_consume = False
            reason = _('Le QR a expiré.')
        return {
            'qr_id': qr.id,
            'name': qr.name,
            'public_code': qr.public_code,
            'state': qr.state,
            'amount_total': qr.amount_total,
            'face_qty_total': qr.face_qty_total,
            'expires_at': fields.Datetime.to_string(qr.expires_at) if qr.expires_at else False,
            'partner_id': qr.partner_id.id,
            'partner_name': qr.partner_id.name,
            'company_id': qr.company_id.id,
            'can_consume': can_consume,
            'reason': reason,
        }

    @http.route('/api/acpec/fueltoken/v1/station/profile', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def profile(self, **kwargs):
        try:
            station, user = self._station_user()
            data = self._station_payload(station)
            data['user_profile'] = self._mobile_profile_payload(user)
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/qr/check', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def check_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code'])
            station, user = self._station_user()
            qr = request.env['acpec.fuel.qr'].sudo().search([('public_code', '=', kwargs.get('public_code'))], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))
            with request.env.cr.savepoint():
                qr._lock_records()
                qr.invalidate_recordset()
                qr.action_refresh_expiration_state()
            return self._json_response(self._qr_check_payload(qr, station))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/qr/use', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def use_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code'])
            station, user = self._station_user()
            qr = request.env['acpec.fuel.qr'].sudo().search([('public_code', '=', kwargs.get('public_code'))], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))
            tx = qr.action_consume_by_station(station, user=user, idempotency_key=kwargs.get('idempotency_key'))
            return self._json_response({
                'transaction_id': tx.id,
                'transaction_name': tx.name,
                'qr_id': qr.id,
                'qr_public_code': qr.public_code,
                'qr_state': qr.state,
                'amount_total': qr.amount_total,
                'station_id': station.id,
                'station_name': station.name,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def station_transactions(self, **kwargs):
        try:
            station, user = self._station_user()
            limit, offset = self._pagination_params(kwargs, default_limit=20, max_limit=200)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            transaction_type = self._get_clean_str(kwargs, 'transaction_type')
            domain = [('station_id', '=', station.id)]
            tx_model = request.env['acpec.fuel.transaction'].sudo()
            _tx_filter_state, _tx_filter_value, tx_filter_error = self._apply_transaction_type_filter(
                domain,
                transaction_type,
            )
            if tx_filter_error:
                return tx_filter_error
            self._add_date_range_domain(domain, date_from, date_to, field_name='create_date')
            total_count = tx_model.search_count(domain)
            records = tx_model.search(domain, order='create_date desc, id desc', limit=limit, offset=offset)
            items = []
            for tx in records:
                items.append({
                    'id': tx.id,
                    'name': tx.name,
                    'transaction_type': tx.transaction_type,
                    'amount_total': tx.amount_total,
                    'qty_total': tx.qty_total,
                    'created_at': fields.Datetime.to_string(tx.create_date) if tx.create_date else False,
                    'qr_id': tx.qr_id.id if tx.qr_id else False,
                    'qr_public_code': tx.qr_id.public_code if tx.qr_id else False,
                    'wallet_id': tx.wallet_id.id if tx.wallet_id else False,
                    'partner_id': tx.wallet_id.partner_id.id if tx.wallet_id else False,
                    'partner_name': tx.wallet_id.partner_id.name if tx.wallet_id else False,
                })
            return self._json_response({
                'station': self._station_payload(station),
                'items': items,
                **self._pagination_meta_legacy(total_count, limit, offset, len(records), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

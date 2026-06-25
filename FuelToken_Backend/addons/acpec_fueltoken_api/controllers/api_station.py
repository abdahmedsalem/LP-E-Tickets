from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenStationApi(AcpecFuelTokenApiCommon):


    def _station_for_fueltoken_user(self, user):
        self._require_fueltoken_user_company(user)
        station = request.env['acpec.fuel.station'].sudo().station_for_user(user)
        self._require_fueltoken_record_company(station)
        return station

    def _station_user(self):
        user = self._require_trusted_mobile_auth()
        self._require_fuel_group(user, 'station')
        station = self._station_for_fueltoken_user(user)
        return station, user

    def _trusted_station_user(self, params=None, purpose='station_sensitive_action'):
        user = self._require_sensitive_action_pin(params or {}, purpose=purpose)
        self._require_fuel_group(user, 'station')
        station = self._station_for_fueltoken_user(user)
        return station, user

    def _require_station_qr_company(self, qr, station):
        """Fail closed without leaking cross-company QR metadata to stations."""
        company = self._fueltoken_company()
        if not qr or qr.company_id != company or station.company_id != company:
            raise ValidationError('QR introuvable.')
        if qr.company_id != station.company_id:
            raise ValidationError('QR introuvable.')
        return qr

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
            'station_id': station.id,
            'name': station.name,
            'code': station.code or False,
            'company_id': station.company_id.id,
            'company_name': station.company_id.name,
            'active': station.active,
            'user_id': station.user_id.id,
            'user_name': station.user_id.name,
            'agents': agents,
            'agent_count': len(agents),
        }

    def _resolve_qr_from_payload(self, params):
        qr = request.env['acpec.fuel.qr'].sudo().resolve_qr_reference(
            public_code=(params or {}).get('public_code'),
            qr_numeric_code=(params or {}).get('qr_numeric_code'),
        )
        if not qr:
            raise ValidationError('QR introuvable.')
        return qr

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

    @http.route('/api/acpec/fueltoken/v1/station/profile', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def profile(self, **kwargs):
        try:
            station, user = self._station_user()
            data = self._station_payload(station)
            data['user_profile'] = self._mobile_profile_payload(user)
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/qr/check', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def check_qr(self, **kwargs):
        try:
            station, user = self._station_user()
            qr = self._resolve_qr_from_payload(kwargs)
            self._require_station_qr_company(qr, station)
            with request.env.cr.savepoint():
                qr._lock_records()
                qr.invalidate_recordset()
                qr.action_refresh_expiration_state()
            return self._json_response(self._qr_check_payload(qr, station))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/qr/use', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def use_qr(self, **kwargs):
        try:
            with self._sensitive_action_transaction(kwargs, purpose='station_qr_use') as user:
                self._require_fuel_group(user, 'station')
                station = self._station_for_fueltoken_user(user)
                idempotency_key = self._require_idempotency_key(kwargs, purpose='station_qr_use')
                qr = self._resolve_qr_from_payload(kwargs)
                self._require_station_qr_company(qr, station)
                request_hash_params = dict(kwargs)
                request_hash_params['public_code'] = qr.public_code
                request_hash_params.pop('qr_numeric_code', None)
                request_hash = self._compute_idempotency_request_hash(request_hash_params, purpose='station_qr_use')
                tx = qr.action_consume_by_station(station, user=user, idempotency_key=idempotency_key, request_hash=request_hash)
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

    @http.route('/api/acpec/fueltoken/v1/station/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_transactions(self, **kwargs):
        try:
            station, user = self._station_user()
            limit, offset = self._pagination_params(kwargs, default_limit=20, max_limit=200)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            transaction_type = self._get_clean_str(kwargs, 'transaction_type')
            company = self._fueltoken_company()
            domain = [
                ('station_id', '=', station.id),
                ('company_id', '=', company.id),
            ]
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

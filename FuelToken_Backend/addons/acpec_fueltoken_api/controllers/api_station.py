from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenStationApi(AcpecFuelTokenApiCommon):

    STATION_TRANSACTIONS_DEFAULT_LIMIT = 20
    STATION_TRANSACTIONS_MAX_LIMIT = 100
    STATION_TRANSACTIONS_MAX_HISTORY_DAYS = 365

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

    def _station_transactions_date_range_params(self, params):
        date_from, date_to = self._date_range_params(params)

        if date_to and not date_from:
            raise ValidationError('date_from est obligatoire lorsque date_to est fourni.')

        if not date_from:
            return date_from, date_to

        start_dt = fields.Datetime.to_datetime(date_from)
        end_dt = fields.Datetime.to_datetime(date_to) if date_to else fields.Datetime.now()
        if not start_dt or not end_dt:
            return date_from, date_to

        if end_dt < start_dt:
            raise ValidationError('date_to doit être postérieure ou égale à date_from.')

        max_seconds = self.STATION_TRANSACTIONS_MAX_HISTORY_DAYS * 24 * 60 * 60
        if (end_dt - start_dt).total_seconds() > max_seconds:
            raise ValidationError(
                'La période demandée ne peut pas dépasser %s jours.'
                % self.STATION_TRANSACTIONS_MAX_HISTORY_DAYS
            )

        return date_from, date_to

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
        debug_reason = False
        if qr.state != 'active':
            can_consume = False
            reason = _('QR introuvable ou non utilisable.')
            debug_reason = 'qr_not_active'
        elif qr.company_id != station.company_id:
            can_consume = False
            reason = _('QR introuvable ou non utilisable.')
            debug_reason = 'qr_wrong_company'
        elif qr.expires_at and qr.expires_at <= fields.Datetime.now():
            can_consume = False
            reason = _('QR introuvable ou non utilisable.')
            debug_reason = 'qr_expired'
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
            'debug_reason': debug_reason,
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
            try:
                qr = self._resolve_qr_from_payload(kwargs)
            except ValidationError as exc:
                if 'QR introuvable' not in str(exc):
                    raise
                return self._sensitive_refusal_response(
                    public_code='QR_NOT_USABLE',
                    debug_reason='qr_not_found',
                    purpose='station_qr_check',
                    params=kwargs,
                    user=user,
                    company=station.company_id,
                    audit_code='QR_NOT_USABLE',
                )
            try:
                self._require_station_qr_company(qr, station)
            except ValidationError:
                return self._sensitive_refusal_response(
                    public_code='QR_NOT_USABLE',
                    debug_reason='qr_wrong_company',
                    purpose='station_qr_check',
                    params=kwargs,
                    user=user,
                    company=station.company_id,
                    audit_code='QR_NOT_USABLE',
                )
            with request.env.cr.savepoint():
                qr._lock_records()
                qr.invalidate_recordset()
                qr.action_refresh_expiration_state()
            payload = self._qr_check_payload(qr, station)
            if not payload.get('can_consume'):
                return self._sensitive_refusal_response(
                    public_code='QR_NOT_USABLE',
                    debug_reason=payload.get('debug_reason') or 'qr_not_active',
                    purpose='station_qr_check',
                    params=kwargs,
                    user=user,
                    company=station.company_id,
                    audit_code='QR_NOT_USABLE',
                )
            payload.pop('debug_reason', None)
            return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/qr/use', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def use_qr(self, **kwargs):
        try:
            with self._sensitive_action_transaction(kwargs, purpose='station_qr_use') as user:
                self._require_fuel_group(user, 'station')
                station = self._station_for_fueltoken_user(user)
                idempotency_key = self._require_idempotency_key(kwargs, purpose='station_qr_use')
                try:
                    qr = self._resolve_qr_from_payload(kwargs)
                except ValidationError as exc:
                    if 'QR introuvable' not in str(exc):
                        raise
                    self._raise_sensitive_action_error(
                        code='QR_NOT_USABLE',
                        public_code='QR_NOT_USABLE',
                        purpose='station_qr_use',
                        debug_reason='qr_not_found',
                        user=user,
                        params=kwargs,
                    )
                try:
                    self._require_station_qr_company(qr, station)
                except ValidationError:
                    self._raise_sensitive_action_error(
                        code='QR_NOT_USABLE',
                        public_code='QR_NOT_USABLE',
                        purpose='station_qr_use',
                        debug_reason='qr_wrong_company',
                        user=user,
                        params=kwargs,
                    )
                request_hash_params = dict(kwargs)
                request_hash_params['public_code'] = qr.public_code
                request_hash_params.pop('qr_numeric_code', None)
                request_hash = self._compute_idempotency_request_hash(request_hash_params, purpose='station_qr_use')
                tx = qr.action_consume_by_station(station, user=user, idempotency_key=idempotency_key, request_hash=request_hash)
                if tx and 'actor_user_id' in tx._fields and not tx.actor_user_id:
                    tx.with_context(allow_fuel_transaction_update=True).write({
                        'actor_user_id': user.id,
                    })
                return self._json_response({
                    'transaction_id': tx.id,
                    'transaction_name': tx.name,
                    'qr_id': qr.id,
                    'qr_public_code': qr.public_code,
                    'qr_state': qr.state,
                    'amount_total': qr.amount_total,
                    'station_id': station.id,
                    'station_name': station.name,
                    'regularization_state': tx.regularization_state,
                    'regularization_reference': tx.regularization_reference or False,
                })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/station/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_transactions(self, **kwargs):
        try:
            station, user = self._station_user()
            limit, offset = self._pagination_params(
                kwargs,
                default_limit=self.STATION_TRANSACTIONS_DEFAULT_LIMIT,
                max_limit=self.STATION_TRANSACTIONS_MAX_LIMIT,
            )
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._station_transactions_date_range_params(kwargs)
            transaction_type = self._get_clean_str(kwargs, 'transaction_type')
            regularization_state = self._get_clean_str(kwargs, 'regularization_state') or 'pending'
            if regularization_state not in ('pending', 'regularized', 'all'):
                raise ValidationError(_('Filtre regularization_state invalide.'))
            company = self._fueltoken_company()
            domain = [
                ('station_id', '=', station.id),
                ('company_id', '=', company.id),
                ('transaction_type', '=', 'consommation_station'),
            ]

            # Patch43M6: station scope first, then agent scope.
            # Responsible/supervisor station sees all station consumptions.
            # Ordinary station agent sees only consumptions where they are the M5 actor.
            if not station.user_id or station.user_id.id != user.id:
                if not user.partner_id:
                    raise ValidationError(_('Partenaire mobile station introuvable.'))
                domain.append(('actor_partner_id', '=', user.partner_id.id))

            if regularization_state != 'all':
                domain.append(('regularization_state', '=', regularization_state))
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
                    'qr_name': tx.qr_id.name if tx.qr_id else False,
                    'qr_public_code': tx.qr_id.public_code if tx.qr_id else False,
                    'consumed_at': fields.Datetime.to_string(tx.qr_id.consumed_at) if tx.qr_id and tx.qr_id.consumed_at else False,
                    'wallet_id': tx.wallet_id.id if tx.wallet_id else False,
                    'partner_id': tx.wallet_id.partner_id.id if tx.wallet_id else False,
                    'partner_name': tx.wallet_id.partner_id.name if tx.wallet_id else False,
                    'actor_partner_id': tx.actor_partner_id.id if tx.actor_partner_id else False,
                    'actor_partner_name': tx.actor_partner_id.name if tx.actor_partner_id else False,
                    'actor_user_id': tx.actor_user_id.id if 'actor_user_id' in tx._fields and tx.actor_user_id else False,
                    'actor_user_name': tx.actor_user_id.name if 'actor_user_id' in tx._fields and tx.actor_user_id else False,
                    'counterparty_partner_id': tx.counterparty_partner_id.id if tx.counterparty_partner_id else False,
                    'counterparty_partner_name': tx.counterparty_partner_id.name if tx.counterparty_partner_id else False,
                    'regularization_state': tx.regularization_state or False,
                    'regularization_reference': tx.regularization_reference or False,
                    'regularization_date': fields.Datetime.to_string(tx.regularization_date) if tx.regularization_date else False,
                })
            return self._json_response({
                'station': self._station_payload(station),
                'items': items,
                'date_from': fields.Datetime.to_string(date_from) if date_from else False,
                'date_to': fields.Datetime.to_string(date_to) if date_to else False,
                'max_history_days': self.STATION_TRANSACTIONS_MAX_HISTORY_DAYS,
                **self._pagination_meta_legacy(total_count, limit, offset, len(records), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

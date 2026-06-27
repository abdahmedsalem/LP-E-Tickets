from odoo import http, _, fields
from odoo.exceptions import AccessError, ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenAdminApi(AcpecFuelTokenApiCommon):

    def _admin_user(self):
        user = self._require_trusted_mobile_auth()
        self._require_fuel_group(user, 'manager')
        self._require_fueltoken_user_company(user)
        return user

    def _trusted_admin_user(self, params=None, purpose='admin_sensitive_action'):
        user = self._require_sensitive_action_pin(params or {}, purpose=purpose)
        self._require_fuel_group(user, 'manager')
        self._require_fueltoken_user_company(user)
        return user

    def _raise_mobile_manager_backoffice_only(self):
        # Do not wrap this message in _().
        # In lightweight controller tests, controller.env can be None even when
        # request.env is patched; Odoo translation may inspect self.env.uid and
        # crash with AttributeError("'NoneType' object has no attribute 'uid'").
        raise AccessError(
            "Action réservée au back-office administratif. "
            "Le manager mobile est limité aux validations positives."
        )

    def _require_purchase_partner_trusted_mobile_access_for_manager_api(self, purchase):
        # API-only H0D guard for mobile manager purchase approval.
        # FuelToken business objects remain economically owned by partner_id.
        # This guard does not change purchase.action_approve() and must not
        # block Odoo back-office/backend administrative approvals.
        error_message = (
            "Le partenaire de l'achat ne dispose d'aucun accès mobile trusted actif."
        )
        if not purchase or not purchase.exists() or not purchase.partner_id:
            raise AccessError(error_message)

        company = purchase.company_id
        user_domain = [
            ('partner_id', '=', purchase.partner_id.id),
            ('active', '=', True),
            ('mobile_only', '=', True),
            ('mobile_state', 'in', ['approved', 'self_registered']),
        ]
        if company:
            user_domain.append(('company_ids', 'in', [company.id]))

        users = request.env['res.users'].sudo().search(user_domain)
        if not users:
            raise AccessError(error_message)

        device_domain = [
            ('user_id', 'in', users.ids),
            ('active', '=', True),
            ('trust_state', '=', 'trusted'),
        ]
        Device = request.env['acpec.mobile.device'].sudo()
        if company and 'company_id' in Device._fields:
            device_domain.append(('company_id', '=', company.id))

        trusted_device = Device.search(device_domain, limit=1)
        if not trusted_device:
            raise AccessError(error_message)
        return trusted_device

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


    def _device_payload(self, device):
        user = device.user_id
        return {
            'id': device.id,
            'name': device.name,
            'user_id': user.id if user else False,
            'user_name': user.name if user else False,
            'mobile_phone': user.mobile_phone if user else False,
            'partner_id': user.partner_id.id if user and user.partner_id else False,
            'partner_name': user.partner_id.name if user and user.partner_id else False,
            'company_id': device.company_id.id if device.company_id else False,
            'company_name': device.company_id.name if device.company_id else False,
            'stable_device_uid': device.stable_device_uid or False,
            'device_name': device.device_name or False,
            'platform': device.platform or False,
            'app_version': device.app_version or False,
            'trust_state': device.trust_state,
            'first_seen_at': fields.Datetime.to_string(device.first_seen_at) if device.first_seen_at else False,
            'last_seen_at': fields.Datetime.to_string(device.last_seen_at) if device.last_seen_at else False,
            'trusted_at': fields.Datetime.to_string(device.trusted_at) if device.trusted_at else False,
            'trusted_by': device.trusted_by.name if device.trusted_by else False,
        }

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_list(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_create(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_update(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/carnet-types/delete', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def carnet_type_delete(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
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
            with self._sensitive_action_transaction(kwargs, purpose='purchase_approve') as user:
                self._require_fuel_group(user, 'manager')
                self._require_keys(kwargs, ['purchase_id'])
                idempotency_key = self._require_idempotency_key(kwargs, purpose='purchase_approve')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='purchase_approve')
                purchase = request.env['acpec.fuel.purchase'].sudo().browse(self._get_optional_int(kwargs, 'purchase_id', 0)).exists()
                if not purchase:
                    raise ValidationError(_('Lot d’achat introuvable.'))
                self._check_record_company_allowed(user, purchase)

                if purchase.approval_idempotency_key == idempotency_key:
                    if purchase.approval_request_hash and purchase.approval_request_hash != request_hash:
                        raise ValidationError('idempotency_conflict: même idempotency_key avec payload différent.')
                    if purchase.state == 'approved':
                        return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))

                self._require_purchase_partner_trusted_mobile_access_for_manager_api(purchase)

                with request.env.cr.savepoint():
                    purchase.sudo().write({
                        'approval_idempotency_key': idempotency_key,
                        'approval_request_hash': request_hash,
                    })
                    purchase.with_user(user).action_approve()
                return self._json_response(self._purchase_payload(purchase.sudo(), detail=True))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/purchases/reject', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchase_reject(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
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


    @http.route('/api/acpec/fueltoken/v1/admin/devices/pending-trust', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def devices_pending_trust(self, **kwargs):
        try:
            user = self._admin_user()
            limit, offset = self._pagination_params(kwargs, default_limit=100, max_limit=200)
            include_meta = self._include_pagination_meta(kwargs)
            domain = self._company_domain_for_user(user)
            domain.extend([
                ('trust_state', '=', 'pending_trust'),
                ('active', '=', True),
                ('user_id.mobile_only', '=', True),
                ('user_id.mobile_state', 'in', ['approved', 'self_registered']),
            ])
            Device = request.env['acpec.mobile.device'].sudo()
            total = Device.search_count(domain)
            records = Device.search(
                domain,
                order='last_seen_at desc, create_date desc, id desc',
                limit=limit,
                offset=offset,
            )
            return self._json_response({
                'items': [self._device_payload(device) for device in records],
                **self._pagination_meta_count_only(total, limit, offset, len(records), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/devices/approve', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def device_approve_pending_trust(self, **kwargs):
        try:
            with self._sensitive_action_transaction(kwargs, purpose='device_approve_pending_trust') as user:
                self._require_fuel_group(user, 'manager')
                self._require_fueltoken_user_company(user)
                self._require_keys(kwargs, ['device_id'])
                idempotency_key = self._require_idempotency_key(kwargs, purpose='device_approve_pending_trust')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='device_approve_pending_trust')

                device = request.env['acpec.mobile.device'].sudo().browse(
                    self._get_optional_int(kwargs, 'device_id', 0)
                ).exists()
                if not device:
                    raise ValidationError(_('Device mobile introuvable.'))
                self._check_record_company_allowed(user, device)

                if device.user_id == user:
                    raise AccessError('Un manager mobile ne peut pas approuver son propre device.')
                if not device.user_id.mobile_only:
                    raise AccessError('Seul un device d’utilisateur mobile peut être approuvé.')
                if device.user_id.mobile_state == 'blocked':
                    raise AccessError('Impossible d’approuver un device d’un utilisateur mobile bloqué.')
                if device.trust_state != 'pending_trust':
                    raise AccessError('Seul un device en attente peut être approuvé par l’API manager mobile.')

                source_session = self._get_mobile_session(required=False)
                device.with_context(
                    acpec_mobile_source_session_id=source_session.id if source_session else False,
                    acpec_fueltoken_mobile_manager_device_approval_user_id=user.id,
                    acpec_fueltoken_device_approval_idempotency_key=idempotency_key,
                    acpec_fueltoken_device_approval_request_hash=request_hash,
                ).sudo().action_trust_device()
                device.invalidate_recordset(['trust_state', 'trusted_at', 'trusted_by'])
                return self._json_response(self._device_payload(device))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_create(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_update(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/stations/disable', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def station_disable(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/admin/reports/summary', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def reports_summary(self, **kwargs):
        try:
            # patch43H0C: le manager mobile est un valideur positif limité.
            # Cette action est réservée au back-office/backend administratif.
            self._admin_user()
            self._raise_mobile_manager_backoffice_only()
        except Exception as exc:
            return self._handle_exception_response(exc)


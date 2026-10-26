import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileQrMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/issue', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def issue_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines'])
            with self._sensitive_action_transaction(kwargs, purpose='qr_issue') as authorized_user:
                idempotency_key = self._require_idempotency_key(kwargs, purpose='qr_issue')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='qr_issue')
                wallet = self._mobile_wallet()
                try:
                    max_amount = int(kwargs.get('max_amount', wallet.qr_max_amount))
                except (TypeError, ValueError):
                    raise ValidationError('Le plafond du QR doit être un montant valide.')
                if max_amount <= 0 or max_amount > wallet.qr_max_amount:
                    raise ValidationError('Le plafond du QR dépasse la limite autorisée pour ce client.')
                mobile_session = self._get_mobile_session(required=True)
                requests = []
                has_explicit_lines = False
                has_legacy_lines = False
                for line in kwargs.get('lines') or []:
                    req = {'qty': int(line.get('qty') or 0)}
                    if line.get('face_line_id'):
                        req['face_line_id'] = int(line.get('face_line_id'))
                        has_explicit_lines = True
                    elif line.get('carnet_type_id'):
                        req['carnet_type_id'] = int(line.get('carnet_type_id'))
                        has_legacy_lines = True
                    elif line.get('face_value') is not None:
                        req['face_value'] = float(line.get('face_value'))
                        has_legacy_lines = True
                    else:
                        raise ValidationError('Chaque ligne doit contenir face_line_id, carnet_type_id ou face_value.')
                    requests.append(req)
                if has_explicit_lines and has_legacy_lines:
                    raise ValidationError('Un QR ne peut pas melanger selection explicite de carnets et allocation automatique.')
                with request.env.cr.savepoint():
                    qr = request.env['acpec.fuel.qr']._issue_from_available_internal(
                        authorized_user,
                        wallet,
                        requests,
                        idempotency_key=idempotency_key,
                        request_hash=request_hash,
                        max_amount=max_amount,
                    )
                    qr_txs = request.env['acpec.fuel.transaction'].sudo().search([
                        ('qr_id', '=', qr.id),
                        ('transaction_type', '=', 'emission_qr'),
                        ('wallet_id', '=', wallet.id),
                    ])
                    self._stamp_mobile_actor_on_transactions(qr_txs, authorized_user, mobile_session)
                    payload = self._qr_payload(qr)
                return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def qr_list(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            limit, offset = self._pagination_params(kwargs, default_limit=50, max_limit=100)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            state = self._get_clean_str(kwargs, 'state')
            domain = [('wallet_id', '=', wallet.id)]
            if state and state != 'all':
                domain.append(('state', '=', state))
            self._add_date_range_domain(domain, date_from, date_to, field_name='create_date')
            qr_model = request.env['acpec.fuel.qr'].sudo()
            total = qr_model.search_count(domain)
            qrs = qr_model.search(domain, order='id desc', limit=limit, offset=offset)
            return self._json_response({
                'items': [self._qr_payload(qr) for qr in qrs],
                **self._pagination_meta_opt_in(total, limit, offset, len(qrs), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def qr_detail(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code'])
            wallet = self._mobile_wallet()
            qr = request.env['acpec.fuel.qr'].sudo().search([
                ('public_code', '=', kwargs.get('public_code')),
                ('wallet_id', '=', wallet.id),
            ], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))
            data = self._qr_payload(qr)
            data['technical_lines'] = self._qr_technical_lines_payload(qr)
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/reveal-code', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def qr_reveal_code(self, **kwargs):
        with self._sensitive_action_transaction(kwargs, purpose='qr_reveal_code') as authorized_user:
            self._require_keys(kwargs, ['public_code'])
            public_code = str(kwargs.get('public_code') or '').strip()
            domain = [('public_code', '=', public_code)]

            is_manager = authorized_user.has_group('acpec_fueltoken_base.group_fuel_manager')
            is_admin = authorized_user.has_group('acpec_fueltoken_base.group_fuel_admin')
            if is_manager or is_admin:
                domain += self._company_domain_for_user(authorized_user, field_name='company_id')
            else:
                domain.append(('partner_id', '=', authorized_user.partner_id.id))

            qr = request.env['acpec.fuel.qr'].sudo().search(domain, limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))

            self._check_record_company_allowed(authorized_user, qr, field_name='company_id')
            qr._ensure_qr_numeric_code_hash()
            return {
                'success': True,
                'name': qr.name,
                'public_code': qr.public_code,
                'qr_numeric_code': qr._qr_numeric_code_display(),
            }

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/retirer', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def retirer_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code', 'lines'])
            with self._sensitive_action_transaction(kwargs, purpose='qr_retirer') as authorized_user:
                idempotency_key = self._require_idempotency_key(kwargs, purpose='qr_retirer')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='qr_retirer')
                wallet = self._mobile_wallet()
                mobile_session = self._get_mobile_session(required=True)
                qr = request.env['acpec.fuel.qr'].sudo().search([
                    ('public_code', '=', kwargs.get('public_code')),
                    ('wallet_id', '=', wallet.id),
                ], limit=1)
                if not qr:
                    raise ValidationError(_('QR introuvable.'))

                child = qr._retirer_to_child_internal(
                    authorized_user,
                    kwargs.get('lines') or [],
                    idempotency_key=idempotency_key,
                    request_hash=request_hash,
                )
                retirer_txs = request.env['acpec.fuel.transaction'].sudo().search([
                    ('transaction_type', '=', 'retirer_qr'),
                    ('parent_qr_id', '=', qr.id),
                    ('qr_id', '=', child.id),
                    ('wallet_id', '=', wallet.id),
                ])
                self._stamp_mobile_actor_on_transactions(retirer_txs, authorized_user, mobile_session)
                source_payload = self._qr_payload(qr)
                child_payload = self._qr_payload(child)
                source_payload['technical_lines'] = self._qr_technical_lines_payload(qr)
                child_payload['technical_lines'] = self._qr_technical_lines_payload(child)
                return self._json_response({'source': source_payload, 'new_qr': child_payload})
        except Exception as exc:
            return self._handle_exception_response(exc)

    # ─── Transfert de carnets ────────────────────────────────────────────────

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/separer', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def separer_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code'])
            with self._sensitive_action_transaction(kwargs, purpose='qr_separer') as authorized_user:
                idempotency_key = self._require_idempotency_key(kwargs, purpose='qr_separer')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='qr_separer')
                wallet = self._mobile_wallet()
                mobile_session = self._get_mobile_session(required=True)
                qr = request.env['acpec.fuel.qr'].sudo().search([
                    ('public_code', '=', kwargs.get('public_code')),
                    ('wallet_id', '=', wallet.id),
                ], limit=1)
                if not qr:
                    raise ValidationError(_('QR introuvable.'))

                child = qr._separer_valid_to_child_internal(
                    authorized_user,
                    idempotency_key=idempotency_key,
                    request_hash=request_hash,
                )
                separer_txs = request.env['acpec.fuel.transaction'].sudo().search([
                    ('transaction_type', '=', 'separer_qr'),
                    ('parent_qr_id', '=', qr.id),
                    ('qr_id', '=', child.id),
                    ('wallet_id', '=', wallet.id),
                ])
                self._stamp_mobile_actor_on_transactions(separer_txs, authorized_user, mobile_session)
                source_payload = self._qr_payload(qr)
                child_payload = self._qr_payload(child)
                source_payload['technical_lines'] = self._qr_technical_lines_payload(qr)
                child_payload['technical_lines'] = self._qr_technical_lines_payload(child)
                return self._json_response({'source': source_payload, 'new_qr': child_payload})
        except Exception as exc:
            return self._handle_exception_response(exc)

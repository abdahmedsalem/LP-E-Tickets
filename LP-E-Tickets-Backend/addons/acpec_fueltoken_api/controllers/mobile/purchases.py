import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobilePurchasesMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def create_purchase(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines', 'proof_data'])

            proof_filename, proof_data, proof_error = self._validate_purchase_payment_proof(
                kwargs.get('proof_filename'),
                kwargs.get('proof_data'),
            )
            if proof_error:
                return self._error_response('PAYMENT_PROOF_INVALID', proof_error)

            kwargs = dict(kwargs)
            kwargs['proof_filename'] = proof_filename
            kwargs['proof_data'] = proof_data

            with self._sensitive_action_transaction(kwargs, purpose='purchase_create') as authorized_user:
                idempotency_key = self._require_idempotency_key(kwargs, purpose='purchase_create')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='purchase_create')
                wallet = self._mobile_wallet()
                mobile_session = self._get_mobile_session(required=True)
                purchase = request.env['acpec.fuel.purchase'].create_from_api(
                    wallet.partner_id,
                    wallet.company_id,
                    kwargs.get('lines') or [],
                    proof_filename,
                    proof_data,
                    payment_reference=kwargs.get('payment_reference'),
                    idempotency_key=idempotency_key,
                    request_hash=request_hash,
                    payment_method_id=kwargs.get('payment_method_id'),
                    payment_method_code=kwargs.get('payment_method_code'),
                )
                purchase_txs = request.env['acpec.fuel.transaction'].sudo().search([
                    ('purchase_id', '=', purchase.id),
                    ('transaction_type', '=', 'purchase_submitted'),
                    ('wallet_id', '=', wallet.id),
                ])
                self._stamp_mobile_actor_on_transactions(purchase_txs, authorized_user, mobile_session)
                return self._json_response({
                    'purchase_id': purchase.id,
                    'public_code': purchase.public_code,
                    'state': purchase.state,
                    'amount_total': purchase.amount_total,
                    **self._purchase_payment_method_payload(purchase),
                })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchases(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            limit, offset = self._pagination_params(kwargs, default_limit=50, max_limit=100)
            include_meta = self._include_pagination_meta(kwargs)
            include_proof_data = self._as_bool_param(kwargs.get('include_proof_data'))
            date_from, date_to = self._date_range_params(kwargs)
            state = self._get_clean_str(kwargs, 'state')

            domain = [
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
            ]
            if state and state != 'all':
                domain.append(('state', '=', state))
            self._add_date_range_domain(domain, date_from, date_to, field_name='submitted_at')

            purchase_model = request.env['acpec.fuel.purchase'].sudo()
            total = purchase_model.search_count(domain)
            items = purchase_model.search(domain, order='id desc', limit=limit, offset=offset)
            result = []
            for p in items:
                lines = []
                for line in p.line_ids:
                    lines.append({
                        'id': line.id,
                        'carnet_type_id': line.carnet_type_id.id,
                        'carnet_type_code': line.carnet_type_id.code,
                        'carnet_type_name': self._carnet_type_label(line.carnet_type_id),
                        'face_count': line.face_count,
                        'face_value': line.face_value,
                        'carnet_qty': line.carnet_qty,
                        'amount_total': line.amount_total,
                    })
                proof_payloads = []
                for index, attachment in enumerate(self._purchase_proof_attachments(p)):
                    proof_payloads.append(
                        self._purchase_proof_attachment_payload(
                            attachment,
                            include_data=include_proof_data and index == 0,
                        )
                    )
                first_proof = proof_payloads[0] if proof_payloads else {}
                first_proof_data = (
                    first_proof.get('proof_image_data')
                    or first_proof.get('image_data')
                    or first_proof.get('payment_proof_data')
                    or first_proof.get('proof_data')
                    or False
                )
                result.append({
                    'id': p.id,
                    'name': p.name,
                    'public_code': p.public_code,
                    'state': p.state,
                    'amount_total': p.amount_total,
                    'face_qty_total': p.face_qty_total,
                    'payment_reference': p.payment_reference or False,
                    **self._purchase_payment_method_payload(p),
                    'payment_proof_path': first_proof.get('url') or False,
                    'payment_proof_url': first_proof.get('url') or False,
                    'proof_filename': first_proof.get('filename') or False,
                    'proof_mimetype': first_proof.get('mimetype') or False,
                    'proof_attachment_id': first_proof.get('id') or False,
                    **({
                        'proof_data': first_proof_data,
                        'payment_proof_data': first_proof_data,
                        'image_data': first_proof_data,
                        'proof_image_data': first_proof_data,
                    } if first_proof_data else {}),
                    'proof_attachments': proof_payloads,
                    'proofs': proof_payloads,
                    'submitted_at': fields.Datetime.to_string(p.submitted_at) if p.submitted_at else False,
                    'approved_at': fields.Datetime.to_string(p.approved_at) if p.approved_at else False,
                    'rejected_at': fields.Datetime.to_string(p.rejected_at) if p.rejected_at else False,
                    'rejection_reason': p.rejection_reason or False,
                    'lines': lines,
                })
            return self._json_response({
                'items': result,
                **self._pagination_meta_opt_in(total, limit, offset, len(items), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchase_detail(self, **kwargs):
        try:
            self._require_keys(kwargs, ['purchase_id'])
            wallet = self._mobile_wallet()
            purchase_id = self._get_optional_int(kwargs, 'purchase_id', 0)
            if purchase_id <= 0:
                raise ValidationError(_('purchase_id invalide.'))
            purchase = request.env['acpec.fuel.purchase'].sudo().search([
                ('id', '=', purchase_id),
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
            ], limit=1)
            if not purchase:
                raise ValidationError(_('Lot d’achat introuvable.'))
            attachments = [
                dict(
                    self._purchase_proof_attachment_payload(
                        attachment,
                        include_data=True,
                    ),
                    create_date=fields.Datetime.to_string(attachment.create_date) if attachment.create_date else False,
                )
                for attachment in self._purchase_proof_attachments(purchase)
            ]
            first_proof = attachments[0] if attachments else {}
            first_proof_data = (
                first_proof.get('proof_image_data')
                or first_proof.get('image_data')
                or first_proof.get('payment_proof_data')
                or first_proof.get('proof_data')
                or False
            )
            lines = []
            for line in purchase.line_ids:
                lines.append(self._purchase_history_line_payload(purchase, line))
            return self._json_response({
                'id': purchase.id,
                'name': purchase.name,
                'public_code': purchase.public_code,
                'state': purchase.state,
                'amount_total': purchase.amount_total,
                'face_qty_total': purchase.face_qty_total,
                'payment_reference': purchase.payment_reference or False,
                **self._purchase_payment_method_payload(purchase),
                'submitted_at': fields.Datetime.to_string(purchase.submitted_at) if purchase.submitted_at else False,
                'approved_at': fields.Datetime.to_string(purchase.approved_at) if purchase.approved_at else False,
                'approved_by': purchase.approved_by.name if purchase.approved_by else False,
                'rejected_at': fields.Datetime.to_string(purchase.rejected_at) if purchase.rejected_at else False,
                'rejected_by': purchase.rejected_by.name if purchase.rejected_by else False,
                'rejection_reason': purchase.rejection_reason or False,
                'payment_proof_path': first_proof.get('url') or False,
                'payment_proof_url': first_proof.get('url') or False,
                'proof_filename': first_proof.get('filename') or False,
                'proof_mimetype': first_proof.get('mimetype') or False,
                'proof_attachment_id': first_proof.get('id') or False,
                **({
                    'proof_data': first_proof_data,
                    'payment_proof_data': first_proof_data,
                    'image_data': first_proof_data,
                    'proof_image_data': first_proof_data,
                } if first_proof_data else {}),
                'proof_attachments': attachments,
                'proofs': attachments,
                'lines': lines,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

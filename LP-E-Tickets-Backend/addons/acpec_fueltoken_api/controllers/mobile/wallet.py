import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileWalletMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/wallet/current', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def current_wallet(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            near_days = self._get_optional_int(kwargs, 'near_expiration_days', 30)
            near_limit = max(1, min(self._get_optional_int(kwargs, 'near_expiration_limit', 10), 50))
            now = fields.Datetime.now()
            near_limit_date = fields.Datetime.add(now, days=near_days)
            near_lines = request.env['acpec.fuel.face.line'].sudo().search([
                ('wallet_id', '=', wallet.id),
                ('qty_available', '>', 0),
                ('expires_at', '!=', False),
                ('expires_at', '<=', fields.Datetime.to_string(near_limit_date)),
            ], order='expires_at, id', limit=near_limit)
            expired_lines = request.env['acpec.fuel.face.line'].sudo().search([
                ('wallet_id', '=', wallet.id),
                ('qty_expired', '>', 0),
            ], order='expires_at desc, id desc', limit=near_limit)
            return self._json_response({
                'wallet_id': wallet.id,
                'currency': wallet.currency_id.name or 'MRU',
                'qr_max_amount': wallet.qr_max_amount,
                'balance': wallet.balance,
                'qty_available': wallet.qty_available,
                'qty_qr_active': wallet.qty_qr_active,
                'qty_qr_blocked': wallet.qty_qr_blocked,
                'qty_consumed': wallet.qty_consumed,
                'qty_expired': wallet.qty_expired,
                'qty_transferred_out': wallet.qty_transferred_out,
                'amount_qr_active': wallet.amount_qr_active,
                'amount_qr_blocked': wallet.amount_qr_blocked,
                'amount_consumed': wallet.amount_consumed,
                'amount_expired': wallet.amount_expired,
                'amount_transferred_out': wallet.amount_transferred_out,
                'breakdown_by_face_value': self._wallet_breakdown_by_face_value(wallet),
                'breakdown_by_carnet_type': self._wallet_breakdown_by_carnet_type(wallet),
                'near_expiration_faces': [{
                    'id': line.id,
                    'face_line_id': line.id,
                    'carnet_no': line.carnet_no,
                    'lot_short_code': line.lot_short_code,
                    'carnet_short_code': line.carnet_short_code,
                    'carnet_sequence': line.carnet_sequence,
                    'purchase': line.purchase_id.name,
                    'carnet_type': line.carnet_type_id.code,
                    'face_value': line.face_value,
                    'qty_available': line.qty_available,
                    'qty_transferred_out': line.qty_transferred_out,
                    'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
                } for line in near_lines],
                'expired_faces': [{
                    'id': line.id,
                    'purchase': line.purchase_id.name,
                    'carnet_type': line.carnet_type_id.code,
                    'face_value': line.face_value,
                    'qty_expired': line.qty_expired,
                    'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
                } for line in expired_lines],
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/wallet/qr-limit', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def update_wallet_qr_limit(self, **kwargs):
        try:
            self._require_keys(kwargs, ['max_amount'])
            wallet = self._mobile_wallet()
            try:
                max_amount = int(kwargs.get('max_amount'))
            except (TypeError, ValueError):
                raise ValidationError('Le plafond du QR doit être un montant valide.')
            if max_amount <= 0:
                raise ValidationError('Le plafond du QR doit être strictement positif.')
            wallet._write_internal({'qr_max_amount': max_amount})
            return self._json_response({
                'wallet_id': wallet.id,
                'currency': wallet.currency_id.name or 'MRU',
                'qr_max_amount': wallet.qr_max_amount,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

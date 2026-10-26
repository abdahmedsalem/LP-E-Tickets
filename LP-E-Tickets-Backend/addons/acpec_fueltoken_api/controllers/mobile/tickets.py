import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileTicketsMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/faces', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def faces(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            transferable_only = self._get_bool_param(kwargs.get('transferable_only'), default=False)
            lines = request.env['acpec.fuel.face.line'].sudo().search([
                ('wallet_id', '=', wallet.id),
                ('qty_available', '>', 0),
            ], order='expires_at, lot_short_code, carnet_sequence, id')
            items = []
            for line in lines:
                if transferable_only and not line.is_transferable_carnet_line():
                    continue
                carnet = line.carnet_type_id
                items.append({
                    'id': line.id,
                    'face_line_id': line.id,
                    'carnet_no': line.carnet_no,
                    'lot_short_code': line.lot_short_code,
                    'carnet_short_code': line.carnet_short_code,
                    'carnet_sequence': line.carnet_sequence,
                    'purchase': line.purchase_id.name,
                    'purchase_id': line.purchase_id.id,
                    'purchase_line_id': line.purchase_line_id.id,
                    'carnet_type': carnet.code,
                    'carnet_type_id': carnet.id,
                    'carnet_type_code': carnet.code,
                    'carnet_type_name': self._carnet_type_label(carnet),
                    'face_count': carnet.face_count,
                    'face_value': line.face_value,
                    'qty_initial': line.qty_initial,
                    'qty_available': line.qty_available,
                    'qty_qr_active': line.qty_qr_active,
                    'qty_qr_blocked': line.qty_qr_blocked,
                    'qty_consumed': line.qty_consumed,
                    'qty_expired': line.qty_expired,
                    'qty_transferred_out': line.qty_transferred_out,
                    'is_transfer_fragment': line.is_transfer_fragment,
                    'origin_face_line_id': line.origin_face_line_id.id if line.origin_face_line_id else False,
                    'is_transferable': line.is_transferable_carnet_line(),
                    'transferable_carnets': line.transferable_carnet_count(),
                    'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
                })
            return self._json_response({'items': items})
        except Exception as exc:
            return self._handle_exception_response(exc)

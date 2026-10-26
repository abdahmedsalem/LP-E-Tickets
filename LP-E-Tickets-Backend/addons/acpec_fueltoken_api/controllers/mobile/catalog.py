import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileCatalogMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/carnet-types', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_types(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            domain = [
                ('active', '=', True),
                ('company_id', '=', wallet.company_id.id),
            ]
            records = request.env['acpec.fuel.carnet.type'].sudo().search(domain, order='face_value, face_count, code')
            items = [self._mobile_carnet_type_payload(rec) for rec in records]
            return self._json_response({'items': items, 'count': len(items)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/payment-methods', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def payment_methods(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            records = request.env['acpec.fuel.payment.method'].sudo().available_for_company(wallet.company_id)
            items = [self._mobile_payment_method_payload(record) for record in records]
            return self._json_response({'items': items, 'count': len(items)})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/stations/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def mobile_stations_list(self, **kwargs):
        """Retourne la liste des stations actives avec leurs coordonnées GPS pour l'application mobile client."""
        try:
            stations = request.env['acpec.fuel.station'].sudo().search(
                [('active', '=', True)],
                order='name, id',
            )
            items = []
            for st in stations:
                items.append({
                    'id': st.id,
                    'name': st.name,
                    'code': st.code or str(st.id),
                    'address': st.address or '',
                    'phone': st.phone or '',
                    'latitude': st.latitude or 0.0,
                    'longitude': st.longitude or 0.0,
                    'company_id': st.company_id.id if st.company_id else False,
                    'company_name': st.company_id.name if st.company_id else '',
                })
            return self._json_response({'items': items, 'count': len(items)})
        except Exception as exc:
            return self._handle_exception_response(exc)

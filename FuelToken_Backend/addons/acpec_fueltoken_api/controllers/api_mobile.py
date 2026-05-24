from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon


class AcpecFuelTokenMobileApi(AcpecMobileAuthApiCommon):

    def _mobile_wallet(self):
        user = self._require_mobile_auth()
        self._require_fuel_group(user, 'client')
        return request.env['acpec.fuel.wallet'].sudo().get_or_create(user.partner_id, user.company_id)

    def _qr_payload(self, qr):
        grouped = {}
        for line in qr.line_ids:
            key = str(line.face_value)
            grouped[key] = grouped.get(key, 0) + line.qty
        return {
            'id': qr.id,
            'name': qr.name,
            'public_code': qr.public_code,
            'state': qr.state,
            'amount_total': qr.amount_total,
            'face_qty_total': qr.face_qty_total,
            'expires_at': fields.Datetime.to_string(qr.expires_at) if qr.expires_at else False,
            'lines': [{'face_value': int(float(value)), 'qty': qty} for value, qty in grouped.items()],
        }

    def _qr_technical_lines_payload(self, qr):
        return [{
            'qr_line_id': line.id,
            'face_line_id': line.face_line_id.id,
            'purchase_id': line.purchase_id.id,
            'purchase_line_id': line.purchase_line_id.id,
            'purchase': line.purchase_id.name,
            'carnet_type_id': line.face_line_id.carnet_type_id.id,
            'carnet_type_code': line.face_line_id.carnet_type_id.code,
            'face_value': line.face_value,
            'qty': line.qty,
            'state': line.state,
            'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
        } for line in qr.line_ids]

    def _parse_datetime_param(self, raw_value, key_name):
        if raw_value in (False, None, ''):
            return False
        try:
            parsed = fields.Datetime.to_datetime(raw_value)
        except Exception:
            parsed = False
        if not parsed:
            raise ValidationError(_("Le paramètre '%s' est invalide.") % key_name)
        return parsed

    def _tx_type_label(self, tx):
        return dict(tx._fields['transaction_type'].selection).get(tx.transaction_type, tx.transaction_type)

    def _tx_payload(self, tx):
        purchase = tx.purchase_id
        return {
            'id': tx.id,
            'name': tx.name,
            'transaction_type': tx.transaction_type,
            'transaction_type_label': self._tx_type_label(tx),
            'amount_total': tx.amount_total,
            'qty_total': tx.qty_total,
            'created_at': fields.Datetime.to_string(tx.create_date) if tx.create_date else False,
            'wallet_id': tx.wallet_id.id if tx.wallet_id else False,
            'purchase_id': purchase.id if purchase else False,
            'purchase_name': purchase.name if purchase else False,
            'purchase_public_code': purchase.public_code if purchase else False,
            'state': purchase.state if purchase else False,
            'purchase_state': purchase.state if purchase else False,
            'submitted_at': fields.Datetime.to_string(tx.purchase_submitted_at) if tx.purchase_submitted_at else False,
            'approved_at': fields.Datetime.to_string(tx.purchase_approved_at) if tx.purchase_approved_at else False,
            'approved_by': purchase.approved_by.name if purchase and purchase.approved_by else False,
            'rejected_at': fields.Datetime.to_string(tx.purchase_rejected_at) if tx.purchase_rejected_at else False,
            'rejected_by': purchase.rejected_by.name if purchase and purchase.rejected_by else False,
            'rejection_reason': tx.purchase_rejection_reason or False,
            'qr_id': tx.qr_id.id if tx.qr_id else False,
            'qr_public_code': tx.qr_id.public_code if tx.qr_id else False,
            'parent_qr_id': tx.parent_qr_id.id if tx.parent_qr_id else False,
            'parent_qr_public_code': tx.parent_qr_id.public_code if tx.parent_qr_id else False,
            'station_id': tx.station_id.id if tx.station_id else False,
            'station_name': tx.station_id.name if tx.station_id else False,
            'note': tx.note or False,
            'lines': [{
                'id': line.id,
                'purchase_id': line.purchase_id.id if line.purchase_id else False,
                'purchase_line_id': line.purchase_line_id.id if line.purchase_line_id else False,
                'face_value': line.face_value,
                'qty': line.qty,
                'amount': line.amount,
                'face_line_id': line.face_line_id.id if line.face_line_id else False,
                'qr_id': line.qr_id.id if line.qr_id else False,
                'qr_line_id': line.qr_line_id.id if line.qr_line_id else False,
                'transfer_id': line.transfer_id.id if line.transfer_id else False,
            } for line in tx.line_ids],
        }

    def _purchase_submission_payload(self, purchase, wallet):
        created_at = purchase.submitted_at or purchase.create_date
        return {
            'id': f'purchase-submitted-{purchase.id}',
            'name': purchase.name,
            'transaction_type': 'achat_carnets',
            'transaction_type_label': 'Achat de carnets',
            'amount_total': purchase.amount_total,
            'qty_total': purchase.face_qty_total,
            'created_at': fields.Datetime.to_string(created_at) if created_at else False,
            'wallet_id': wallet.id if wallet else False,
            'purchase_id': purchase.id,
            'purchase_name': purchase.name,
            'purchase_public_code': purchase.public_code,
            'state': purchase.state,
            'purchase_state': purchase.state,
            'submitted_at': fields.Datetime.to_string(purchase.submitted_at) if purchase.submitted_at else False,
            'approved_at': fields.Datetime.to_string(purchase.approved_at) if purchase.approved_at else False,
            'approved_by': purchase.approved_by.name if purchase.approved_by else False,
            'rejected_at': fields.Datetime.to_string(purchase.rejected_at) if purchase.rejected_at else False,
            'rejected_by': purchase.rejected_by.name if purchase.rejected_by else False,
            'rejection_reason': purchase.rejection_reason or False,
            'qr_id': False,
            'qr_public_code': False,
            'parent_qr_id': False,
            'parent_qr_public_code': False,
            'station_id': False,
            'station_name': False,
            'note': _('Demande d’achat en attente de validation') if purchase.state == 'submitted' else False,
            'lines': [{
                'id': line.id,
                'purchase_id': purchase.id,
                'purchase_line_id': line.id,
                'face_value': line.face_value,
                'qty': line.generated_face_qty,
                'amount': line.amount_total,
            } for line in purchase.line_ids],
        }

    def _history_sort_key(self, item):
        return item.get('created_at') or item.get('submitted_at') or item.get('approved_at') or ''

    def _wallet_breakdown_by_face_value(self, wallet):
        groups = request.env['acpec.fuel.face.line'].sudo().read_group(
            [('wallet_id', '=', wallet.id)],
            [
                'face_value',
                'qty_available:sum',
                'qty_qr_active:sum',
                'qty_qr_blocked:sum',
                'qty_consumed:sum',
                'qty_expired:sum',
            ],
            ['face_value'],
            lazy=False,
        )
        items = []
        for item in groups:
            face_value = item.get('face_value') or 0
            qty_available = item.get('qty_available') or 0
            qty_qr_active = item.get('qty_qr_active') or 0
            qty_qr_blocked = item.get('qty_qr_blocked') or 0
            qty_consumed = item.get('qty_consumed') or 0
            qty_expired = item.get('qty_expired') or 0
            items.append({
                'face_value': face_value,
                'qty_available': qty_available,
                'amount_available': qty_available * face_value,
                'qty_qr_active': qty_qr_active,
                'amount_qr_active': qty_qr_active * face_value,
                'qty_qr_blocked': qty_qr_blocked,
                'amount_qr_blocked': qty_qr_blocked * face_value,
                'qty_consumed': qty_consumed,
                'amount_consumed': qty_consumed * face_value,
                'qty_expired': qty_expired,
                'amount_expired': qty_expired * face_value,
            })
        return sorted(items, key=lambda item: item['face_value'])

    def _wallet_breakdown_by_carnet_type(self, wallet):
        groups = request.env['acpec.fuel.face.line'].sudo().read_group(
            [('wallet_id', '=', wallet.id)],
            [
                'carnet_type_id',
                'qty_available:sum',
                'qty_qr_active:sum',
                'qty_qr_blocked:sum',
                'qty_consumed:sum',
                'qty_expired:sum',
            ],
            ['carnet_type_id'],
            lazy=False,
        )
        items = []
        for item in groups:
            carnet_type = item.get('carnet_type_id')
            if not carnet_type:
                continue
            carnet = request.env['acpec.fuel.carnet.type'].sudo().browse(carnet_type[0])
            face_value = carnet.face_value or 0
            qty_available = item.get('qty_available') or 0
            items.append({
                'carnet_type_id': carnet.id,
                'carnet_type_code': carnet.code,
                'carnet_type_name': carnet.name,
                'face_value': face_value,
                'qty_available': qty_available,
                'amount_available': qty_available * face_value,
                'qty_qr_active': item.get('qty_qr_active') or 0,
                'qty_qr_blocked': item.get('qty_qr_blocked') or 0,
                'qty_consumed': item.get('qty_consumed') or 0,
                'qty_expired': item.get('qty_expired') or 0,
            })
        return items

    @http.route('/api/acpec/fueltoken/v1/mobile/carnet-types', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def carnet_types(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            domain = [
                ('active', '=', True),
                ('company_id', '=', wallet.company_id.id),
            ]
            records = request.env['acpec.fuel.carnet.type'].sudo().search(domain, order='face_value, face_count, code')
            items = []
            for rec in records:
                items.append({
                    'id': rec.id,
                    'code': rec.code,
                    'name': rec.name,
                    'face_count': rec.face_count,
                    'face_value': rec.face_value,
                    'carnet_amount': rec.carnet_amount,
                    'validity_days': rec.validity_days,
                })
            return self._json_response({'items': items, 'count': len(items)})
        except Exception as exc:
            return self._handle_exception_response(exc)

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
                'balance': wallet.balance,
                'qty_available': wallet.qty_available,
                'qty_qr_active': wallet.qty_qr_active,
                'qty_qr_blocked': wallet.qty_qr_blocked,
                'qty_consumed': wallet.qty_consumed,
                'qty_expired': wallet.qty_expired,
                'amount_qr_active': wallet.amount_qr_active,
                'amount_qr_blocked': wallet.amount_qr_blocked,
                'amount_consumed': wallet.amount_consumed,
                'amount_expired': wallet.amount_expired,
                'breakdown_by_face_value': self._wallet_breakdown_by_face_value(wallet),
                'breakdown_by_carnet_type': self._wallet_breakdown_by_carnet_type(wallet),
                'near_expiration_faces': [{
                    'id': line.id,
                    'purchase': line.purchase_id.name,
                    'carnet_type': line.carnet_type_id.code,
                    'face_value': line.face_value,
                    'qty_available': line.qty_available,
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

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def create_purchase(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines', 'proof_data'])
            wallet = self._mobile_wallet()
            purchase = request.env['acpec.fuel.purchase'].sudo().create_from_api(
                wallet.partner_id,
                wallet.company_id,
                kwargs.get('lines') or [],
                kwargs.get('proof_filename') or _('preuve_paiement.pdf'),
                kwargs.get('proof_data'),
                payment_reference=kwargs.get('payment_reference'),
                idempotency_key=kwargs.get('idempotency_key'),
            )
            return self._json_response({
                'purchase_id': purchase.id,
                'public_code': purchase.public_code,
                'state': purchase.state,
                'amount_total': purchase.amount_total,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def purchases(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            items = request.env['acpec.fuel.purchase'].sudo().search([
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
            ], order='id desc', limit=50)
            return self._json_response({'items': [{
                'id': p.id,
                'name': p.name,
                'public_code': p.public_code,
                'state': p.state,
                'amount_total': p.amount_total,
                'face_qty_total': p.face_qty_total,
                'submitted_at': fields.Datetime.to_string(p.submitted_at) if p.submitted_at else False,
                'approved_at': fields.Datetime.to_string(p.approved_at) if p.approved_at else False,
            } for p in items]})
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
            attachments = []
            for attachment in purchase.proof_attachment_ids:
                attachments.append({
                    'id': attachment.id,
                    'name': attachment.name,
                    'mimetype': attachment.mimetype or False,
                    'file_size': attachment.file_size or 0,
                    'create_date': fields.Datetime.to_string(attachment.create_date) if attachment.create_date else False,
                })
            lines = []
            for line in purchase.line_ids:
                lines.append({
                    'id': line.id,
                    'carnet_type_id': line.carnet_type_id.id,
                    'carnet_type_code': line.carnet_type_id.code,
                    'carnet_type_name': line.carnet_type_id.name,
                    'carnet_qty': line.carnet_qty,
                    'face_count': line.face_count,
                    'face_value': line.face_value,
                    'generated_face_qty': line.generated_face_qty,
                    'amount_total': line.amount_total,
                })
            return self._json_response({
                'id': purchase.id,
                'name': purchase.name,
                'public_code': purchase.public_code,
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
                'proof_attachments': attachments,
                'lines': lines,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def transactions(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            tx_model = request.env['acpec.fuel.transaction'].sudo()
            purchase_model = request.env['acpec.fuel.purchase'].sudo()
            date_from = self._parse_datetime_param(kwargs.get('date_from'), 'date_from')
            date_to = self._parse_datetime_param(kwargs.get('date_to'), 'date_to')
            limit = max(1, min(self._get_optional_int(kwargs, 'limit', 20), 200))
            offset = max(0, self._get_optional_int(kwargs, 'offset', 0))
            if date_from and date_to and date_from > date_to:
                raise ValidationError(_('La plage de dates est invalide.'))
            domain = [('wallet_id', '=', wallet.id)]
            if date_from:
                domain.append(('create_date', '>=', fields.Datetime.to_string(date_from)))
            if date_to:
                domain.append(('create_date', '<=', fields.Datetime.to_string(date_to)))
            records = tx_model.search(domain, order='create_date desc, id desc')
            items = [self._tx_payload(tx) for tx in records]
            existing_purchase_ids = {
                tx.purchase_id.id
                for tx in records
                if tx.purchase_id
            }
            submitted_domain = [
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
                ('state', '=', 'submitted'),
            ]
            submitted_purchases = purchase_model.search(
                submitted_domain,
                order='submitted_at desc, id desc',
            )
            for purchase in submitted_purchases:
                if purchase.id in existing_purchase_ids:
                    continue
                payload = self._purchase_submission_payload(purchase, wallet)
                created_at = self._parse_datetime_param(payload.get('created_at'), 'created_at') if payload.get('created_at') else False
                if date_from and created_at and created_at < date_from:
                    continue
                if date_to and created_at and created_at > date_to:
                    continue
                items.append(payload)
            items.sort(key=self._history_sort_key, reverse=True)
            total_count = len(items)
            page_items = items[offset:offset + limit]
            return self._json_response({
                'items': page_items,
                'count': total_count,
                'limit': limit,
                'offset': offset,
                'has_more': (offset + len(page_items)) < total_count,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/transactions/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def transaction_detail(self, **kwargs):
        try:
            self._require_keys(kwargs, ['transaction_id'])
            wallet = self._mobile_wallet()
            tx_id = self._get_optional_int(kwargs, 'transaction_id', 0)
            if tx_id <= 0:
                raise ValidationError(_('transaction_id invalide.'))
            tx = request.env['acpec.fuel.transaction'].sudo().search([
                ('id', '=', tx_id),
                ('wallet_id', '=', wallet.id),
            ], limit=1)
            if not tx:
                raise ValidationError(_('Transaction introuvable.'))
            data = self._tx_payload(tx)
            data['lines'] = []
            for line in tx.line_ids:
                data['lines'].append({
                    'id': line.id,
                    'face_value': line.face_value,
                    'qty': line.qty,
                    'amount': line.amount,
                    'purchase_id': line.purchase_id.id if line.purchase_id else False,
                    'purchase_public_code': line.purchase_id.public_code if line.purchase_id else False,
                    'purchase_line_id': line.purchase_line_id.id if line.purchase_line_id else False,
                    'face_line_id': line.face_line_id.id if line.face_line_id else False,
                    'qr_id': line.qr_id.id if line.qr_id else False,
                    'qr_public_code': line.qr_id.public_code if line.qr_id else False,
                    'qr_line_id': line.qr_line_id.id if line.qr_line_id else False,
                })
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/faces', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def faces(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            lines = request.env['acpec.fuel.face.line'].sudo().search([
                ('wallet_id', '=', wallet.id),
                ('qty_available', '>', 0),
            ], order='expires_at, id')
            items = []
            for line in lines:
                items.append({
                    'id': line.id,
                    'purchase': line.purchase_id.name,
                    'carnet_type': line.carnet_type_id.code,
                    'face_value': line.face_value,
                    'qty_available': line.qty_available,
                    'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
                })
            return self._json_response({'items': items})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/issue', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def issue_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines'])
            wallet = self._mobile_wallet()
            requests = []
            for line in kwargs.get('lines') or []:
                req = {'qty': int(line.get('qty') or 0)}
                if line.get('carnet_type_id'):
                    req['carnet_type_id'] = int(line.get('carnet_type_id'))
                else:
                    req['face_value'] = float(line.get('face_value'))
                requests.append(req)
            with request.env.cr.savepoint():
                qr = request.env['acpec.fuel.qr'].sudo().issue_from_available(
                    wallet,
                    requests,
                    idempotency_key=kwargs.get('idempotency_key'),
                )
                payload = self._qr_payload(qr)
            return self._json_response(payload)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def qr_list(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            state = kwargs.get('state')
            domain = [('wallet_id', '=', wallet.id)]
            if state:
                domain.append(('state', '=', state))
            qrs = request.env['acpec.fuel.qr'].sudo().search(domain, order='id desc', limit=50)
            return self._json_response({'items': [self._qr_payload(qr) for qr in qrs]})
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

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/split', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def split_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code', 'children'])
            wallet = self._mobile_wallet()
            qr = request.env['acpec.fuel.qr'].sudo().search([
                ('public_code', '=', kwargs.get('public_code')),
                ('wallet_id', '=', wallet.id),
            ], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))
            children = qr.action_split(kwargs.get('children') or [], idempotency_key=kwargs.get('idempotency_key'))
            return self._json_response({'parent': self._qr_payload(qr), 'children': [self._qr_payload(child) for child in children]})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/retirer', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def retirer_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code', 'lines'])
            wallet = self._mobile_wallet()
            qr = request.env['acpec.fuel.qr'].sudo().search([
                ('public_code', '=', kwargs.get('public_code')),
                ('wallet_id', '=', wallet.id),
            ], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))

            child = qr.action_retirer_to_child(
                kwargs.get('lines') or [],
                idempotency_key=kwargs.get('idempotency_key'),
            )
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
            wallet = self._mobile_wallet()
            qr = request.env['acpec.fuel.qr'].sudo().search([
                ('public_code', '=', kwargs.get('public_code')),
                ('wallet_id', '=', wallet.id),
            ], limit=1)
            if not qr:
                raise ValidationError(_('QR introuvable.'))

            child = qr.action_separer_valid_to_child(
                idempotency_key=kwargs.get('idempotency_key'),
            )
            source_payload = self._qr_payload(qr)
            child_payload = self._qr_payload(child)
            source_payload['technical_lines'] = self._qr_technical_lines_payload(qr)
            child_payload['technical_lines'] = self._qr_technical_lines_payload(child)
            return self._json_response({'source': source_payload, 'new_qr': child_payload})
        except Exception as exc:
            return self._handle_exception_response(exc)

    def _transfer_payload(self, transfer):
        return {
            'id': transfer.id,
            'name': transfer.name,
            'public_code': transfer.public_code,
            'state': transfer.state,
            'amount_total': transfer.amount_total,
            'face_qty_total': transfer.face_qty_total,
            'source_partner': transfer.source_partner_id.display_name,
            'dest_partner': transfer.dest_partner_id.display_name,
            'confirmed_at': fields.Datetime.to_string(transfer.confirmed_at) if transfer.confirmed_at else False,
            'note': transfer.note or False,
            'lines': [{
                'carnet_type_code': line.carnet_type_id.code,
                'carnet_type_name': line.carnet_type_id.name,
                'face_value': line.face_value,
                'face_count': line.face_count,
                'carnet_qty': line.carnet_qty,
                'qty_faces': line.qty_faces,
                'amount_total': line.amount_total,
                'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
            } for line in transfer.line_ids],
        }

    @http.route(
        '/api/acpec/fueltoken/v1/mobile/carnets/transfer',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False,
    )
    def transfer_carnets(self, **kwargs):
        """Transfert de carnets complets vers un autre client identifié par numéro de téléphone.

        Corps JSON attendu :
            recipient_phone  (str, obligatoire) — numéro de téléphone/login du destinataire
            lines            (list, obligatoire) — liste de {face_line_id, carnet_qty}
            note             (str, optionnel)
            idempotency_key  (str, optionnel)

        Règles métier vérifiées :
            - Le destinataire existe, appartient à la même société, a le groupe FuelToken Client.
            - Le transfert ne peut pas être vers soi-même.
            - Chaque face_line appartient au wallet source.
            - Les faces sont disponibles (non en QR actif/bloqué).
            - La face_line n'est pas expirée.
            - Le transfert porte sur des carnets complets (carnet_qty × face_count).
            - L'expiration d'origine est conservée sur le wallet destinataire.
        """
        try:
            self._require_keys(kwargs, ['recipient_phone', 'lines'])
            source_user = self._require_mobile_auth()
            self._require_fuel_group(source_user, 'client')
            wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                source_user.partner_id, source_user.company_id,
            )

            # ── 1. Identifier le destinataire par téléphone (login) ──────────
            recipient_phone = self._get_clean_str(kwargs, 'recipient_phone')
            if not recipient_phone:
                raise ValidationError(_('Le numéro de téléphone du destinataire est requis.'))

            recipient_user = request.env['res.users'].sudo().search([
                ('login', '=', recipient_phone),
                ('active', '=', True),
                ('company_ids', 'in', [wallet.company_id.id]),
            ], limit=1)
            if not recipient_user:
                raise ValidationError(
                    _("Aucun compte trouvé pour le numéro '%s'.") % recipient_phone
                )
            if recipient_user.id == source_user.id:
                raise ValidationError(_('Impossible de transférer vers votre propre compte.'))
            if not self._has_group_safe(recipient_user, 'acpec_fueltoken_base.group_fuel_user'):
                raise ValidationError(_('Le destinataire ne possède pas de compte FuelToken actif.'))

            # ── 2. Idempotence (vérification avant création) ─────────────────
            idempotency_key = self._get_clean_str(kwargs, 'idempotency_key') or False
            if idempotency_key:
                existing = request.env['acpec.fuel.carnet.transfer'].sudo().search([
                    ('source_wallet_id', '=', wallet.id),
                    ('idempotency_key', '=', idempotency_key),
                ], limit=1)
                if existing and existing.state == 'confirmed':
                    return self._json_response(self._transfer_payload(existing))

            # ── 3. Wallet destinataire (find or create) ──────────────────────
            dest_wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                recipient_user.partner_id, wallet.company_id,
            )

            # ── 4. Construire les lignes de transfert ────────────────────────
            raw_lines = kwargs.get('lines') or []
            if not raw_lines:
                raise ValidationError(_('Au moins une ligne de transfert est requise.'))

            transfer_line_vals = []
            for item in raw_lines:
                face_line_id = self._get_optional_int(item, 'face_line_id', 0)
                carnet_qty = self._get_optional_int(item, 'carnet_qty', 0)
                if not face_line_id or face_line_id <= 0:
                    raise ValidationError(_("Paramètre 'face_line_id' invalide ou manquant."))
                if not carnet_qty or carnet_qty <= 0:
                    raise ValidationError(_("Paramètre 'carnet_qty' doit être un entier positif."))
                transfer_line_vals.append({
                    'face_line_id': face_line_id,
                    'carnet_qty': carnet_qty,
                })

            # ── 5. Créer et confirmer le transfert ───────────────────────────
            with request.env.cr.savepoint():
                transfer = request.env['acpec.fuel.carnet.transfer'].sudo().create({
                    'source_wallet_id': wallet.id,
                    'dest_wallet_id': dest_wallet.id,
                    'company_id': wallet.company_id.id,
                    'note': self._get_clean_str(kwargs, 'note') or False,
                    'idempotency_key': idempotency_key or False,
                    'line_ids': [(0, 0, vals) for vals in transfer_line_vals],
                })
                transfer.action_confirm()

            return self._json_response(self._transfer_payload(transfer))
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route(
        '/api/acpec/fueltoken/v1/mobile/carnets/transfers',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False,
    )
    def transfer_list(self, **kwargs):
        """Historique des transferts du client authentifié (source et destinataire)."""
        try:
            user = self._require_mobile_auth()
            self._require_fuel_group(user, 'client')
            limit = max(1, min(self._get_optional_int(kwargs, 'limit', 20), 100))
            offset = max(0, self._get_optional_int(kwargs, 'offset', 0))
            direction = kwargs.get('direction')  # 'sent' | 'received' | None (tous)

            domain = ['|',
                ('source_partner_id', '=', user.partner_id.id),
                ('dest_partner_id', '=', user.partner_id.id),
            ]
            if direction == 'sent':
                domain = [('source_partner_id', '=', user.partner_id.id)]
            elif direction == 'received':
                domain = [('dest_partner_id', '=', user.partner_id.id)]

            total = request.env['acpec.fuel.carnet.transfer'].sudo().search_count(domain)
            records = request.env['acpec.fuel.carnet.transfer'].sudo().search(
                domain, order='id desc', limit=limit, offset=offset,
            )
            return self._json_response({
                'items': [self._transfer_payload(t) for t in records],
                'count': total,
                'limit': limit,
                'offset': offset,
                'has_more': (offset + len(records)) < total,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

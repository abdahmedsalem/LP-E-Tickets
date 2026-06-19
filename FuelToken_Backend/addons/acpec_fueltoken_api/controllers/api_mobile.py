from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from .api_common import AcpecFuelTokenApiCommon


class AcpecFuelTokenMobileApi(AcpecFuelTokenApiCommon):

    def _carnet_type_label(self, carnet):
        if not carnet:
            return False
        return carnet.name or carnet.code or _('Carnet de tickets')

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
            'generated_at': fields.Datetime.to_string(qr.create_date) if qr.create_date else False,
            'consumed_at': fields.Datetime.to_string(qr.consumed_at) if qr.consumed_at else False,
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

    def _tx_type_label(self, tx):
        return dict(tx._fields['transaction_type'].selection).get(tx.transaction_type, tx.transaction_type)

    def _history_carnet_type(self, line):
        face_line = line.face_line_id
        if face_line and face_line.carnet_type_id:
            return face_line.carnet_type_id
        purchase_line = line.purchase_line_id
        if purchase_line and purchase_line.carnet_type_id:
            return purchase_line.carnet_type_id
        return False

    def _history_line_expiration(self, line, fallback=False):
        transaction = line.transaction_id
        if transaction and transaction.transaction_type == 'purchase_submitted':
            return fallback or False

        face_line = line.face_line_id
        if face_line and face_line.expires_at:
            return face_line.expires_at

        purchase_line = line.purchase_line_id
        validity_days = 0
        if purchase_line and purchase_line.carnet_type_id:
            validity_days = int(purchase_line.carnet_type_id.validity_days or 0)
        if validity_days > 0:
            purchase = transaction.purchase_id if transaction and transaction.purchase_id else False
            base = (
                (purchase.approved_at if purchase else False)
                or (purchase.submitted_at if purchase else False)
                or (transaction.create_date if transaction else False)
                or fields.Datetime.now()
            )
            return fields.Datetime.add(base, days=validity_days)
        return fallback or False

    def _history_line_payload(self, line, fallback_expiration=False):
        carnet_type = self._history_carnet_type(line)
        expiration = self._history_line_expiration(line, fallback_expiration)
        face_count = 0
        if carnet_type:
            face_count = int(carnet_type.face_count or 0)
        elif line.purchase_line_id:
            face_count = int(line.purchase_line_id.face_count or 0)
        return {
            'id': line.id,
            'purchase_id': line.purchase_id.id if line.purchase_id else False,
            'purchase_line_id': line.purchase_line_id.id if line.purchase_line_id else False,
            'face_line_id': line.face_line_id.id if line.face_line_id else False,
            'carnet_type_id': carnet_type.id if carnet_type else False,
            'carnet_type_code': carnet_type.code if carnet_type else False,
            'carnet_type_name': self._carnet_type_label(carnet_type) if carnet_type else False,
            'carnet_size': face_count,
            'face_count': face_count,
            'face_value': line.face_value,
            'qty': line.qty,
            'amount': line.amount,
            'qr_id': line.qr_id.id if line.qr_id else False,
            'qr_line_id': line.qr_line_id.id if line.qr_line_id else False,
            'transfer_id': line.transfer_id.id if line.transfer_id else False,
            'expiration_date': fields.Datetime.to_string(expiration) if expiration else False,
        }

    def _purchase_history_line_payload(self, purchase, line, fallback_expiration=False):
        carnet_type = line.carnet_type_id
        expiration = fallback_expiration
        if not expiration and carnet_type and int(carnet_type.validity_days or 0) > 0:
            base = purchase.approved_at or purchase.submitted_at or purchase.create_date or fields.Datetime.now()
            expiration = fields.Datetime.add(base, days=int(carnet_type.validity_days or 0))
        return {
            'id': line.id,
            'purchase_id': purchase.id,
            'purchase_line_id': line.id,
            'carnet_type_id': carnet_type.id,
            'carnet_type_code': carnet_type.code,
            'carnet_type_name': self._carnet_type_label(carnet_type),
            'carnet_size': int(carnet_type.face_count or 0),
            'face_count': int(carnet_type.face_count or 0),
            'face_value': line.face_value,
            'carnet_qty': line.carnet_qty,
            'amount_total': line.amount_total,
            'qty': line.generated_face_qty,
            'amount': line.amount_total,
            'expiration_date': fields.Datetime.to_string(expiration) if expiration else False,
        }

    def _purchase_event_state(self, tx):
        if tx.transaction_type == 'purchase_submitted':
            return 'submitted'
        if tx.transaction_type == 'purchase_approved':
            return 'approved'
        return tx.purchase_id.state if tx.purchase_id else False

    def _tx_payload(self, tx):
        purchase = tx.purchase_id
        transfer = tx.transfer_id
        purchase_event_state = self._purchase_event_state(tx)
        is_purchase_submitted = tx.transaction_type == 'purchase_submitted'
        is_purchase_approved = tx.transaction_type == 'purchase_approved'

        # Direction du transfert de carnets : sortant (source) ou entrant (dest)
        transfer_direction = False
        transfer_other_party = False
        if transfer:
            wallet = tx.wallet_id
            if wallet and transfer.source_wallet_id == wallet:
                transfer_direction = 'outgoing'
                transfer_other_party = transfer.dest_partner_id.display_name or False
            elif wallet and transfer.dest_wallet_id == wallet:
                transfer_direction = 'incoming'
                transfer_other_party = transfer.source_partner_id.display_name or False

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
            'state': purchase_event_state,
            'purchase_state': purchase_event_state,
            'purchase_current_state': purchase.state if purchase else False,
            'submitted_at': fields.Datetime.to_string(tx.purchase_submitted_at) if tx.purchase_submitted_at else False,
            'approved_at': fields.Datetime.to_string(tx.purchase_approved_at) if is_purchase_approved and tx.purchase_approved_at else False,
            'approved_by': purchase.approved_by.name if is_purchase_approved and purchase and purchase.approved_by else False,
            'rejected_at': fields.Datetime.to_string(tx.purchase_rejected_at) if not is_purchase_submitted and tx.purchase_rejected_at else False,
            'rejected_by': purchase.rejected_by.name if not is_purchase_submitted and purchase and purchase.rejected_by else False,
            'rejection_reason': False if is_purchase_submitted else (tx.purchase_rejection_reason or False),
            'qr_id': tx.qr_id.id if tx.qr_id else False,
            'qr_public_code': tx.qr_id.public_code if tx.qr_id else False,
            'parent_qr_id': tx.parent_qr_id.id if tx.parent_qr_id else False,
            'parent_qr_public_code': tx.parent_qr_id.public_code if tx.parent_qr_id else False,
            'station_id': tx.station_id.id if tx.station_id else False,
            'station_name': tx.station_id.name if tx.station_id else False,
            'note': tx.note or False,
            # Transfert de carnets : direction et autre partie
            'transfer_id': transfer.id if transfer else False,
            'transfer_direction': transfer_direction,
            'transfer_other_party': transfer_other_party,
            'lines': [self._history_line_payload(line) for line in tx.line_ids],
        }

    def _purchase_submission_payload(self, purchase, wallet):
        created_at = purchase.submitted_at or purchase.create_date
        return {
            'id': f'purchase-submitted-{purchase.id}',
            'name': purchase.name,
            'transaction_type': 'purchase_submitted',
            'transaction_type_label': 'Demande d’achat soumise',
            'amount_total': purchase.amount_total,
            'qty_total': purchase.face_qty_total,
            'created_at': fields.Datetime.to_string(created_at) if created_at else False,
            'wallet_id': wallet.id if wallet else False,
            'purchase_id': purchase.id,
            'purchase_name': purchase.name,
            'purchase_public_code': purchase.public_code,
            'state': 'submitted',
            'purchase_state': 'submitted',
            'purchase_current_state': purchase.state,
            'submitted_at': fields.Datetime.to_string(purchase.submitted_at) if purchase.submitted_at else False,
            'approved_at': False,
            'approved_by': False,
            'rejected_at': False,
            'rejected_by': False,
            'rejection_reason': False,
            'qr_id': False,
            'qr_public_code': False,
            'parent_qr_id': False,
            'parent_qr_public_code': False,
            'station_id': False,
            'station_name': False,
            'note': _('Demande d’achat en attente de validation') if purchase.state == 'submitted' else False,
            'lines': [
                dict(self._purchase_history_line_payload(purchase, line), expiration_date=False)
                for line in purchase.line_ids
            ],
        }

    def _history_sort_key(self, item):
        """Retourne une clé de tri ISO pour un élément d'historique.

        Odoo peut retourner False au lieu de None pour les champs datetime vides ;
        on normalise en chaîne vide pour éviter une erreur de comparaison.
        """
        for key in ('created_at', 'submitted_at', 'approved_at', 'rejected_at', 'date'):
            val = item.get(key)
            if val and isinstance(val, str) and val.strip():
                return val.strip()
        return ''

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
                'carnet_type_name': self._carnet_type_label(carnet),
                'face_value': face_value,
                'qty_available': qty_available,
                'amount_available': qty_available * face_value,
                'qty_qr_active': item.get('qty_qr_active') or 0,
                'qty_qr_blocked': item.get('qty_qr_blocked') or 0,
                'qty_consumed': item.get('qty_consumed') or 0,
                'qty_expired': item.get('qty_expired') or 0,
            })
        return items

    def _mobile_carnet_type_payload(self, rec):
        currency = rec.currency_id or rec.company_id.currency_id
        face_count = rec.face_count or 0
        face_value = rec.face_value or 0
        carnet_amount = rec.carnet_amount or (face_count * face_value)
        sequence = getattr(rec, 'sequence', 0)
        try:
            ticket_face = rec.ticket_face_id
        except Exception:
            ticket_face = False

        return {
            'id': rec.id,
            'code': rec.code or False,
            'name': self._carnet_type_label(rec),
            'display_name': self._carnet_type_label(rec),

            'ticket_face_id': ticket_face.id if ticket_face else False,
            'ticket_face_name': ticket_face.name if ticket_face else False,

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

    @http.route('/api/acpec/fueltoken/v1/mobile/carnet-types', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/wallet/current', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def create_purchase(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines', 'proof_data'])
            self._require_sensitive_action_pin(kwargs, purpose='purchase_create')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def purchases(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            limit, offset = self._pagination_params(kwargs, default_limit=50, max_limit=100)
            include_meta = self._include_pagination_meta(kwargs)
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
                result.append({
                    'id': p.id,
                    'name': p.name,
                    'public_code': p.public_code,
                    'state': p.state,
                    'amount_total': p.amount_total,
                    'face_qty_total': p.face_qty_total,
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

    @http.route('/api/acpec/fueltoken/v1/mobile/purchases/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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
                lines.append(self._purchase_history_line_payload(purchase, line))
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

    @http.route('/api/acpec/fueltoken/v1/mobile/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def transactions(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            tx_model = request.env['acpec.fuel.transaction'].sudo()
            purchase_model = request.env['acpec.fuel.purchase'].sudo()
            date_from, date_to = self._date_range_params(kwargs)
            limit, offset = self._pagination_params(kwargs, default_limit=20, max_limit=200)
            include_meta = self._include_pagination_meta(kwargs)
            transaction_type_filter = self._get_clean_str(kwargs, 'transaction_type')
            domain = [('wallet_id', '=', wallet.id)]
            tx_filter_state, tx_filter_value, tx_filter_error = self._apply_transaction_type_filter(
                domain,
                transaction_type_filter,
            )
            if tx_filter_error:
                return tx_filter_error
            if date_from:
                domain.append(('create_date', '>=', fields.Datetime.to_string(date_from)))
            if date_to:
                domain.append(('create_date', '<=', fields.Datetime.to_string(date_to)))

            # Fallback défensif : une soumission doit désormais avoir sa vraie
            # transaction purchase_submitted. On ne synthétise que les rares achats
            # soumis sans transaction, pour éviter les doublons dans l'historique.
            # Si le client filtre sur un autre type, ce fallback ne doit pas polluer
            # le résultat.
            include_submitted_fallback = tx_filter_state != 'ok' or tx_filter_value == 'purchase_submitted'
            submitted_domain = [
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
                ('state', '=', 'submitted'),
            ]
            submitted_purchases = purchase_model.browse()
            if include_submitted_fallback:
                submitted_purchases = purchase_model.search(
                    submitted_domain,
                    order='submitted_at desc, id desc',
                )
            submitted_items = []
            existing_purchase_ids = set()
            submitted_purchase_ids = submitted_purchases.ids
            purchase_ids_with_submitted_tx = set()
            if submitted_purchase_ids:
                purchase_ids_with_submitted_tx = set(tx_model.search([
                    ('wallet_id', '=', wallet.id),
                    ('purchase_id', 'in', submitted_purchase_ids),
                    ('transaction_type', '=', 'purchase_submitted'),
                ]).mapped('purchase_id').ids)
            for purchase in submitted_purchases:
                if purchase.id in purchase_ids_with_submitted_tx:
                    continue
                payload = self._purchase_submission_payload(purchase, wallet)
                created_at = self._parse_datetime_param(payload.get('created_at'), 'created_at') if payload.get('created_at') else False
                if date_from and created_at and created_at < date_from:
                    continue
                if date_to and created_at and created_at > date_to:
                    continue
                submitted_items.append(payload)
                existing_purchase_ids.add(purchase.id)

            # Compte total DB pour les transactions (sans charger tous les enregistrements)
            tx_count = tx_model.search_count(domain)
            total_count = tx_count + len(submitted_items)

            # Pagination DB sur les transactions ; on décale l'offset en tenant compte
            # des achats soumis qui apparaissent toujours en tête (offset=0).
            submitted_count = len(submitted_items)
            if offset < submitted_count:
                # La page contient des achats soumis + potentiellement des transactions
                head_items = submitted_items[offset:offset + limit]
                tx_needed = limit - len(head_items)
                if tx_needed > 0:
                    tx_records = tx_model.search(domain, order='create_date desc, id desc', limit=tx_needed, offset=0)
                    tx_items = [self._tx_payload(tx) for tx in tx_records if tx.purchase_id.id not in existing_purchase_ids or not tx.purchase_id]
                    head_items += tx_items
                page_items = head_items
            else:
                tx_offset = offset - submitted_count
                tx_records = tx_model.search(domain, order='create_date desc, id desc', limit=limit, offset=tx_offset)
                page_items = [self._tx_payload(tx) for tx in tx_records]

            return self._json_response({
                'items': page_items,
                **self._pagination_meta_legacy(total_count, limit, offset, len(page_items), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/transactions/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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
            data['lines'] = [self._history_line_payload(line) for line in tx.line_ids]
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/faces', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def faces(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            transferable_only = self._get_bool_param(kwargs.get('transferable_only'), default=False)
            lines = request.env['acpec.fuel.face.line'].sudo().search([
                ('wallet_id', '=', wallet.id),
                ('qty_available', '>', 0),
            ], order='expires_at, id')
            items = []
            for line in lines:
                if transferable_only and not line.is_transferable_carnet_line():
                    continue
                carnet = line.carnet_type_id
                items.append({
                    'id': line.id,
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
                    'is_transferable': line.is_transferable_carnet_line(),
                    'transferable_carnets': line.transferable_carnet_count(),
                    'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
                })
            return self._json_response({'items': items})
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/issue', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def issue_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['lines'])
            self._require_sensitive_action_pin(kwargs, purpose='qr_issue')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/list', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/retirer', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def retirer_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code', 'lines'])
            self._require_sensitive_action_pin(kwargs, purpose='qr_retirer')
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

    @http.route('/api/acpec/fueltoken/v1/mobile/qr/separer', type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*')
    def separer_qr(self, **kwargs):
        try:
            self._require_keys(kwargs, ['public_code'])
            self._require_sensitive_action_pin(kwargs, purpose='qr_separer')
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
            'created_at': fields.Datetime.to_string(transfer.create_date) if transfer.create_date else False,
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
        '/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*',
    )
    def transfer_carnets_recipient(self, **kwargs):
        """Résout un numéro de téléphone en nom de destinataire avant transfert.

        Corps JSON : { recipient_phone: str }
        Réponse    : { recipient_name: str, recipient_phone: str }
        """
        try:
            self._require_keys(kwargs, ['recipient_phone'])
            source_user = self._require_mobile_auth()
            self._require_fuel_group(source_user, 'client')
            wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                source_user.partner_id, source_user.company_id,
            )
            recipient_phone = self._get_clean_str(kwargs, 'recipient_phone')
            if not recipient_phone:
                raise ValidationError(_('Le numéro de téléphone du destinataire est requis.'))

            # Normalisation et validation du numéro de téléphone destinataire
            parsed = self._parse_signup_identifier(recipient_phone)
            recipient_phone = parsed['login']

            recipient_user = request.env['res.users'].sudo().search([
                ('login', '=', recipient_phone),
                ('active', '=', True),
                ('company_ids', 'in', [wallet.company_id.id]),
            ], limit=1)
            if not recipient_user:
                raise ValidationError(_('Destinataire introuvable ou indisponible.'))
            if recipient_user.id == source_user.id:
                raise ValidationError(_('Impossible de transférer vers votre propre compte.'))
            if not self._has_group_safe(recipient_user, 'acpec_fueltoken_base.group_fuel_user'):
                raise ValidationError(_('Destinataire introuvable ou indisponible.'))

            return self._json_response({
                'recipient_name': recipient_user.partner_id.display_name or recipient_phone,
                'recipient_phone': recipient_phone,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

    @http.route(
        '/api/acpec/fueltoken/v1/mobile/carnets/transfer',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*',
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
            source_user = self._require_sensitive_action_pin(kwargs, purpose='carnet_transfer')
            self._require_fuel_group(source_user, 'client')
            wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                source_user.partner_id, source_user.company_id,
            )

            # ── 1. Identifier le destinataire par téléphone (login) ──────────
            recipient_phone = self._get_clean_str(kwargs, 'recipient_phone')
            if not recipient_phone:
                raise ValidationError(_('Le numéro de téléphone du destinataire est requis.'))

            # Normalisation et validation du numéro de téléphone destinataire
            parsed = self._parse_signup_identifier(recipient_phone)
            recipient_phone = parsed['login']

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
        type='jsonrpc', auth='public', methods=['POST'], csrf=False, cors='*',
    )
    def transfer_list(self, **kwargs):
        """Historique des transferts du client authentifié (source et destinataire)."""
        try:
            user = self._require_mobile_auth()
            self._require_fuel_group(user, 'client')
            limit, offset = self._pagination_params(kwargs, default_limit=20, max_limit=100)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            direction = kwargs.get('direction')  # 'sent' | 'received' | None (tous)
            state = self._get_clean_str(kwargs, 'state')

            domain = ['|',
                ('source_partner_id', '=', user.partner_id.id),
                ('dest_partner_id', '=', user.partner_id.id),
            ]
            if direction == 'sent':
                domain = [('source_partner_id', '=', user.partner_id.id)]
            elif direction == 'received':
                domain = [('dest_partner_id', '=', user.partner_id.id)]
            if state and state != 'all':
                domain.append(('state', '=', state))
            self._add_date_range_domain(domain, date_from, date_to, field_name='create_date')

            transfer_model = request.env['acpec.fuel.carnet.transfer'].sudo()
            total = transfer_model.search_count(domain)
            records = transfer_model.search(
                domain, order='id desc', limit=limit, offset=offset,
            )
            return self._json_response({
                'items': [self._transfer_payload(t) for t in records],
                **self._pagination_meta_legacy(total, limit, offset, len(records), include_meta),
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

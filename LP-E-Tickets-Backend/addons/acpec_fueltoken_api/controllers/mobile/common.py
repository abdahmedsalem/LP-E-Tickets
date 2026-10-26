import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request

from ..api_common import AcpecFuelTokenApiCommon

class MobileCommonMixin(AcpecFuelTokenApiCommon):

    PURCHASE_PAYMENT_PROOF_MAX_BYTES = 5 * 1024 * 1024
    PURCHASE_PAYMENT_PROOF_BASE64_MARGIN_CHARS = 8192
    PURCHASE_PAYMENT_PROOF_ALLOWED_EXTENSIONS = frozenset(('jpg', 'jpeg', 'png', 'pdf'))
    PURCHASE_PAYMENT_PROOF_JPEG_SIGNATURE = bytes.fromhex('ffd8ff')
    PURCHASE_PAYMENT_PROOF_PNG_SIGNATURE = bytes.fromhex('89504e470d0a1a0a')
    PURCHASE_PAYMENT_PROOF_PDF_SIGNATURE = b'%PDF-'
    MOBILE_TRANSACTIONS_DEFAULT_LIMIT = 20
    MOBILE_TRANSACTIONS_MAX_LIMIT = 100
    MOBILE_TRANSACTIONS_MAX_HISTORY_DAYS = 365

    def _purchase_payment_proof_invalid_message(self):
        # Do not wrap this message in _().
        # This helper can run in lightweight controller tests before a real
        # HTTP request/controller env exists; Odoo translation may inspect
        # self.env.uid and crash with AttributeError("'NoneType' object has no attribute 'uid'").
        return 'Preuve de paiement invalide. Formats acceptés : JPG, PNG ou PDF, taille maximale 5 Mo.'

    def _purchase_payment_proof_max_base64_chars(self):
        return ((self.PURCHASE_PAYMENT_PROOF_MAX_BYTES + 2) // 3) * 4

    def _validate_purchase_payment_proof(self, proof_filename, proof_data):
        """Validate mobile purchase payment proof before action_code.

        Only mobile purchase creation sends files in V1. The backend remains
        the authority even if the mobile app also validates type/size: unsupported
        proof payloads are rejected before the sensitive action transaction so
        an invalid file never consumes a PIN/action_code attempt.
        """
        message = self._purchase_payment_proof_invalid_message()

        def reject():
            return False, False, message

        raw_name = str(proof_filename or '').strip()
        raw_name = raw_name.replace('\\', '/')
        filename = os.path.basename(raw_name)
        if not filename or filename in ('.', '..') or '.' not in filename:
            return reject()

        extension = filename.rsplit('.', 1)[1].lower()
        if extension not in self.PURCHASE_PAYMENT_PROOF_ALLOWED_EXTENSIONS:
            return reject()

        if proof_data in (None, False, ''):
            return reject()

        max_base64_chars = self._purchase_payment_proof_max_base64_chars()
        max_text_chars = max_base64_chars + self.PURCHASE_PAYMENT_PROOF_BASE64_MARGIN_CHARS

        # DoS guard: reject an abnormally large text payload BEFORE split(),
        # join(), base64 decoding, or any other allocation-heavy processing.
        if isinstance(proof_data, bytes):
            if len(proof_data) > max_text_chars:
                return reject()
            try:
                proof_text = proof_data.decode('ascii')
            except Exception:
                return reject()
        elif isinstance(proof_data, str):
            if len(proof_data) > max_text_chars:
                return reject()
            proof_text = proof_data
        else:
            return reject()

        if proof_text.lstrip()[:5].lower() == 'data:':
            return reject()

        compact_data = ''.join(proof_text.split())
        if not compact_data or len(compact_data) > max_base64_chars:
            return reject()

        try:
            raw = base64.b64decode(compact_data, validate=True)
        except (binascii.Error, ValueError):
            return reject()

        if not raw or len(raw) > self.PURCHASE_PAYMENT_PROOF_MAX_BYTES:
            return reject()

        if extension in ('jpg', 'jpeg'):
            valid_signature = raw.startswith(self.PURCHASE_PAYMENT_PROOF_JPEG_SIGNATURE)
        elif extension == 'png':
            valid_signature = raw.startswith(self.PURCHASE_PAYMENT_PROOF_PNG_SIGNATURE)
        else:
            valid_signature = raw.startswith(self.PURCHASE_PAYMENT_PROOF_PDF_SIGNATURE)

        if not valid_signature:
            return reject()

        return filename, compact_data, False

    def _mobile_wallet(self):
        user = self._require_trusted_mobile_auth()
        self._require_fuel_group(user, 'client')
        company = self._require_fueltoken_user_company(user)
        return request.env['acpec.fuel.wallet'].sudo().get_or_create(user.partner_id, company)

    def _stamp_mobile_actor_on_transactions(self, transactions, actor_user, mobile_session=False):
        """Append mobile actor/session audit to transactions created by mobile endpoints.

        Doctrine:
        - transaction.partner_id stays wallet_id.partner_id and remains the row
          perspective / wallet owner.
        - actor_user_id / actor_partner_id are audit snapshots of the mobile user
          who executed the action.
        - counterparty is intentionally untouched for mono-wallet purchase/QR
          operations.
        """
        transactions = transactions.sudo().exists()
        if not transactions:
            return transactions

        actor_user = request.env['res.users'].sudo().browse(
            actor_user.id if hasattr(actor_user, 'id') else int(actor_user or 0)
        ).exists()
        if not actor_user:
            return transactions

        vals = {}
        fields_map = transactions._fields
        if 'actor_user_id' in fields_map:
            vals['actor_user_id'] = actor_user.id
        if 'actor_partner_id' in fields_map and actor_user.partner_id:
            vals['actor_partner_id'] = actor_user.partner_id.id

        if mobile_session:
            mobile_session = mobile_session.sudo().exists()
            if mobile_session:
                if 'mobile_session_id' in fields_map:
                    vals['mobile_session_id'] = mobile_session.id
                if 'device_uid' in fields_map and mobile_session.device_uid:
                    vals['device_uid'] = mobile_session.device_uid

        if vals:
            transactions.with_context(allow_fuel_transaction_update=True).write(vals)
        return transactions

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
            'carnet_type_name': self._carnet_type_label(
                line.face_line_id.carnet_type_id
            ),
            'face_value': line.face_value,
            'qty': line.qty,
            'state': line.state,
            'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
        } for line in qr.line_ids]

    def _tx_type_label(self, tx):
        return dict(tx._fields['transaction_type'].selection).get(tx.transaction_type, tx.transaction_type)

    def _mobile_transactions_date_range_params(self, params):
        date_from, date_to = self._date_range_params(params)
        if date_to and not date_from:
            raise ValidationError('date_from est obligatoire lorsque date_to est fourni.')

        if date_from:
            effective_date_to = date_to or fields.Datetime.now()
            if effective_date_to < date_from:
                raise ValidationError('date_to doit être postérieure ou égale à date_from.')
            if (effective_date_to - date_from).days > self.MOBILE_TRANSACTIONS_MAX_HISTORY_DAYS:
                raise ValidationError(
                    'La période demandée ne peut pas dépasser %s jours.'
                    % self.MOBILE_TRANSACTIONS_MAX_HISTORY_DAYS
                )

        return date_from, date_to

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
            'ticket_transfer_id': line.ticket_transfer_id.id if line.ticket_transfer_id else False,
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

    def _purchase_proof_attachments(self, purchase):
        attachments = purchase.sudo().proof_attachment_ids
        if not attachments:
            attachments = request.env['ir.attachment'].sudo().search([
                ('res_model', '=', purchase._name),
                ('res_id', '=', purchase.id),
            ])
        return attachments

    def _purchase_proof_attachment_payload(self, attachment, include_data=False):
        mimetype = attachment.mimetype or False
        payload = {
            'id': attachment.id,
            'name': attachment.name,
            'filename': attachment.name,
            'mimetype': mimetype,
            'file_size': attachment.file_size or 0,
            'size': attachment.file_size or 0,
            'url': '/web/content/%s' % attachment.id,
            'download_url': '/web/content/%s?download=true' % attachment.id,
        }
        if include_data:
            proof_data = attachment.sudo().datas or False
            if isinstance(proof_data, bytes):
                proof_data = proof_data.decode('ascii')
            payload.update({
                'proof_data': proof_data,
                'payment_proof_data': proof_data,
                'attachment_data': proof_data,
                'image_data': proof_data,
                'proof_image_data': proof_data,
            })
        return payload

    def _purchase_event_state(self, tx):
        # Patch43M14: rejection is carried by acpec.fuel.purchase, not by a
        # dedicated purchase_rejected transaction_type. A rejected purchase keeps
        # its purchase_submitted TX, but the mobile payload must expose the
        # effective business state as rejected.
        if tx.purchase_id and tx.purchase_id.state == 'rejected':
            return 'rejected'
        if tx.transaction_type == 'purchase_submitted':
            return 'submitted'
        if tx.transaction_type == 'purchase_approved':
            return 'approved'
        return tx.purchase_id.state if tx.purchase_id else False

    def _tx_payload(self, tx):
        purchase = tx.purchase_id
        transfer = tx.transfer_id
        ticket_transfer = tx.ticket_transfer_id
        purchase_event_state = self._purchase_event_state(tx)
        is_purchase_submitted = tx.transaction_type == 'purchase_submitted'
        is_purchase_approved = tx.transaction_type == 'purchase_approved'
        # Patch43M20-B: rejected purchases do not create a new TX and do not
        # introduce a purchase_rejected type. A rejected purchase keeps the
        # submitted TX and exposes rejection through purchase_state / related
        # purchase fields.
        is_purchase_rejected = bool(purchase and purchase.state == 'rejected')

        # Direction du transfert : sortant (source) ou entrant (dest).
        transfer_direction = False
        transfer_other_party = False
        ticket_transfer_direction = False
        ticket_transfer_other_party = False
        wallet = tx.wallet_id
        if transfer:
            if wallet and transfer.source_wallet_id == wallet:
                transfer_direction = 'outgoing'
                transfer_other_party = transfer.dest_partner_id.display_name or False
            elif wallet and transfer.dest_wallet_id == wallet:
                transfer_direction = 'incoming'
                transfer_other_party = transfer.source_partner_id.display_name or False
        if ticket_transfer:
            if wallet and ticket_transfer.source_wallet_id == wallet:
                ticket_transfer_direction = 'outgoing'
                ticket_transfer_other_party = ticket_transfer.dest_partner_id.display_name or False
            elif wallet and ticket_transfer.dest_wallet_id == wallet:
                ticket_transfer_direction = 'incoming'
                ticket_transfer_other_party = ticket_transfer.source_partner_id.display_name or False

        actor_user = tx.actor_user_id if 'actor_user_id' in tx._fields else False
        counterparty_user = tx.counterparty_user_id if 'counterparty_user_id' in tx._fields else False

        return {
            'id': tx.id,
            'name': tx.operation_ref or tx.name,
            'operation_ref': tx.operation_ref or tx.name,
            'transaction_type': tx.transaction_type,
            'transaction_type_label': self._tx_type_label(tx),
            **self._transaction_economic_payload(
                tx.transaction_effect,
                tx.signed_amount,
            ),
            'amount_total': tx.amount_total,
            'qty_total': tx.qty_total,
            'date': fields.Datetime.to_string(tx.create_date) if tx.create_date else False,
            'created_at': fields.Datetime.to_string(tx.create_date) if tx.create_date else False,
            'wallet_id': tx.wallet_id.id if tx.wallet_id else False,
            'partner_id': tx.partner_id.id if tx.partner_id else False,
            'partner_name': tx.partner_id.display_name if tx.partner_id else False,
            'actor_partner_id': tx.actor_partner_id.id if tx.actor_partner_id else False,
            'actor_partner_name': tx.actor_partner_id.display_name if tx.actor_partner_id else False,
            'actor_user_id': actor_user.id if actor_user else False,
            'actor_user_name': actor_user.name if actor_user else False,
            'counterparty_partner_id': tx.counterparty_partner_id.id if tx.counterparty_partner_id else False,
            'counterparty_partner_name': tx.counterparty_partner_id.display_name if tx.counterparty_partner_id else False,
            'counterparty_user_id': counterparty_user.id if counterparty_user else False,
            'counterparty_user_name': counterparty_user.name if counterparty_user else False,
            'purchase_id': purchase.id if purchase else False,
            'purchase_name': purchase.name if purchase else False,
            'purchase_public_code': purchase.public_code if purchase else False,
            'state': purchase_event_state,
            'purchase_state': purchase_event_state,
            'purchase_current_state': purchase.state if purchase else False,
            'submitted_at': fields.Datetime.to_string(tx.purchase_submitted_at) if tx.purchase_submitted_at else False,
            'approved_at': fields.Datetime.to_string(tx.purchase_approved_at) if is_purchase_approved and tx.purchase_approved_at else False,
            'approved_by': purchase.approved_by.name if is_purchase_approved and purchase and purchase.approved_by else False,
            'rejected_at': fields.Datetime.to_string(tx.purchase_rejected_at) if is_purchase_rejected and tx.purchase_rejected_at else False,
            'rejected_by': purchase.rejected_by.name if is_purchase_rejected and purchase and purchase.rejected_by else False,
            'rejection_reason': tx.purchase_rejection_reason if is_purchase_rejected and tx.purchase_rejection_reason else False,
            'qr_id': tx.qr_id.id if tx.qr_id else False,
            'qr_name': tx.qr_id.name if tx.qr_id else False,
            'qr_public_code': tx.qr_id.public_code if tx.qr_id else False,
            'parent_qr_id': tx.parent_qr_id.id if tx.parent_qr_id else False,
            'parent_qr_name': tx.parent_qr_id.name if tx.parent_qr_id else False,
            'parent_qr_public_code': tx.parent_qr_id.public_code if tx.parent_qr_id else False,
            'station_id': tx.station_id.id if tx.station_id else False,
            'station_name': tx.station_id.name if tx.station_id else False,
            'regularization_state': tx.regularization_state or False,
            'regularization_reference': tx.regularization_reference or False,
            'regularization_date': fields.Datetime.to_string(tx.regularization_date) if tx.regularization_date else False,
            'regularized_by': tx.regularized_by_id.name if tx.regularized_by_id else False,
            'note': tx.note or False,
            # Transfert de carnets : direction et autre partie
            'transfer_id': transfer.id if transfer else False,
            'transfer_direction': transfer_direction,
            'transfer_other_party': transfer_other_party,
            # Transfert de tickets : direction et autre partie
            'ticket_transfer_id': ticket_transfer.id if ticket_transfer else False,
            'ticket_transfer_direction': ticket_transfer_direction,
            'ticket_transfer_other_party': ticket_transfer_other_party,
            'lines': [self._history_line_payload(line) for line in tx.line_ids],
        }

    def _purchase_submission_payload(self, purchase, wallet):
        created_at = purchase.submitted_at or purchase.create_date
        return {
            'id': f'purchase-submitted-{purchase.id}',
            'name': purchase.name,
            'transaction_type': 'purchase_submitted',
            'transaction_type_label': 'Demande d’achat soumise',
            **self._transaction_economic_payload('no_effect', 0.0),
            'amount_total': purchase.amount_total,
            'qty_total': purchase.face_qty_total,
            'date': fields.Datetime.to_string(created_at) if created_at else False,
            'created_at': fields.Datetime.to_string(created_at) if created_at else False,
            'wallet_id': wallet.id if wallet else False,
            'partner_id': wallet.partner_id.id if wallet and wallet.partner_id else False,
            'partner_name': wallet.partner_id.display_name if wallet and wallet.partner_id else False,
            'actor_partner_id': False,
            'actor_partner_name': False,
            'actor_user_id': False,
            'actor_user_name': False,
            'counterparty_partner_id': False,
            'counterparty_partner_name': False,
            'counterparty_user_id': False,
            'counterparty_user_name': False,
            'purchase_id': purchase.id,
            'purchase_name': purchase.name,
            'purchase_public_code': purchase.public_code,
            **self._purchase_payment_method_payload(purchase),
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
            'qr_name': False,
            'qr_public_code': False,
            'parent_qr_id': False,
            'parent_qr_name': False,
            'parent_qr_public_code': False,
            'station_id': False,
            'station_name': False,
            'regularization_state': False,
            'regularization_reference': False,
            'regularization_date': False,
            'regularized_by': False,
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
        groups = request.env['acpec.fuel.face.line'].sudo()._read_group(
            [('wallet_id', '=', wallet.id)],
            ['face_value'],
            ['qty_available:sum', 'qty_qr_active:sum', 'qty_qr_blocked:sum', 'qty_consumed:sum', 'qty_expired:sum', 'qty_transferred_out:sum'],
        )
        result = []
        for face_value, qty_available, qty_qr_active, qty_qr_blocked, qty_consumed, qty_expired, qty_transferred_out in groups:
            face_value = face_value or 0
            qty_available = qty_available or 0
            qty_qr_active = qty_qr_active or 0
            qty_qr_blocked = qty_qr_blocked or 0
            qty_consumed = qty_consumed or 0
            qty_expired = qty_expired or 0
            qty_transferred_out = qty_transferred_out or 0
            result.append({
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
                'qty_transferred_out': qty_transferred_out,
                'amount_transferred_out': qty_transferred_out * face_value,
            })
        return sorted(result, key=lambda item: item['face_value'])

    def _wallet_breakdown_by_carnet_type(self, wallet):
        groups = request.env['acpec.fuel.face.line'].sudo()._read_group(
            [('wallet_id', '=', wallet.id)],
            ['carnet_type_id'],
            ['qty_available:sum', 'qty_qr_active:sum', 'qty_qr_blocked:sum', 'qty_consumed:sum', 'qty_expired:sum', 'qty_transferred_out:sum'],
        )
        result = []
        for carnet_type, qty_available, qty_qr_active, qty_qr_blocked, qty_consumed, qty_expired, qty_transferred_out in groups:
            if not carnet_type:
                continue
            face_value = carnet_type.face_value or 0
            qty_available = qty_available or 0
            qty_qr_active = qty_qr_active or 0
            qty_qr_blocked = qty_qr_blocked or 0
            qty_consumed = qty_consumed or 0
            qty_expired = qty_expired or 0
            qty_transferred_out = qty_transferred_out or 0
            result.append({
                'carnet_type_id': carnet_type.id,
                'carnet_type_code': carnet_type.code,
                'carnet_type_name': self._carnet_type_label(carnet_type),
                'face_count': carnet_type.face_count,
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
                'qty_transferred_out': qty_transferred_out,
                'amount_transferred_out': qty_transferred_out * face_value,
            })
        return sorted(result, key=lambda item: (item['face_value'], item['carnet_type_code'] or ''))

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
            'name': rec.name or rec.code or _('Carnet de tickets'),
            'name_ar': rec.name_ar or False,
            'carnet_type_name': self._carnet_type_label(rec),
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

    def _mobile_payment_method_payload(self, record):
        return {
            'id': record.id,
            'code': record.code,
            'name': record.name,
            'display_name': record.name,
            'merchant_code': record.merchant_code,
            'logo_data': record.image_128 or False,
            'image_128': record.image_128 or False,
            'instructions': record.instructions or False,
            'color_hex': record.color_hex or False,
            'sequence': record.sequence,
            'company_id': record.company_id.id if record.company_id else False,
            'company_name': record.company_id.name if record.company_id else False,
        }

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
                'face_line_id': line.face_line_id.id,
                'dest_face_line_id': line.dest_face_line_id.id if line.dest_face_line_id else False,
                'carnet_no': line.face_line_id.carnet_no,
                'carnet_short_code': line.face_line_id.carnet_short_code,
                'lot_short_code': line.face_line_id.lot_short_code,
                'carnet_sequence': line.face_line_id.carnet_sequence,
                'carnet_type_code': line.carnet_type_id.code,
                'carnet_type_name': self._carnet_type_label(line.carnet_type_id),
                'face_value': line.face_value,
                'face_count': line.face_count,
                'carnet_qty': line.carnet_qty,
                'qty_faces': line.qty_faces,
                'amount_total': line.amount_total,
                'expires_at': fields.Datetime.to_string(line.expires_at) if line.expires_at else False,
            } for line in transfer.line_ids],
        }

    def _ticket_transfer_payload(self, transfer):
        return {
            'id': transfer.id,
            'name': transfer.name,
            'public_code': transfer.public_code,
            'state': transfer.state,
            'created_at': fields.Datetime.to_string(transfer.create_date) if transfer.create_date else False,
            'amount_total': transfer.amount_total,
            'qty_tickets_total': transfer.face_qty_total,
            'face_qty_total': transfer.face_qty_total,
            'source_partner': transfer.source_partner_id.display_name,
            'dest_partner': transfer.dest_partner_id.display_name,
            'confirmed_at': fields.Datetime.to_string(transfer.confirmed_at) if transfer.confirmed_at else False,
            'note': transfer.note or False,
            'lines': [{
                'source_face_line_id': line.source_face_line_id.id,
                'dest_face_line_id': line.dest_face_line_id.id if line.dest_face_line_id else False,
                'source_carnet_no': line.source_face_line_id.carnet_no,
                'source_carnet_short_code': line.source_face_line_id.carnet_short_code,
                'dest_carnet_no': line.dest_face_line_id.carnet_no if line.dest_face_line_id else False,
                'dest_carnet_short_code': line.dest_face_line_id.carnet_short_code if line.dest_face_line_id else False,
                'lot_short_code': line.source_face_line_id.lot_short_code,
                'carnet_type_code': line.carnet_type_id.code,
                'carnet_type_name': self._carnet_type_label(line.carnet_type_id),
                'face_value': line.face_value,
                'qty_tickets': line.qty_faces,
                'qty_faces': line.qty_faces,
                'amount_total': line.amount_total,
                'expires_at': fields.Datetime.to_string(line.source_face_line_id.expires_at) if line.source_face_line_id.expires_at else False,
            } for line in transfer.line_ids],
        }

    def _finalize_idempotent_transfer_replay(self, transfer, source_user, request_hash, purpose, kwargs):
        if transfer.request_hash and transfer.request_hash != request_hash:
            self._raise_sensitive_action_error(
                code='IDEMPOTENCY_PAYLOAD_MISMATCH',
                public_code='REQUEST_REFUSED',
                purpose=purpose,
                debug_reason='idempotency_payload_mismatch',
                user=source_user,
                params=kwargs,
            )
        if transfer.state != 'confirmed':
            mobile_session = self._get_mobile_session(required=True)
            transfer._confirm_mobile_internal(
                actor_user=source_user,
                mobile_session=mobile_session,
            )
        return transfer

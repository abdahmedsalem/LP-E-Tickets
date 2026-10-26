import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileTransactionsMixin:

    @http.route('/api/acpec/fueltoken/v1/mobile/transactions', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def transactions(self, **kwargs):
        try:
            wallet = self._mobile_wallet()
            tx_model = request.env['acpec.fuel.transaction'].sudo()
            purchase_model = request.env['acpec.fuel.purchase'].sudo()
            date_from, date_to = self._mobile_transactions_date_range_params(kwargs)
            limit, offset = self._pagination_params(
                kwargs,
                default_limit=self.MOBILE_TRANSACTIONS_DEFAULT_LIMIT,
                max_limit=self.MOBILE_TRANSACTIONS_MAX_LIMIT,
            )
            include_meta = self._include_pagination_meta(kwargs)
            transaction_type_filter = self._get_clean_str(kwargs, 'transaction_type')
            # Mobile-user history is scoped by the transaction row perspective:
            # partner_id is wallet_id.partner_id. Do not filter on actor or
            # counterparty: transfer rows deliberately share the same global
            # actor/counterparty snapshots while each row belongs to a different
            # wallet partner.
            domain = [
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
            ]
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
                    ('partner_id', '=', wallet.partner_id.id),
                    ('company_id', '=', wallet.company_id.id),
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
                ('partner_id', '=', wallet.partner_id.id),
                ('company_id', '=', wallet.company_id.id),
            ], limit=1)
            if not tx:
                raise ValidationError('Transaction introuvable.')
            data = self._tx_payload(tx)
            data['lines'] = [self._history_line_payload(line) for line in tx.line_ids]
            return self._json_response(data)
        except Exception as exc:
            return self._handle_exception_response(exc)

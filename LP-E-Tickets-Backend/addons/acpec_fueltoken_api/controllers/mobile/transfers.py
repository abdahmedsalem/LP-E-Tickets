import base64
import binascii
import os
import time
import psycopg2
from odoo import http, _, fields
from odoo.exceptions import ValidationError
from odoo.http import request


class MobileTransfersMixin:

    @http.route(
        '/api/acpec/fueltoken/v1/mobile/tickets/transfer',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False,
    )
    def transfer_tickets(self, **kwargs):
        """Transfert de tickets entiers disponibles vers un autre client mobile."""
        endpoint = 'mobile.tickets.transfer'
        operation = 'ticket_transfer'
        started_at = time.monotonic()
        self._log_api_diagnostic_in(endpoint, kwargs, operation=operation)
        try:
            self._require_keys(kwargs, ['recipient_phone', 'lines'])
            with self._sensitive_action_transaction(kwargs, purpose='ticket_transfer') as source_user:
                self._require_fuel_group(source_user, 'client')
                company = self._require_fueltoken_user_company(source_user)
                source_wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                    source_user.partner_id, company,
                )

                recipient_phone = self._get_clean_str(kwargs, 'recipient_phone')
                if not recipient_phone:
                    raise ValidationError('Le numéro de téléphone du destinataire est requis.')
                parsed = self._parse_signup_identifier(recipient_phone)
                recipient_phone = parsed['login']

                recipient_user = request.env['res.users'].sudo().search([
                    ('login', '=', recipient_phone),
                    ('active', '=', True),
                    ('company_ids', 'in', [source_wallet.company_id.id]),
                ], limit=1)
                if not recipient_user:
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='ticket_transfer',
                        debug_reason='recipient_not_found',
                        user=source_user,
                        params=kwargs,
                    )
                if recipient_user.id == source_user.id:
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='ticket_transfer',
                        debug_reason='recipient_self_transfer',
                        user=source_user,
                        params=kwargs,
                    )
                if not self._has_group_safe(recipient_user, 'acpec_fueltoken_base.group_fuel_user'):
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='ticket_transfer',
                        debug_reason='recipient_not_allowed',
                        user=source_user,
                        params=kwargs,
                    )

                note = self._get_clean_str(kwargs, 'note') or False

                idempotency_key = self._require_idempotency_key(kwargs, purpose='ticket_transfer')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='ticket_transfer')
                existing = request.env['acpec.fuel.ticket.transfer'].sudo().search([
                    ('source_wallet_id', '=', source_wallet.id),
                    ('idempotency_key', '=', idempotency_key),
                ], limit=1)
                if existing:
                    if existing.request_hash and existing.request_hash != request_hash:
                        self._raise_sensitive_action_error(
                            code='IDEMPOTENCY_PAYLOAD_MISMATCH',
                            public_code='REQUEST_REFUSED',
                            purpose='ticket_transfer',
                            debug_reason='idempotency_payload_mismatch',
                            user=source_user,
                            params=kwargs,
                        )
                    if existing.state != 'confirmed':
                        mobile_session = self._get_mobile_session(required=True)
                        existing._confirm_mobile_internal(
                            actor_user=source_user,
                            mobile_session=mobile_session,
                        )
                    response = self._json_response(self._ticket_transfer_payload(existing))
                    self._log_api_diagnostic_out(endpoint, response, operation=operation, started_at=started_at)
                    return response

                dest_wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                    recipient_user.partner_id, source_wallet.company_id,
                )
                raw_lines = kwargs.get('lines') or []
                if not raw_lines:
                    raise ValidationError('Au moins une ligne de transfert est requise.')

                transfer_line_vals = []
                for item in raw_lines:
                    face_line_id = self._get_optional_int(item, 'face_line_id', 0)
                    qty_tickets = self._get_optional_int(item, 'qty_tickets', 0)
                    if not face_line_id or face_line_id <= 0:
                        raise ValidationError("Paramètre 'face_line_id' invalide ou manquant.")
                    if not qty_tickets or qty_tickets <= 0:
                        raise ValidationError("Paramètre 'qty_tickets' doit être un entier positif.")
                    transfer_line_vals.append({
                        'source_face_line_id': face_line_id,
                        'qty_faces': qty_tickets,
                    })

                transfer = False
                try:
                    with request.env.cr.savepoint():
                        transfer = request.env['acpec.fuel.ticket.transfer']._create_internal({
                            'source_wallet_id': source_wallet.id,
                            'dest_wallet_id': dest_wallet.id,
                            'company_id': source_wallet.company_id.id,
                            'note': note or False,
                            'idempotency_key': idempotency_key,
                            'request_hash': request_hash,
                            'line_ids': [(0, 0, vals) for vals in transfer_line_vals],
                        })
                        mobile_session = self._get_mobile_session(required=True)
                        transfer._confirm_mobile_internal(
                            actor_user=source_user,
                            mobile_session=mobile_session,
                        )
                except psycopg2.IntegrityError as error:
                    if getattr(error.diag, 'constraint_name', False) not in (
                        'acpec_fuel_ticket_transfer_idempotency_source_wallet_unique',
                    ):
                        raise
                    transfer = request.env['acpec.fuel.ticket.transfer'].sudo().search([
                        ('source_wallet_id', '=', source_wallet.id),
                        ('idempotency_key', '=', idempotency_key),
                    ], limit=1)
                    if not transfer:
                        raise

                transfer = self._finalize_idempotent_transfer_replay(
                    transfer,
                    source_user,
                    request_hash,
                    'ticket_transfer',
                    kwargs,
                )

                response = self._json_response(self._ticket_transfer_payload(transfer))
                self._log_api_diagnostic_out(endpoint, response, operation=operation, started_at=started_at)
                return response
        except Exception as exc:
            response = self._handle_exception_response(exc, params=kwargs, operation=operation, endpoint=endpoint)
            self._log_api_diagnostic_out(endpoint, response, operation=operation, started_at=started_at)
            return response

    @http.route(
        '/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient',
        type='jsonrpc', auth='public', methods=['POST'], csrf=False,
    )
    def transfer_carnets_recipient(self, **kwargs):
        """Résout un numéro de téléphone en nom de destinataire avant transfert.

        Corps JSON : { recipient_phone: str }
        Réponse    : { recipient_name: str, recipient_phone: str }
        """
        try:
            self._require_keys(kwargs, ['recipient_phone'])
            source_user = self._require_trusted_mobile_auth()
            self._require_fuel_group(source_user, 'client')
            company = self._require_fueltoken_user_company(source_user)
            wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                source_user.partner_id, company,
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
                return self._sensitive_refusal_response(
                    public_code='TRANSFER_REFUSED',
                    debug_reason='recipient_not_found',
                    purpose='carnet_transfer_recipient',
                    params=kwargs,
                    user=source_user,
                    company=company,
                    audit_code='RECIPIENT_NOT_ALLOWED',
                )
            if recipient_user.id == source_user.id:
                return self._sensitive_refusal_response(
                    public_code='TRANSFER_REFUSED',
                    debug_reason='recipient_self_transfer',
                    purpose='carnet_transfer_recipient',
                    params=kwargs,
                    user=source_user,
                    company=company,
                    audit_code='RECIPIENT_NOT_ALLOWED',
                )
            if not self._has_group_safe(recipient_user, 'acpec_fueltoken_base.group_fuel_user'):
                return self._sensitive_refusal_response(
                    public_code='TRANSFER_REFUSED',
                    debug_reason='recipient_not_allowed',
                    purpose='carnet_transfer_recipient',
                    params=kwargs,
                    user=source_user,
                    company=company,
                    audit_code='RECIPIENT_NOT_ALLOWED',
                )

            return self._json_response({
                'recipient_name': recipient_user.partner_id.display_name or recipient_phone,
                'recipient_phone': recipient_phone,
            })
        except Exception as exc:
            return self._handle_exception_response(exc)

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
            idempotency_key  (str, obligatoire)

        Règles métier vérifiées :
            - Le destinataire existe, appartient à la même société, a le groupe FuelToken Client.
            - Le transfert ne peut pas être vers soi-même.
            - Chaque face_line appartient au wallet source.
            - Les tickets de chaque carnet sont disponibles (non en QR actif/bloqué).
            - La face_line n'est pas expirée.
            - Le transfert porte sur des carnets complets (carnet_qty × face_count).
            - L'expiration d'origine est conservée sur le wallet destinataire.
            """
        try:
            self._require_keys(kwargs, ['recipient_phone', 'lines'])
            with self._sensitive_action_transaction(kwargs, purpose='carnet_transfer') as source_user:
                self._require_fuel_group(source_user, 'client')
                company = self._require_fueltoken_user_company(source_user)
                wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                    source_user.partner_id, company,
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
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='carnet_transfer',
                        debug_reason='recipient_not_found',
                        user=source_user,
                        params=kwargs,
                    )
                if recipient_user.id == source_user.id:
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='carnet_transfer',
                        debug_reason='recipient_self_transfer',
                        user=source_user,
                        params=kwargs,
                    )
                if not self._has_group_safe(recipient_user, 'acpec_fueltoken_base.group_fuel_user'):
                    self._raise_sensitive_action_error(
                        code='RECIPIENT_NOT_ALLOWED',
                        public_code='TRANSFER_REFUSED',
                        purpose='carnet_transfer',
                        debug_reason='recipient_not_allowed',
                        user=source_user,
                        params=kwargs,
                    )

                # ── 2. Idempotence (vérification avant création) ─────────────────
                idempotency_key = self._require_idempotency_key(kwargs, purpose='carnet_transfer')
                request_hash = self._compute_idempotency_request_hash(kwargs, purpose='carnet_transfer')
                if idempotency_key:
                    existing = request.env['acpec.fuel.carnet.transfer'].sudo().search([
                        ('source_wallet_id', '=', wallet.id),
                        ('idempotency_key', '=', idempotency_key),
                    ], limit=1)
                    if existing:
                        existing = self._finalize_idempotent_transfer_replay(
                            existing,
                            source_user,
                            request_hash,
                            'carnet_transfer',
                            kwargs,
                        )
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
                transfer = False
                try:
                    with request.env.cr.savepoint():
                        transfer = request.env['acpec.fuel.carnet.transfer']._create_internal({
                            'source_wallet_id': wallet.id,
                            'dest_wallet_id': dest_wallet.id,
                            'company_id': wallet.company_id.id,
                            'note': self._get_clean_str(kwargs, 'note') or False,
                            'idempotency_key': idempotency_key or False,
                            'request_hash': request_hash,
                            'line_ids': [(0, 0, vals) for vals in transfer_line_vals],
                        })
                        mobile_session = self._get_mobile_session(required=True)
                        transfer._confirm_mobile_internal(
                            actor_user=source_user,
                            mobile_session=mobile_session,
                        )
                except psycopg2.IntegrityError as error:
                    if getattr(error.diag, 'constraint_name', False) not in (
                        'acpec_fuel_carnet_transfer_idempotency_source_wallet_unique',
                        'acpec_fuel_carnet_transfer_idempotency_unique',
                    ):
                        raise
                    transfer = request.env['acpec.fuel.carnet.transfer'].sudo().search([
                        ('source_wallet_id', '=', wallet.id),
                        ('idempotency_key', '=', idempotency_key),
                    ], limit=1)
                    if not transfer:
                        raise

                transfer = self._finalize_idempotent_transfer_replay(
                    transfer,
                    source_user,
                    request_hash,
                    'carnet_transfer',
                    kwargs,
                )

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
            user = self._require_trusted_mobile_auth()
            self._require_fuel_group(user, 'client')
            company = self._require_fueltoken_user_company(user)
            wallet = request.env['acpec.fuel.wallet'].sudo().get_or_create(
                user.partner_id, company,
            )
            limit, offset = self._pagination_params(kwargs, default_limit=20, max_limit=100)
            include_meta = self._include_pagination_meta(kwargs)
            date_from, date_to = self._date_range_params(kwargs)
            direction = kwargs.get('direction')  # 'sent' | 'received' | None (tous)
            state = self._get_clean_str(kwargs, 'state')

            domain = [
                ('company_id', '=', wallet.company_id.id),
                '|',
                ('source_partner_id', '=', user.partner_id.id),
                ('dest_partner_id', '=', user.partner_id.id),
            ]
            if direction == 'sent':
                domain = [
                    ('company_id', '=', wallet.company_id.id),
                    ('source_partner_id', '=', user.partner_id.id),
                ]
            elif direction == 'received':
                domain = [
                    ('company_id', '=', wallet.company_id.id),
                    ('dest_partner_id', '=', user.partner_id.id),
                ]
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

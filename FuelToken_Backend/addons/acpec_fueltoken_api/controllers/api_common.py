from odoo import fields
from odoo.exceptions import AccessError, ValidationError
from odoo.http import request

from odoo.addons.acpec_mobile_auth.controllers.api_common import AcpecMobileAuthApiCommon
import hashlib
import json


class AcpecFuelTokenApiCommon(AcpecMobileAuthApiCommon):
    """FuelToken API shared helpers.

    Keep pagination/date/transaction-type filter semantics in one place so the
    mobile, station and admin controllers do not drift apart.  This class is
    module-local on purpose: generic authentication stays in acpec_mobile_auth,
    while FuelToken-specific transaction semantics stay here.
    """

    OBSOLETE_TRANSACTION_TYPES = {
        'achat_carnets': {
            'replaced_by': ['purchase_submitted', 'purchase_approved'],
            'hint': (
                "Le type de transaction 'achat_carnets' a été supprimé. "
                "Filtrez sur 'purchase_submitted' pour les demandes soumises "
                "ou sur 'purchase_approved' pour les achats approuvés."
            ),
        },
    }

    _IDEMPOTENCY_HASH_EXCLUDED_KEYS = {
        'action_code',
        'action_pin',
        'pin',
        'secret_code',
        'idempotency_key',
        'access_token',
        'refresh_token',
        'token',
        'password',
    }

    def _normalize_idempotency_hash_value(self, value):
        if isinstance(value, dict):
            return {
                str(key): self._normalize_idempotency_hash_value(val)
                for key, val in sorted(value.items(), key=lambda item: str(item[0]))
                if str(key) not in self._IDEMPOTENCY_HASH_EXCLUDED_KEYS
            }
        if isinstance(value, (list, tuple)):
            return [self._normalize_idempotency_hash_value(item) for item in value]
        return value

    def _compute_idempotency_request_hash(self, params, purpose='sensitive_action'):
        payload = {
            'purpose': purpose,
            'params': self._normalize_idempotency_hash_value(params or {}),
        }
        raw = json.dumps(
            payload,
            sort_keys=True,
            separators=(',', ':'),
            ensure_ascii=False,
            default=str,
        )
        return hashlib.sha256(raw.encode('utf-8')).hexdigest()

    def _require_idempotency_key(self, params, purpose='sensitive_action'):
        raw_value = (params or {}).get('idempotency_key')
        idempotency_key = str(raw_value).strip() if raw_value not in (None, False) else False
        if not idempotency_key:
            raise ValidationError('idempotency_key est obligatoire pour cette action sensible.')
        return idempotency_key

    def _controller_env(self):
        """Return an Odoo env usable from HTTP routes and lightweight tests."""
        test_env = getattr(self, '_test_env', None)
        if test_env:
            return test_env
        env = getattr(request, 'env', None)
        if env:
            return env
        return getattr(self, 'env', None)

    def _fueltoken_company(self):
        """Return the unique company allowed to carry FuelToken.

        FuelToken is mono-company even when the Odoo database is multi-company.
        Patch43E1 enforces the uniqueness at database level; runtime code stays
        fail-closed in case the module is misconfigured or the flag is missing.
        """
        env = self._controller_env()
        if not env:
            raise AccessError('Configuration Tickets Carburant indisponible.')
        company_model = env['res.company'].sudo()
        if 'acpec_fueltoken_enabled' not in company_model._fields:
            raise AccessError('Configuration Tickets Carburant invalide : société FuelToken non définie.')
        companies = company_model.search([('acpec_fueltoken_enabled', '=', True)], limit=2)
        if len(companies) != 1:
            raise AccessError('Configuration Tickets Carburant invalide : exactement une société FuelToken doit être active.')
        return companies

    def _fueltoken_company_domain(self, field_name='company_id'):
        company = self._fueltoken_company()
        return [(field_name, '=', company.id)]

    def _require_fueltoken_user_company(self, user):
        """Ensure a mobile FuelToken actor belongs to the unique FuelToken company."""
        if not user:
            raise AccessError('Utilisateur mobile introuvable.')
        company = self._fueltoken_company()
        if user.company_id != company or company not in user.company_ids:
            raise AccessError('Utilisateur hors société Tickets Carburant.')
        return company

    def _require_fueltoken_record_company(self, record, field_name='company_id'):
        """Ensure sudo-browsed FuelToken records belong to the unique FuelToken company."""
        if not record:
            return record
        company = self._fueltoken_company()
        for rec in record:
            if field_name not in rec._fields:
                raise AccessError('Accès refusé : objet sans société Tickets Carburant.')
            record_company = rec[field_name]
            if not record_company:
                raise AccessError('Accès refusé : société Tickets Carburant manquante.')
            if record_company != company:
                raise AccessError('Accès refusé : objet hors société Tickets Carburant.')
        return record

    def _company_domain_for_user(self, user, field_name='company_id'):
        """FuelToken runtime domain: always the unique FuelToken company.

        The inherited helper exposes all user company_ids.  That is correct for
        generic mobile auth, but FuelToken is mono-company by doctrine.
        """
        self._require_fueltoken_user_company(user)
        return self._fueltoken_company_domain(field_name=field_name)

    def _require_allowed_company(self, user, company_id=False):
        """Return company only if it is the unique FuelToken company for this user."""
        fueltoken_company = self._require_fueltoken_user_company(user)
        target_company_id = company_id or fueltoken_company.id
        company = self._controller_env()['res.company'].sudo().browse(target_company_id).exists()
        if not company:
            raise ValidationError('Société introuvable.')
        if company != fueltoken_company:
            raise AccessError('Société non autorisée pour Tickets Carburant.')
        return company

    def _check_record_company_allowed(self, user, record, field_name='company_id'):
        self._require_fueltoken_user_company(user)
        return self._require_fueltoken_record_company(record, field_name=field_name)

    def _require_user_company_membership(self, target_user, company):
        if not target_user:
            raise ValidationError('Utilisateur introuvable.')
        fueltoken_company = self._fueltoken_company()
        if company != fueltoken_company:
            raise ValidationError('La société doit être la société Tickets Carburant.')
        if target_user.company_id != fueltoken_company or fueltoken_company not in target_user.company_ids:
            raise ValidationError('L’utilisateur doit appartenir à la société Tickets Carburant.')
        return target_user

    def _transaction_type_allowed_values(self):
        env = self._controller_env()
        if not env:
            return []
        tx_model = env['acpec.fuel.transaction'].sudo()
        return [value for value, _label in tx_model._fields['transaction_type'].selection]

    def classify_transaction_type_filter(self, raw_value, allowed_values=None):
        """Classify a transaction_type filter before applying it.

        ``achat_carnets`` is intentionally obsolete: Patch 2 split it into
        ``purchase_submitted`` and ``purchase_approved``.  ``all`` and empty
        values mean "no filter" uniformly on every endpoint.
        """
        value = (str(raw_value) if raw_value not in (False, None) else '').strip()
        if not value or value == 'all':
            return 'empty', False

        obsolete = self.OBSOLETE_TRANSACTION_TYPES.get(value)
        if obsolete:
            replaced_by = list(obsolete.get('replaced_by') or [])
            hint = obsolete.get('hint') or (
                "Le type de transaction '%s' a été supprimé. Utilisez : %s."
                % (value, ', '.join(replaced_by))
            )
            return 'obsolete', {
                'transaction_type': value,
                'replaced_by': replaced_by,
                'message': hint,
            }

        allowed = set(allowed_values if allowed_values is not None else self._transaction_type_allowed_values())
        if value in allowed:
            return 'ok', value

        return 'unknown', {
            'transaction_type': value,
            'allowed_values': sorted(allowed),
            'message': "Type de transaction inconnu : '%s'." % value,
        }

    def _apply_transaction_type_filter(self, domain, raw_value):
        """Append a transaction_type domain filter or return an API error.

        Returns ``(state, value, error_response)``.  When ``error_response`` is
        not false, callers should return it immediately.
        """
        state, payload = self.classify_transaction_type_filter(raw_value)
        if state == 'obsolete':
            return state, payload, self._error_response(
                'OBSOLETE_TRANSACTION_TYPE',
                payload['message'],
                details=payload,
            )
        if state == 'unknown':
            return state, payload, self._error_response(
                'UNKNOWN_TRANSACTION_TYPE',
                payload['message'],
                details=payload,
            )
        if state == 'ok':
            domain.append(('transaction_type', '=', payload))
        return state, payload, False

    def _parse_datetime_param(self, raw_value, key_name):
        if raw_value in (False, None, ''):
            return False
        try:
            parsed = fields.Datetime.to_datetime(raw_value)
        except Exception:
            parsed = False
        if not parsed:
            raise ValidationError("Le paramètre '%s' est invalide." % key_name)
        return parsed

    def _pagination_params(self, params, default_limit=20, max_limit=100):
        limit = max(1, min(self._get_optional_int(params, 'limit', default_limit), max_limit))
        offset = max(0, self._get_optional_int(params, 'offset', 0))
        return limit, offset

    def _as_bool_param(self, value):
        if isinstance(value, bool):
            return value
        if value in (False, None, ''):
            return False
        return str(value).strip().lower() in ('1', 'true', 'yes', 'y', 'on')

    def _include_pagination_meta(self, params):
        """Opt-in flag for new pagination metadata.

        Patch 2.4.2 is intentionally contract-safe: existing endpoints keep
        their historical response shape by default.  Clients that are ready for
        the richer pagination contract can pass ``include_pagination_meta=true``
        and will receive ``next_offset`` in addition to the usual metadata.
        """
        return self._as_bool_param(params.get('include_pagination_meta'))

    def _pagination_meta(self, total, limit, offset, page_size, include_next_offset=False):
        has_more = (offset + page_size) < total
        meta = {
            'count': total,
            'limit': limit,
            'offset': offset,
            'has_more': has_more,
        }
        if include_next_offset:
            meta['next_offset'] = (offset + limit) if has_more else None
        return meta

    def _pagination_meta_count_only(self, total, limit, offset, page_size, include_full_meta=False):
        if include_full_meta:
            return self._pagination_meta(
                total, limit, offset, page_size, include_next_offset=True,
            )
        return {'count': total}

    def _pagination_meta_opt_in(self, total, limit, offset, page_size, include_full_meta=False):
        if include_full_meta:
            return self._pagination_meta(
                total, limit, offset, page_size, include_next_offset=True,
            )
        return {}

    def _pagination_meta_legacy(self, total, limit, offset, page_size, include_next_offset=False):
        return self._pagination_meta(
            total, limit, offset, page_size, include_next_offset=include_next_offset,
        )

    def _date_range_params(self, params):
        date_from = self._parse_datetime_param(params.get('date_from'), 'date_from')
        date_to = self._parse_datetime_param(params.get('date_to'), 'date_to')
        if date_from and date_to and date_from > date_to:
            raise ValidationError('La plage de dates est invalide.')
        return date_from, date_to

    def _add_date_range_domain(self, domain, date_from=False, date_to=False, field_name='create_date'):
        if date_from:
            domain.append((field_name, '>=', fields.Datetime.to_string(date_from)))
        if date_to:
            domain.append((field_name, '<=', fields.Datetime.to_string(date_to)))
        return domain

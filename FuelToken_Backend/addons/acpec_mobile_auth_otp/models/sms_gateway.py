import json
import logging
import re
import os

try:
    import requests
except Exception:  # pragma: no cover - handled at runtime
    requests = None

from odoo import _, api, models
from odoo.exceptions import ValidationError

_logger = logging.getLogger(__name__)


class AcpecSmsGateway(models.AbstractModel):
    _name = 'acpec.sms.gateway'
    _description = 'ACPEC SMS Gateway'

    @api.model
    def _get_sms_config(self):
        icp = self.env['ir.config_parameter'].sudo()
        provider = (
            icp.get_param('SMS_PROVIDER')
            or os.getenv('SMS_PROVIDER')
            or 'chinguisoft'
        ).strip().lower()
        validation_key = (
            icp.get_param('SMS_VALIDATION_KEY')
            or os.getenv('SMS_VALIDATION_KEY')
            or os.getenv('CHINGUI_SOFT_VALIDATION_KEY')
            or os.getenv('CHINGUISOFT_VALIDATION_KEY')
            or ''
        ).strip()
        token = (
            icp.get_param('SMS_TOKEN')
            or os.getenv('SMS_TOKEN')
            or os.getenv('CHINGUI_SOFT_TOKEN')
            or os.getenv('CHINGUISOFT_TOKEN')
            or ''
        ).strip()
        base_url = (
            icp.get_param('SMS_URL')
            or os.getenv('SMS_URL')
            or os.getenv('CHINGUISOFT_URL')
            or 'https://chinguisoft.com/api/sms/validation'
        ).strip()
        default_lang = (
            icp.get_param('SMS_DEFAULT_LANG')
            or os.getenv('SMS_DEFAULT_LANG')
            or 'fr'
        ).strip().lower()
        return {
            'provider': provider,
            'validation_key': validation_key,
            'token': token,
            'base_url': base_url,
            'default_lang': default_lang if default_lang in ('fr', 'ar') else 'fr',
        }

    @api.model
    def _normalize_phone(self, phone):
        digits = re.sub(r'\D+', '', phone or '')
        if len(digits) == 11 and digits.startswith('222'):
            digits = digits[3:]
        if len(digits) != 8 or digits[0] not in {'2', '3', '4'}:
            raise ValidationError(_('Le numero mobile doit contenir 8 chiffres et commencer par 2, 3 ou 4.'))
        return digits

    @api.model
    def _build_url(self, base_url, validation_key):
        base_url = (base_url or '').rstrip('/')
        if '{validation_key}' in base_url:
            return base_url.format(validation_key=validation_key)
        return '%s/%s' % (base_url, validation_key)

    @api.model
    def _normalize_lang(self, lang, default_lang='fr'):
        lang = (lang or default_lang or 'fr').strip().lower()
        if lang.startswith('ar'):
            return 'ar'
        return 'fr'

    @api.model
    def send_validation_sms(self, phone, code=None, lang=None):
        config = self._get_sms_config()
        if config['provider'] != 'chinguisoft':
            raise ValidationError(_('Le provider SMS configure n est pas pris en charge.'))
        if not config['validation_key'] or not config['token']:
            raise ValidationError(_('La configuration SMS Chinguisoft est incomplete.'))
        if requests is None:
            raise ValidationError(_('Le module Python requests est indisponible sur ce serveur.'))

        normalized_phone = self._normalize_phone(phone)
        normalized_lang = self._normalize_lang(lang, config['default_lang'])
        payload = {
            'phone': normalized_phone,
            'lang': normalized_lang,
        }
        if code is not None:
            payload['code'] = str(code).strip()

        url = self._build_url(config['base_url'], config['validation_key'])
        headers = {
            'Validation-token': config['token'],
            'Content-Type': 'application/json',
        }
        response = requests.post(url, json=payload, headers=headers, timeout=15)
        body = response.text or ''
        if response.status_code >= 400:
            _logger.warning(
                'Chinguisoft SMS request failed: status=%s url=%s body=%s',
                response.status_code,
                url,
                body,
            )
            raise ValidationError(_('L envoi SMS a echoue via Chinguisoft (code HTTP %s).') % response.status_code)

        try:
            data = response.json()
        except Exception:
            try:
                data = json.loads(body) if body else {}
            except Exception:
                data = {'raw_response': body}

        _logger.info('Chinguisoft SMS sent to %s with response %s', normalized_phone, data)
        return data

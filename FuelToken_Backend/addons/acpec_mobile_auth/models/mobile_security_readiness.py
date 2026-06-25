import os

from odoo import api, models


class AcpecMobileSecurityReadiness(models.AbstractModel):
    _name = 'acpec.mobile.security.readiness'
    _description = 'ACPEC Mobile Security Production Readiness Check'

    SMS_DEFAULT_URL = 'https://chinguisoft.com/api/sms/validation'

    @api.model
    def _is_truthy(self, value):
        return str(value or '').strip().casefold() in ('1', 'true', 'yes', 'y', 'on')

    @api.model
    def _issue(self, code, severity, message, setting_key=False):
        return {
            'code': code,
            'severity': severity,
            'message': message,
            'setting_key': setting_key or False,
        }

    @api.model
    def _raw_setting(self, key):
        return self.env['acpec.mobile.security.setting'].sudo().get_active_value(key)

    @api.model
    def _raw_bool(self, key, default=False):
        raw = self._raw_setting(key)
        if raw in (False, None, ''):
            return bool(default)
        return self._is_truthy(raw)

    @api.model
    def _raw_int(self, key):
        raw = self._raw_setting(key)
        if raw in (False, None, ''):
            return None
        try:
            return int(raw)
        except Exception:
            return None

    @api.model
    def _env_value(self, keys, default=''):
        for env_key in keys:
            value = os.getenv(env_key)
            if value not in (None, ''):
                return str(value).strip()
        return default


    @api.model
    def _fueltoken_company_count(self):
        company_model = self.env['res.company'].sudo()
        if 'acpec_fueltoken_enabled' not in company_model._fields:
            return None
        helper = getattr(company_model, '_fueltoken_company_count', None)
        if helper:
            return helper()
        return company_model.search_count([('acpec_fueltoken_enabled', '=', True)])

    @api.model
    def _mobile_identity_duplicate_phone_rows(self):
        users_model = self.env['res.users'].sudo().with_context(active_test=False)
        helper = getattr(users_model, '_acpec_mobile_identity_duplicate_phone_rows', None)
        if helper:
            return helper()
        return []

    @api.model
    def _mobile_identity_issues(self):
        users_model = self.env['res.users'].sudo().with_context(active_test=False)
        required_fields = {'mobile_only', 'mobile_phone', 'login'}
        missing_fields = sorted(required_fields - set(users_model._fields))
        if missing_fields:
            return [self._issue(
                'MOBILE_IDENTITY_FIELDS_MISSING',
                'critical',
                'Champs identité mobile absents sur res.users: %s.' % ', '.join(missing_fields),
                'res.users',
            )]

        issues = []
        mobile_users = users_model.search([('mobile_only', '=', True)])
        missing_phone = self.env['res.users']
        invalid_phone = self.env['res.users']
        login_mismatch = self.env['res.users']

        for user in mobile_users:
            login = (user.login or '').strip()
            phone = (user.mobile_phone or '').strip()
            if not phone:
                missing_phone |= user
                continue
            if not users_model._acpec_is_canonical_mobile_phone(phone):
                invalid_phone |= user
                continue
            if login != phone:
                login_mismatch |= user

        duplicate_rows = self._mobile_identity_duplicate_phone_rows()

        if missing_phone:
            issues.append(self._issue(
                'MOBILE_IDENTITY_MOBILE_PHONE_MISSING',
                'critical',
                '%s utilisateur(s) mobile_only n’ont pas de mobile_phone.' % len(missing_phone),
                'res.users.mobile_phone',
            ))
        if invalid_phone:
            issues.append(self._issue(
                'MOBILE_IDENTITY_MOBILE_PHONE_INVALID',
                'critical',
                '%s utilisateur(s) mobile_only ont un mobile_phone non canonique local 8 chiffres.' % len(invalid_phone),
                'res.users.mobile_phone',
            ))
        if login_mismatch:
            issues.append(self._issue(
                'MOBILE_IDENTITY_LOGIN_PHONE_MISMATCH',
                'critical',
                '%s utilisateur(s) mobile_only ont login différent de mobile_phone.' % len(login_mismatch),
                'res.users.login',
            ))
        if duplicate_rows:
            issues.append(self._issue(
                'MOBILE_IDENTITY_MOBILE_PHONE_NOT_UNIQUE',
                'critical',
                'Des utilisateurs mobile_only partagent le même mobile_phone ; unicité obligatoire.',
                'res.users.mobile_phone',
            ))
        return issues

    @api.model
    def _resolved_sms_config(self):
        # Patch36A: readiness does not read ir.config_parameter.
        # SMS secrets are runtime/deployment secrets, therefore read from env.
        return {
            'provider': self._env_value(['SMS_PROVIDER'], default='chinguisoft').lower(),
            'validation_key': self._env_value([
                'SMS_VALIDATION_KEY',
                'CHINGUI_SOFT_VALIDATION_KEY',
                'CHINGUISOFT_VALIDATION_KEY',
            ]),
            'token': self._env_value([
                'SMS_TOKEN',
                'CHINGUI_SOFT_TOKEN',
                'CHINGUISOFT_TOKEN',
            ]),
            'base_url': self._env_value(['SMS_URL', 'CHINGUISOFT_URL'], default=self.SMS_DEFAULT_URL),
        }

    @api.model
    def check_mobile_security_readiness(self):
        """Return readiness issues without changing configuration."""
        policy = self.env['acpec.mobile.security.policy'].sudo()
        issues = []

        env_label = policy.runtime_env_label()
        env_sources = policy.runtime_env_sources()
        dev_relax = policy.runtime_allows_dev_relax()
        strict_security = not dev_relax

        if not env_sources:
            issues.append(self._issue(
                'RUNTIME_ENV_MISSING',
                'critical',
                'Aucun environnement runtime ACPEC_ENV/ODOO_ENV/ENV n’est déclaré ; posture stricte appliquée par défaut.',
            ))

        if env_label == policy.ENV_LABEL_UNKNOWN:
            issues.append(self._issue(
                'RUNTIME_ENV_UNKNOWN',
                'critical',
                'Une valeur d’environnement runtime est inconnue ; posture stricte appliquée par défaut.',
            ))

        if policy.runtime_has_concurrent_prod_dev_signal():
            issues.append(self._issue(
                'RUNTIME_ENV_CONFLICTING_PROD_DEV',
                'critical',
                'Signaux runtime contradictoires : dev-like et production-like présents ; production/strict gagne.',
            ))

        if policy.runtime_dev_mode_flag_enabled() and env_label != policy.ENV_LABEL_DEV_LIKE:
            issues.append(self._issue(
                'DEV_MODE_FLAG_OUTSIDE_DEV_LIKE',
                'critical',
                'ACPEC_FUELTOKEN_DEV_MODE est actif hors environnement local/dev/test explicite ; relax dev refusé.',
                policy.DEV_MODE_ENV_KEY,
            ))

        if policy.runtime_legacy_test_mode_present():
            issues.append(self._issue(
                'LEGACY_TEST_MODE_FLAG_PRESENT',
                'critical',
                'ACPEC_FUELTOKEN_TEST_MODE est obsolète et ne doit plus être utilisé ; utiliser ACPEC_FUELTOKEN_DEV_MODE.',
                policy.LEGACY_TEST_MODE_ENV_KEY,
            ))

        if policy.runtime_odoo_test_enable_enabled() and not policy.runtime_acpec_env_is_test():
            issues.append(self._issue(
                'ODOO_TEST_ENABLE_WITHOUT_ACPEC_ENV_TEST',
                'critical',
                'Odoo test_enable est actif sans ACPEC_ENV=test explicite ; test_enable ne peut jamais activer le relax dev.',
                'test_enable',
            ))

        fueltoken_company_count = self._fueltoken_company_count()
        if fueltoken_company_count is None:
            issues.append(self._issue(
                'FUELTOKEN_COMPANY_FLAG_MISSING',
                'critical',
                'Le champ société FuelToken acpec_fueltoken_enabled est absent ; installer/mettre à jour acpec_fueltoken_base.',
                'res.company.acpec_fueltoken_enabled',
            ))
        elif fueltoken_company_count < 1:
            issues.append(self._issue(
                'FUELTOKEN_COMPANY_MISSING',
                'critical',
                'Aucune société ne porte Tickets Carburant ; exactement une société FuelToken est obligatoire.',
                'res.company.acpec_fueltoken_enabled',
            ))
        elif fueltoken_company_count > 1:
            issues.append(self._issue(
                'FUELTOKEN_COMPANY_NOT_UNIQUE',
                'critical',
                'Plusieurs sociétés portent Tickets Carburant ; une seule société FuelToken est autorisée.',
                'res.company.acpec_fueltoken_enabled',
            ))

        issues.extend(self._mobile_identity_issues())

        if self._raw_bool(policy.OTP_DEV_MODE_KEY, default=False):
            issues.append(self._issue(
                'OTP_DEV_MODE_LEGACY_SETTING_ENABLED',
                'critical',
                'Le paramètre legacy acpec_mobile_auth.otp_dev_mode est actif ; Patch36A utilise uniquement ACPEC_FUELTOKEN_DEV_MODE.',
                policy.OTP_DEV_MODE_KEY,
            ))

        antiflood_specs = [
            ('OTP_REQUEST_COOLDOWN_ZERO', policy.OTP_REQUEST_COOLDOWN_SECONDS[0], 'Le délai minimum entre demandes OTP est configuré à zéro.'),
            ('OTP_IDENTIFIER_PER_MINUTE_ZERO', policy.OTP_LIMIT_IDENTIFIER_PER_MINUTE[0], 'La limite OTP par identifiant et par minute est configurée à zéro.'),
            ('OTP_IDENTIFIER_PER_DAY_ZERO', policy.OTP_LIMIT_IDENTIFIER_PER_DAY[0], 'La limite OTP par identifiant et par jour est configurée à zéro.'),
            ('OTP_IP_PER_HOUR_ZERO', policy.OTP_LIMIT_IP_PER_HOUR[0], 'La limite OTP par IP et par heure est configurée à zéro.'),
            ('OTP_REGISTER_IP_PER_DAY_ZERO', policy.OTP_LIMIT_REGISTER_IP_PER_DAY[0], 'La limite OTP inscription par IP et par jour est configurée à zéro.'),
        ]

        for code, key, message in antiflood_specs:
            value = self._raw_int(key)
            if strict_security and value is not None and value <= 0:
                issues.append(self._issue(code, 'critical', message, key))

        sms_config = self._resolved_sms_config()
        if strict_security and sms_config['provider'] == 'chinguisoft':
            if not sms_config['base_url']:
                issues.append(self._issue(
                    'SMS_URL_MISSING',
                    'warning',
                    'Le fournisseur SMS Chinguisoft est actif mais l’URL SMS est vide.',
                    'SMS_URL',
                ))
            if not sms_config['validation_key']:
                issues.append(self._issue(
                    'SMS_VALIDATION_KEY_MISSING',
                    'critical',
                    'Le fournisseur SMS Chinguisoft est actif mais la clé de validation SMS est vide.',
                    'SMS_VALIDATION_KEY',
                ))
            if not sms_config['token']:
                issues.append(self._issue(
                    'SMS_TOKEN_MISSING',
                    'critical',
                    'Le fournisseur SMS Chinguisoft est actif mais le token SMS est vide.',
                    'SMS_TOKEN',
                ))

        return {
            'production': env_label == policy.ENV_LABEL_PRODUCTION,
            'runtime_env_label': env_label,
            'runtime_dev_relax': dev_relax,
            'runtime_env_sources': env_sources,
            'ready': not any(issue['severity'] == 'critical' for issue in issues),
            'issues': issues,
        }

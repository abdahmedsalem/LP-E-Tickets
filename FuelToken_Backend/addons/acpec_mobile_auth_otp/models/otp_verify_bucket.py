from dateutil.relativedelta import relativedelta
from psycopg2 import IntegrityError

from odoo import _, api, fields, models

from odoo.addons.acpec_mobile_auth.exceptions import MobileAuthRateLimitError


class AcpecMobileAuthOtpVerifyBucket(models.Model):
    _name = 'acpec.mobile.auth.otp.verify.bucket'
    _description = 'ACPEC Mobile OTP Verify Antiflood Bucket'
    _table = 'acpec_mobile_auth_otp_verify_bucket'
    _rec_name = 'key'
    _order = 'write_date desc, id desc'

    scope = fields.Selection([
        ('identifier', 'Identifier'),
        ('ip', 'IP'),
    ], required=True, index=True)
    purpose = fields.Selection([
        ('login', 'Login'),
        ('register', 'Register'),
        ('reset', 'Reset'),
    ], default='login', required=True, index=True)
    key = fields.Char(required=True, index=True)
    failed_count = fields.Integer(default=0, required=True)
    locked_until = fields.Datetime(index=True)
    last_failed_at = fields.Datetime(index=True)

    _scope_purpose_key_unique = models.Constraint(
        'UNIQUE(scope, purpose, key)',
        'An OTP verify antiflood bucket already exists for this scope, purpose and key.',
    )

    @api.model
    def _rate_limit_message(self):
        return _('Trop de demandes OTP. Veuillez réessayer plus tard.')

    @api.model
    def _otp_max_attempts(self):
        return self.env['acpec.mobile.security.policy'].sudo().otp_max_attempts()

    @api.model
    def _max_attempts_for_scope(self, scope):
        return self._otp_max_attempts()

    @api.model
    def _lock_minutes(self):
        # Keep identifier verify lock aligned with the existing challenge lock
        # duration used by acpec.mobile.auth.otp.verify().
        return 15

    @api.model
    def _failure_window_delta(self, scope):
        return relativedelta(minutes=self._lock_minutes())

    @api.model
    def _normalize_key(self, key):
        return (key or '').strip()

    @api.model
    def _raise_rate_limited(self, debug_reason):
        exc = MobileAuthRateLimitError(self._rate_limit_message())
        exc.acpec_debug_reason = debug_reason
        raise exc

    def _lock_for_update(self):
        self.ensure_one()
        self.env.cr.execute(
            'SELECT id FROM acpec_mobile_auth_otp_verify_bucket WHERE id = %s FOR UPDATE',
            [self.id],
        )
        self.invalidate_recordset(['failed_count', 'locked_until', 'last_failed_at'])
        return self

    def _reset_counts(self):
        self.ensure_one()
        self.write({
            'failed_count': 0,
            'locked_until': False,
            'last_failed_at': False,
        })

    def _reset_if_stale(self, scope, now):
        self.ensure_one()
        if self.locked_until and self.locked_until <= now:
            self._reset_counts()
            return True

        if (
            not self.locked_until
            and self.last_failed_at
            and self.last_failed_at <= now - self._failure_window_delta(scope)
        ):
            self._reset_counts()
            return True

        return False

    @api.model
    def _scope_enabled(self, scope):
        # K5 deliberately keeps verify-OTP hard lock on the canonical
        # identifier only. A hard IP verify lock is too risky behind reverse
        # proxies and mobile-network CGNAT: one shared IP could lock many
        # legitimate users. Request-OTP already keeps its IP antiflood for SMS
        # cost/provider protection.
        if scope == 'ip':
            return False
        return self._max_attempts_for_scope(scope) > 0

    @api.model
    def _get_or_create_locked(self, scope, purpose, key):
        key = self._normalize_key(key)
        purpose = purpose or 'login'
        if not key or not self._scope_enabled(scope):
            return self.browse()

        domain = [
            ('scope', '=', scope),
            ('purpose', '=', purpose),
            ('key', '=', key),
        ]

        bucket = self.sudo().search(domain, limit=1)
        if not bucket:
            try:
                with self.env.cr.savepoint():
                    bucket = self.sudo().create({
                        'scope': scope,
                        'purpose': purpose,
                        'key': key,
                    })
            except IntegrityError:
                bucket = self.sudo().search(domain, limit=1)

        if bucket:
            bucket._lock_for_update()
        return bucket

    @api.model
    def _check_bucket_allowed(self, scope, purpose, key):
        key = self._normalize_key(key)
        purpose = purpose or 'login'
        if not key or not self._scope_enabled(scope):
            return True

        bucket = self.sudo().search([
            ('scope', '=', scope),
            ('purpose', '=', purpose),
            ('key', '=', key),
        ], limit=1)
        if not bucket:
            return True

        bucket._lock_for_update()
        now = fields.Datetime.now()
        bucket._reset_if_stale(scope, now)

        if bucket.locked_until and bucket.locked_until > now:
            self._raise_rate_limited('otp_verify_%s_rate_limited' % scope)

        return True

    @api.model
    def check_verify_allowed(self, identifier, purpose='login', request_ip=False):
        self._check_bucket_allowed('identifier', purpose, identifier)
        return True

    @api.model
    def _record_bucket_failure(self, scope, purpose, key):
        key = self._normalize_key(key)
        purpose = purpose or 'login'
        if not key or not self._scope_enabled(scope):
            return False

        bucket = self._get_or_create_locked(scope, purpose, key)
        if not bucket:
            return False

        now = fields.Datetime.now()
        bucket._reset_if_stale(scope, now)

        max_attempts = self._max_attempts_for_scope(scope)
        failed_count = (bucket.failed_count or 0) + 1

        vals = {
            'failed_count': failed_count,
            'last_failed_at': now,
        }
        if max_attempts > 0 and failed_count >= max_attempts:
            vals['locked_until'] = now + self._failure_window_delta(scope)

        bucket.write(vals)
        return bucket

    @api.model
    def record_verify_failure(self, identifier, purpose='login', request_ip=False):
        self._record_bucket_failure('identifier', purpose, identifier)
        return True

    @api.model
    def _reset_bucket(self, scope, purpose, key):
        key = self._normalize_key(key)
        purpose = purpose or 'login'
        if not key or not self._scope_enabled(scope):
            return False

        bucket = self.sudo().search([
            ('scope', '=', scope),
            ('purpose', '=', purpose),
            ('key', '=', key),
        ], limit=1)
        if not bucket:
            return False

        bucket._lock_for_update()
        bucket._reset_counts()
        return True

    @api.model
    def record_verify_success(self, identifier, purpose='login', request_ip=False):
        self._reset_bucket('identifier', purpose, identifier)
        return True

    @api.autovacuum
    def _gc_otp_verify_buckets(self):
        cutoff = fields.Datetime.now() - relativedelta(days=7)
        stale = self.sudo().search([
            '|',
            '&', ('failed_count', '=', 0), ('write_date', '<', fields.Datetime.to_string(cutoff)),
            '&', ('last_failed_at', '!=', False), ('last_failed_at', '<', fields.Datetime.to_string(cutoff)),
        ], limit=5000)
        stale.unlink()
        return True

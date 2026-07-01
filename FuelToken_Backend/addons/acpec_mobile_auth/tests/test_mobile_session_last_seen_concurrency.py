from pathlib import Path

from odoo.tests.common import TransactionCase

from odoo.addons.acpec_mobile_auth.models import mobile_session


class TestMobileSessionLastSeenConcurrency(TransactionCase):

    def _source(self):
        return Path(mobile_session.__file__).read_text(encoding='utf-8')

    def test_authenticate_access_token_uses_best_effort_last_seen_touch(self):
        source = self._source()
        self.assertIn('def _touch_last_seen_at_best_effort', source)
        self.assertIn('session._touch_last_seen_at_best_effort(now=now)', source)
        self.assertNotIn("session.sudo().write({'last_seen_at': now})\n        return session", source)

    def test_best_effort_last_seen_touch_is_throttled_and_savepointed(self):
        source = self._source()
        self.assertIn('ACCESS_LAST_SEEN_TOUCH_MIN_SECONDS = 60', source)
        self.assertIn('def _should_touch_last_seen_at', source)
        self.assertIn('with self.env.cr.savepoint()', source)
        self.assertIn('pg_errors.SerializationFailure', source)
        self.assertIn('pg_errors.DeadlockDetected', source)

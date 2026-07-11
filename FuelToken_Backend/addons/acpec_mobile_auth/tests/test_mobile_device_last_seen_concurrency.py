from pathlib import Path
from unittest.mock import patch

from psycopg2 import errors as pg_errors

from odoo import fields
from odoo.tests.common import TransactionCase

from odoo.addons.acpec_mobile_auth.models import mobile_session


class TestMobileDeviceLastSeenConcurrency(TransactionCase):
    """Patch43K6.

    Le touch presence/metadata d'un device existant est best-effort :
    une SerializationFailure sur acpec_mobile_device ne doit jamais
    faire echouer le flux refresh/login. Le touch est throttle, mais
    une metadata reellement changee force l'ecriture.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.user = cls.env['res.users'].create({
            'name': 'Test 43K6 Mobile User',
            'login': 'test_43k6_mobile_user',
        })
        cls.device = cls.env['acpec.mobile.device'].sudo().with_context(
            acpec_mobile_device_internal_create=True,
        ).create({
            'user_id': cls.user.id,
            'stable_device_uid': 'ft-test-43k6-device',
        })
        cls.Session = cls.env['acpec.mobile.session']

    def _source(self):
        return Path(mobile_session.__file__).read_text(encoding='utf-8')

    def _device_class(self):
        return type(self.env['acpec.mobile.device'])

    # ---- comportement : erreurs de concurrence avalees ----------------

    def test_serialization_failure_on_device_touch_is_swallowed(self):
        # device_name change => update_vals non vide => write appele.
        with patch.object(
            self._device_class(), '_write_internal',
            side_effect=pg_errors.SerializationFailure('concurrent update'),
        ) as mocked_write:
            self.Session._touch_device_metadata_best_effort(
                self.device.sudo(),
                {'device_name': 'Pixel 43K6'},
            )
        mocked_write.assert_called_once()

    def test_deadlock_on_device_touch_is_swallowed(self):
        # Sans metadata changee et avec last_seen_at recent, le helper
        # early-return et le test serait vacueux : on force une metadata.
        with patch.object(
            self._device_class(), '_write_internal',
            side_effect=pg_errors.DeadlockDetected('deadlock'),
        ) as mocked_write:
            self.Session._touch_device_metadata_best_effort(
                self.device.sudo(),
                {'device_name': 'Pixel 43K6 deadlock'},
            )
        mocked_write.assert_called_once()

    def test_get_or_create_survives_concurrent_device_touch(self):
        """Le chemin refresh/login retourne le device malgre le conflit."""
        with patch.object(
            self._device_class(), '_write_internal',
            side_effect=pg_errors.SerializationFailure('concurrent update'),
        ):
            device = self.Session._get_or_create_device_for_session(
                self.user,
                {'device_uid': 'ft-test-43k6-device', 'device_name': 'Pixel 43K6'},
            )
        self.assertEqual(device.id, self.device.id)

    # ---- comportement : throttle -------------------------------------

    def test_device_touch_is_throttled_without_metadata_change(self):
        """last_seen_at recent + aucune metadata changee => aucun write."""
        self.env.cr.execute(
            'UPDATE acpec_mobile_device SET last_seen_at = %s WHERE id = %s',
            [fields.Datetime.now(), self.device.id],
        )
        self.device.invalidate_recordset(['last_seen_at'])
        with patch.object(self._device_class(), '_write_internal') as mocked_write:
            self.Session._touch_device_metadata_best_effort(self.device.sudo())
        mocked_write.assert_not_called()

    def test_changed_metadata_forces_write_despite_recent_last_seen(self):
        """Le throttle ne doit pas bloquer une mise a jour utile."""
        self.env.cr.execute(
            'UPDATE acpec_mobile_device SET last_seen_at = %s WHERE id = %s',
            [fields.Datetime.now(), self.device.id],
        )
        self.device.invalidate_recordset(['last_seen_at'])
        with patch.object(self._device_class(), '_write_internal') as mocked_write:
            self.Session._touch_device_metadata_best_effort(
                self.device.sudo(),
                {'device_name': 'Pixel 43K6 renomme'},
            )
        mocked_write.assert_called_once()
        written_vals = mocked_write.call_args.args[0]
        self.assertEqual(written_vals.get('device_name'), 'Pixel 43K6 renomme')
        self.assertIn('last_seen_at', written_vals)

    def test_stale_last_seen_triggers_touch_without_metadata(self):
        """last_seen_at trop ancien => touch meme sans metadata."""
        self.env.cr.execute(
            "UPDATE acpec_mobile_device SET last_seen_at = %s - interval '10 minutes' WHERE id = %s",
            [fields.Datetime.now(), self.device.id],
        )
        self.device.invalidate_recordset(['last_seen_at'])
        with patch.object(self._device_class(), '_write_internal') as mocked_write:
            self.Session._touch_device_metadata_best_effort(self.device.sudo())
        mocked_write.assert_called_once()

    # ---- comportement : pas de silence total --------------------------

    def test_other_exceptions_still_propagate(self):
        with patch.object(self._device_class(), '_write_internal', side_effect=ValueError('boom')):
            with self.assertRaises(ValueError):
                self.Session._touch_device_metadata_best_effort(
                    self.device.sudo(),
                    {'device_name': 'Pixel 43K6 bis'},
                )

    # ---- garde-fous de source style Patch43J3 --------------------------

    def test_device_touch_is_best_effort_savepointed_and_throttled(self):
        source = self._source()
        self.assertIn('DEVICE_LAST_SEEN_TOUCH_MIN_SECONDS = 60', source)
        self.assertIn('def _touch_device_metadata_best_effort', source)
        self.assertIn('def _should_touch_device_last_seen_at', source)
        self.assertIn('mobile_device_last_seen_touch_skipped', source)
        self.assertNotIn(
            "update_vals = {'last_seen_at': now}\n"
            "        if device_vals.get('device_name'):",
            source,
        )

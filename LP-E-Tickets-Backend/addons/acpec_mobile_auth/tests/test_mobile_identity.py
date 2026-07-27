from psycopg2 import IntegrityError


def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

from odoo.tests.common import TransactionCase
from odoo.tools import mute_logger


class TestMobileIdentity(TransactionCase):

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _existing_partner(self):
        partner = self.env.user.sudo().partner_id or self.env.company.sudo().partner_id
        self.assertTrue(partner)
        return partner

    def _unused_mobile_phone(self):
        Users = self.env['res.users'].sudo().with_context(active_test=False)
        for number in range(43000000, 43009999):
            phone = str(number)
            if not Users.search([('acpec_mobile_phone', '=', phone)], limit=1):
                return phone
        self.fail('No unused mobile phone found for test')

    def _create_mobile_user(self, login, mobile_phone):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        return Users.create({
            'name': login,
            'login': mobile_phone,
            'partner_id': self._existing_partner().id,
            'mobile_phone': mobile_phone,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids([
                'base.group_portal',
                'acpec_mobile_auth.group_mobile_auth_user',
            ]))],
        })

    def test_mobile_phone_normalization_helpers(self):
        Users = self.env['res.users'].sudo()

        self.assertEqual(Users._acpec_normalize_mobile_phone('32340001'), '32340001')
        self.assertEqual(Users._acpec_normalize_mobile_phone('+222 32 34 00 01'), '+222 32 34 00 01')
        self.assertEqual(Users._acpec_normalize_mobile_phone('00222 32340002'), '00222 32340002')
        self.assertTrue(Users._acpec_is_valid_mobile_phone('32340003'))
        self.assertTrue(Users._acpec_is_canonical_mobile_phone('32340004'))
        self.assertFalse(Users._acpec_is_valid_mobile_phone('+222 32 34 00 04'))
        self.assertFalse(Users._acpec_is_canonical_mobile_phone('+222 32 34 00 04'))
        self.assertFalse(Users._acpec_is_valid_mobile_phone('323420056'))
        self.assertFalse(Users._acpec_is_valid_mobile_phone('3475'))
        self.assertFalse(Users._acpec_is_valid_mobile_phone('59000001'))
        self.assertFalse(Users._acpec_is_valid_mobile_phone('123'))

    def test_duplicate_mobile_phone_is_rejected_for_mobile_only_users(self):
        phone = self._unused_mobile_phone()
        self._create_mobile_user('mobile-identity-1-%s@example.com' % phone, phone)

        with self.assertRaises(IntegrityError), mute_logger('odoo.sql_db'):
            with self.env.cr.savepoint():
                self._create_mobile_user('mobile-identity-2-%s@example.com' % phone, phone)
                self.env.flush_all()

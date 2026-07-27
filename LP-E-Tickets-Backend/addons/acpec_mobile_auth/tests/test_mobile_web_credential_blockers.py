from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase



def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

class TestMobileWebCredentialBlockers(TransactionCase):

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

    def _create_user(self, login, *, mobile_only=False):
        Users = self.env['res.users'].sudo().with_context(
            no_reset_password=True,
            acpec_mobile_allow_password_write=True,
        )
        identity_login = _acpec_test_mobile_phone(login) if mobile_only else login
        vals = {
            'name': login,
            'login': identity_login,
            'partner_id': self._existing_partner().id,
            'password': 'Credential-Blocker-18B!',
            'acpec_mobile_only': mobile_only,
            'acpec_mobile_state': 'approved' if mobile_only else False,
        }
        if mobile_only:
            vals['mobile_phone'] = identity_login
            vals['group_ids'] = [(6, 0, self._group_ids([
                'base.group_portal',
                'acpec_mobile_auth.group_mobile_auth_user',
            ]))]
        return Users.create(vals)

    def test_api_key_creation_is_blocked_for_mobile_only_target(self):
        user = self._create_user('mobile-api-key-blocked@example.com', mobile_only=True)
        ApiKeys = self.env['res.users.apikeys'].sudo()
        with self.assertRaises(AccessError):
            ApiKeys.create({
                'name': 'Blocked API key',
                'user_id': user.id,
                'scope': 'rpc',
                'key': 'blocked',
                'index': 'blocked',
            })

    def test_totp_device_creation_is_blocked_for_mobile_only_target(self):
        user = self._create_user('mobile-totp-blocked@example.com', mobile_only=True)
        Device = self.env['auth_totp.device'].sudo()
        with self.assertRaises(AccessError):
            Device.create({
                'name': 'Blocked TOTP',
                'user_id': user.id,
                'scope': 'login',
                'key': 'blocked',
                'index': 'blocked',
            })

    def test_cleanup_removes_existing_mobile_only_web_credentials(self):
        mobile_user = self._create_user('mobile-cleanup-credentials@example.com', mobile_only=True)
        regular_user = self._create_user('regular-keep-credentials@example.com', mobile_only=False)

        # Bypass blockers to simulate legacy/pre-patch rows.
        # Odoo enforces API/TOTP index format constraints; keep test rows valid.
        mobile_index = ("%08x" % mobile_user.id)[-8:]
        regular_index = ("%08x" % regular_user.id)[-8:]
        mobile_totp_index = ("t%07x" % mobile_user.id)[-8:]
        mobile_api_key = "a" * 128
        regular_api_key = "b" * 128
        mobile_totp_key = "A" * 32
        self.env.cr.execute(
            """
            INSERT INTO res_users_apikeys(name, user_id, scope, index, key, create_date)
            VALUES (%s, %s, %s, %s, %s, NOW())
            RETURNING id
            """,
            ('mobile legacy api', mobile_user.id, 'rpc', mobile_index, mobile_api_key),
        )
        mobile_api_id = self.env.cr.fetchone()[0]

        self.env.cr.execute(
            """
            INSERT INTO res_users_apikeys(name, user_id, scope, index, key, create_date)
            VALUES (%s, %s, %s, %s, %s, NOW())
            RETURNING id
            """,
            ('regular api', regular_user.id, 'rpc', regular_index, regular_api_key),
        )
        regular_api_id = self.env.cr.fetchone()[0]

        self.env.cr.execute(
            """
            INSERT INTO auth_totp_device(name, user_id, scope, index, key, create_date)
            VALUES (%s, %s, %s, %s, %s, NOW())
            RETURNING id
            """,
            ('mobile legacy totp', mobile_user.id, 'login', mobile_totp_index, mobile_totp_key),
        )
        mobile_totp_id = self.env.cr.fetchone()[0]


        cleaned = self.env['acpec.mobile.web.credential.mixin'].sudo()._acpec_cleanup_mobile_only_web_credentials()
        self.assertGreaterEqual(cleaned['api_keys'], 1)
        self.assertGreaterEqual(cleaned['totp_devices'], 1)

        self.assertFalse(self.env['res.users.apikeys'].sudo().browse(mobile_api_id).exists())
        self.assertTrue(self.env['res.users.apikeys'].sudo().browse(regular_api_id).exists())
        self.assertFalse(self.env['auth_totp.device'].sudo().browse(mobile_totp_id).exists())

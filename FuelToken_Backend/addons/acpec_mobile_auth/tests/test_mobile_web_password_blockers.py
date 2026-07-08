from odoo.exceptions import AccessDenied, AccessError, UserError
from odoo.tests.common import TransactionCase



def _acpec_test_mobile_phone(label):
    """Return a deterministic canonical 8-digit mobile phone for test labels."""
    value = 2166136261
    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 10000000
    return "3%07d" % value

class TestMobileWebPasswordBlockers(TransactionCase):

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

    def _auth_password(self, login, password):
        return self.env['res.users'].sudo().authenticate({
            'login': login,
            'password': password,
            'type': 'password',
        }, {'interactive': False})

    def _create_user(self, login, password, *, mobile_only=False, groups=None):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        identity_login = _acpec_test_mobile_phone(login) if mobile_only else login
        vals = {
            'name': login,
            'login': identity_login,
            'partner_id': self._existing_partner().id,
            'password': password,
            'acpec_mobile_only': mobile_only,
            'acpec_mobile_state': 'approved' if mobile_only else False,
        }
        if mobile_only:
            vals['mobile_phone'] = identity_login
        if groups:
            vals['group_ids'] = [(6, 0, self._group_ids(groups))]
        return Users.create(vals)

    def test_password_auth_is_blocked_for_mobile_only_even_with_known_password(self):
        login = 'mobile-web-blocked@example.com'
        password = 'Known-Mobile-Password-18A!'
        user = self._create_user(login, password, mobile_only=True, groups=[
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])
        with self.assertRaises(AccessDenied):
            self._auth_password(user.login, password)

    def test_password_auth_still_works_for_non_mobile_user(self):
        login = 'regular-web-user-18a@example.com'
        password = 'Known-Regular-Password-18A!'
        user = self._create_user(login, password, mobile_only=False)
        result = self._auth_password(login, password)
        self.assertEqual(result.get('uid'), user.id)

    def test_standard_password_write_is_blocked_for_mobile_only(self):
        user = self._create_user('mobile-password-write-blocked@example.com', 'Old-Password-18A!', mobile_only=True, groups=[
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])
        with self.assertRaises(AccessError):
            user.write({'password': 'New-Password-18A!'})

    def test_system_context_can_rotate_mobile_only_random_password(self):
        user = self._create_user('mobile-password-rotate-system@example.com', 'Old-Password-18A!', mobile_only=True, groups=[
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])
        user.with_context(acpec_mobile_allow_password_write=True).write({
            'password': user._acpec_mobile_unusable_password(),
        })
        with self.assertRaises(AccessDenied):
            self._auth_password(user.login, 'Old-Password-18A!')

    def test_reset_password_is_blocked_or_noop_for_mobile_only(self):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        user = self._create_user('mobile-reset-blocked@example.com', 'Reset-Password-18A!', mobile_only=True, groups=[
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ])
        with self.assertRaises(UserError):
            user.action_reset_password()
        self.assertTrue(Users.reset_password(user.login))

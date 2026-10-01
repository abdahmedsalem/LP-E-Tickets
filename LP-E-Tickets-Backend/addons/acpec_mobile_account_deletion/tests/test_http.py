import json

from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestAccountDeletionHttp(HttpCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.processing_days', '7')
        users = cls.env['res.users'].sudo().with_context(
            acpec_mobile_allow_password_write=True, no_reset_password=True)
        cls.user = users.create({
            'name': 'Deletion HTTP test', 'login': '23451234',
            'mobile_phone': '23451234', 'email': 'deletion-http@example.test',
            'acpec_mobile_only': True, 'acpec_mobile_state': 'approved',
            'password': users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, [cls.env.ref('base.group_portal').id,
                cls.env.ref('acpec_mobile_auth.group_mobile_auth_user').id])],
        })
        cls.user.set_mobile_pin('1234')
        data = cls.env['acpec.mobile.session'].sudo().create_for_user(cls.user, {
            'device_uid': 'deletion-http-device', 'platform': 'ios',
        })
        data['session'].action_trust_device()
        cls.token = data['access_token']
        cls.session = data['session']

    def rpc(self, suffix, params=None, authenticated=True):
        headers = {'Content-Type': 'application/json'}
        if authenticated:
            headers['Authorization'] = 'Bearer ' + self.token
        response = self.url_open('/api/acpec/mobile_auth/v1/account-deletion/' + suffix,
            data=json.dumps({'jsonrpc': '2.0', 'method': 'call', 'id': 1,
                             'params': params or {}}), headers=headers)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertNotIn('error', body, body)
        return body['result']

    def test_submit_receipt_status_and_retry(self):
        status = self.rpc('status')
        self.assertTrue(status['success'])
        self.assertEqual(status['data']['processing_days'], 7)
        self.assertFalse(status['data']['request'])
        params = {'confirmed': True, 'action_code': '1234', 'user_id': self.env.user.id}
        first = self.rpc('request', params)
        self.assertTrue(first['success'], first)
        retry = self.rpc('request', params)
        self.assertEqual(first['data'], retry['data'])
        self.assertEqual(self.rpc('status')['data']['request'], first['data'])
        self.env.invalidate_all()
        records = self.env['acpec.mobile.account.deletion'].sudo().search([
            ('reference', '=', first['data']['reference'])])
        self.assertEqual(len(records), 1)
        self.assertEqual(records.user_id, self.user)
        self.assertEqual(records.state, 'pending')
        self.assertTrue(self.user.active)

    def test_requires_session_confirmation_and_correct_pin(self):
        for suffix in ('status', 'request'):
            self.assertFalse(self.rpc(suffix, authenticated=False)['success'])
        for params in ({'action_code': '1234'},
                       {'confirmed': True, 'action_code': '9999'}):
            self.assertFalse(self.rpc('request', params)['success'])
        self.assertFalse(self.rpc('status')['data']['request'])

    def test_unconfigured_policy_does_not_accept_request(self):
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.processing_days', 'invalid')
        self.assertFalse(self.rpc('request', {
            'confirmed': True, 'action_code': '1234'})['success'])
        self.env.invalidate_all()
        self.assertFalse(self.env['acpec.mobile.account.deletion'].sudo().search([
            ('user_id', '=', self.user.id)]))

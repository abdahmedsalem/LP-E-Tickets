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

    def test_immediate_deletion_and_unauthenticated_recovery(self):
        import uuid
        preview = self.rpc('preview')
        self.assertTrue(preview['success'], preview)
        key = str(uuid.uuid4())
        params = {'confirmed': True, 'action_code': '1234',
                  'snapshot': preview['data']['snapshot'], 'waive_value': False,
                  'recovery_key': key, 'user_id': self.env.user.id}
        result = self.rpc('execute', params)
        self.assertTrue(result['success'], result)
        self.assertTrue(result['data']['completed'])
        self.env.invalidate_all()
        self.assertFalse(self.user.active)
        self.assertFalse(self.user.acpec_mobile_phone)
        self.assertFalse(self.user.partner_id.phone)
        self.assertFalse(self.env['acpec.mobile.session'].sudo().search_count([('user_id', '=', self.user.id)]))
        recovered = self.rpc('recover', {'recovery_key': key}, authenticated=False)
        self.assertEqual(recovered['data'], result['data'])
        self.assertEqual(self.rpc('execute', params, authenticated=False)['data'], result['data'])
        self.assertFalse(self.rpc('recover', {'recovery_key': str(uuid.uuid4())},
                                  authenticated=False)['data']['completed'])
        self.assertFalse(self.rpc('preview')['success'])
        self.assertTrue(self.env.ref('base.user_admin').active)

    def test_immediate_requires_session_confirmation_and_pin(self):
        import uuid
        report = self.rpc('preview')['data']
        params = {'confirmed': True, 'action_code': '9999', 'snapshot': report['snapshot'],
                  'waive_value': False, 'recovery_key': str(uuid.uuid4())}
        self.assertFalse(self.rpc('preview', authenticated=False)['success'])
        self.assertFalse(self.rpc('execute', params, authenticated=False)['success'])
        result = self.rpc('execute', params)
        self.assertFalse(result['success'], result)
        self.env.invalidate_all()
        self.assertTrue(self.user.active)
        self.assertEqual(self.user.acpec_mobile_pin_failed_count, 1)
        params['action_code'] = '1234'
        params['confirmed'] = False
        self.assertFalse(self.rpc('execute', params)['success'])
        self.assertTrue(self.user.active)

    def test_immediate_rejects_changed_wallet_without_odoo_policy_configuration(self):
        import uuid
        preview = self.rpc('preview')
        self.assertTrue(preview['success'], preview)
        self.assertNotIn('retention_notice', preview['data'])
        params = {'confirmed': True, 'action_code': '1234', 'snapshot': '0' * 64,
                  'waive_value': False, 'recovery_key': str(uuid.uuid4())}
        self.assertFalse(self.rpc('execute', params)['success'])
        self.env.invalidate_all()
        self.assertTrue(self.user.active)
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_mobile_account_deletion.retention_notice', '')
        self.assertTrue(self.rpc('preview')['success'])

    def test_immediate_audit_failure_rolls_back_erasure(self):
        import uuid
        from unittest.mock import patch
        from odoo.addons.acpec_mobile_account_deletion.controllers.account_deletion import AccountDeletionApi
        report = self.rpc('preview')['data']
        params = {'confirmed': True, 'action_code': '1234', 'snapshot': report['snapshot'],
                  'waive_value': False, 'recovery_key': str(uuid.uuid4())}
        with patch.object(AccountDeletionApi, '_audit_in_transaction', side_effect=RuntimeError('audit unavailable')):
            result = self.rpc('execute', params)
        self.assertFalse(result['success'], result)
        self.env.invalidate_all()
        self.assertTrue(self.user.active)
        self.assertEqual(self.user.acpec_mobile_phone, '23451234')
        self.assertTrue(self.session.exists())
        self.assertFalse(self.env['acpec.mobile.account.deletion'].sudo().search([('user_id', '=', self.user.id)]))

    def test_pending_device_can_delete_with_session_and_correct_pin(self):
        import uuid
        self.session.device_id._write_internal({'trust_state': 'pending_trust'})
        self.session._write_internal({'device_trust_state': 'pending_trust'})
        report = self.rpc('preview')
        self.assertTrue(report['success'], report)
        result = self.rpc('execute', {
            'confirmed': True, 'action_code': '1234',
            'snapshot': report['data']['snapshot'], 'waive_value': False,
            'recovery_key': str(uuid.uuid4())})
        self.assertTrue(result['success'], result)
        self.env.invalidate_all()
        self.assertFalse(self.user.active)

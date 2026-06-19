from odoo.exceptions import AccessError, ValidationError
from odoo.tests.common import TransactionCase


class TestMobileUserBaseline(TransactionCase):

    def _group_ids(self, xmlids):
        ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _existing_partner(self):
        """Use an existing valid partner.

        During module-load tests for acpec_mobile_auth, the database may already
        have NOT NULL partner columns introduced by other installed modules,
        while their ORM fields/defaults are not yet available in this module's
        loading phase. These tests target res.users mobile baseline behavior,
        not partner creation.
        """
        partner = self.env.user.sudo().partner_id or self.env.company.sudo().partner_id
        self.assertTrue(partner)
        return partner

    def test_mobile_session_accepts_portal_mobile_only_baseline(self):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        partner = self._existing_partner()
        user = Users.create({
            'name': 'Mobile Baseline Test',
            'login': 'mobile-baseline-test',
            'partner_id': partner.id,
            'mobile_only': True,
            'mobile_state': 'approved',
            'password': Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._group_ids([
                'base.group_portal',
                'acpec_mobile_auth.group_mobile_auth_user',
            ]))],
        })
        self.env['acpec.mobile.session'].sudo()._check_mobile_only_user(user)

    def test_mobile_user_rejects_mobile_group_without_mobile_only(self):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        partner = self._existing_partner()
        with self.assertRaises(ValidationError):
            Users.create({
                'name': 'Mobile Missing Flag Test',
                'login': 'mobile-missing-flag-test',
                'partner_id': partner.id,
                'mobile_only': False,
                'mobile_state': 'approved',
                'password': Users._acpec_mobile_unusable_password(),
                'group_ids': [(6, 0, self._group_ids([
                    'base.group_portal',
                    'acpec_mobile_auth.group_mobile_auth_user',
                ]))],
            })

    def test_mobile_user_rejects_mobile_only_without_portal_baseline(self):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        partner = self._existing_partner()
        with self.assertRaises(ValidationError):
            Users.create({
                'name': 'Mobile Missing Portal Test',
                'login': 'mobile-missing-portal-test',
                'partner_id': partner.id,
                'mobile_only': True,
                'mobile_state': 'approved',
                'password': Users._acpec_mobile_unusable_password(),
                'group_ids': [(6, 0, self._group_ids([
                    'acpec_mobile_auth.group_mobile_auth_user',
                ]))],
            })

    def test_mobile_session_rejects_non_mobile_only_user(self):
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        partner = self._existing_partner()
        user = Users.create({
            'name': 'Non Mobile Test',
            'login': 'non-mobile-test',
            'partner_id': partner.id,
            'mobile_only': False,
            'mobile_state': 'approved',
            'password': Users._acpec_mobile_unusable_password(),
        })
        with self.assertRaises(AccessError):
            self.env['acpec.mobile.session'].sudo()._check_mobile_only_user(user)

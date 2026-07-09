# -*- coding: utf-8 -*-
import uuid

from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestCompanyMobileAuthEnabledGuard(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Company = self.env['res.company'].sudo()
        self.Users = self.env['res.users'].sudo()

    def _create_mobile_auth_company(self, enabled=True):
        return self.Company.create({
            'name': 'Patch2W Mobile Auth Company %s' % uuid.uuid4().hex[:8],
            'acpec_mobile_auth_enabled': enabled,
        })

    def _mobile_group_ids(self):
        ids = []
        for xmlid in (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
        ):
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                ids.append(group.id)
        return ids

    def _create_active_mobile_user(self, company):
        phone = '38%06d' % (company.id % 1000000)
        vals = {
            'name': 'Patch2W Mobile User %s' % phone,
            'login': phone,
            'email': 'patch2w.mobile.%s@example.invalid' % phone,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
            'mobile_phone': phone,
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'self_registered',
            'password': self.Users._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._mobile_group_ids())],
        }
        if 'acpec_mobile_phone' in self.Users._fields:
            vals['acpec_mobile_phone'] = phone
        return self.Users.with_context(
            acpec_mobile_allow_password_write=True,
            no_reset_password=True,
            acpec_fueltoken_allow_mobile_identity_initialization=True,
        ).create(vals)

    def test_patch2w_mobile_auth_disable_is_blocked_with_active_mobile_user(self):
        company = self._create_mobile_auth_company(enabled=True)
        self._create_active_mobile_user(company)

        company.write({'acpec_mobile_auth_enabled': True})

        with self.assertRaises(ValidationError):
            company.write({'acpec_mobile_auth_enabled': False})

        company.invalidate_recordset(['acpec_mobile_auth_enabled'])
        self.assertTrue(company.acpec_mobile_auth_enabled)

    def test_patch2w_mobile_auth_disable_is_allowed_without_mobile_user(self):
        company = self._create_mobile_auth_company(enabled=True)

        company.write({'acpec_mobile_auth_enabled': False})
        company.invalidate_recordset(['acpec_mobile_auth_enabled'])
        self.assertFalse(company.acpec_mobile_auth_enabled)

        company.write({'acpec_mobile_auth_enabled': True})
        company.invalidate_recordset(['acpec_mobile_auth_enabled'])
        self.assertTrue(company.acpec_mobile_auth_enabled)

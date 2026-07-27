# -*- coding: utf-8 -*-
import uuid

from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestCompanyFuelTokenEnabledGuard(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Company = self.env['res.company'].sudo()
        self.Partner = self.env['res.partner'].sudo()
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()

    def _prepare_enabled_company(self):
        company = self.env.company.sudo()
        other_enabled = self.Company.search([
            ('acpec_fueltoken_enabled', '=', True),
            ('id', '!=', company.id),
        ])
        if other_enabled:
            other_enabled.write({'acpec_fueltoken_enabled': False})
        if not company.acpec_fueltoken_enabled:
            company.write({'acpec_fueltoken_enabled': True})
        return company

    def test_patch2w_fueltoken_disable_is_blocked_when_wallet_exists(self):
        company = self._prepare_enabled_company()
        partner = self.Partner.create({
            'name': 'Patch2W FuelToken Wallet Partner %s' % uuid.uuid4().hex[:8],
        })
        self.Wallet.get_or_create(partner, company)

        company.write({'acpec_fueltoken_enabled': True})

        with self.assertRaises(ValidationError):
            company.write({'acpec_fueltoken_enabled': False})

        company.invalidate_recordset(['acpec_fueltoken_enabled'])
        self.assertTrue(company.acpec_fueltoken_enabled)

# -*- coding: utf-8 -*-

from psycopg2 import IntegrityError

from odoo.tests import TransactionCase, tagged
from odoo.tools import mute_logger


@tagged('post_install', '-at_install')
class TestFuelTokenCompanyUnique(TransactionCase):

    def _ensure_single_fueltoken_company(self):
        Company = self.env['res.company'].sudo()
        fuel_company = Company.search([('acpec_fueltoken_enabled', '=', True)], limit=1)
        if fuel_company:
            Company.search([
                ('acpec_fueltoken_enabled', '=', True),
                ('id', '!=', fuel_company.id),
            ]).write({'acpec_fueltoken_enabled': False})
            return fuel_company

        self.env.company.sudo().write({'acpec_fueltoken_enabled': True})
        return self.env.company.sudo()

    def test_single_fueltoken_company_helper_returns_unique_company(self):
        fuel_company = self._ensure_single_fueltoken_company()
        Company = self.env['res.company'].sudo()

        self.assertEqual(Company._fueltoken_company_count(), 1)
        self.assertEqual(Company._fueltoken_company(), fuel_company)

    def test_second_fueltoken_company_is_rejected_by_partial_unique_index(self):
        self._ensure_single_fueltoken_company()
        Company = self.env['res.company'].sudo()

        with self.assertRaises(IntegrityError), mute_logger('odoo.sql_db'):
            with self.env.cr.savepoint():
                Company.create({
                    'name': 'Patch43E1 second FuelToken company must fail',
                    'acpec_fueltoken_enabled': True,
                })

    def test_new_company_is_not_fueltoken_enabled_by_default(self):
        company = self.env['res.company'].sudo().create({
            'name': 'Patch43E1 regular Odoo company',
        })
        self.assertFalse(company.acpec_fueltoken_enabled)

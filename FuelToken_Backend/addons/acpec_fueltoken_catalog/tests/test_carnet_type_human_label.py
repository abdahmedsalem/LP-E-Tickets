# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCarnetTypeHumanLabel(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.currency = cls.env.company.currency_id
        cls.company = cls.env['res.company'].create({
            'name': 'ACPEC K4 Carnet Label Company',
            'currency_id': cls.currency.id,
        })

    def _create_carnet_type(self, face_count, face_value):
        return self.env['acpec.fuel.carnet.type'].create({
            'company_id': self.company.id,
            'face_count': face_count,
            'face_value': face_value,
            'validity_days': 30,
        })

    def _sql_name(self, carnet_type):
        self.env.cr.execute(
            """
            SELECT name
              FROM acpec_fuel_carnet_type
             WHERE id = %s
            """,
            [carnet_type.id],
        )
        return self.env.cr.fetchone()[0]

    def test_carnet_type_name_uses_human_multiplication_label(self):
        carnet_type = self._create_carnet_type(10, 100)

        self.assertEqual(
            carnet_type.name,
            'Carnet - 10 tickets x 100 %s' % self.currency.name,
        )

    def test_carnet_type_name_uses_ticket_singular(self):
        carnet_type = self._create_carnet_type(1, 250)

        self.assertEqual(
            carnet_type.name,
            'Carnet - 1 ticket x 250 %s' % self.currency.name,
        )

    def test_carnet_type_code_remains_short_technical_code_without_currency(self):
        carnet_type = self._create_carnet_type(10, 500)

        self.assertEqual(carnet_type.code, 'C10T-500')
        self.assertNotIn(self.currency.name, carnet_type.code)
        self.assertEqual(
            carnet_type.name,
            'Carnet - 10 tickets x 500 %s' % self.currency.name,
        )

    def test_refresh_human_names_updates_legacy_stored_values(self):
        carnet_type = self._create_carnet_type(10, 300)

        legacy_name = 'Carnet de 10 tickets - 300%s' % self.currency.name
        expected_name = 'Carnet - 10 tickets x 300 %s' % self.currency.name

        self.env.cr.execute(
            """
            UPDATE acpec_fuel_carnet_type
               SET name = %s
             WHERE id = %s
            """,
            [legacy_name, carnet_type.id],
        )

        self.assertEqual(self._sql_name(carnet_type), legacy_name)

        self.env['acpec.fuel.carnet.type']._refresh_human_carnet_type_names()

        self.assertEqual(self._sql_name(carnet_type), expected_name)

        carnet_type.invalidate_recordset(['name'])
        self.assertEqual(carnet_type.name, expected_name)

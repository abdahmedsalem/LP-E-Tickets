from uuid import uuid4

from odoo.tests.common import TransactionCase
from odoo.exceptions import UserError, ValidationError


class TestReferenceSnapshotArchivePolicyM21E(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company
        cls.CarnetType = cls.env['acpec.fuel.carnet.type'].sudo()
        cls.Purchase = cls.env['acpec.fuel.purchase'].sudo()
        cls.PurchaseLine = cls.env['acpec.fuel.purchase.line'].sudo()
        cls.Station = cls.env['acpec.fuel.station'].sudo()

    def _create_unique_carnet_type(self, face_count=10):
        for face_value in range(991001, 991801):
            code = 'C%sT-%s' % (face_count, face_value)
            if not self.CarnetType.search([
                ('code', '=', code),
                ('company_id', '=', self.company.id),
            ], limit=1):
                return self.CarnetType.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })
        self.fail('Unable to create unique carnet type for M21-E test')

    def _create_purchase_line_for_carnet_type(self, carnet_type):
        partner = self.env['res.partner'].sudo().create({
            'name': 'M21E Client %s' % uuid4().hex[:8],
            'phone': 'm21e-%s' % uuid4().hex[:8],
            'company_id': self.company.id,
        })
        purchase = self.Purchase._create_internal({
            'partner_id': partner.id,
            'company_id': self.company.id,
            'payment_reference': 'M21E-%s' % uuid4().hex[:8],
        })
        line = self.PurchaseLine._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': carnet_type.id,
            'carnet_qty': 1,
        })
        return purchase, line

    def test_m21e_purchase_line_snapshots_face_count_and_face_value_at_create(self):
        carnet_type = self._create_unique_carnet_type()
        original_face_value = carnet_type.face_value
        purchase, line = self._create_purchase_line_for_carnet_type(carnet_type)

        self.assertEqual(line.face_count, carnet_type.face_count)
        self.assertEqual(line.face_value, original_face_value)

        self.env.cr.execute(
            'UPDATE acpec_fuel_carnet_type SET face_value = face_value + 1 WHERE id = %s',
            [carnet_type.id],
        )
        carnet_type.invalidate_recordset(['face_value'])
        line.invalidate_recordset(['face_value', 'amount_total'])

        self.assertEqual(line.face_value, original_face_value)
        self.assertEqual(
            line.amount_total,
            line.carnet_qty * line.face_count * original_face_value,
        )
        self.assertTrue(purchase)

    def test_m21e_used_carnet_type_structural_fields_are_locked_but_archive_allowed(self):
        carnet_type = self._create_unique_carnet_type()
        self._create_purchase_line_for_carnet_type(carnet_type)

        with self.assertRaises(ValidationError):
            carnet_type.write({'face_value': carnet_type.face_value + 1})

        with self.assertRaises(ValidationError):
            carnet_type.write({'face_count': carnet_type.face_count + 1})

        with self.assertRaises(ValidationError):
            carnet_type.write({'validity_days': carnet_type.validity_days + 1})

        carnet_type.write({'active': False})
        self.assertFalse(carnet_type.active)

    def test_m21e_unused_carnet_type_remains_bo_editable_but_not_deletable(self):
        carnet_type = self._create_unique_carnet_type(face_count=11)

        carnet_type.write({
            'face_value': carnet_type.face_value + 1,
            'validity_days': carnet_type.validity_days + 1,
        })
        self.assertTrue(carnet_type.face_value)

        with self.assertRaises(UserError):
            carnet_type.unlink()

    def test_m21e_station_can_be_archived_but_not_deleted(self):
        station = self.Station.create({
            'name': 'M21E Station %s' % uuid4().hex[:8],
            'code': 'M21E-ST-%s' % uuid4().hex[:8],
            'company_id': self.company.id,
        })

        station.write({'active': False})
        self.assertFalse(station.active)

        with self.assertRaises(UserError):
            station.unlink()

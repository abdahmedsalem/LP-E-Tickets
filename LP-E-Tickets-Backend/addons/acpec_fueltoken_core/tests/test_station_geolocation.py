# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestStationGeolocation(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.station = cls.env['acpec.fuel.station'].create({
            'name': 'Station geolocalisee',
            'code': 'ST-GEO-TEST',
            'company_id': cls.env.company.id,
        })

    def test_station_accepts_valid_coordinates(self):
        self.station.write({
            'address': 'Nouakchott',
            'phone': '45000000',
            'latitude': 18.0858,
            'longitude': -15.9785,
        })

        self.assertEqual(self.station.address, 'Nouakchott')
        self.assertAlmostEqual(self.station.latitude, 18.0858)
        self.assertAlmostEqual(self.station.longitude, -15.9785)

    def test_station_rejects_invalid_latitude(self):
        with self.assertRaises(ValidationError):
            self.station.write({'latitude': 91})

    def test_station_rejects_invalid_longitude(self):
        with self.assertRaises(ValidationError):
            self.station.write({'longitude': -181})

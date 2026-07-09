# -*- coding: utf-8 -*-
from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestPurchaseRuntimeGuardsM21C(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.PurchaseLine = self.env['acpec.fuel.purchase.line'].sudo()
        self.Partner = self.env['res.partner'].sudo()
        self.CarnetType = self.env['acpec.fuel.carnet.type'].sudo()
        self.partner = self.Partner.create({'name': 'M21C Client'})
        self.carnet_type = self.CarnetType.create({
            'name': 'M21C Carnet 100',
            'code': 'M21C100',
            'face_value': 99999111,
            'face_count': 10,
            'active': True,
        })

    def _purchase(self):
        return self.Purchase.with_context(
            allow_fuel_purchase_create=True,
            allow_fuel_purchase_line_create=True,
        ).create({
            'partner_id': self.partner.id,
            'company_id': self.env.company.id,
            'payment_reference': 'PAY-M21C',
        })

    def _line(self, purchase):
        return self.PurchaseLine.with_context(
            allow_fuel_purchase_line_create=True,
        ).create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })

    def test_m21c_purchase_create_requires_internal_context(self):
        with self.assertRaises(UserError):
            self.Purchase.create({
                'partner_id': self.partner.id,
                'company_id': self.env.company.id,
                'payment_reference': 'PAY-M21C-DIRECT',
            })

    def test_m21c_purchase_line_create_requires_internal_context(self):
        purchase = self._purchase()

        with self.assertRaises(UserError):
            self.PurchaseLine.create({
                'purchase_id': purchase.id,
                'carnet_type_id': self.carnet_type.id,
                'carnet_qty': 1,
            })

    def test_m21c_purchase_unlink_is_forbidden(self):
        purchase = self._purchase()

        with self.assertRaises(UserError):
            purchase.unlink()

    def test_m21c_purchase_line_unlink_is_forbidden(self):
        purchase = self._purchase()
        line = self._line(purchase)

        with self.assertRaises(UserError):
            line.unlink()

# -*- coding: utf-8 -*-
from odoo.tests.common import TransactionCase


class TestMobilePhoneChangeRemovedC0(TransactionCase):

    def test_patch43m23_c0_obsolete_model_is_not_registered(self):
        self.assertNotIn(
            'acpec.fueltoken.mobile.phone.change.log',
            self.env.registry.models,
        )

    def test_patch43m23_c0_refusal_method_is_preserved(self):
        self.assertTrue(
            hasattr(
                self.env['res.users'],
                'action_fueltoken_change_mobile_phone',
            )
        )

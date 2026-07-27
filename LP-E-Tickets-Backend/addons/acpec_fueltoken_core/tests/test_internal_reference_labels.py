# -*- coding: utf-8 -*-
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestInternalReferenceLabels(TransactionCase):

    def test_patch43m20_a1_sequence_name_fields_are_internal_references(self):
        expected_models = [
            'acpec.fuel.transaction',
            'acpec.fuel.purchase',
            'acpec.fuel.qr',
            'acpec.fuel.carnet.transfer',
            'acpec.fuel.ticket.transfer',
        ]

        for model_name in expected_models:
            model = self.env[model_name]
            self.assertIn('name', model._fields)
            self.assertEqual(
                model._fields['name'].string,
                'Référence interne',
                '%s.name must be labelled as internal reference' % model_name,
            )

# -*- coding: utf-8 -*-

from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestTransactionEconomicEffect(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Transaction = self.env['acpec.fuel.transaction'].sudo()
        self.company = self.env.company

    def _log_transaction(self, transaction_type, transaction_effect=False, amount=100.0, qty=2):
        kwargs = {
            'lines': [{
                'face_value': amount,
                'qty': qty,
            }],
            'note': 'Patch43M20-C economic effect test',
        }
        if transaction_effect:
            kwargs['transaction_effect'] = transaction_effect
        tx = self.Transaction.log(
            transaction_type,
            self.company,
            **kwargs
        )
        tx.invalidate_recordset(['transaction_effect', 'amount_total', 'signed_amount'])
        return tx

    def test_default_economic_effect_mapping_and_signed_amount(self):
        cases = [
            ('purchase_submitted', 'no_effect', 0.0),
            ('purchase_approved', 'incoming', 200.0),
            ('emission_qr', 'outgoing', -200.0),
            ('consommation_station', 'no_effect', 0.0),
            ('retirer_qr', 'no_effect', 0.0),
            ('separer_qr', 'no_effect', 0.0),
            ('blocage_qr', 'no_effect', 0.0),
            ('expiration_qr', 'no_effect', 0.0),
            ('expiration_faces', 'outgoing', -200.0),
        ]
        for transaction_type, expected_effect, expected_signed_amount in cases:
            tx = self._log_transaction(transaction_type)
            self.assertEqual(tx.amount_total, 200.0)
            self.assertEqual(tx.transaction_effect, expected_effect)
            self.assertEqual(tx.signed_amount, expected_signed_amount)

    def test_transfer_effect_can_be_explicitly_outgoing_or_incoming(self):
        outgoing_tx = self._log_transaction('transfert_ticket', transaction_effect='outgoing')
        incoming_tx = self._log_transaction('transfert_ticket', transaction_effect='incoming')
        neutral_tx = self._log_transaction('transfert_ticket')

        self.assertEqual(outgoing_tx.transaction_effect, 'outgoing')
        self.assertEqual(outgoing_tx.signed_amount, -200.0)

        self.assertEqual(incoming_tx.transaction_effect, 'incoming')
        self.assertEqual(incoming_tx.signed_amount, 200.0)

        self.assertEqual(neutral_tx.transaction_effect, 'no_effect')
        self.assertEqual(neutral_tx.signed_amount, 0.0)

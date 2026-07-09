# -*- coding: utf-8 -*-
import base64

from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestCarnetTransferLockReread(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()
        self.Transfer = self.env['acpec.fuel.carnet.transfer'].sudo()
        self.carnet_type = self._create_unique_carnet_type()

    def _create_unique_carnet_type(self):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(902001, 902301):
            code = 'C%sT-%s' % (face_count, face_value)
            if not carnet_model.search([
                ('company_id', '=', self.company.id),
                ('code', '=', code),
            ], limit=1):
                return carnet_model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })
        self.fail('Impossible de créer un type de carnet isolé pour G5.')

    def _create_partner_wallet(self, name):
        partner = self.env['res.partner'].sudo().create({'name': name})
        wallet = self.Wallet.get_or_create(partner, self.company)
        return partner, wallet

    def _create_source_face_line(self, source_partner):
        purchase = self.Purchase.with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).create({
            'partner_id': source_partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-G5-TR5',
        })
        self.env['acpec.fuel.purchase.line'].with_context(allow_fuel_purchase_line_create=True).sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-g5.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test G5\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.FaceLine.search([('purchase_id', '=', purchase.id)], limit=1)
        self.assertTrue(face_line)
        self.assertEqual(face_line.qty_initial, self.carnet_type.face_count)
        self.assertEqual(face_line.qty_available, self.carnet_type.face_count)
        return face_line

    def test_g5_transfer_rereads_locked_face_line_before_confirming(self):
        source_partner, source_wallet = self._create_partner_wallet('G5 Source')
        _dest_partner, dest_wallet = self._create_partner_wallet('G5 Destination')
        _hijack_partner, hijack_wallet = self._create_partner_wallet('G5 Hijack Wallet')

        face_line = self._create_source_face_line(source_partner)
        self.assertEqual(face_line.wallet_id.id, source_wallet.id)

        transfer = self.Transfer.create({
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'G5-TR5-REREAD',
            'line_ids': [(0, 0, {
                'face_line_id': face_line.id,
                'carnet_qty': 1,
            })],
        })

        # Charger volontairement le cache ORM avant modification SQL directe.
        cached_wallet_id = transfer.line_ids.face_line_id.wallet_id.id
        self.assertEqual(cached_wallet_id, source_wallet.id)

        # Mutation hors ORM : simule un changement concurrent déjà committé/visible.
        # Sans invalidate_recordset() après FOR UPDATE, action_confirm pourrait lire
        # l'ancien wallet depuis le cache et confirmer à tort.
        self.env.cr.execute(
            'UPDATE acpec_fuel_face_line SET wallet_id = %s WHERE id = %s',
            [hijack_wallet.id, face_line.id],
        )

        with self.assertRaises(ValidationError):
            transfer.action_confirm(actor_user=self.env.user)

        face_line.invalidate_recordset(['wallet_id'])
        transfer.invalidate_recordset(['state'])

        self.assertEqual(face_line.wallet_id.id, hijack_wallet.id)
        self.assertEqual(transfer.state, 'draft')

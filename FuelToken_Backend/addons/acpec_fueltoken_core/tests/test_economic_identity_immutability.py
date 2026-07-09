# -*- coding: utf-8 -*-
import base64
import uuid

from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestEconomicIdentityImmutability(TransactionCase):

    QR_FACE_QTY = 4

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()
        self.Qr = self.env['acpec.fuel.qr'].sudo()
        self.Transfer = self.env['acpec.fuel.carnet.transfer'].sudo()
        self.carnet_type = self._create_unique_carnet_type()

    def _create_unique_carnet_type(self):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(906001, 906401):
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
        self.fail('Impossible de créer un type de carnet isolé pour G8.')

    def _create_partner_wallet(self, name):
        partner = self.env['res.partner'].sudo().create({'name': name})
        wallet = self.Wallet.get_or_create(partner, self.company)
        return partner, wallet

    def _create_purchase_with_two_carnets(self, partner, suffix):
        purchase = self.Purchase.with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).create({
            'partner_id': partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-G8-%s' % suffix,
        })
        purchase_line = self.env['acpec.fuel.purchase.line'].with_context(allow_fuel_purchase_line_create=True).sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 2,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-g8.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test G8\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_lines = self.FaceLine.search([
            ('purchase_id', '=', purchase.id),
        ], order='carnet_sequence,id')
        self.assertEqual(len(face_lines), 2)
        return purchase, purchase_line, face_lines

    def test_patch2v_wallet_partner_and_company_are_immutable_after_creation(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, wallet = self._create_partner_wallet('G8 Wallet Identity Source %s' % suffix)
        other_partner = self.env['res.partner'].sudo().create({
            'name': 'G8 Wallet Identity Other %s' % suffix,
        })
        other_company = self.env['res.company'].sudo().create({
            'name': 'G8 Wallet Identity Company %s' % suffix,
        })

        old_partner = wallet.partner_id
        old_company = wallet.company_id

        # Idempotent writes are harmless and must not break normal ORM/form flows.
        wallet.write({
            'partner_id': old_partner.id,
            'company_id': old_company.id,
        })

        forbidden_writes = [
            {'partner_id': other_partner.id},
            {'partner_id': False},
            {'company_id': other_company.id},
            {'company_id': False},
            {'partner_id': other_partner.id, 'company_id': other_company.id},
        ]

        for vals in forbidden_writes:
            with self.assertRaises(ValidationError):
                wallet.write(vals)

            wallet.invalidate_recordset(['partner_id', 'company_id'])
            self.assertEqual(wallet.partner_id.id, old_partner.id)
            self.assertEqual(wallet.company_id.id, old_company.id)

    def test_g8_face_line_direct_economic_mutations_are_blocked_but_transfer_flow_works(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('G8 Source %s' % suffix)
        _dest_partner, dest_wallet = self._create_partner_wallet('G8 Destination %s' % suffix)
        _purchase, _purchase_line, face_lines = self._create_purchase_with_two_carnets(source_partner, suffix)

        face_line = face_lines[0]
        transfer_face_line = face_lines[1]

        with self.assertRaises(ValidationError):
            face_line.write({'face_value': face_line.face_value + 1})

        with self.assertRaises(ValidationError):
            face_line.write({'qty_initial': face_line.qty_initial + 1})

        with self.assertRaises(ValidationError):
            face_line.write({'lot_short_code': 'BADG8'})

        with self.assertRaises(ValidationError):
            face_line.write({'is_transfer_fragment': True})

        with self.assertRaises(ValidationError):
            face_line.write({'origin_face_line_id': transfer_face_line.id})

        with self.assertRaises(ValidationError):
            face_line.write({'origin_ticket_transfer_line_id': 1})

        with self.assertRaises(ValidationError):
            face_line.write({'wallet_id': dest_wallet.id})

        # Cette mutation respecte la somme C2, mais contournerait les flux métier.
        # Elle doit donc être refusée par VAL1/G8.
        with self.assertRaises(ValidationError):
            face_line.write({
                'qty_available': face_line.qty_available - 1,
                'qty_consumed': face_line.qty_consumed + 1,
            })

        transfer = self.Transfer.create({
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'G8-TRF-%s' % suffix,
            'line_ids': [(0, 0, {
                'face_line_id': transfer_face_line.id,
                'carnet_qty': 1,
            })],
        })
        transfer.action_confirm(actor_user=self.env.user)

        transfer_face_line.invalidate_recordset(['wallet_id'])
        self.assertEqual(transfer_face_line.wallet_id.id, dest_wallet.id)

    def test_g8_qr_line_direct_economic_mutations_are_blocked_but_split_flow_works(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('G8 QR Source %s' % suffix)
        _purchase, _purchase_line, face_lines = self._create_purchase_with_two_carnets(source_partner, suffix)

        face_line = face_lines[0]
        qr = self.Qr.issue_from_available(
            source_wallet,
            [{'face_line_id': face_line.id, 'qty': self.QR_FACE_QTY}],
            idempotency_key='G8-QR-%s' % suffix,
            request_hash='G8-QR-HASH-%s' % suffix,
        )
        qr_line = qr.line_ids[0]

        with self.assertRaises(ValidationError):
            qr_line.write({'face_value': qr_line.face_value + 1})

        with self.assertRaises(ValidationError):
            qr_line.write({'purchase_id': False})

        with self.assertRaises(ValidationError):
            qr_line.write({'qty': qr_line.qty - 1})

        with self.assertRaises(ValidationError):
            qr_line.write({'state': 'consumed'})

        empty_qr = self.Qr.with_context(allow_fuel_qr_create=True).create({'wallet_id': source_wallet.id})
        with self.assertRaises(ValidationError):
            qr_line.write({'qr_id': empty_qr.id})

        child = qr.action_retirer_to_child(
            [{'qr_line_id': qr_line.id, 'qty': 1}],
            idempotency_key='G8-RETIRER-%s' % suffix,
            request_hash='G8-RETIRER-HASH-%s' % suffix,
        )
        self.assertTrue(child)
        self.assertTrue(child.line_ids)
        self.assertEqual(child.line_ids[0].purchase_id.id, qr_line.purchase_id.id)
        self.assertEqual(child.line_ids[0].purchase_line_id.id, qr_line.purchase_line_id.id)
        self.assertEqual(child.line_ids[0].face_line_id.id, face_line.id)

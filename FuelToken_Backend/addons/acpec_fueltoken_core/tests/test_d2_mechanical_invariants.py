# -*- coding: utf-8 -*-
import base64

from odoo.exceptions import ValidationError, UserError
from odoo.tests import TransactionCase, tagged
from odoo.tools import mute_logger


@tagged('-at_install', 'post_install')
class TestD2MechanicalInvariants(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.partner = self.env['res.partner'].sudo().create({
            'name': 'Client G3 invariants',
        })
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()
        self.Qr = self.env['acpec.fuel.qr'].sudo()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.carnet_type = self._create_unique_carnet_type()

    def _create_unique_carnet_type(self):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(901001, 901201):
            code = 'C%sT-%s' % (face_count, face_value)
            if not carnet_model.search([('company_id', '=', self.company.id), ('code', '=', code)], limit=1):
                return carnet_model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })
        self.fail('Impossible de créer un type de carnet isolé pour G3.')

    def _create_purchase_with_face_line(self):
        purchase = self.Purchase.with_context(allow_fuel_purchase_create=True, allow_fuel_purchase_line_create=True).create({
            'partner_id': self.partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-G3-D2',
        })
        self.env['acpec.fuel.purchase.line'].with_context(allow_fuel_purchase_line_create=True).sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-g3.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test G3\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.with_context(allow_fuel_purchase_update=True).sudo().write({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.FaceLine.search([('purchase_id', '=', purchase.id)], limit=1)
        self.assertTrue(face_line)
        return purchase, face_line

    def test_g3_w1_wallet_is_unique_per_partner_company_and_get_or_create_is_idempotent(self):
        wallet_1 = self.Wallet.get_or_create(self.partner, self.company)
        wallet_2 = self.Wallet.get_or_create(self.partner, self.company)

        self.assertEqual(wallet_1, wallet_2)

        wallets = self.Wallet.search([
            ('partner_id', '=', self.partner.id),
            ('company_id', '=', self.company.id),
        ])
        self.assertEqual(len(wallets), 1)

        with mute_logger('odoo.sql_db'):
            with self.assertRaises(Exception):
                with self.env.cr.savepoint():
                    self.Wallet.with_context(allow_fuel_wallet_create=True).create({
                        'partner_id': self.partner.id,
                        'company_id': self.company.id,
                    })

        wallets.invalidate_recordset()
        wallets = self.Wallet.search([
            ('partner_id', '=', self.partner.id),
            ('company_id', '=', self.company.id),
        ])
        self.assertEqual(len(wallets), 1)


    def test_m21b3_face_line_create_requires_internal_context(self):
        FaceLine = self.env['acpec.fuel.face.line']

        with self.assertRaises(UserError):
            FaceLine.create({})

    def test_m21b3_face_line_unlink_is_forbidden(self):
        _purchase, face_line = self._create_purchase_with_face_line()

        with self.assertRaises(UserError):
            face_line.unlink()

    def test_g3_c2_face_quantities_must_conserve_initial_quantity(self):
        _purchase, face_line = self._create_purchase_with_face_line()

        self.assertEqual(
            face_line.qty_initial,
            face_line.qty_available
            + face_line.qty_qr_active
            + face_line.qty_qr_blocked
            + face_line.qty_consumed
            + face_line.qty_expired
            + face_line.qty_transferred_out,
        )

        with self.assertRaises(ValidationError):
            face_line.write({'qty_available': face_line.qty_available - 1})

        with self.assertRaises(ValidationError):
            face_line.write({'qty_transferred_out': face_line.qty_transferred_out + 1})

        transfer_qty = 2
        face_line.with_context(allow_fuel_face_line_state_update=True).write({
            'qty_available': face_line.qty_available - transfer_qty,
            'qty_transferred_out': face_line.qty_transferred_out + transfer_qty,
        })

        face_line.invalidate_recordset([
            'qty_initial',
            'qty_available',
            'qty_qr_active',
            'qty_qr_blocked',
            'qty_consumed',
            'qty_expired',
            'qty_transferred_out',
        ])
        self.assertEqual(
            face_line.qty_initial,
            face_line.qty_available
            + face_line.qty_qr_active
            + face_line.qty_qr_blocked
            + face_line.qty_consumed
            + face_line.qty_expired
            + face_line.qty_transferred_out,
        )
        self.assertEqual(face_line.qty_transferred_out, transfer_qty)

        wallet = face_line.wallet_id
        self.assertEqual(wallet.qty_transferred_out, transfer_qty)
        self.assertEqual(wallet.amount_transferred_out, transfer_qty * face_line.face_value)
        self.assertEqual(wallet.balance, face_line.qty_available * face_line.face_value)

    def test_g3_q8_qr_public_and_numeric_identifiers_are_generated_and_unique(self):
        wallet = self.Wallet.get_or_create(self.partner, self.company)

        qr_1 = self.Qr.with_context(allow_fuel_qr_create=True).create({'wallet_id': wallet.id})
        qr_2 = self.Qr.with_context(allow_fuel_qr_create=True).create({'wallet_id': wallet.id})

        self.assertTrue(qr_1.public_code)
        self.assertTrue(qr_2.public_code)
        self.assertNotEqual(qr_1.public_code, qr_2.public_code)

        self.assertTrue(qr_1.qr_numeric_code_hash)
        self.assertTrue(qr_2.qr_numeric_code_hash)
        self.assertTrue(qr_1.qr_numeric_code_nonce)
        self.assertTrue(qr_2.qr_numeric_code_nonce)
        self.assertNotEqual(qr_1.qr_numeric_code_hash, qr_2.qr_numeric_code_hash)

        self.assertNotEqual(qr_1.public_code, qr_1.name)
        self.assertNotEqual(qr_2.public_code, qr_2.name)

        with mute_logger('odoo.sql_db'):
            with self.assertRaises(Exception):
                with self.env.cr.savepoint():
                    self.Qr.with_context(allow_fuel_qr_create=True).create({
                        'wallet_id': wallet.id,
                        'public_code': qr_1.public_code,
                    })

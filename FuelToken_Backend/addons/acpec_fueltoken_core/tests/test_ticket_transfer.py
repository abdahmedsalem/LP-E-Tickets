# -*- coding: utf-8 -*-
import base64
import uuid

from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestTicketTransfer(TransactionCase):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()
        self.Qr = self.env['acpec.fuel.qr'].sudo()
        self.Tx = self.env['acpec.fuel.transaction'].sudo()
        self.TicketTransfer = self.env['acpec.fuel.ticket.transfer'].sudo()
        self.carnet_type = self._create_unique_carnet_type()

    def _create_unique_carnet_type(self):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(907001, 907401):
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
        self.fail('Impossible de créer un type de carnet isolé pour I1.')

    def _create_partner_wallet(self, name):
        partner = self.env['res.partner'].sudo().create({'name': name})
        wallet = self.Wallet.get_or_create(partner, self.company)
        return partner, wallet

    def _create_purchase_with_face_line(self, partner, suffix):
        purchase = self.Purchase.create({
            'partner_id': partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-I1-%s' % suffix,
        })
        purchase_line = self.env['acpec.fuel.purchase.line'].sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-i1.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test I1\n').decode('ascii'),
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
        return purchase, purchase_line, face_line

    def _create_ticket_transfer(self, source_wallet, dest_wallet, face_line, qty, suffix, note=True):
        return self.TicketTransfer.with_context(allow_fuel_ticket_transfer_create=True).create({
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'I1-TKT-%s' % suffix,
            'request_hash': 'I1-HASH-%s' % suffix,
            'note': 'Motif transfert I1 %s' % suffix if note else False,
            'line_ids': [(0, 0, {
                'source_face_line_id': face_line.id,
                'qty_faces': qty,
            })],
        })

    def test_i1_ticket_transfer_creates_destination_fragment_and_preserves_origin(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('I1 Source %s' % suffix)
        _dest_partner, dest_wallet = self._create_partner_wallet('I1 Destination %s' % suffix)
        purchase, purchase_line, face_line = self._create_purchase_with_face_line(source_partner, suffix)

        original_initial = face_line.qty_initial
        qty = 3
        transfer = self._create_ticket_transfer(source_wallet, dest_wallet, face_line, qty, suffix)
        transfer.action_confirm(actor_user=self.env.user)

        transfer.invalidate_recordset(['state', 'face_qty_total', 'amount_total'])
        line = transfer.line_ids[0]
        line.invalidate_recordset(['dest_face_line_id'])
        dest_line = line.dest_face_line_id
        self.assertTrue(dest_line)

        face_line.invalidate_recordset(['qty_initial', 'qty_available', 'qty_transferred_out'])
        dest_line.invalidate_recordset()
        source_wallet.invalidate_recordset()
        dest_wallet.invalidate_recordset()

        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(face_line.qty_initial, original_initial)
        self.assertEqual(face_line.qty_available, original_initial - qty)
        self.assertEqual(face_line.qty_transferred_out, qty)
        self.assertEqual(source_wallet.balance, (original_initial - qty) * face_line.face_value)

        self.assertEqual(dest_line.wallet_id.id, dest_wallet.id)
        self.assertEqual(dest_line.qty_initial, qty)
        self.assertEqual(dest_line.qty_available, qty)
        self.assertEqual(dest_line.qty_transferred_out, 0)
        self.assertTrue(dest_line.is_transfer_fragment)
        self.assertEqual(dest_line.origin_face_line_id.id, face_line.id)
        self.assertEqual(dest_line.origin_ticket_transfer_line_id.id, line.id)
        self.assertEqual(dest_line.purchase_id.id, purchase.id)
        self.assertEqual(dest_line.purchase_line_id.id, purchase_line.id)
        self.assertEqual(dest_line.carnet_type_id.id, face_line.carnet_type_id.id)
        self.assertEqual(dest_line.face_value, face_line.face_value)
        self.assertTrue(dest_line.carnet_no)
        self.assertTrue(dest_line.carnet_short_code)
        self.assertNotEqual(dest_line.carnet_no, face_line.carnet_no)
        self.assertNotEqual(dest_line.carnet_short_code, face_line.carnet_short_code)
        self.assertEqual(dest_wallet.balance, qty * face_line.face_value)

        txs = self.Tx.search([
            ('transaction_type', '=', 'transfert_ticket'),
            ('ticket_transfer_id', '=', transfer.id),
        ])
        self.assertEqual(len(txs), 2)
        self.assertEqual(set(txs.mapped('wallet_id').ids), {source_wallet.id, dest_wallet.id})
        self.assertEqual(sum(txs.mapped('qty_total')), qty * 2)
        src_tx = txs.filtered(lambda tx: tx.wallet_id == source_wallet)
        dst_tx = txs.filtered(lambda tx: tx.wallet_id == dest_wallet)
        self.assertEqual(src_tx.line_ids.face_line_id.id, face_line.id)
        self.assertEqual(dst_tx.line_ids.face_line_id.id, dest_line.id)
        for tx in txs:
            self.assertEqual(tx.ticket_transfer_id.id, transfer.id)
            self.assertEqual(tx.line_ids.ticket_transfer_id.id, transfer.id)
            self.assertEqual(tx.line_ids.purchase_id.id, purchase.id)
            self.assertEqual(tx.line_ids.purchase_line_id.id, purchase_line.id)
            self.assertEqual(tx.line_ids.qty, qty)

        transfer.action_confirm(actor_user=self.env.user)
        self.assertEqual(self.FaceLine.search_count([('origin_ticket_transfer_line_id', '=', line.id)]), 1)
        self.assertEqual(self.Tx.search_count([('transaction_type', '=', 'transfert_ticket'), ('ticket_transfer_id', '=', transfer.id)]), 2)

    def test_i1_ticket_transfer_rejects_non_available_quantity_and_requires_note(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('I1 Source guard %s' % suffix)
        _dest_partner, dest_wallet = self._create_partner_wallet('I1 Destination guard %s' % suffix)
        _purchase, _purchase_line, face_line = self._create_purchase_with_face_line(source_partner, suffix)

        self.Qr.issue_from_available(
            source_wallet,
            [{'face_line_id': face_line.id, 'qty': 4}],
            idempotency_key='I1-QR-%s' % suffix,
            request_hash='I1-QR-HASH-%s' % suffix,
        )
        face_line.invalidate_recordset(['qty_available', 'qty_qr_active'])
        self.assertEqual(face_line.qty_qr_active, 4)

        transfer = self._create_ticket_transfer(source_wallet, dest_wallet, face_line, face_line.qty_available + 1, suffix)
        with self.assertRaises(ValidationError):
            transfer.action_confirm(actor_user=self.env.user)

        no_note = self._create_ticket_transfer(source_wallet, dest_wallet, face_line, 1, 'NO-NOTE-%s' % suffix, note=False)
        with self.assertRaises(ValidationError):
            no_note.action_confirm(actor_user=self.env.user)

    def test_i1a_ticket_transfer_is_internal_create_only_and_bo_read_only(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('I1A Source guard %s' % suffix)
        _dest_partner, dest_wallet = self._create_partner_wallet('I1A Destination guard %s' % suffix)
        _purchase, _purchase_line, face_line = self._create_purchase_with_face_line(source_partner, suffix)

        vals = {
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'I1A-TKT-%s' % suffix,
            'request_hash': 'I1A-HASH-%s' % suffix,
            'note': 'Motif transfert I1A %s' % suffix,
            'line_ids': [(0, 0, {
                'source_face_line_id': face_line.id,
                'qty_faces': 1,
            })],
        }

        with self.assertRaises(UserError):
            self.TicketTransfer.create(vals)

        transfer = self.TicketTransfer.with_context(allow_fuel_ticket_transfer_create=True).create(vals)

        with self.assertRaises(UserError):
            transfer.write({'note': 'mutation BO interdite'})
        transfer.with_context(allow_fuel_ticket_transfer_update=True).write({'note': 'mutation interne autorisée'})

        with self.assertRaises(UserError):
            transfer.line_ids.write({'qty_faces': 2})
        transfer.line_ids.with_context(allow_fuel_ticket_transfer_update=True).write({'qty_faces': 1})

        with self.assertRaises(UserError):
            transfer.unlink()
        transfer.with_context(allow_fuel_ticket_transfer_unlink=True).unlink()

    def test_i1_confirmed_ticket_transfer_is_immutable(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner, source_wallet = self._create_partner_wallet('I1 Source immut %s' % suffix)
        _dest_partner, dest_wallet = self._create_partner_wallet('I1 Destination immut %s' % suffix)
        _purchase, _purchase_line, face_line = self._create_purchase_with_face_line(source_partner, suffix)

        transfer = self._create_ticket_transfer(source_wallet, dest_wallet, face_line, 2, suffix)
        transfer.action_confirm(actor_user=self.env.user)

        with self.assertRaises(UserError):
            transfer.write({'note': 'mutation interdite'})
        with self.assertRaises(UserError):
            transfer.line_ids.write({'qty_faces': 1})
        with self.assertRaises(UserError):
            transfer.unlink()

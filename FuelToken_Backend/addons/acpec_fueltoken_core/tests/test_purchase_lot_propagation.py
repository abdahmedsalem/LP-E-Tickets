# -*- coding: utf-8 -*-
import base64
import uuid

from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestPurchaseLotPropagation(TransactionCase):

    QR_FACE_QTY = 4

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Wallet = self.env['acpec.fuel.wallet'].sudo()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()
        self.FaceLine = self.env['acpec.fuel.face.line'].sudo()
        self.Qr = self.env['acpec.fuel.qr'].sudo()
        self.Tx = self.env['acpec.fuel.transaction'].sudo()
        self.Transfer = self.env['acpec.fuel.carnet.transfer'].sudo()
        self.carnet_type = self._create_unique_carnet_type()

    def _create_unique_carnet_type(self):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(904001, 904401):
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
        self.fail('Impossible de créer un type de carnet isolé pour G6.')

    def _mobile_station_group_ids(self):
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_station',
        )
        group_ids = []
        for xmlid in xmlids:
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                group_ids.append(group.id)
        return group_ids

    def _test_phone_21(self, seed):
        value = 2166136261
        for char in str(seed):
            value ^= ord(char)
            value = (value * 16777619) % 1000000
        return "21%06d" % value

    def _create_station_user(self, suffix):
        phone = self._test_phone_21('g6-station-%s' % suffix)
        user_model = self.env['res.users'].sudo()
        return user_model.with_context(no_reset_password=True).create({
            'name': 'Station G6 %s' % suffix,
            'login': phone,
            'mobile_phone': phone,
            'active': True,
            'company_id': self.company.id,
            'company_ids': [(6, 0, [self.company.id])],
            'acpec_mobile_only': True,
            'acpec_mobile_state': 'approved',
            'password': user_model._acpec_mobile_unusable_password(),
            'group_ids': [(6, 0, self._mobile_station_group_ids())],
        })

    def _create_station_record(self, suffix):
        station_user = self._create_station_user(suffix)
        Station = self.env['acpec.fuel.station'].sudo()
        vals = {
            'name': 'Station G6 %s' % suffix,
            'company_id': self.company.id,
        }
        if 'code' in Station._fields:
            vals['code'] = 'STG6%s' % suffix.upper().replace('-', '')[:12]
        if 'active' in Station._fields:
            vals['active'] = True
        if 'user_id' in Station._fields:
            vals['user_id'] = station_user.id
        if 'station_user_id' in Station._fields:
            vals['station_user_id'] = station_user.id
        if 'partner_id' in Station._fields:
            vals['partner_id'] = station_user.partner_id.id
        return Station.create(vals), station_user

    def _create_purchase_with_two_carnets(self, partner, suffix):
        purchase = self.Purchase._create_internal({
            'partner_id': partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-G6-%s' % suffix,
        })
        purchase_line = self.env['acpec.fuel.purchase.line']._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 2,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-g6.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test G6\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase._write_proof_internal({'proof_attachment_ids': [(4, attachment.id)]})

        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_lines = self.FaceLine.search([
            ('purchase_id', '=', purchase.id),
        ], order='carnet_sequence,id')

        self.assertEqual(len(face_lines), 2)
        self.assertEqual(set(face_lines.mapped('purchase_id').ids), {purchase.id})
        self.assertEqual(set(face_lines.mapped('purchase_line_id').ids), {purchase_line.id})
        return purchase, purchase_line, face_lines

    def _assert_tx_line_origin(self, line, purchase, purchase_line, face_line=False, qr=False, qr_line=False, transfer=False):
        self.assertEqual(line.purchase_id.id, purchase.id)
        self.assertEqual(line.purchase_line_id.id, purchase_line.id)
        if face_line:
            self.assertEqual(line.face_line_id.id, face_line.id)
        if qr:
            self.assertEqual(line.qr_id.id, qr.id)
        if qr_line:
            self.assertEqual(line.qr_line_id.id, qr_line.id)
        if transfer:
            self.assertEqual(line.transfer_id.id, transfer.id)

    def test_g6_purchase_origin_is_preserved_through_qr_consume_and_transfer(self):
        suffix = uuid.uuid4().hex[:8]
        source_partner = self.env['res.partner'].sudo().create({
            'name': 'Client source G6 %s' % suffix,
        })
        dest_partner = self.env['res.partner'].sudo().create({
            'name': 'Client destination G6 %s' % suffix,
        })

        source_wallet = self.Wallet.get_or_create(source_partner, self.company)
        dest_wallet = self.Wallet.get_or_create(dest_partner, self.company)

        purchase, purchase_line, face_lines = self._create_purchase_with_two_carnets(source_partner, suffix)
        qr_face_line = face_lines[0]
        transfer_face_line = face_lines[1]

        # 1) purchase -> face_line
        for face_line in face_lines:
            self.assertEqual(face_line.wallet_id.id, source_wallet.id)
            self.assertEqual(face_line.purchase_id.id, purchase.id)
            self.assertEqual(face_line.purchase_line_id.id, purchase_line.id)
            self.assertTrue(face_line.lot_short_code)
            self.assertTrue(face_line.carnet_short_code)

        approved_tx = self.Tx.search([
            ('transaction_type', '=', 'purchase_approved'),
            ('purchase_id', '=', purchase.id),
        ], limit=1)
        self.assertTrue(approved_tx)
        self.assertEqual(set(approved_tx.line_ids.mapped('face_line_id').ids), set(face_lines.ids))
        for tx_line in approved_tx.line_ids:
            self._assert_tx_line_origin(
                tx_line,
                purchase,
                purchase_line,
                face_line=tx_line.face_line_id,
            )

        # 2) face_line -> qr_line -> emission transaction
        qr = self.Qr.issue_from_available(
            source_wallet,
            [{'face_line_id': qr_face_line.id, 'qty': self.QR_FACE_QTY}],
            idempotency_key='G6-QR-%s' % suffix,
            request_hash='G6-QR-HASH-%s' % suffix,
        )
        self.assertTrue(qr.line_ids)
        qr_line = qr.line_ids[0]
        self.assertEqual(qr_line.face_line_id.id, qr_face_line.id)
        self.assertEqual(qr_line.purchase_id.id, purchase.id)
        self.assertEqual(qr_line.purchase_line_id.id, purchase_line.id)

        emission_tx = self.Tx.search([
            ('transaction_type', '=', 'emission_qr'),
            ('qr_id', '=', qr.id),
        ], limit=1)
        self.assertTrue(emission_tx)
        self.assertEqual(len(emission_tx.line_ids), 1)
        self._assert_tx_line_origin(
            emission_tx.line_ids[0],
            purchase,
            purchase_line,
            face_line=qr_face_line,
            qr=qr,
            qr_line=qr_line,
        )

        # 3) qr_line -> consommation station transaction
        station, station_user = self._create_station_record(suffix)
        consume_tx = qr.action_consume_by_station(
            station,
            user=station_user,
            idempotency_key='G6-CONSUME-%s' % suffix,
            request_hash='G6-CONSUME-HASH-%s' % suffix,
        )
        self.assertTrue(consume_tx)
        self.assertEqual(consume_tx.transaction_type, 'consommation_station')
        self.assertEqual(len(consume_tx.line_ids), 1)
        self._assert_tx_line_origin(
            consume_tx.line_ids[0],
            purchase,
            purchase_line,
            face_line=qr_face_line,
            qr=qr,
            qr_line=qr_line,
        )

        # 4) transfert : même face_line intacte déplacée, origine achat conservée.
        transfer = self.Transfer._create_internal({
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'G6-TRF-%s' % suffix,
            'line_ids': [(0, 0, {
                'face_line_id': transfer_face_line.id,
                'carnet_qty': 1,
            })],
        })
        transfer._confirm_internal(self.env.user)

        transfer.invalidate_recordset(['state'])
        transfer_face_line.invalidate_recordset(['wallet_id', 'purchase_id', 'purchase_line_id'])
        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(transfer_face_line.wallet_id.id, dest_wallet.id)
        self.assertEqual(transfer.line_ids.dest_face_line_id.id, transfer_face_line.id)
        self.assertEqual(transfer_face_line.purchase_id.id, purchase.id)
        self.assertEqual(transfer_face_line.purchase_line_id.id, purchase_line.id)

        transfer_txs = self.Tx.search([
            ('transaction_type', '=', 'transfert_carnet'),
            ('transfer_id', '=', transfer.id),
        ])
        self.assertEqual(len(transfer_txs), 2)
        self.assertEqual(set(transfer_txs.mapped('wallet_id').ids), {source_wallet.id, dest_wallet.id})

        for tx in transfer_txs:
            self.assertEqual(len(tx.line_ids), 1)
            self._assert_tx_line_origin(
                tx.line_ids[0],
                purchase,
                purchase_line,
                face_line=transfer_face_line,
                transfer=transfer,
            )

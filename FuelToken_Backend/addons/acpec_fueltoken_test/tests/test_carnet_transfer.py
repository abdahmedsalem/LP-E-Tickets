import base64
from types import SimpleNamespace
from unittest.mock import patch

from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged('-at_install', 'post_install')
class TestFuelCarnetTransfer(TransactionCase):

    def _create_bundle(self, carnet_qty=1):
        company = self.env.company
        source_partner = self.env['res.partner'].create({'name': 'Client transfert carnet'})
        source_user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'User transfert source',
            'login': 'source-transfer@example.com',
            'partner_id': source_partner.id,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
        })
        wallet = self.env['acpec.fuel.wallet'].sudo().get_or_create(source_partner, company)
        carnet = self.env['acpec.fuel.carnet.type'].sudo().create({
            'name': 'Carnet transfert test',
            'code': 'TRF-4',
            'face_count': 4,
            'face_value': 1000,
            'validity_days': 30,
            'active': True,
            'company_id': company.id,
        })
        purchase = self.env['acpec.fuel.purchase'].sudo().create_from_api(
            source_partner,
            company,
            [{'carnet_type_id': carnet.id, 'carnet_qty': carnet_qty}],
            'preuve-test.txt',
            base64.b64encode(b'proof').decode(),
            payment_reference='TEST-TRANSFER-001',
            idempotency_key='TEST-TRANSFER-PURCHASE-001',
        )
        purchase.action_approve()
        face_line = self.env['acpec.fuel.face.line'].sudo().search([
            ('purchase_id', '=', purchase.id),
            ('purchase_line_id', '=', purchase.line_ids[0].id),
        ], limit=1)

        dest_partner = self.env['res.partner'].create({'name': 'Destinataire transfert carnet'})
        dest_user = self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': 'User transfert destinataire',
            'login': 'dest-transfer@example.com',
            'partner_id': dest_partner.id,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
        })
        dest_wallet = self.env['acpec.fuel.wallet'].sudo().get_or_create(dest_partner, company)
        return {
            'company': company,
            'source_partner': source_partner,
            'source_user': source_user,
            'wallet': wallet,
            'carnet': carnet,
            'purchase': purchase,
            'face_line': face_line,
            'dest_partner': dest_partner,
            'dest_user': dest_user,
            'dest_wallet': dest_wallet,
        }

    def test_api_transfer_route_confirms_full_carnet(self):
        bundle = self._create_bundle(carnet_qty=1)
        controller = AcpecFuelTokenMobileApi()
        controller._require_mobile_auth = lambda: bundle['source_user']
        controller._require_fuel_group = lambda user, group: None
        controller._has_group_safe = lambda user, group: True
        controller._get_clean_str = lambda params, key: str(params.get(key) or '').strip()
        controller._get_optional_int = lambda params, key, default=0: int(params.get(key) or default)
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr)

        with patch('odoo.addons.acpec_fueltoken_api.controllers.api_mobile.request', dummy_request):
            response = controller.transfer_carnets(
                recipient_phone=bundle['dest_user'].login,
                lines=[{'face_line_id': bundle['face_line'].id, 'carnet_qty': 1}],
                note='Transfert test',
                idempotency_key='TEST-TRANSFER-API-001',
            )

        self.assertTrue(response['ok'])
        data = response['data']
        self.assertEqual(data['state'], 'confirmed')
        self.assertEqual(data['source_partner'], bundle['source_partner'].display_name)
        self.assertEqual(data['dest_partner'], bundle['dest_partner'].display_name)
        self.assertEqual(data['face_qty_total'], 4)
        self.assertEqual(data['amount_total'], 4000)
        self.assertEqual(data['lines'][0]['carnet_type_code'], bundle['carnet'].code)
        self.assertEqual(data['lines'][0]['carnet_type_name'], bundle['carnet'].name)
        self.assertTrue(data['lines'][0]['expires_at'])

    def test_faces_route_returns_transferable_intact_lines(self):
        bundle = self._create_bundle(carnet_qty=2)
        controller = AcpecFuelTokenMobileApi()
        controller._require_mobile_auth = lambda: bundle['source_user']
        controller._require_fuel_group = lambda user, group: None
        controller._get_bool_param = lambda value, default=False: bool(value) if value not in (None, '', False) else default
        dummy_request = SimpleNamespace(env=self.env, cr=self.env.cr)

        with patch('odoo.addons.acpec_fueltoken_api.controllers.api_mobile.request', dummy_request):
            response = controller.faces(transferable_only=True)

        self.assertTrue(response['ok'])
        items = response['data']['items']
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item['carnet_type_id'], bundle['carnet'].id)
        self.assertEqual(item['carnet_type_code'], bundle['carnet'].code)
        self.assertEqual(item['carnet_type_name'], bundle['carnet'].name)
        self.assertEqual(item['face_count'], bundle['carnet'].face_count)
        self.assertEqual(item['qty_initial'], 8)
        self.assertEqual(item['qty_available'], 8)
        self.assertTrue(item['is_transferable'])
        self.assertEqual(item['transferable_carnets'], 2)

    def test_confirm_rejects_partial_carnet_line(self):
        bundle = self._create_bundle(carnet_qty=2)
        self.env['acpec.fuel.qr'].sudo().issue_from_available(
            bundle['wallet'],
            [{'carnet_type_id': bundle['carnet'].id, 'qty': bundle['carnet'].face_count}],
            idempotency_key='TEST-TRANSFER-QR-001',
        )
        face_line = bundle['face_line']
        face_line.invalidate_recordset(['qty_initial', 'qty_available'])
        self.assertEqual(face_line.qty_initial, 8)
        self.assertEqual(face_line.qty_available, 4)

        transfer = self.env['acpec.fuel.carnet.transfer'].sudo().create({
            'source_wallet_id': bundle['wallet'].id,
            'dest_wallet_id': bundle['dest_wallet'].id,
            'company_id': bundle['company'].id,
            'line_ids': [(0, 0, {
                'face_line_id': face_line.id,
                'carnet_qty': 1,
            })],
        })

        with self.assertRaises(ValidationError):
            transfer.action_confirm()

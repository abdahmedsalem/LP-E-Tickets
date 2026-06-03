import base64

from odoo import fields
from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged('-at_install', 'post_install')
class TestFuelQrSeparation(TransactionCase):

    def _build_mixed_qr(self):
        company = self.env.company
        partner = self.env['res.partner'].create({
            'name': 'Client separation QR',
        })
        wallet = self.env['acpec.fuel.wallet'].sudo().get_or_create(partner, company)

        carnet_expired = self.env['acpec.fuel.carnet.type'].sudo().create({
            'name': 'Carnet test expire',
            'code': 'T-EXP',
            'face_count': 4,
            'face_value': 1000,
            'validity_days': 1,
            'active': True,
            'company_id': company.id,
        })
        carnet_valid = self.env['acpec.fuel.carnet.type'].sudo().create({
            'name': 'Carnet test valide',
            'code': 'T-VAL',
            'face_count': 4,
            'face_value': 1000,
            'validity_days': 30,
            'active': True,
            'company_id': company.id,
        })

        purchase = self.env['acpec.fuel.purchase'].sudo().create_from_api(
            partner,
            company,
            [
                {'carnet_type_id': carnet_expired.id, 'carnet_qty': 1},
                {'carnet_type_id': carnet_valid.id, 'carnet_qty': 1},
            ],
            'preuve-test.txt',
            base64.b64encode(b'proof').decode(),
            payment_reference='TEST-SEPARATION-001',
            idempotency_key='TEST-SEPARATION-PURCHASE-001',
        )
        purchase.action_approve()

        qr = self.env['acpec.fuel.qr'].sudo().issue_from_available(
            wallet,
            [
                {'carnet_type_id': carnet_expired.id, 'qty': carnet_expired.face_count},
                {'carnet_type_id': carnet_valid.id, 'qty': carnet_valid.face_count},
            ],
            idempotency_key='TEST-SEPARATION-ISSUE-001',
        )

        lines = qr.line_ids.sorted('id')
        self.assertEqual(len(lines), 2)

        now = fields.Datetime.now()
        lines[0].write({'expires_at': fields.Datetime.add(now, days=-2)})
        lines[1].write({'expires_at': fields.Datetime.add(now, days=2)})
        qr.action_refresh_expiration_state()
        qr.invalidate_recordset(['state'])
        return qr

    def test_partial_expiration_forces_blocked_state_in_payload(self):
        qr = self._build_mixed_qr()
        payload = AcpecFuelTokenMobileApi()._qr_payload(qr)

        self.assertEqual(payload['state'], 'blocked')
        self.assertTrue(payload['generated_at'])
        self.assertTrue(payload['expires_at'])
        self.assertFalse(payload['consumed_at'])

    def test_separation_moves_valid_lines_to_child_and_leaves_expired_source(self):
        qr = self._build_mixed_qr()

        child = qr.action_separer_valid_to_child(idempotency_key='TEST-SEPARATION-SPLIT-001')
        same_child = qr.action_separer_valid_to_child(idempotency_key='TEST-SEPARATION-SPLIT-001')

        self.assertEqual(child.id, same_child.id)
        self.assertEqual(qr.state, 'expired')
        self.assertEqual(child.state, 'active')
        self.assertEqual(child.parent_id.id, qr.id)

        source_states = set(qr.line_ids.mapped('state'))
        child_states = set(child.line_ids.mapped('state'))
        self.assertEqual(source_states, {'expired'})
        self.assertEqual(child_states, {'active'})
        self.assertEqual(len(qr.line_ids), 1)
        self.assertEqual(len(child.line_ids), 1)

        tx = self.env['acpec.fuel.transaction'].sudo().search([
            ('transaction_type', '=', 'separer_qr'),
            ('parent_qr_id', '=', qr.id),
            ('qr_id', '=', child.id),
        ], limit=1)
        self.assertTrue(tx)


import uuid

from odoo import fields
from odoo.exceptions import UserError, ValidationError
from odoo.tests import tagged
from odoo.tests.common import TransactionCase


@tagged('-at_install', 'post_install')
class TestFaceLineRuntimeGuardsM23C6B(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        suffix = uuid.uuid4().hex[:8]
        face_value = 930000 + int(suffix[:4], 16)

        cls.company = cls.env.company
        cls.FaceLine = cls.env['acpec.fuel.face.line']

        cls.partner = cls.env['res.partner'].sudo().create({
            'name': 'M23C6B Source %s' % suffix,
        })
        cls.dest_partner = cls.env['res.partner'].sudo().create({
            'name': 'M23C6B Destination %s' % suffix,
        })

        Wallet = cls.env['acpec.fuel.wallet']
        cls.wallet = Wallet.get_or_create(
            cls.partner,
            cls.company,
        )
        cls.dest_wallet = Wallet.get_or_create(
            cls.dest_partner,
            cls.company,
        )

        cls.carnet_type = cls.env[
            'acpec.fuel.carnet.type'
        ].sudo().create({
            'face_count': 10,
            'face_value': face_value,
            'validity_days': 365,
            'company_id': cls.company.id,
        })

        cls.purchase = cls.env[
            'acpec.fuel.purchase'
        ].sudo().with_context(
            allow_fuel_purchase_create=True,
            allow_fuel_purchase_line_create=True,
        ).create({
            'partner_id': cls.partner.id,
            'company_id': cls.company.id,
            'payment_reference': 'M23C6B-%s' % suffix,
        })

        cls.purchase_line = cls.env[
            'acpec.fuel.purchase.line'
        ].sudo().with_context(
            allow_fuel_purchase_line_create=True,
        ).create({
            'purchase_id': cls.purchase.id,
            'carnet_type_id': cls.carnet_type.id,
            'carnet_qty': 1,
        })

    def _vals(self):
        return {
            'wallet_id': self.wallet.id,
            'purchase_id': self.purchase.id,
            'purchase_line_id': self.purchase_line.id,
            'carnet_type_id': self.carnet_type.id,
            'face_value': self.carnet_type.face_value,
            'qty_initial': 10,
            'qty_available': 10,
            'expires_at': fields.Datetime.add(
                fields.Datetime.now(),
                days=365,
            ),
        }

    def _face_line(self):
        return self.FaceLine._create_internal(self._vals())

    def test_m23c6b_face_line_acl_is_read_only(self):
        accesses = self.env['ir.model.access'].sudo().search([
            ('model_id.model', '=', 'acpec.fuel.face.line'),
            ('active', '=', True),
        ])

        self.assertTrue(accesses)

        for access in accesses:
            self.assertTrue(access.perm_read)
            self.assertFalse(access.perm_write)
            self.assertFalse(access.perm_create)
            self.assertFalse(access.perm_unlink)

    def test_m23c6b_create_requires_sudo_and_exact_context(self):
        vals = self._vals()

        with self.assertRaises(UserError):
            self.FaceLine.create(vals)

        with self.assertRaises(UserError):
            self.FaceLine.sudo().create(vals)

        with self.assertRaises(UserError):
            self.FaceLine.sudo().with_context(
                allow_fuel_face_line_create=True,
            ).create(vals)

        admin_user = self.env.ref('base.user_admin')

        with self.assertRaises(UserError):
            self.FaceLine.with_user(admin_user).with_context(
                acpec_fueltoken_face_line_internal_operation='create',
            ).create(vals)

        face_line = self.FaceLine._create_internal(vals)

        self.assertTrue(face_line)
        self.assertEqual(face_line.wallet_id, self.wallet)
        self.assertEqual(face_line.qty_initial, 10)
        self.assertEqual(face_line.qty_available, 10)

    def test_m23c6b_write_requires_private_state_helper(self):
        face_line = self._face_line()

        state_vals = {
            'qty_available': 8,
            'qty_transferred_out': 2,
        }

        with self.assertRaises(UserError):
            face_line.write(state_vals)

        with self.assertRaises(UserError):
            face_line.sudo().with_context(
                allow_fuel_face_line_state_update=True,
            ).write(state_vals)

        with self.assertRaises(UserError):
            face_line.sudo().with_context(
                allow_fuel_face_line_economic_update=True,
            ).write({
                'face_value': face_line.face_value + 1,
            })

        with self.assertRaises(UserError):
            face_line.sudo().with_context(
                acpec_fueltoken_face_line_internal_operation='create',
            ).write(state_vals)

        face_line._write_state_internal(state_vals)

        self.assertEqual(face_line.qty_available, 8)
        self.assertEqual(face_line.qty_transferred_out, 2)

    def test_m23c6b_state_helper_preserves_quantity_invariant(self):
        face_line = self._face_line()

        face_line._write_state_internal({
            'qty_available': 7,
            'qty_qr_active': 3,
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

        with self.assertRaises(ValidationError):
            face_line._write_state_internal({
                'qty_available': 6,
            })

    def test_m23c6b_state_helper_allows_current_holder_move(self):
        face_line = self._face_line()

        face_line._write_state_internal({
            'wallet_id': self.dest_wallet.id,
        })

        face_line.invalidate_recordset([
            'wallet_id',
            'partner_id',
            'company_id',
        ])

        self.assertEqual(face_line.wallet_id, self.dest_wallet)
        self.assertEqual(
            face_line.partner_id,
            self.dest_partner,
        )
        self.assertEqual(face_line.company_id, self.company)

    def test_m23c6b_state_helper_rejects_economic_identity(self):
        face_line = self._face_line()

        forbidden_writes = [
            {
                'face_value': face_line.face_value + 1,
            },
            {
                'qty_initial': face_line.qty_initial + 1,
            },
            {
                'expires_at': fields.Datetime.now(),
            },
            {
                'name': 'BAD-M23C6B',
            },
            {
                'purchase_id': False,
            },
            {
                'wallet_id': self.dest_wallet.id,
                'carnet_type_id': False,
            },
        ]

        for vals in forbidden_writes:
            with self.assertRaises(ValidationError):
                face_line._write_state_internal(vals)

        face_line.invalidate_recordset([
            'wallet_id',
            'face_value',
            'qty_initial',
            'expires_at',
            'name',
            'purchase_id',
            'carnet_type_id',
        ])

        self.assertEqual(face_line.wallet_id, self.wallet)
        self.assertEqual(
            face_line.face_value,
            self.carnet_type.face_value,
        )
        self.assertEqual(face_line.qty_initial, 10)
        self.assertTrue(face_line.expires_at)
        self.assertEqual(face_line.purchase_id, self.purchase)
        self.assertEqual(
            face_line.carnet_type_id,
            self.carnet_type,
        )

    def test_m23c6b_unlink_remains_absolutely_forbidden(self):
        face_line = self._face_line()

        with self.assertRaises(UserError):
            face_line.unlink()

        with self.assertRaises(UserError):
            face_line.sudo().unlink()

        with self.assertRaises(UserError):
            face_line.sudo().with_context(
                acpec_fueltoken_face_line_internal_operation='purge',
            ).unlink()

        self.assertTrue(face_line.exists())

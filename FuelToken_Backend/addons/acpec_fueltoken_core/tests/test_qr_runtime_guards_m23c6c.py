# -*- coding: utf-8 -*-
import uuid

from odoo import fields
from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestQrRuntimeGuardsM23C6C(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        suffix = uuid.uuid4().hex[:8]
        face_value = 940000 + int(suffix[:4], 16)

        cls.company = cls.env.company
        cls.Qr = cls.env['acpec.fuel.qr']
        cls.QrLine = cls.env['acpec.fuel.qr.line']

        cls.partner = cls.env['res.partner'].sudo().create({
            'name': 'M23C6C Client %s' % suffix,
        })
        cls.wallet = cls.env['acpec.fuel.wallet'].get_or_create(
            cls.partner,
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
            'payment_reference': 'M23C6C-%s' % suffix,
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

        cls.face_line = cls.env[
            'acpec.fuel.face.line'
        ]._create_internal({
            'wallet_id': cls.wallet.id,
            'purchase_id': cls.purchase.id,
            'purchase_line_id': cls.purchase_line.id,
            'carnet_type_id': cls.carnet_type.id,
            'face_value': face_value,
            'qty_initial': 10,
            'qty_available': 10,
            'expires_at': fields.Datetime.add(
                fields.Datetime.now(),
                days=365,
            ),
        })

    def _qr_vals(self):
        return {
            'wallet_id': self.wallet.id,
        }

    def _qr(self):
        return self.Qr._create_internal(
            self._qr_vals()
        )

    def _qr_line_vals(self, qr):
        return {
            'qr_id': qr.id,
            'face_line_id': self.face_line.id,
            'purchase_id': self.purchase.id,
            'purchase_line_id': self.purchase_line.id,
            'face_value': self.face_line.face_value,
            'qty': 3,
            'state': 'active',
            'expires_at': self.face_line.expires_at,
        }

    def _qr_line(self, qr=False):
        qr = qr or self._qr()
        return self.QrLine._create_internal(
            self._qr_line_vals(qr)
        )

    def test_m23c6c_qr_and_line_acl_are_read_only(self):
        for model_name in (
            'acpec.fuel.qr',
            'acpec.fuel.qr.line',
        ):
            accesses = self.env['ir.model.access'].sudo().search([
                ('model_id.model', '=', model_name),
                ('active', '=', True),
            ])

            self.assertEqual(len(accesses), 3)

            for access in accesses:
                self.assertTrue(access.perm_read)
                self.assertFalse(access.perm_write)
                self.assertFalse(access.perm_create)
                self.assertFalse(access.perm_unlink)

    def test_m23c6c_qr_create_requires_sudo_and_exact_context(self):
        vals = self._qr_vals()

        with self.assertRaises(UserError):
            self.Qr.create(vals)

        with self.assertRaises(UserError):
            self.Qr.sudo().create(vals)

        with self.assertRaises(UserError):
            self.Qr.sudo().with_context(
                allow_fuel_qr_create=True,
            ).create(vals)

        admin_user = self.env.ref('base.user_admin')

        with self.assertRaises(UserError):
            self.Qr.with_user(admin_user).with_context(
                acpec_fueltoken_qr_internal_operation='create',
            ).create(vals)

        qr = self.Qr._create_internal(vals)

        self.assertTrue(qr)
        self.assertTrue(qr.public_code)
        self.assertTrue(qr.qr_numeric_code_hash)
        self.assertTrue(qr.qr_numeric_code_nonce)

    def test_m23c6c_qr_write_requires_private_helpers(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.write({'state': 'blocked'})

        with self.assertRaises(UserError):
            qr.sudo().with_context(
                allow_fuel_qr_state_update=True,
            ).write({'state': 'blocked'})

        with self.assertRaises(UserError):
            qr.sudo().with_context(
                allow_fuel_qr_economic_update=True,
            ).write({'request_hash': 'legacy'})

        with self.assertRaises(UserError):
            qr.sudo().with_context(
                acpec_fueltoken_qr_internal_operation='create',
            ).write({'state': 'blocked'})

        qr._write_state_internal({
            'state': 'blocked',
        })

        self.assertEqual(qr.state, 'blocked')

        with self.assertRaises(ValidationError):
            qr._write_state_internal({
                'request_hash': 'forbidden',
            })

        with self.assertRaises(ValidationError):
            qr._write_state_internal({
                'state': 'active',
                'wallet_id': self.wallet.id,
            })

    def test_m23c6c_numeric_hash_backfill_is_narrow_and_one_shot(self):
        qr = self._qr()

        nonce, code_hash = qr._build_unique_qr_numeric_code_values(
            qr.public_code,
            exclude_id=qr.id,
        )

        with self.assertRaises(ValidationError):
            qr._write_numeric_hash_internal({
                'qr_numeric_code_nonce': nonce,
                'qr_numeric_code_hash': code_hash,
            })

        with self.assertRaises(ValidationError):
            qr._write_numeric_hash_internal({
                'qr_numeric_code_hash': code_hash,
            })

        self.env.cr.execute(
            '''
            UPDATE acpec_fuel_qr
               SET qr_numeric_code_hash = NULL,
                   qr_numeric_code_nonce = NULL
             WHERE id = %s
            ''',
            (qr.id,),
        )
        qr.invalidate_recordset([
            'qr_numeric_code_hash',
            'qr_numeric_code_nonce',
        ])

        qr._ensure_qr_numeric_code_hash()
        qr.invalidate_recordset([
            'qr_numeric_code_hash',
            'qr_numeric_code_nonce',
        ])

        self.assertTrue(qr.qr_numeric_code_hash)
        self.assertTrue(qr.qr_numeric_code_nonce)

        original_hash = qr.qr_numeric_code_hash
        original_nonce = qr.qr_numeric_code_nonce

        qr._ensure_qr_numeric_code_hash()
        qr.invalidate_recordset([
            'qr_numeric_code_hash',
            'qr_numeric_code_nonce',
        ])

        self.assertEqual(
            qr.qr_numeric_code_hash,
            original_hash,
        )
        self.assertEqual(
            qr.qr_numeric_code_nonce,
            original_nonce,
        )

    def test_m23c6c_qr_unlink_is_absolutely_forbidden(self):
        qr = self._qr()

        with self.assertRaises(UserError):
            qr.unlink()

        with self.assertRaises(UserError):
            qr.sudo().unlink()

        with self.assertRaises(UserError):
            qr.sudo().with_context(
                allow_fuel_qr_unlink=True,
            ).unlink()

        with self.assertRaises(UserError):
            qr.sudo().with_context(
                acpec_fueltoken_qr_internal_operation='purge',
            ).unlink()

        self.assertTrue(qr.exists())

    def test_m23c6c_qr_line_create_requires_sudo_and_exact_context(self):
        qr = self._qr()
        vals = self._qr_line_vals(qr)

        with self.assertRaises(UserError):
            self.QrLine.create(vals)

        with self.assertRaises(UserError):
            self.QrLine.sudo().create(vals)

        with self.assertRaises(UserError):
            self.QrLine.sudo().with_context(
                allow_fuel_qr_line_create=True,
            ).create(vals)

        admin_user = self.env.ref('base.user_admin')

        with self.assertRaises(UserError):
            self.QrLine.with_user(admin_user).with_context(
                acpec_fueltoken_qr_line_internal_operation='create',
            ).create(vals)

        line = self.QrLine._create_internal(vals)

        self.assertTrue(line)
        self.assertEqual(line.qr_id, qr)
        self.assertEqual(line.qty, 3)

    def test_m23c6c_qr_line_write_is_state_only(self):
        line = self._qr_line()
        other_qr = self._qr()

        with self.assertRaises(UserError):
            line.write({'state': 'blocked'})

        with self.assertRaises(UserError):
            line.sudo().with_context(
                allow_fuel_qr_line_state_update=True,
            ).write({'state': 'blocked'})

        with self.assertRaises(UserError):
            line.sudo().with_context(
                allow_fuel_qr_line_economic_update=True,
            ).write({
                'expires_at': fields.Datetime.now(),
            })

        line._write_state_internal({
            'qr_id': other_qr.id,
            'qty': 2,
            'state': 'blocked',
        })

        line.invalidate_recordset([
            'qr_id',
            'qty',
            'state',
        ])

        self.assertEqual(line.qr_id, other_qr)
        self.assertEqual(line.qty, 2)
        self.assertEqual(line.state, 'blocked')

        forbidden_writes = [
            {
                'face_value': line.face_value + 1,
            },
            {
                'expires_at': fields.Datetime.now(),
            },
            {
                'purchase_id': False,
            },
            {
                'state': 'active',
                'face_line_id': False,
            },
        ]

        for vals in forbidden_writes:
            with self.assertRaises(ValidationError):
                line._write_state_internal(vals)

    def test_m23c6c_qr_line_unlink_is_absolutely_forbidden(self):
        line = self._qr_line()

        with self.assertRaises(UserError):
            line.unlink()

        with self.assertRaises(UserError):
            line.sudo().unlink()

        with self.assertRaises(UserError):
            line.sudo().with_context(
                allow_fuel_qr_line_unlink=True,
            ).unlink()

        with self.assertRaises(UserError):
            line.sudo().with_context(
                acpec_fueltoken_qr_line_internal_operation='purge',
            ).unlink()

        self.assertTrue(line.exists())

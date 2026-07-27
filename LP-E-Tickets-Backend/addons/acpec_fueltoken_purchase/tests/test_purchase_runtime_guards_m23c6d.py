# -*- coding: utf-8 -*-
from odoo import fields
from odoo.exceptions import UserError, ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestPurchaseRuntimeGuardsM23C6D(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Purchase = self.env['acpec.fuel.purchase']
        self.PurchaseLine = self.env['acpec.fuel.purchase.line']
        self.partner = self.env['res.partner'].sudo().create({
            'name': 'M23C6D Client',
            'company_id': self.env.company.id,
        })
        self.carnet_type = self._create_unique_carnet_type()
        self.non_sudo_user = self.env.ref('base.user_admin')

    def _create_unique_carnet_type(self):
        model = self.env['acpec.fuel.carnet.type'].sudo()
        for face_value in range(996001, 996101):
            code = 'C10T-%s' % face_value
            if not model.search([
                ('code', '=', code),
                ('company_id', '=', self.env.company.id),
            ], limit=1):
                return model.create({
                    'face_count': 10,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.env.company.id,
                })
        self.fail('Impossible de créer un type de carnet C6-D isolé.')

    def _purchase_vals(self):
        return {
            'partner_id': self.partner.id,
            'company_id': self.env.company.id,
            'payment_reference': 'PAY-M23C6D',
        }

    def _purchase(self):
        return self.Purchase._create_internal(
            self._purchase_vals()
        )

    def _line_vals(self, purchase):
        return {
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        }

    def _line(self, purchase):
        return self.PurchaseLine._create_internal(
            self._line_vals(purchase)
        )

    def _attachment(self, purchase):
        return self.env['ir.attachment'].sudo().create({
            'name': 'preuve-m23c6d.pdf',
            'datas': 'JVBERi0xLjQKJUVPRgo=',
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })

    def _attach_proof(self, purchase):
        attachment = self._attachment(purchase)
        purchase._write_proof_internal({
            'proof_attachment_ids': [(4, attachment.id)],
        })
        return attachment

    def test_m23c6d_purchase_and_line_acl_are_read_only(self):
        access_model = self.env['ir.model.access'].sudo()
        for model_name in (
            'acpec.fuel.purchase',
            'acpec.fuel.purchase.line',
        ):
            model = self.env['ir.model'].sudo().search([
                ('model', '=', model_name),
            ], limit=1)
            rows = access_model.search([
                ('model_id', '=', model.id),
                ('group_id', 'in', [
                    self.env.ref(
                        'acpec_fueltoken_base.group_fuel_user'
                    ).id,
                    self.env.ref(
                        'acpec_fueltoken_base.group_fuel_manager'
                    ).id,
                    self.env.ref(
                        'acpec_fueltoken_base.group_fuel_admin'
                    ).id,
                ]),
            ])
            self.assertEqual(len(rows), 3)
            self.assertTrue(all(rows.mapped('perm_read')))
            self.assertFalse(any(rows.mapped('perm_write')))
            self.assertFalse(any(rows.mapped('perm_create')))
            self.assertFalse(any(rows.mapped('perm_unlink')))

    def test_m23c6d_purchase_create_requires_sudo_and_exact_context(self):
        vals = self._purchase_vals()

        with self.assertRaises(UserError):
            self.Purchase.create(vals)

        with self.assertRaises(UserError):
            self.Purchase.with_context(
                allow_fuel_purchase_create=True,
            ).create(vals)

        with self.assertRaises(UserError):
            self.Purchase.with_user(
                self.non_sudo_user
            ).with_context(
                acpec_fueltoken_purchase_internal_operation='create',
            ).create(vals)

        with self.assertRaises(UserError):
            self.Purchase.sudo().with_context(
                acpec_fueltoken_purchase_internal_operation='wrong',
            ).create(vals)

        purchase = self.Purchase._create_internal(vals)
        self.assertTrue(purchase)
        self.assertTrue(purchase.env.su)

    def test_m23c6d_purchase_line_create_requires_sudo_and_exact_context(self):
        purchase = self._purchase()
        vals = self._line_vals(purchase)

        with self.assertRaises(UserError):
            self.PurchaseLine.create(vals)

        with self.assertRaises(UserError):
            self.PurchaseLine.with_context(
                allow_fuel_purchase_line_create=True,
            ).create(vals)

        with self.assertRaises(UserError):
            self.PurchaseLine.with_user(
                self.non_sudo_user
            ).with_context(
                acpec_fueltoken_purchase_line_internal_operation='create',
            ).create(vals)

        with self.assertRaises(UserError):
            self.PurchaseLine.sudo().with_context(
                acpec_fueltoken_purchase_line_internal_operation='wrong',
            ).create(vals)

        line = self.PurchaseLine._create_internal(vals)
        self.assertTrue(line)
        self.assertEqual(line.purchase_id, purchase)

    def test_m23c6d_purchase_write_operations_are_narrow(self):
        purchase = self._purchase()
        self._line(purchase)
        attachment = self._attachment(purchase)

        with self.assertRaises(UserError):
            purchase.write({
                'payment_reference': 'DIRECT',
            })

        with self.assertRaises(UserError):
            purchase.with_context(
                allow_fuel_purchase_update=True,
            ).write({
                'payment_reference': 'LEGACY',
            })

        with self.assertRaises(UserError):
            purchase.with_context(
                allow_fuel_purchase_workflow_update=True,
            ).write({
                'state': 'submitted',
            })

        with self.assertRaises(UserError):
            purchase.with_user(
                self.non_sudo_user
            ).with_context(
                acpec_fueltoken_purchase_internal_operation='proof_write',
            ).write({
                'proof_attachment_ids': [(4, attachment.id)],
            })

        with self.assertRaises(UserError):
            purchase._write_proof_internal({
                'proof_attachment_ids': [(4, attachment.id)],
                'payment_reference': 'EXTRA',
            })

        purchase._write_proof_internal({
            'proof_attachment_ids': [(4, attachment.id)],
        })
        purchase.action_submit()
        self.assertEqual(purchase.state, 'submitted')

        with self.assertRaises(UserError):
            purchase._write_proof_internal({
                'proof_attachment_ids': [(5, 0, 0)],
            })

        purchase.action_reject(
            reason='Preuve non conforme C6-D',
        )
        self.assertEqual(purchase.state, 'rejected')
        self.assertEqual(
            purchase.rejection_reason,
            'Preuve non conforme C6-D',
        )

    def test_m23c6d_approval_idempotency_is_narrow_and_one_shot(self):
        purchase = self._purchase()

        with self.assertRaises(UserError):
            purchase.write({
                'approval_idempotency_key': 'DIRECT',
                'approval_request_hash': 'DIRECT-HASH',
            })

        purchase._set_approval_idempotency(
            'M23C6D-APPROVE',
            'M23C6D-HASH',
        )
        purchase._set_approval_idempotency(
            'M23C6D-APPROVE',
            'M23C6D-HASH',
        )

        with self.assertRaises(ValidationError):
            purchase._set_approval_idempotency(
                'M23C6D-OTHER',
                'M23C6D-OTHER-HASH',
            )

        with self.assertRaises(UserError):
            purchase._write_approval_idempotency_internal({
                'approval_idempotency_key': 'MISSING-HASH',
            })

    def test_m23c6d_fuel_value_confirmation_is_true_only_and_approved_only(self):
        purchase = self._purchase()

        with self.assertRaises(UserError):
            purchase._write_fuel_value_internal({
                'fuel_value_created': True,
            })

        purchase._write_approval_internal({
            'state': 'approved',
            'approved_at': fields.Datetime.now(),
            'approved_by': self.env.user.id,
            'rejection_reason': False,
        })
        purchase._write_fuel_value_internal({
            'fuel_value_created': True,
        })
        self.assertTrue(purchase.fuel_value_created)

        with self.assertRaises(ValidationError):
            purchase._write_fuel_value_internal({
                'fuel_value_created': False,
            })

        with self.assertRaises(UserError):
            purchase._write_fuel_value_internal({
                'fuel_value_created': True,
                'payment_reference': 'EXTRA',
            })

    def test_m23c6d_purchase_line_snapshot_write_is_narrow(self):
        purchase = self._purchase()
        line = self._line(purchase)

        with self.assertRaises(UserError):
            line.write({
                'carnet_qty': 2,
            })

        with self.assertRaises(UserError):
            line.with_context(
                allow_fuel_purchase_line_update=True,
            ).write({
                'face_count': 11,
                'face_value': line.face_value,
            })

        with self.assertRaises(UserError):
            line.with_user(
                self.non_sudo_user
            ).with_context(
                acpec_fueltoken_purchase_line_internal_operation='snapshot_write',
            ).write({
                'face_count': 11,
                'face_value': line.face_value,
            })

        with self.assertRaises(UserError):
            line._write_snapshot_internal({
                'face_count': 11,
            })

        line._write_snapshot_internal({
            'face_count': 11,
            'face_value': line.face_value,
        })
        self.assertEqual(line.face_count, 11)

    def test_m23c6d_purchase_and_line_unlink_are_absolutely_forbidden(self):
        purchase = self._purchase()
        line = self._line(purchase)

        with self.assertRaises(UserError):
            purchase.with_context(
                allow_fuel_purchase_unlink=True,
            ).unlink()

        with self.assertRaises(UserError):
            line.with_context(
                allow_fuel_purchase_line_unlink=True,
            ).unlink()

        with self.assertRaises(UserError):
            purchase.sudo().with_context(
                acpec_fueltoken_purchase_internal_operation='purge',
            ).unlink()

        with self.assertRaises(UserError):
            line.sudo().with_context(
                acpec_fueltoken_purchase_line_internal_operation='purge',
            ).unlink()

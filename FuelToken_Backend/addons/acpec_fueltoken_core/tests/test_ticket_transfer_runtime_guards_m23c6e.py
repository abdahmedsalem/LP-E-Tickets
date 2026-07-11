# -*- coding: utf-8 -*-
import ast
import base64
import csv
import pathlib
import uuid

from odoo.exceptions import AccessError, UserError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestTicketTransferRuntimeGuardsM23C6E(TransactionCase):

    LEGACY_CONTEXTS = (
        'allow_fuel_ticket_transfer_create',
        'allow_fuel_ticket_transfer_update',
        'allow_fuel_ticket_transfer_unlink',
    )
    TRANSFER_OPERATION_CONTEXT = (
        'acpec_fueltoken_ticket_transfer_internal_operation'
    )
    TRANSFER_ACTOR_CONTEXT = (
        'acpec_fueltoken_ticket_transfer_internal_actor_user_id'
    )
    LINE_OPERATION_CONTEXT = (
        'acpec_fueltoken_ticket_transfer_line_internal_operation'
    )

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company
        cls.Transfer = cls.env['acpec.fuel.ticket.transfer']
        cls.TransferLine = cls.env['acpec.fuel.ticket.transfer.line']
        cls.Wallet = cls.env['acpec.fuel.wallet']
        cls.Purchase = cls.env['acpec.fuel.purchase']
        cls.FaceLine = cls.env['acpec.fuel.face.line']
        cls.non_sudo_user = cls.env.ref('base.user_admin')
        cls.other_actor = cls.env.ref('base.user_root')
        cls.carnet_type = cls._create_unique_carnet_type()

    @classmethod
    def _create_unique_carnet_type(cls):
        model = cls.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(971001, 971801):
            code = 'C%sT-%s' % (face_count, face_value)
            if not model.search([
                ('company_id', '=', cls.company.id),
                ('code', '=', code),
            ], limit=1):
                return model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': cls.company.id,
                })
        raise AssertionError(
            'Impossible de créer un type de carnet isolé pour M23-C6E.'
        )

    def _create_partner_wallet(self, label):
        partner = self.env['res.partner'].sudo().create({
            'name': 'M23C6E %s %s' % (label, uuid.uuid4().hex[:8]),
        })
        wallet = self.Wallet.get_or_create(partner, self.company)
        return partner, wallet

    def _create_source_face_line(self, source_partner):
        suffix = uuid.uuid4().hex[:8]
        purchase = self.Purchase._create_internal({
            'partner_id': source_partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-M23C6E-%s' % suffix,
        })
        self.env['acpec.fuel.purchase.line']._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-m23c6e.pdf',
            'datas': base64.b64encode(
                b'%PDF-1.4\npreuve M23-C6E\n'
            ).decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase._write_proof_internal({
            'proof_attachment_ids': [(4, attachment.id)],
        })
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()
        face_line = self.FaceLine.sudo().search([
            ('purchase_id', '=', purchase.id),
        ], limit=1)
        self.assertTrue(face_line)
        return face_line

    def _transfer_vals(self, with_line=True):
        source_partner, source_wallet = self._create_partner_wallet('source')
        _dest_partner, dest_wallet = self._create_partner_wallet('destination')
        face_line = self._create_source_face_line(source_partner)
        vals = {
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'M23C6E-%s' % uuid.uuid4().hex,
            'request_hash': 'M23C6E-HASH-%s' % uuid.uuid4().hex,
            'note': 'Transfert test M23-C6E',
        }
        if with_line:
            vals['line_ids'] = [(0, 0, {
                'source_face_line_id': face_line.id,
                'qty_faces': 1,
            })]
        return vals, face_line

    def _create_transfer(self, with_line=True):
        vals, face_line = self._transfer_vals(with_line=with_line)
        return self.Transfer._create_internal(vals), face_line

    def test_m23c6e_transfer_create_requires_sudo_and_exact_operation(self):
        vals, _face_line = self._transfer_vals()

        with self.assertRaises(AccessError):
            self.Transfer.create(vals)

        with self.assertRaises(AccessError):
            self.Transfer.sudo().with_context(
                **{self.LEGACY_CONTEXTS[0]: True}
            ).create(vals)

        with self.assertRaises(AccessError):
            self.Transfer.with_user(self.non_sudo_user).with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'create'}
            ).create(vals)

        with self.assertRaises(AccessError):
            self.Transfer.sudo().with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'confirmation_write'}
            ).create(vals)

        transfer = self.Transfer._create_internal(vals)
        self.assertEqual(transfer.state, 'draft')
        self.assertTrue(transfer.public_code)
        self.assertEqual(len(transfer.line_ids), 1)
        self.assertFalse(
            transfer.env.context.get(self.TRANSFER_OPERATION_CONTEXT)
        )
        self.assertFalse(
            transfer.env.context.get(self.LINE_OPERATION_CONTEXT)
        )

        invalid_vals, _face_line = self._transfer_vals()
        invalid_vals['state'] = 'confirmed'
        with self.assertRaises(AccessError):
            self.Transfer._create_internal(invalid_vals)

    def test_m23c6e_line_create_requires_sudo_and_exact_operation(self):
        transfer, face_line = self._create_transfer(with_line=False)
        vals = {
            'transfer_id': transfer.id,
            'source_face_line_id': face_line.id,
            'qty_faces': 1,
        }

        with self.assertRaises(AccessError):
            self.TransferLine.create(vals)

        with self.assertRaises(AccessError):
            self.TransferLine.sudo().with_context(
                **{self.LEGACY_CONTEXTS[0]: True}
            ).create(vals)

        with self.assertRaises(AccessError):
            self.TransferLine.with_user(self.non_sudo_user).with_context(
                **{self.LINE_OPERATION_CONTEXT: 'create'}
            ).create(vals)

        with self.assertRaises(AccessError):
            self.TransferLine.sudo().with_context(
                **{self.LINE_OPERATION_CONTEXT: 'destination_write'}
            ).create(vals)

        line = self.TransferLine._create_internal(vals)
        self.assertEqual(line.transfer_id, transfer)
        self.assertFalse(
            line.env.context.get(self.LINE_OPERATION_CONTEXT)
        )

        with self.assertRaises(AccessError):
            self.TransferLine._create_internal(dict(
                vals,
                dest_face_line_id=face_line.id,
            ))

    def test_m23c6e_transfer_write_operations_are_narrow(self):
        transfer, _face_line = self._create_transfer()

        with self.assertRaises(AccessError):
            transfer.write({'note': 'mutation directe'})

        with self.assertRaises(AccessError):
            transfer.sudo().with_context(
                **{self.LEGACY_CONTEXTS[1]: True}
            ).write({'state': 'cancelled'})

        with self.assertRaises(AccessError):
            transfer.with_user(self.non_sudo_user).with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'cancellation_write'}
            ).write({'state': 'cancelled'})

        with self.assertRaises(AccessError):
            transfer.sudo().with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'cancellation_write'}
            ).write({
                'state': 'cancelled',
                'note': 'champ supplémentaire',
            })

        with self.assertRaises(AccessError):
            transfer._write_cancellation_internal({'state': 'draft'})

    def test_m23c6e_line_destination_write_is_narrow_and_one_shot(self):
        transfer, face_line = self._create_transfer()
        line = transfer.line_ids

        with self.assertRaises(AccessError):
            line.write({'dest_face_line_id': face_line.id})

        with self.assertRaises(AccessError):
            line.sudo().with_context(
                **{self.LEGACY_CONTEXTS[1]: True}
            ).write({'dest_face_line_id': face_line.id})

        with self.assertRaises(AccessError):
            line.with_user(self.non_sudo_user).with_context(
                **{self.LINE_OPERATION_CONTEXT: 'destination_write'}
            ).write({'dest_face_line_id': face_line.id})

        with self.assertRaises(AccessError):
            line.sudo().with_context(
                **{self.LINE_OPERATION_CONTEXT: 'destination_write'}
            ).write({
                'dest_face_line_id': face_line.id,
                'qty_faces': 1,
            })

        line._write_destination_internal({
            'dest_face_line_id': face_line.id,
        })
        self.assertEqual(line.dest_face_line_id, face_line)

        with self.assertRaises(AccessError):
            line._write_destination_internal({
                'dest_face_line_id': face_line.id,
            })

    def test_m23c6e_confirmation_requires_internal_actor_binding(self):
        transfer, _face_line = self._create_transfer()

        with self.assertRaises(AccessError):
            transfer.action_confirm(actor_user=self.non_sudo_user)

        with self.assertRaises(AccessError):
            transfer.sudo().with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'confirm'}
            ).action_confirm(actor_user=self.non_sudo_user)

        with self.assertRaises(AccessError):
            transfer.sudo().with_context(**{
                self.TRANSFER_OPERATION_CONTEXT: 'confirm',
                self.TRANSFER_ACTOR_CONTEXT: self.other_actor.id,
            }).action_confirm(actor_user=self.non_sudo_user)

        transfer._confirm_internal(self.non_sudo_user)
        transfer.invalidate_recordset([
            'state',
            'confirmed_at',
            'confirmed_by',
        ])
        transfer.line_ids.invalidate_recordset(['dest_face_line_id'])
        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(transfer.confirmed_by, self.non_sudo_user)
        self.assertTrue(transfer.confirmed_at)
        self.assertTrue(transfer.line_ids.dest_face_line_id)

        self.assertTrue(
            transfer._confirm_internal(self.non_sudo_user)
        )

    def test_m23c6e_cancellation_requires_internal_actor_binding(self):
        transfer, _face_line = self._create_transfer()

        with self.assertRaises(AccessError):
            transfer.action_cancel(actor_user=self.non_sudo_user)

        with self.assertRaises(AccessError):
            transfer.sudo().with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'cancel'}
            ).action_cancel(actor_user=self.non_sudo_user)

        transfer._cancel_internal(self.non_sudo_user)
        transfer.invalidate_recordset(['state'])
        self.assertEqual(transfer.state, 'cancelled')
        self.assertTrue(
            transfer._cancel_internal(self.non_sudo_user)
        )

        confirmed, _face_line = self._create_transfer()
        confirmed._confirm_internal(self.non_sudo_user)
        with self.assertRaises(UserError):
            confirmed._cancel_internal(self.non_sudo_user)

    def test_m23c6e_transfer_and_line_unlink_are_absolutely_forbidden(self):
        transfer, _face_line = self._create_transfer()
        line = transfer.line_ids

        with self.assertRaises(UserError):
            line.unlink()
        with self.assertRaises(UserError):
            line.sudo().with_context(
                **{self.LEGACY_CONTEXTS[2]: True}
            ).unlink()
        with self.assertRaises(UserError):
            line.sudo().with_context(
                **{self.LINE_OPERATION_CONTEXT: 'purge'}
            ).unlink()

        with self.assertRaises(UserError):
            transfer.unlink()
        with self.assertRaises(UserError):
            transfer.sudo().with_context(
                **{self.LEGACY_CONTEXTS[2]: True}
            ).unlink()
        with self.assertRaises(UserError):
            transfer.sudo().with_context(
                **{self.TRANSFER_OPERATION_CONTEXT: 'purge'}
            ).unlink()

    def test_m23c6e_acl_and_runtime_callers_are_locked(self):
        addons_root = pathlib.Path(__file__).resolve().parents[2]
        acl_path = (
            addons_root
            / 'acpec_fueltoken_core'
            / 'security'
            / 'ir.model.access.csv'
        )
        with acl_path.open(
            'r',
            encoding='utf-8-sig',
            newline='',
        ) as stream:
            rows = list(csv.DictReader(stream))

        target_rows = [
            row
            for row in rows
            if row.get('model_id:id') in (
                'model_acpec_fuel_ticket_transfer',
                'model_acpec_fuel_ticket_transfer_line',
            )
        ]
        self.assertEqual(len(target_rows), 6)
        for row in target_rows:
            self.assertEqual(row.get('perm_read'), '1')
            self.assertEqual(row.get('perm_write'), '0')
            self.assertEqual(row.get('perm_create'), '0')
            self.assertEqual(row.get('perm_unlink'), '0')

        runtime_paths = (
            addons_root
            / 'acpec_fueltoken_core'
            / 'models'
            / 'fuel_ticket_transfer.py',
            addons_root
            / 'acpec_fueltoken_api'
            / 'controllers'
            / 'api_mobile.py',
            addons_root
            / 'acpec_fueltoken_api'
            / 'models'
            / 'fuel_mobile_audit.py',
            addons_root
            / 'acpec_fueltoken_company'
            / 'models'
            / 'fuel_distributor.py',
        )
        runtime_sources = {
            path: path.read_text(encoding='utf-8-sig')
            for path in runtime_paths
        }
        for source in runtime_sources.values():
            for legacy_context in self.LEGACY_CONTEXTS:
                self.assertNotIn(legacy_context, source)

        controller_source = runtime_sources[runtime_paths[1]]
        controller_tree = ast.parse(controller_source)
        transfer_methods = [
            node
            for node in ast.walk(controller_tree)
            if (
                isinstance(node, ast.FunctionDef)
                and node.name == 'transfer_tickets'
            )
        ]
        self.assertEqual(len(transfer_methods), 1)
        transfer_block = ast.get_source_segment(
            controller_source,
            transfer_methods[0],
        ) or ''
        self.assertIn('._create_internal({', transfer_block)
        self.assertEqual(
            transfer_block.count('._confirm_mobile_internal('),
            2,
        )

        audit_source = runtime_sources[runtime_paths[2]]
        self.assertIn('def _confirm_mobile_internal(', audit_source)
        self.assertIn('self._confirm_internal(actor_user)', audit_source)
        self.assertIn(
            'self._write_mobile_audit_internal({',
            audit_source,
        )

        distributor_source = runtime_sources[runtime_paths[3]]
        distributor_tree = ast.parse(distributor_source)
        distributor_methods = [
            node
            for node in ast.walk(distributor_tree)
            if (
                isinstance(node, ast.FunctionDef)
                and node.name == 'action_transfer_tickets_to_member'
            )
        ]
        self.assertEqual(len(distributor_methods), 1)
        distributor_block = ast.get_source_segment(
            distributor_source,
            distributor_methods[0],
        ) or ''
        self.assertIn(
            "self.env['acpec.fuel.ticket.transfer']._create_internal({",
            distributor_block,
        )
        self.assertEqual(
            distributor_block.count('._confirm_internal(operator_user)'),
            2,
        )

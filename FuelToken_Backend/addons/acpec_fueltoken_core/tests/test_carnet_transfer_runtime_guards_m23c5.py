# -*- coding: utf-8 -*-
import base64
import pathlib
import uuid

from lxml import etree

from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCarnetTransferRuntimeGuardsM23C5(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.company = cls.env.company
        cls.Transfer = cls.env['acpec.fuel.carnet.transfer']
        cls.TransferLine = cls.env['acpec.fuel.carnet.transfer.line']
        cls.Wallet = cls.env['acpec.fuel.wallet'].sudo()
        cls.Purchase = cls.env['acpec.fuel.purchase'].sudo()
        cls.FaceLine = cls.env['acpec.fuel.face.line'].sudo()

        Users = cls.env['res.users'].sudo().with_context(no_reset_password=True)
        group_user = cls.env.ref('base.group_user')
        group_admin = cls.env.ref('acpec_fueltoken_base.group_fuel_admin')

        cls.fuel_admin = Users.create({
            'name': 'Fuel Admin M23C5',
            'login': 'fuel-admin-m23c5@example.com',
            'email': 'fuel-admin-m23c5@example.com',
            'active': True,
            'company_id': cls.company.id,
            'company_ids': [(6, 0, [cls.company.id])],
            'group_ids': [(6, 0, [group_user.id, group_admin.id])],
        })
        cls.regular_user = Users.create({
            'name': 'Regular User M23C5',
            'login': 'regular-user-m23c5@example.com',
            'email': 'regular-user-m23c5@example.com',
            'active': True,
            'company_id': cls.company.id,
            'company_ids': [(6, 0, [cls.company.id])],
            'group_ids': [(6, 0, [group_user.id])],
        })

    def _create_partner_wallet(self, label):
        partner = self.env['res.partner'].sudo().create({
            'name': 'M23C5 %s %s' % (label, uuid.uuid4().hex[:8]),
        })
        return partner, self.Wallet.get_or_create(partner, self.company)

    def _create_unique_carnet_type(self):
        model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(913001, 913601):
            code = 'C%sT-%s' % (face_count, face_value)
            if not model.search([
                ('company_id', '=', self.company.id),
                ('code', '=', code),
            ], limit=1):
                return model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })
        self.fail('Impossible de créer un type de carnet isolé pour M23C5.')

    def _create_source_face_line(self, source_partner):
        carnet_type = self._create_unique_carnet_type()
        suffix = uuid.uuid4().hex[:8]
        purchase = self.Purchase.with_context(
            allow_fuel_purchase_create=True,
            allow_fuel_purchase_line_create=True,
        ).create({
            'partner_id': source_partner.id,
            'company_id': self.company.id,
            'payment_reference': 'PAY-M23C5-%s' % suffix,
        })
        self.env['acpec.fuel.purchase.line'].sudo().with_context(
            allow_fuel_purchase_line_create=True,
        ).create({
            'purchase_id': purchase.id,
            'carnet_type_id': carnet_type.id,
            'carnet_qty': 1,
        })
        attachment = self.env['ir.attachment'].sudo().create({
            'name': 'preuve-m23c5-%s.pdf' % suffix,
            'datas': base64.b64encode(
                b'%PDF-1.4\npreuve transfert M23C5\n'
            ).decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.sudo().with_context(
            allow_fuel_purchase_update=True,
        ).write({'proof_attachment_ids': [(4, attachment.id)]})
        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()
        face_line = self.FaceLine.search([
            ('purchase_id', '=', purchase.id),
        ], limit=1)
        self.assertTrue(face_line)
        return face_line

    def _draft_vals(self, source_wallet, dest_wallet, face_line=False):
        vals = {
            'source_wallet_id': source_wallet.id,
            'dest_wallet_id': dest_wallet.id,
            'company_id': self.company.id,
            'idempotency_key': 'M23C5-%s' % uuid.uuid4().hex,
        }
        if face_line:
            vals['line_ids'] = [(0, 0, {
                'face_line_id': face_line.id,
                'carnet_qty': 1,
            })]
        return vals

    def _create_draft(self, with_line=False):
        source_partner, source_wallet = self._create_partner_wallet('Source')
        _dest_partner, dest_wallet = self._create_partner_wallet('Destination')
        face_line = False
        if with_line:
            face_line = self._create_source_face_line(source_partner)
            self.assertEqual(face_line.wallet_id, source_wallet)
        transfer = self.Transfer._create_internal(
            self._draft_vals(source_wallet, dest_wallet, face_line=face_line)
        )
        return transfer, face_line, source_wallet, dest_wallet

    def test_m23c5_acl_parent_and_lines_are_read_only(self):
        for model_name in (
            'acpec.fuel.carnet.transfer',
            'acpec.fuel.carnet.transfer.line',
        ):
            for group_xmlid in (
                'acpec_fueltoken_base.group_fuel_user',
                'acpec_fueltoken_base.group_fuel_manager',
                'acpec_fueltoken_base.group_fuel_admin',
            ):
                group = self.env.ref(group_xmlid)
                access = self.env['ir.model.access'].sudo().search([
                    ('model_id.model', '=', model_name),
                    ('group_id', '=', group.id),
                ], limit=1)
                self.assertTrue(access)
                self.assertTrue(access.perm_read)
                self.assertFalse(access.perm_create)
                self.assertFalse(access.perm_write)
                self.assertFalse(access.perm_unlink)

    def test_m23c5_parent_create_requires_sudo_and_exact_context(self):
        _source_partner, source_wallet = self._create_partner_wallet('Create Source')
        _dest_partner, dest_wallet = self._create_partner_wallet('Create Destination')
        vals = self._draft_vals(source_wallet, dest_wallet)

        with self.assertRaises(AccessError):
            self.Transfer.sudo().create(vals)
        with self.assertRaises(AccessError):
            self.Transfer.with_user(self.regular_user).with_context(
                acpec_fuel_carnet_transfer_internal_create=True,
            ).create(vals)

        transfer = self.Transfer._create_internal(vals)
        self.assertTrue(transfer)
        for key in (
            'acpec_fuel_carnet_transfer_internal_create',
            'acpec_fuel_carnet_transfer_internal_write',
            'acpec_fuel_carnet_transfer_internal_purge',
            'acpec_fuel_carnet_transfer_internal_confirm',
            'acpec_fuel_carnet_transfer_internal_cancel',
            'acpec_fuel_carnet_transfer_action_actor_user_id',
            'acpec_fuel_carnet_transfer_line_internal_create',
            'acpec_fuel_carnet_transfer_line_internal_write',
            'acpec_fuel_carnet_transfer_line_internal_purge',
        ):
            self.assertFalse(transfer.env.context.get(key))

    def test_m23c5_parent_write_and_draft_purge_are_controlled(self):
        transfer, _face_line, _source_wallet, _dest_wallet = self._create_draft()
        transfer_id = transfer.id

        with self.assertRaises(AccessError):
            transfer.sudo().write({'note': 'direct denied'})
        transfer._write_internal({'note': 'internal allowed'})
        transfer.invalidate_recordset(['note'])
        self.assertEqual(transfer.note, 'internal allowed')

        with self.assertRaises(AccessError):
            transfer.sudo().unlink()
        transfer._purge_internal()
        self.assertFalse(self.Transfer.sudo().browse(transfer_id).exists())

    def test_m23c5_line_create_write_and_purge_are_controlled(self):
        transfer, face_line, _source_wallet, _dest_wallet = self._create_draft(
            with_line=True
        )
        original_line = transfer.line_ids
        original_line._purge_internal()

        vals = {
            'transfer_id': transfer.id,
            'face_line_id': face_line.id,
            'carnet_qty': 1,
        }
        with self.assertRaises(AccessError):
            self.TransferLine.sudo().create(vals)

        line = self.TransferLine._create_internal(vals)
        with self.assertRaises(AccessError):
            line.sudo().write({'dest_face_line_id': face_line.id})
        line._write_internal({'dest_face_line_id': face_line.id})
        line.invalidate_recordset(['dest_face_line_id'])
        self.assertEqual(line.dest_face_line_id, face_line)

        line_id = line.id
        with self.assertRaises(AccessError):
            line.sudo().unlink()
        line._purge_internal()
        self.assertFalse(self.TransferLine.sudo().browse(line_id).exists())

    def test_m23c5_backoffice_cancel_requires_fuel_admin(self):
        transfer, _face_line, _source_wallet, _dest_wallet = self._create_draft()
        with self.assertRaises(AccessError):
            transfer.with_user(self.regular_user).action_cancel()
        with self.assertRaises(AccessError):
            transfer.sudo().action_cancel(actor_user=self.regular_user)

        transfer.with_user(self.fuel_admin).action_cancel()
        transfer.invalidate_recordset(['state'])
        self.assertEqual(transfer.state, 'cancelled')
        transfer._purge_internal()

    def test_m23c5_internal_confirm_preserves_actor_and_is_append_only(self):
        transfer, face_line, _source_wallet, dest_wallet = self._create_draft(
            with_line=True
        )
        transfer._confirm_internal(self.regular_user)
        transfer.invalidate_recordset(['state', 'confirmed_by'])
        face_line.invalidate_recordset(['wallet_id'])
        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(transfer.confirmed_by, self.regular_user)
        self.assertEqual(face_line.wallet_id, dest_wallet)
        self.assertEqual(transfer.line_ids.dest_face_line_id, face_line)

        with self.assertRaises(AccessError):
            transfer._write_internal({'note': 'confirmed mutation denied'})
        with self.assertRaises(AccessError):
            transfer._purge_internal()
        with self.assertRaises(AccessError):
            transfer.line_ids._write_internal({'carnet_qty': 1})
        with self.assertRaises(AccessError):
            transfer.line_ids._purge_internal()

    def test_m23c5_bo_admin_confirm_works_with_readonly_acl(self):
        transfer, face_line, _source_wallet, dest_wallet = self._create_draft(
            with_line=True
        )
        transfer.with_user(self.fuel_admin).action_confirm()
        transfer.invalidate_recordset(['state', 'confirmed_by'])
        face_line.invalidate_recordset(['wallet_id'])
        self.assertEqual(transfer.state, 'confirmed')
        self.assertEqual(transfer.confirmed_by, self.fuel_admin)
        self.assertEqual(face_line.wallet_id, dest_wallet)

    def test_m23c5_views_are_read_only_and_actions_are_admin_only(self):
        list_view = self.env.ref(
            'acpec_fueltoken_core.view_fuel_carnet_transfer_list'
        )
        list_root = etree.fromstring(list_view.arch_db.encode('utf-8'))
        self.assertEqual(list_root.tag, 'list')
        self.assertEqual(list_root.get('create'), '0')
        self.assertEqual(list_root.get('edit'), '0')
        self.assertEqual(list_root.get('delete'), '0')

        form_view = self.env.ref(
            'acpec_fueltoken_core.view_fuel_carnet_transfer_form'
        )
        form_root = etree.fromstring(form_view.arch_db.encode('utf-8'))
        self.assertEqual(form_root.tag, 'form')
        self.assertEqual(form_root.get('create'), '0')
        self.assertEqual(form_root.get('edit'), '0')
        self.assertEqual(form_root.get('delete'), '0')
        buttons = form_root.xpath("//button[@name='action_confirm' or @name='action_cancel']")
        self.assertEqual(len(buttons), 2)
        for button in buttons:
            self.assertEqual(
                button.get('groups'),
                'acpec_fueltoken_base.group_fuel_admin',
            )

    def test_m23c5_runtime_callers_use_private_helpers(self):
        addons_dir = pathlib.Path(__file__).resolve().parents[2]

        api_controller = (
            addons_dir / 'acpec_fueltoken_api' / 'controllers' / 'api_mobile.py'
        ).read_text(encoding='utf-8')
        carnet_start = api_controller.index('    def transfer_carnets(self, **kwargs):')
        carnet_end = api_controller.index(
            "    @http.route(\n        '/api/acpec/fueltoken/v1/mobile/carnets/transfers'",
            carnet_start,
        )
        carnet_block = api_controller[carnet_start:carnet_end]
        self.assertIn("._create_internal({", carnet_block)
        self.assertIn('._confirm_mobile_internal(', carnet_block)
        self.assertNotIn(".sudo().create({", carnet_block)
        self.assertNotIn('.action_confirm_mobile(', carnet_block)

        audit_model = (
            addons_dir / 'acpec_fueltoken_api' / 'models' / 'fuel_mobile_audit.py'
        ).read_text(encoding='utf-8')
        audit_block = audit_model[
            audit_model.index('class AcpecFuelCarnetTransfer'):
            audit_model.index('class AcpecFuelTicketTransfer')
        ]
        self.assertIn('def _confirm_mobile_internal(', audit_block)
        self.assertIn('self._confirm_internal(actor_user)', audit_block)
        self.assertIn('self._write_internal({', audit_block)
        self.assertNotIn('self.sudo().write({', audit_block)

        distributor_model = (
            addons_dir / 'acpec_fueltoken_company' / 'models' / 'fuel_distributor.py'
        ).read_text(encoding='utf-8')
        distribution_block = distributor_model[
            distributor_model.index('    def action_distribute_to_member('):
            distributor_model.index('    def _prepare_ticket_transfer_line_vals(')
        ]
        self.assertIn('._create_internal(transfer_vals)', distribution_block)
        self.assertIn('._confirm_internal(operator_user)', distribution_block)
        self.assertNotIn(".sudo().create(transfer_vals)", distribution_block)
        self.assertNotIn('.action_confirm(actor_user=operator_user)', distribution_block)

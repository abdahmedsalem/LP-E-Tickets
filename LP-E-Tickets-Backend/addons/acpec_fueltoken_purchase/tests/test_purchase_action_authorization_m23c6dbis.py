# -*- coding: utf-8 -*-
import base64
import uuid

from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestPurchaseActionAuthorizationM23C6DBis(
    TransactionCase
):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Purchase = self.env[
            'acpec.fuel.purchase'
        ]
        self.PurchaseLine = self.env[
            'acpec.fuel.purchase.line'
        ]
        self.partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'C6D-bis Client %s'
            % uuid.uuid4().hex[:8],
            'company_id': self.company.id,
        })
        self.carnet_type = (
            self._create_unique_carnet_type()
        )
        self.client_user = self._create_user(
            'client',
            'acpec_fueltoken_base.group_fuel_user',
        )
        self.manager_user = self._create_user(
            'manager',
            'acpec_fueltoken_base.group_fuel_manager',
        )
        self.admin_user = self._create_user(
            'admin',
            'acpec_fueltoken_base.group_fuel_admin',
        )

    def _create_user(self, label, group_xmlid):
        suffix = uuid.uuid4().hex[:8]
        group_ids = [
            self.env.ref('base.group_user').id,
            self.env.ref(group_xmlid).id,
        ]
        return self.env[
            'res.users'
        ].sudo().with_context(
            no_reset_password=True,
        ).create({
            'name': 'C6D-bis %s %s'
            % (label, suffix),
            'login': 'c6dbis-%s-%s@example.com'
            % (label, suffix),
            'email': 'c6dbis-%s-%s@example.com'
            % (label, suffix),
            'active': True,
            'company_id': self.company.id,
            'company_ids': [
                (6, 0, [self.company.id]),
            ],
            'group_ids': [(6, 0, group_ids)],
        })

    def _create_unique_carnet_type(self):
        model = self.env[
            'acpec.fuel.carnet.type'
        ].sudo()

        for face_value in range(
            995001,
            995501,
        ):
            code = 'C10T-%s' % face_value
            existing = model.search([
                ('company_id', '=', self.company.id),
                ('code', '=', code),
            ], limit=1)

            if not existing:
                return model.create({
                    'face_count': 10,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': self.company.id,
                })

        self.fail(
            'Impossible de créer un type de carnet C6D-bis.'
        )

    def _ready_purchase(self, suffix):
        purchase = self.Purchase._create_internal({
            'partner_id': self.partner.id,
            'company_id': self.company.id,
            'payment_reference': (
                'PAY-C6DBIS-%s' % suffix
            ),
        })
        self.PurchaseLine._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })

        attachment = self.env[
            'ir.attachment'
        ].sudo().create({
            'name': 'preuve-c6dbis-%s.pdf'
            % suffix,
            'datas': base64.b64encode(
                b'%PDF-1.4\npreuve C6D-bis\n'
            ).decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })

        purchase._write_proof_internal({
            'proof_attachment_ids': [
                (4, attachment.id),
            ],
        })
        purchase.action_submit()
        return purchase

    def test_public_approve_and_reject_require_admin(
        self,
    ):
        client_purchase = self._ready_purchase(
            'CLIENT'
        )
        with self.assertRaises(AccessError):
            client_purchase.with_user(
                self.client_user
            ).action_approve()

        manager_purchase = self._ready_purchase(
            'MANAGER'
        )
        with self.assertRaises(AccessError):
            manager_purchase.with_user(
                self.manager_user
            ).action_approve()

        with self.assertRaises(AccessError):
            manager_purchase.with_user(
                self.manager_user
            ).action_reject(
                reason='Rejet direct manager interdit',
            )

    def test_admin_public_actions_record_real_actor(
        self,
    ):
        approved_purchase = self._ready_purchase(
            'ADMIN-APPROVE'
        )
        approved_purchase.with_user(
            self.admin_user
        ).action_approve()

        self.assertEqual(
            approved_purchase.state,
            'approved',
        )
        self.assertEqual(
            approved_purchase.approved_by,
            self.admin_user,
        )

        rejected_purchase = self._ready_purchase(
            'ADMIN-REJECT'
        )
        rejected_purchase.with_user(
            self.admin_user
        ).action_reject(
            reason='Rejet administratif C6D-bis',
        )

        self.assertEqual(
            rejected_purchase.state,
            'rejected',
        )
        self.assertEqual(
            rejected_purchase.rejected_by,
            self.admin_user,
        )

    def test_superuser_public_action_remains_allowed(
        self,
    ):
        purchase = self._ready_purchase(
            'SUPERUSER'
        )
        purchase.action_approve()

        self.assertEqual(
            purchase.state,
            'approved',
        )
        self.assertEqual(
            purchase.approved_by.id,
            self.env.uid,
        )

    def test_manager_internal_approval_is_actor_bound(
        self,
    ):
        purchase = self._ready_purchase(
            'INTERNAL-MANAGER'
        )
        purchase._approve_internal(
            self.manager_user
        )

        self.assertEqual(
            purchase.state,
            'approved',
        )
        self.assertEqual(
            purchase.approved_by,
            self.manager_user,
        )

        invalid_purchase = self._ready_purchase(
            'INVALID-CONTEXT'
        )

        with self.assertRaises(AccessError):
            invalid_purchase.sudo().action_approve(
                actor_user=self.manager_user,
            )

        with self.assertRaises(AccessError):
            invalid_purchase.sudo().with_context(
                acpec_fueltoken_purchase_action_operation=(
                    'approve'
                ),
                acpec_fueltoken_purchase_action_actor_user_id=(
                    self.manager_user.id
                ),
            ).action_approve(
                actor_user=self.admin_user,
            )

    def test_internal_helpers_validate_actor_role(
        self,
    ):
        purchase = self._ready_purchase(
            'INVALID-ACTOR'
        )

        with self.assertRaises(AccessError):
            purchase._approve_internal(
                self.client_user
            )

        with self.assertRaises(AccessError):
            purchase._reject_internal(
                self.manager_user,
                reason='Rejet manager interdit',
            )

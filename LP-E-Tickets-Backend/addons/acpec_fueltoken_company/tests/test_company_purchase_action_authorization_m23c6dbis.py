# -*- coding: utf-8 -*-
import uuid

from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCompanyPurchaseActionAuthorizationM23C6DBis(
    TransactionCase
):

    def setUp(self):
        super().setUp()
        self.company = self.env.company
        self.Distributor = self.env[
            'acpec.fuel.distributor'
        ]
        self.Purchase = self.env[
            'acpec.fuel.purchase'
        ]
        self.distributor = self._create_distributor()
        self.client_user = self._create_internal_user(
            'client',
            'acpec_fueltoken_base.group_fuel_user',
        )
        self.manager_user = self._create_internal_user(
            'manager',
            'acpec_fueltoken_base.group_fuel_manager',
        )
        self.admin_user = self._create_internal_user(
            'admin',
            'acpec_fueltoken_base.group_fuel_admin',
        )

    def _create_internal_user(
        self,
        label,
        group_xmlid,
    ):
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
            'name': 'Company C6D-bis %s %s'
            % (label, suffix),
            'login': 'company-c6dbis-%s-%s@example.com'
            % (label, suffix),
            'email': 'company-c6dbis-%s-%s@example.com'
            % (label, suffix),
            'active': True,
            'company_id': self.company.id,
            'company_ids': [
                (6, 0, [self.company.id]),
            ],
            'group_ids': [(6, 0, group_ids)],
        })

    def _create_distributor(self):
        suffix = uuid.uuid4().hex[:8]

        partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Société C6D-bis %s'
            % suffix,
            'is_company': True,
            'company_id': self.company.id,
        })

        portal_group = self.env.ref(
            'base.group_portal'
        )

        self.env[
            'res.users'
        ].sudo().with_context(
            no_reset_password=True,
        ).create({
            'name': 'Portail C6D-bis %s'
            % suffix,
            'login': 'portal-c6dbis-%s@example.com'
            % suffix,
            'email': 'portal-c6dbis-%s@example.com'
            % suffix,
            'partner_id': partner.id,
            'active': True,
            'company_id': self.company.id,
            'company_ids': [
                (6, 0, [self.company.id]),
            ],
            'group_ids': [
                (6, 0, [portal_group.id]),
            ],
        })

        return self.Distributor.sudo().create({
            'name': 'Compte Société C6D-bis %s'
            % suffix,
            'code': 'C6DBIS-%s'
            % suffix.upper(),
            'partner_id': partner.id,
            'company_id': self.company.id,
            'active': True,
            'state': 'active',
        })

    def test_company_purchase_action_rejects_client(
        self,
    ):
        with self.assertRaises(AccessError):
            self.distributor.with_user(
                self.client_user
            ).action_create_company_purchase()

    def test_company_purchase_action_allows_manager(
        self,
    ):
        action = self.distributor.with_user(
            self.manager_user
        ).action_create_company_purchase()

        purchase = self.Purchase.sudo().browse(
            action.get('res_id')
        ).exists()

        self.assertTrue(purchase)
        self.assertEqual(
            purchase.state,
            'draft',
        )
        self.assertEqual(
            purchase.partner_id,
            self.distributor.partner_id,
        )
        self.assertEqual(
            purchase.company_id,
            self.company,
        )

    def test_company_purchase_action_allows_admin(
        self,
    ):
        action = self.distributor.with_user(
            self.admin_user
        ).action_create_company_purchase()

        purchase = self.Purchase.sudo().browse(
            action.get('res_id')
        ).exists()

        self.assertTrue(purchase)
        self.assertEqual(
            purchase.partner_id,
            self.distributor.partner_id,
        )

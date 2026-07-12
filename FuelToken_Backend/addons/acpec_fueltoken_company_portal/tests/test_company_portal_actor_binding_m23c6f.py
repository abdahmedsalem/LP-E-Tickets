# -*- coding: utf-8 -*-
import base64
import uuid

from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCompanyPortalActorBindingM23C6F(
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
        self.PurchaseLine = self.env[
            'acpec.fuel.purchase.line'
        ]
        self.FaceLine = self.env[
            'acpec.fuel.face.line'
        ]

        self.distributor_partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Société M23C6F %s'
            % uuid.uuid4().hex[:8],
            'is_company': True,
            'company_id': self.company.id,
        })

        self.exact_portal_user = self._create_portal_user(
            self.distributor_partner,
            'exact',
        )

        self.member_partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Membre M23C6F %s'
            % uuid.uuid4().hex[:8],
            'is_company': False,
            'company_id': self.company.id,
        })

        self.member_mobile_user = (
            self._create_mobile_user(
                self.member_partner,
                'member',
            )
        )

        self.distributor = self.Distributor.sudo().create({
            'name': 'Compte Société M23C6F %s'
            % uuid.uuid4().hex[:8],
            'code': 'M23C6F-%s'
            % uuid.uuid4().hex[:8].upper(),
            'partner_id': self.distributor_partner.id,
            'company_id': self.company.id,
            'active': True,
            'state': 'active',
            'member_partner_ids': [
                (6, 0, [self.member_partner.id]),
            ],
        })

        self.child_partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Contact enfant M23C6F %s'
            % uuid.uuid4().hex[:8],
            'parent_id': self.distributor_partner.id,
            'is_company': False,
            'company_id': self.company.id,
        })

        self.child_portal_user = self._create_portal_user(
            self.child_partner,
            'child',
        )

        self.other_company_partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Autre société M23C6F %s'
            % uuid.uuid4().hex[:8],
            'is_company': True,
            'company_id': self.company.id,
        })

        self.other_portal_user = self._create_portal_user(
            self.other_company_partner,
            'other',
        )

        self.manager_user = self._create_internal_user(
            'manager',
            'acpec_fueltoken_base.group_fuel_manager',
        )

        self.carnet_type = self._create_unique_carnet_type()

    def _create_portal_user(
        self,
        partner,
        label,
    ):
        suffix = uuid.uuid4().hex[:8]
        portal_group = self.env.ref(
            'base.group_portal'
        )

        return self.env[
            'res.users'
        ].sudo().with_context(
            no_reset_password=True,
        ).create({
            'name': 'Portail M23C6F %s %s'
            % (label, suffix),
            'login': 'portal-m23c6f-%s-%s@example.com'
            % (label, suffix),
            'email': 'portal-m23c6f-%s-%s@example.com'
            % (label, suffix),
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
            'name': 'Interne M23C6F %s %s'
            % (label, suffix),
            'login': 'internal-m23c6f-%s-%s@example.com'
            % (label, suffix),
            'email': 'internal-m23c6f-%s-%s@example.com'
            % (label, suffix),
            'active': True,
            'company_id': self.company.id,
            'company_ids': [
                (6, 0, [self.company.id]),
            ],
            'group_ids': [
                (6, 0, group_ids),
            ],
        })

    def _create_mobile_user(
        self,
        partner,
        label,
    ):
        suffix = uuid.uuid4().hex[:8]

        group_ids = [
            self.env.ref('base.group_user').id,
            self.env.ref(
                'acpec_fueltoken_base.group_fuel_user'
            ).id,
        ]

        return self.env[
            'res.users'
        ].sudo().with_context(
            no_reset_password=True,
            acpec_fueltoken_allow_mobile_identity_initialization=True,
        ).create({
            'name': 'Mobile M23C6F %s %s'
            % (label, suffix),
            'login': 'mobile-m23c6f-%s-%s@example.com'
            % (label, suffix),
            'email': 'mobile-m23c6f-%s-%s@example.com'
            % (label, suffix),
            'partner_id': partner.id,
            'active': True,
            'company_id': self.company.id,
            'company_ids': [
                (6, 0, [self.company.id]),
            ],
            'group_ids': [
                (6, 0, group_ids),
            ],
            'acpec_mobile_state': 'approved',
        })

    def _create_unique_carnet_type(self):
        model = self.env[
            'acpec.fuel.carnet.type'
        ].sudo()

        face_count = 10

        for face_value in range(
            983001,
            983801,
        ):
            code = 'C%sT-%s' % (
                face_count,
                face_value,
            )

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

        self.fail(
            'Impossible de créer un type de carnet '
            'isolé pour M23C6F.'
        )

    def _create_source_face_line(
        self,
        source_partner=None,
    ):
        source_partner = (
            source_partner
            or self.distributor_partner
        )
        suffix = uuid.uuid4().hex[:8]

        purchase = self.Purchase.sudo()._create_internal({
            'partner_id': source_partner.id,
            'company_id': self.company.id,
            'payment_reference': (
                'PAY-M23C6F-%s' % suffix
            ),
        })

        self.PurchaseLine.sudo()._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': self.carnet_type.id,
            'carnet_qty': 1,
        })

        attachment = self.env[
            'ir.attachment'
        ].sudo().create({
            'name': 'preuve-m23c6f-%s.pdf'
            % suffix,
            'datas': base64.b64encode(
                b'%PDF-1.4\npreuve M23C6F\n'
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
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = self.FaceLine.sudo().search([
            ('purchase_id', '=', purchase.id),
        ], limit=1)

        self.assertTrue(face_line)

        return face_line

    def _distribute_carnet(
        self,
        actor_user,
        face_line=None,
        distributor=None,
    ):
        distributor = (
            distributor
            or self.distributor
        )
        face_line = (
            face_line
            or self._create_source_face_line()
        )

        return distributor.sudo().action_distribute_to_member(
            self.member_partner,
            [{
                'face_line_id': face_line.id,
                'carnet_qty': 1,
            }],
            idempotency_key=(
                'M23C6F-CARNET-%s'
                % uuid.uuid4().hex
            ),
            confirm=True,
            operator_user=actor_user,
        )

    def _transfer_ticket(
        self,
        actor_user,
        face_line=None,
    ):
        face_line = (
            face_line
            or self._create_source_face_line()
        )

        return self.distributor.sudo(
        ).action_transfer_tickets_to_member(
            self.member_partner,
            [{
                'face_line_id': face_line.id,
                'qty_tickets': 1,
            }],
            idempotency_key=(
                'M23C6F-TICKET-%s'
                % uuid.uuid4().hex
            ),
            confirm=True,
            operator_user=actor_user,
        )

    def test_exact_partner_portal_can_distribute_and_is_audited(
        self,
    ):
        transfer = self._distribute_carnet(
            self.exact_portal_user
        )

        transfer.invalidate_recordset([
            'state',
            'confirmed_by',
        ])

        self.assertEqual(
            transfer.state,
            'confirmed',
        )
        self.assertEqual(
            transfer.confirmed_by.id,
            self.exact_portal_user.id,
        )

    def test_exact_partner_portal_can_transfer_tickets_and_is_audited(
        self,
    ):
        transfer = self._transfer_ticket(
            self.exact_portal_user
        )

        transfer.invalidate_recordset([
            'state',
            'confirmed_by',
        ])

        self.assertEqual(
            transfer.state,
            'confirmed',
        )
        self.assertEqual(
            transfer.confirmed_by.id,
            self.exact_portal_user.id,
        )

    def test_child_contact_keeps_commercial_visibility_but_cannot_distribute(
        self,
    ):
        visible = self.Distributor.with_user(
            self.child_portal_user
        ).search([
            ('id', '=', self.distributor.id),
        ])

        self.assertEqual(
            visible.ids,
            [self.distributor.id],
        )

        with self.assertRaises(AccessError):
            self._distribute_carnet(
                self.child_portal_user
            )

    def test_other_company_portal_cannot_act_for_distributor(
        self,
    ):
        visible = self.Distributor.with_user(
            self.other_portal_user
        ).search([
            ('id', '=', self.distributor.id),
        ])

        self.assertFalse(visible)

        with self.assertRaises(AccessError):
            self._transfer_ticket(
                self.other_portal_user
            )

    def test_mobile_client_cannot_act_as_company_representative(
        self,
    ):
        with self.assertRaises(AccessError):
            self._distribute_carnet(
                self.member_mobile_user
            )

    def test_sudo_call_without_explicit_actor_is_denied(
        self,
    ):
        face_line = self._create_source_face_line()

        with self.assertRaises(AccessError):
            self.distributor.sudo(
            ).action_distribute_to_member(
                self.member_partner,
                [{
                    'face_line_id': face_line.id,
                    'carnet_qty': 1,
                }],
                idempotency_key=(
                    'M23C6F-NO-ACTOR-%s'
                    % uuid.uuid4().hex
                ),
                confirm=True,
            )

    def test_manager_backoffice_operator_is_allowed_and_audited(
        self,
    ):
        face_line = self._create_source_face_line()

        transfer = self.distributor.with_user(
            self.manager_user
        ).action_distribute_to_member(
            self.member_partner,
            [{
                'face_line_id': face_line.id,
                'carnet_qty': 1,
            }],
            idempotency_key=(
                'M23C6F-BO-%s'
                % uuid.uuid4().hex
            ),
            confirm=True,
            operator_user=self.manager_user,
        )

        transfer.invalidate_recordset([
            'state',
            'confirmed_by',
        ])

        self.assertEqual(
            transfer.state,
            'confirmed',
        )
        self.assertEqual(
            transfer.confirmed_by.id,
            self.manager_user.id,
        )

    def test_member_outside_distributor_is_denied(
        self,
    ):
        outsider = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Membre externe M23C6F %s'
            % uuid.uuid4().hex[:8],
            'is_company': False,
            'company_id': self.company.id,
        })

        self._create_mobile_user(
            outsider,
            'outsider',
        )

        face_line = self._create_source_face_line()

        with self.assertRaises(ValidationError):
            self.distributor.sudo(
            ).action_distribute_to_member(
                outsider,
                [{
                    'face_line_id': face_line.id,
                    'carnet_qty': 1,
                }],
                confirm=True,
                operator_user=self.exact_portal_user,
            )

    def test_source_carnet_from_another_wallet_is_denied(
        self,
    ):
        outsider_partner = self.env[
            'res.partner'
        ].sudo().create({
            'name': 'Wallet externe M23C6F %s'
            % uuid.uuid4().hex[:8],
            'is_company': False,
            'company_id': self.company.id,
        })

        outsider_face_line = (
            self._create_source_face_line(
                source_partner=outsider_partner,
            )
        )

        with self.assertRaises(ValidationError):
            self._distribute_carnet(
                self.exact_portal_user,
                face_line=outsider_face_line,
            )

    def test_exact_partner_rule_is_not_replaced_by_commercial_partner_rule(
        self,
    ):
        self.assertEqual(
            self.child_portal_user.partner_id.commercial_partner_id,
            self.distributor.partner_id,
        )
        self.assertNotEqual(
            self.child_portal_user.partner_id,
            self.distributor.partner_id,
        )

        with self.assertRaises(AccessError):
            self._transfer_ticket(
                self.child_portal_user
            )

    def test_non_sudo_caller_cannot_spoof_operator_user(
        self,
    ):
        face_line = self._create_source_face_line()

        with self.assertRaises(AccessError):
            self.distributor.with_user(
                self.child_portal_user
            ).action_distribute_to_member(
                self.member_partner,
                [{
                    'face_line_id': face_line.id,
                    'carnet_qty': 1,
                }],
                idempotency_key=(
                    'M23C6F-SPOOF-%s'
                    % uuid.uuid4().hex
                ),
                confirm=True,
                operator_user=self.exact_portal_user,
            )

# -*- coding: utf-8 -*-
import uuid

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged

from .qr_action_test_utils import create_mobile_test_user


@tagged("post_install", "-at_install")
class TestQrActionAuthorizationM23C6CBis(TransactionCase):

    QR_QTY = 4

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.company = cls.env.company
        cls.Qr = cls.env['acpec.fuel.qr']
        cls.FaceLine = cls.env['acpec.fuel.face.line']
        suffix = uuid.uuid4().hex[:8]

        cls.partner_a = cls.env[
            'res.partner'
        ].sudo().create({
            'name': 'C6CBIS Client A %s' % suffix,
        })
        cls.client_a = create_mobile_test_user(
            cls.env,
            cls.company,
            'C6CBIS Client A %s' % suffix,
            role='client',
            partner=cls.partner_a,
        )
        cls.wallet_a = cls.env[
            'acpec.fuel.wallet'
        ].get_or_create(
            cls.partner_a,
            cls.company,
        )

        cls.partner_b = cls.env[
            'res.partner'
        ].sudo().create({
            'name': 'C6CBIS Client B %s' % suffix,
        })
        cls.client_b = create_mobile_test_user(
            cls.env,
            cls.company,
            'C6CBIS Client B %s' % suffix,
            role='client',
            partner=cls.partner_b,
        )
        cls.wallet_b = cls.env[
            'acpec.fuel.wallet'
        ].get_or_create(
            cls.partner_b,
            cls.company,
        )

        cls.face_line_a = cls._create_stock(
            cls.wallet_a,
            suffix,
            0,
        )
        cls.face_line_b = cls._create_stock(
            cls.wallet_b,
            suffix,
            1,
        )

        cls.station_user = create_mobile_test_user(
            cls.env,
            cls.company,
            'C6CBIS Station B %s' % suffix,
            role='station',
        )
        cls.station = cls.env[
            'acpec.fuel.station'
        ].sudo().create({
            'name': 'C6CBIS Station B %s' % suffix,
            'user_id': cls.station_user.id,
            'company_id': cls.company.id,
        })

        cls.other_station_user = create_mobile_test_user(
            cls.env,
            cls.company,
            'C6CBIS Station C %s' % suffix,
            role='station',
        )
        cls.other_station = cls.env[
            'acpec.fuel.station'
        ].sudo().create({
            'name': 'C6CBIS Station C %s' % suffix,
            'user_id': cls.other_station_user.id,
            'company_id': cls.company.id,
        })

        cls.manager_user = create_mobile_test_user(
            cls.env,
            cls.company,
            'C6CBIS Manager %s' % suffix,
            role='manager',
        )

    @classmethod
    def _create_stock(
        cls,
        wallet,
        suffix,
        offset,
    ):
        carnet_model = cls.env[
            'acpec.fuel.carnet.type'
        ].sudo()

        carnet_type = False

        for face_value in range(
            965000 + (offset * 500),
            965500 + (offset * 500),
        ):
            code = 'C20T-%s' % face_value
            if not carnet_model.search([
                ('company_id', '=', cls.company.id),
                ('code', '=', code),
            ], limit=1):
                carnet_type = carnet_model.create({
                    'face_count': 20,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': cls.company.id,
                })
                break

        if not carnet_type:
            raise AssertionError(
                "Aucun type de carnet libre pour C6C-bis."
            )

        purchase = cls.env[
            'acpec.fuel.purchase'
        ]._create_internal({
            'partner_id': wallet.partner_id.id,
            'company_id': cls.company.id,
            'payment_reference': (
                'C6CBIS-%s-%s'
                % (
                    suffix,
                    offset,
                )
            ),
        })

        purchase_line = cls.env[
            'acpec.fuel.purchase.line'
        ]._create_internal({
            'purchase_id': purchase.id,
            'carnet_type_id': carnet_type.id,
            'carnet_qty': 1,
        })

        return cls.env[
            'acpec.fuel.face.line'
        ]._create_internal({
            'wallet_id': wallet.id,
            'purchase_id': purchase.id,
            'purchase_line_id': purchase_line.id,
            'carnet_type_id': carnet_type.id,
            'face_value': carnet_type.face_value,
            'qty_initial': 20,
            'qty_available': 20,
            'expires_at': fields.Datetime.add(
                fields.Datetime.now(),
                days=365,
            ),
        })

    def _issue(
        self,
        actor,
        wallet,
        face_line,
        suffix,
    ):
        return self.Qr._issue_from_available_internal(
            actor,
            wallet,
            [{
                'face_line_id': face_line.id,
                'qty': self.QR_QTY,
            }],
            idempotency_key=(
                'C6CBIS-ISSUE-%s-%s'
                % (
                    suffix,
                    uuid.uuid4().hex,
                )
            ),
            request_hash=(
                'C6CBIS-ISSUE-HASH-%s'
                % suffix
            ),
        )

    def test_public_economic_methods_reject_direct_calls(self):
        request_lines = [{
            'face_line_id': self.face_line_a.id,
            'qty': self.QR_QTY,
        }]

        with self.assertRaises(AccessError):
            self.Qr.with_user(
                self.client_a
            ).issue_from_available(
                self.wallet_a,
                request_lines,
                actor_user=self.client_a,
            )

        with self.assertRaises(AccessError):
            self.Qr.sudo().issue_from_available(
                self.wallet_a,
                request_lines,
                actor_user=self.client_a,
            )

        qr = self._issue(
            self.client_a,
            self.wallet_a,
            self.face_line_a,
            'DIRECT',
        )

        with self.assertRaises(AccessError):
            qr.with_user(
                self.station_user
            ).action_consume_by_station(
                self.station,
                user=self.station_user,
            )

        with self.assertRaises(AccessError):
            qr.sudo().action_consume_by_station(
                self.station,
                user=self.station_user,
            )

        with self.assertRaises(AccessError):
            qr.sudo().action_retirer_to_child(
                [{
                    'qr_line_id': qr.line_ids[0].id,
                    'qty': 1,
                }],
                actor_user=self.client_a,
            )

        with self.assertRaises(AccessError):
            qr.sudo().action_separer_valid_to_child(
                actor_user=self.client_a,
            )

    def test_issue_requires_exact_context_and_own_wallet(self):
        request_lines = [{
            'face_line_id': self.face_line_a.id,
            'qty': self.QR_QTY,
        }]

        with self.assertRaises(AccessError):
            self.Qr.sudo().with_context(
                acpec_fueltoken_qr_action_operation='consume',
                acpec_fueltoken_qr_action_actor_user_id=(
                    self.client_a.id
                ),
            ).issue_from_available(
                self.wallet_a,
                request_lines,
                actor_user=self.client_a,
            )

        with self.assertRaises(AccessError):
            self.Qr.sudo().with_context(
                acpec_fueltoken_qr_action_operation='issue',
                acpec_fueltoken_qr_action_actor_user_id=(
                    self.client_b.id
                ),
            ).issue_from_available(
                self.wallet_a,
                request_lines,
                actor_user=self.client_a,
            )

        with self.assertRaises(AccessError):
            self.Qr._issue_from_available_internal(
                self.client_a,
                self.wallet_b,
                [{
                    'face_line_id': self.face_line_b.id,
                    'qty': self.QR_QTY,
                }],
            )

        qr = self._issue(
            self.client_a,
            self.wallet_a,
            self.face_line_a,
            'OWN-WALLET',
        )
        self.assertEqual(
            qr.wallet_id,
            self.wallet_a,
        )

    def test_client_cannot_mutate_another_clients_qr(self):
        qr = self._issue(
            self.client_b,
            self.wallet_b,
            self.face_line_b,
            'FOREIGN-CLIENT',
        )

        with self.assertRaises(AccessError):
            qr._retirer_to_child_internal(
                self.client_a,
                [{
                    'qr_line_id': qr.line_ids[0].id,
                    'qty': 1,
                }],
            )

        with self.assertRaises(AccessError):
            qr._separer_valid_to_child_internal(
                self.client_a,
            )

        self.assertEqual(
            qr.wallet_id,
            self.wallet_b,
        )
        self.assertEqual(
            qr.state,
            'active',
        )

    def test_station_agent_consumes_other_users_qr(self):
        qr = self._issue(
            self.client_a,
            self.wallet_a,
            self.face_line_a,
            'BEARER-POSITIVE',
        )

        self.assertNotEqual(
            self.station_user.partner_id,
            self.partner_a,
        )
        self.assertEqual(
            qr.wallet_id.partner_id,
            self.partner_a,
        )

        tx = qr._consume_by_station_internal(
            self.station_user,
            self.station,
            idempotency_key=(
                'C6CBIS-CONSUME-%s'
                % uuid.uuid4().hex
            ),
            request_hash='C6CBIS-CONSUME-HASH',
        )

        qr.invalidate_recordset([
            'state',
            'consumed_station_id',
            'consumed_user_id',
            'consumed_partner_id',
        ])

        self.assertTrue(tx)
        self.assertEqual(
            qr.state,
            'consumed',
        )
        self.assertEqual(
            qr.consumed_station_id,
            self.station,
        )
        self.assertEqual(
            qr.consumed_user_id,
            self.station_user,
        )
        self.assertEqual(
            qr.consumed_partner_id,
            self.station_user.partner_id,
        )
        self.assertEqual(
            qr.wallet_id.partner_id,
            self.partner_a,
        )
        self.assertEqual(
            tx.wallet_id,
            self.wallet_a,
        )
        self.assertEqual(
            tx.station_id,
            self.station,
        )

    def test_station_must_use_its_own_assigned_station(self):
        qr = self._issue(
            self.client_a,
            self.wallet_a,
            self.face_line_a,
            'WRONG-STATION',
        )

        with self.assertRaises(AccessError):
            qr._consume_by_station_internal(
                self.station_user,
                self.other_station,
            )

        self.assertEqual(
            qr.state,
            'active',
        )

    def test_manager_cannot_be_used_as_client_or_station_actor(self):
        with self.assertRaises(AccessError):
            self.Qr._issue_from_available_internal(
                self.manager_user,
                self.wallet_a,
                [{
                    'face_line_id': self.face_line_a.id,
                    'qty': self.QR_QTY,
                }],
            )

        qr = self._issue(
            self.client_a,
            self.wallet_a,
            self.face_line_a,
            'MANAGER-NEGATIVE',
        )

        with self.assertRaises(AccessError):
            qr._consume_by_station_internal(
                self.manager_user,
                self.station,
            )

        self.assertEqual(
            qr.state,
            'active',
        )

    def test_technical_methods_are_private_only(self):
        for model, public_name, private_name in (
            (
                self.Qr,
                'resolve_qr_reference',
                '_resolve_qr_reference_internal',
            ),
            (
                self.Qr,
                'action_refresh_expiration_state',
                '_refresh_expiration_state_internal',
            ),
            (
                self.FaceLine,
                'reserve_available',
                '_reserve_available_internal',
            ),
            (
                self.FaceLine,
                'move_available_to_expired',
                '_move_available_to_expired_internal',
            ),
        ):
            self.assertFalse(
                hasattr(
                    model,
                    public_name,
                )
            )
            self.assertTrue(
                hasattr(
                    model,
                    private_name,
                )
            )

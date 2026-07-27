import xml.etree.ElementTree as ET

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestBusinessIdentityViewsReadonlyM23A(
    TransactionCase
):

    def _root(self, xmlid):
        view = self.env.ref(xmlid)
        return ET.fromstring(view.arch_db or '')

    def _assert_locked_root(
        self,
        xmlid,
        expected_tag,
    ):
        root = self._root(xmlid)

        self.assertEqual(
            root.tag,
            expected_tag,
            xmlid,
        )

        for attribute in (
            'create',
            'edit',
            'delete',
        ):
            self.assertIn(
                root.get(attribute),
                ('0', 'false'),
                '%s must lock %s'
                % (xmlid, attribute),
            )

        return root

    def _assert_fields_readonly(
        self,
        root,
        xmlid,
        field_names,
    ):
        for field_name in field_names:
            fields = root.findall(
                ".//field[@name='%s']"
                % field_name
            )

            self.assertTrue(
                fields,
                '%s missing field %s'
                % (xmlid, field_name),
            )

            self.assertTrue(
                any(
                    field.get('readonly')
                    in ('1', 'true')
                    for field in fields
                ),
                '%s.%s must be readonly'
                % (xmlid, field_name),
            )

    def _assert_nested_list_locked(
        self,
        root,
        xmlid,
        field_name,
    ):
        fields = root.findall(
            ".//field[@name='%s']"
            % field_name
        )

        self.assertEqual(
            len(fields),
            1,
            '%s.%s must be unique'
            % (xmlid, field_name),
        )

        relation = fields[0]

        self.assertIn(
            relation.get('readonly'),
            ('1', 'true'),
            '%s.%s must be readonly'
            % (xmlid, field_name),
        )

        nested_list = relation.find('list')

        self.assertIsNotNone(
            nested_list,
            '%s.%s missing nested list'
            % (xmlid, field_name),
        )

        for attribute in (
            'create',
            'edit',
            'delete',
        ):
            self.assertIn(
                nested_list.get(attribute),
                ('0', 'false'),
                '%s.%s list must lock %s'
                % (
                    xmlid,
                    field_name,
                    attribute,
                ),
            )

    def test_m23a_core_business_view_roots_are_locked(
        self,
    ):
        for xmlid, expected_tag in (
            (
                'acpec_fueltoken_core.'
                'view_fuel_transaction_list',
                'list',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_transaction_form',
                'form',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_qr_list',
                'list',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_qr_form',
                'form',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_wallet_list',
                'list',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_wallet_form',
                'form',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_face_line_list',
                'list',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_carnet_transfer_list',
                'list',
            ),
            (
                'acpec_fueltoken_core.'
                'view_fuel_carnet_transfer_form',
                'form',
            ),
        ):
            self._assert_locked_root(
                xmlid,
                expected_tag,
            )

    def test_m23a_transaction_identity_is_readonly(
        self,
    ):
        xmlid = (
            'acpec_fueltoken_core.'
            'view_fuel_transaction_form'
        )
        root = self._assert_locked_root(
            xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            xmlid,
            (
                'name',
                'operation_ref',
                'transaction_type',
                'wallet_id',
                'purchase_id',
                'qr_id',
                'parent_qr_id',
                'station_id',
                'regularization_state',
                'regularization_reference',
                'regularization_date',
                'regularized_by_id',
                'qty_total',
                'amount_total',
                'company_id',
                'idempotency_key',
                'line_ids',
                'note',
            ),
        )

        self._assert_nested_list_locked(
            root,
            xmlid,
            'line_ids',
        )

        self.assertNotIn(
            'force_save=',
            self.env.ref(xmlid).arch_db or '',
        )

    def test_m23a_qr_identity_is_readonly(
        self,
    ):
        xmlid = (
            'acpec_fueltoken_core.'
            'view_fuel_qr_form'
        )
        root = self._assert_locked_root(
            xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            xmlid,
            (
                'name',
                'wallet_id',
                'state',
                'amount_total',
                'face_qty_total',
                'expires_at',
                'parent_id',
                'line_ids',
                'child_ids',
            ),
        )

        self._assert_nested_list_locked(
            root,
            xmlid,
            'line_ids',
        )
        self._assert_nested_list_locked(
            root,
            xmlid,
            'child_ids',
        )

    def test_m23a_wallet_identity_is_readonly(
        self,
    ):
        xmlid = (
            'acpec_fueltoken_core.'
            'view_fuel_wallet_form'
        )
        root = self._assert_locked_root(
            xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            xmlid,
            (
                'partner_id',
                'company_id',
                'balance',
                'qty_available',
                'amount_qr_active',
                'amount_qr_blocked',
                'face_line_ids',
            ),
        )

        self._assert_nested_list_locked(
            root,
            xmlid,
            'face_line_ids',
        )

    def test_m23a_carnet_transfer_is_readonly(
        self,
    ):
        xmlid = (
            'acpec_fueltoken_core.'
            'view_fuel_carnet_transfer_form'
        )
        root = self._assert_locked_root(
            xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            xmlid,
            (
                'name',
                'state',
                'source_wallet_id',
                'dest_wallet_id',
                'company_id',
                'face_qty_total',
                'amount_total',
                'confirmed_at',
                'confirmed_by',
                'line_ids',
                'note',
            ),
        )

        self._assert_nested_list_locked(
            root,
            xmlid,
            'line_ids',
        )

        for button_name in (
            'action_confirm',
            'action_cancel',
        ):
            self.assertIsNotNone(
                root.find(
                    ".//button[@name='%s']"
                    % button_name
                ),
                button_name,
            )

        self.assertNotIn(
            'force_save=',
            self.env.ref(xmlid).arch_db or '',
        )

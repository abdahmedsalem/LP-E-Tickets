import xml.etree.ElementTree as ET

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestBusinessIdentityViewsReadonlyM23A(
    TransactionCase
):

    def _root(self, xmlid):
        return ET.fromstring(
            self.env.ref(xmlid).arch_db or ''
        )

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

    def test_m23a_carnet_form_is_readonly(
        self,
    ):
        xmlid = (
            'acpec_fueltoken_backoffice_ui.'
            'view_backoffice_fuel_face_line_'
            'form_ticket_labels'
        )
        root = self._assert_locked_root(
            xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            xmlid,
            (
                'wallet_id',
                'partner_id',
                'purchase_id',
                'purchase_line_id',
                'carnet_no',
                'carnet_short_code',
                'lot_short_code',
                'carnet_sequence',
                'carnet_type_id',
                'face_value',
                'qty_initial',
                'qty_available',
                'qty_qr_active',
                'qty_qr_blocked',
                'qty_consumed',
                'qty_expired',
                'expires_at',
                'company_id',
                'currency_id',
            ),
        )

        self.assertNotIn(
            'force_save=',
            self.env.ref(xmlid).arch_db or '',
        )

    def test_m23a_ticket_transfer_remains_readonly(
        self,
    ):
        list_xmlid = (
            'acpec_fueltoken_backoffice_ui.'
            'view_backoffice_fuel_ticket_transfer_list'
        )
        form_xmlid = (
            'acpec_fueltoken_backoffice_ui.'
            'view_backoffice_fuel_ticket_transfer_form'
        )

        self._assert_locked_root(
            list_xmlid,
            'list',
        )
        root = self._assert_locked_root(
            form_xmlid,
            'form',
        )

        self._assert_fields_readonly(
            root,
            form_xmlid,
            (
                'name',
                'state',
                'source_wallet_id',
                'source_partner_id',
                'dest_wallet_id',
                'dest_partner_id',
                'face_qty_total',
                'amount_total',
                'confirmed_at',
                'confirmed_by',
                'company_id',
                'line_ids',
                'note',
            ),
        )

        line_ids = root.find(
            ".//field[@name='line_ids']"
        )
        self.assertIsNotNone(line_ids)

        nested_list = line_ids.find('list')
        self.assertIsNotNone(nested_list)

        for attribute in (
            'create',
            'edit',
            'delete',
        ):
            self.assertIn(
                nested_list.get(attribute),
                ('0', 'false'),
            )

        self.assertNotIn(
            'force_save=',
            self.env.ref(form_xmlid).arch_db or '',
        )

import xml.etree.ElementTree as ET

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestMobileIdentityViewsReadonlyM23B(TransactionCase):

    def _combined_root(self, xmlid, model_name):
        view = self.env.ref(xmlid)
        result = self.env[model_name].get_view(
            view_id=view.id,
            view_type='form',
        )
        return ET.fromstring(result.get('arch') or '')

    def _assert_readonly_expression(
        self,
        nodes,
        expected_count,
        expression,
        label,
    ):
        self.assertEqual(
            len(nodes),
            expected_count,
            '%s: nombre de champs inattendu' % label,
        )

        for node in nodes:
            self.assertEqual(
                node.get('readonly'),
                expression,
                '%s doit être readonly selon %s'
                % (label, expression),
            )

    def _assert_hidden_flag(
        self,
        root,
        path,
        flag_name,
    ):
        nodes = root.findall(path)

        self._assert_readonly_expression(
            nodes,
            1,
            flag_name,
            flag_name,
        )

        self.assertIn(
            nodes[0].get('invisible'),
            ('1', 'true'),
            '%s doit rester invisible' % flag_name,
        )

    def test_m23b_partner_main_form_identity_is_conditionally_readonly(
        self,
    ):
        root = self._combined_root(
            'base.view_partner_form',
            'res.partner',
        )

        self._assert_hidden_flag(
            root,
            "./sheet/field[@name='acpec_is_mobile_partner']",
            'acpec_is_mobile_partner',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div[@class='mb8']/div/div/h1/"
                "field[@name='name']"
            ),
            2,
            'acpec_is_mobile_partner',
            'base.view_partner_form.name',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/notebook/page[@name='sales_purchases']/"
                "group/group[@name='misc']/field[@name='ref']"
            ),
            1,
            'acpec_is_mobile_partner',
            'base.view_partner_form.ref',
        )

    def test_m23b_partner_simple_form_identity_is_conditionally_readonly(
        self,
    ):
        root = self._combined_root(
            'base.view_partner_simple_form',
            'res.partner',
        )

        self._assert_hidden_flag(
            root,
            "./field[@name='acpec_is_mobile_partner']",
            'acpec_is_mobile_partner',
        )

        self._assert_readonly_expression(
            root.findall(
                "./div[@class='oe_title']/h1/field[@name='name']"
            ),
            2,
            'acpec_is_mobile_partner',
            'base.view_partner_simple_form.name',
        )

    def test_m23b_user_main_form_identity_is_conditionally_readonly(
        self,
    ):
        root = self._combined_root(
            'base.view_users_form',
            'res.users',
        )

        self._assert_hidden_flag(
            root,
            "./sheet/field[@name='acpec_mobile_only']",
            'acpec_mobile_only',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div/div/h1/field[@name='name']"
            ),
            1,
            'acpec_mobile_only',
            'base.view_users_form.name',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div/div/h5/div/field[@name='login']"
            ),
            1,
            'acpec_mobile_only',
            'base.view_users_form.login',
        )

    def test_m23b_user_simple_form_identity_is_conditionally_readonly(
        self,
    ):
        root = self._combined_root(
            'base.view_users_simple_form',
            'res.users',
        )

        self._assert_hidden_flag(
            root,
            "./sheet/field[@name='acpec_mobile_only']",
            'acpec_mobile_only',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div/div/h1/field[@name='name']"
            ),
            1,
            'acpec_mobile_only',
            'base.view_users_simple_form.name',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div/div/div/field[@name='login']"
            ),
            1,
            'acpec_mobile_only',
            'base.view_users_simple_form.login',
        )

    def test_m23b_user_preferences_name_is_conditionally_readonly(
        self,
    ):
        root = self._combined_root(
            'base.view_users_form_simple_modif',
            'res.users',
        )

        self._assert_hidden_flag(
            root,
            "./sheet/field[@name='acpec_mobile_only']",
            'acpec_mobile_only',
        )

        self._assert_readonly_expression(
            root.findall(
                "./sheet/div/div/h1/field[@name='name']"
            ),
            1,
            'acpec_mobile_only',
            'base.view_users_form_simple_modif.name',
        )

    def test_m23b_extension_views_use_safe_class_xpaths(self):
        for xmlid in (
            'acpec_fueltoken_mobile_security.'
            'view_partner_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_partner_simple_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_simple_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_preferences_form_mobile_identity_readonly_m23b',
        ):
            self.assertNotIn(
                '@class',
                self.env.ref(xmlid).arch_db or '',
                '%s doit utiliser hasclass() dans ses XPath'
                % xmlid,
            )

    def test_m23b_extension_views_do_not_use_force_save(self):
        for xmlid in (
            'acpec_fueltoken_mobile_security.'
            'view_partner_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_partner_simple_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_simple_form_mobile_identity_readonly_m23b',
            'acpec_fueltoken_mobile_security.'
            'view_users_preferences_form_mobile_identity_readonly_m23b',
        ):
            self.assertNotIn(
                'force_save=',
                self.env.ref(xmlid).arch_db or '',
                xmlid,
            )

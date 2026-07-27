import re
from pathlib import Path

from odoo.tests.common import TransactionCase


class TestReferenceApiArchiveDeleteDoctrineM21F(TransactionCase):

    def _api_admin_source(self):
        here = Path(__file__).resolve()
        addon_root = here.parents[1]
        api_admin = addon_root / 'controllers' / 'api_admin.py'
        self.assertTrue(api_admin.exists(), 'api_admin.py must exist')
        return api_admin.read_text(encoding='utf-8')

    def _method_block(self, source, method_name):
        marker = '    def %s(' % method_name
        start = source.find(marker)
        self.assertNotEqual(start, -1, 'Missing api_admin method %s' % method_name)

        next_route = source.find('\n    @http.route', start + len(marker))
        if next_route == -1:
            return source[start:]
        return source[start:next_route]

    def test_m21f_reference_mobile_admin_endpoints_remain_backoffice_only(self):
        source = self._api_admin_source()
        methods = (
            'carnet_type_create',
            'carnet_type_update',
            'carnet_type_delete',
            'station_create',
            'station_update',
            'station_disable',
        )

        for method_name in methods:
            block = self._method_block(source, method_name)
            self.assertIn(
                '_raise_mobile_manager_backoffice_only()',
                block,
                '%s must remain reserved to back-office administration' % method_name,
            )

    def test_m21f_reference_mobile_admin_endpoints_do_not_unlink(self):
        source = self._api_admin_source()
        methods = (
            'carnet_type_create',
            'carnet_type_update',
            'carnet_type_delete',
            'station_create',
            'station_update',
            'station_disable',
        )

        for method_name in methods:
            block = self._method_block(source, method_name)
            self.assertNotRegex(
                block,
                re.compile(r'\.unlink\s*\('),
                '%s must not physically delete reference records' % method_name,
            )

    def test_m21f_reference_acl_keep_bo_write_but_no_unlink(self):
        expectations = (
            ('acpec.fuel.carnet.type', 'acpec_fueltoken_base.group_fuel_admin', True, True, True, False),
            ('acpec.fuel.station', 'acpec_fueltoken_base.group_fuel_manager', True, True, True, False),
            ('acpec.fuel.station', 'acpec_fueltoken_base.group_fuel_admin', True, True, True, False),
            ('acpec.fuel.distributor', 'acpec_fueltoken_base.group_fuel_manager', True, True, True, False),
            ('acpec.fuel.distributor', 'acpec_fueltoken_base.group_fuel_admin', True, True, True, False),
        )

        Access = self.env['ir.model.access'].sudo()
        for model_name, group_xmlid, can_read, can_write, can_create, can_unlink in expectations:
            group = self.env.ref(group_xmlid)
            access = Access.search([
                ('model_id.model', '=', model_name),
                ('group_id', '=', group.id),
            ], limit=1)
            self.assertTrue(access, 'Missing ACL for %s / %s' % (model_name, group_xmlid))
            self.assertEqual(access.perm_read, can_read, 'Unexpected read ACL for %s / %s' % (model_name, group_xmlid))
            self.assertEqual(access.perm_write, can_write, 'Unexpected write ACL for %s / %s' % (model_name, group_xmlid))
            self.assertEqual(access.perm_create, can_create, 'Unexpected create ACL for %s / %s' % (model_name, group_xmlid))
            self.assertEqual(access.perm_unlink, can_unlink, 'Unexpected unlink ACL for %s / %s' % (model_name, group_xmlid))

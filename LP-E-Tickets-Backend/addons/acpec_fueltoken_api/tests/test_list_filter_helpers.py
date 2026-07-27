from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_common import AcpecFuelTokenApiCommon


@tagged('-at_install', 'post_install')
class TestAcpecFuelApiListFilterHelpers(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = AcpecFuelTokenApiCommon()
        self.controller._test_env = self.env

    def test_pagination_params_are_bounded(self):
        limit, offset = self.controller._pagination_params(
            {'limit': 999, 'offset': -5},
            default_limit=20,
            max_limit=100,
        )

        self.assertEqual(limit, 100)
        self.assertEqual(offset, 0)

    def test_pagination_meta_keeps_legacy_shape_by_default(self):
        page = self.controller._pagination_meta_legacy(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_next_offset=False,
        )

        self.assertEqual(page['count'], 73)
        self.assertEqual(page['limit'], 20)
        self.assertEqual(page['offset'], 0)
        self.assertTrue(page['has_more'])
        self.assertNotIn('next_offset', page)

    def test_pagination_meta_exposes_next_offset_when_opted_in(self):
        first_page = self.controller._pagination_meta_legacy(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_next_offset=True,
        )
        self.assertTrue(first_page['has_more'])
        self.assertEqual(first_page['next_offset'], 20)

        last_page = self.controller._pagination_meta_legacy(
            total=73,
            limit=20,
            offset=60,
            page_size=13,
            include_next_offset=True,
        )
        self.assertFalse(last_page['has_more'])
        self.assertIsNone(last_page['next_offset'])

    def test_count_only_meta_can_opt_into_full_pagination(self):
        legacy = self.controller._pagination_meta_count_only(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_full_meta=False,
        )
        self.assertEqual(legacy, {'count': 73})

        full = self.controller._pagination_meta_count_only(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_full_meta=True,
        )
        self.assertEqual(full['next_offset'], 20)

    def test_items_only_meta_can_opt_into_full_pagination(self):
        legacy = self.controller._pagination_meta_opt_in(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_full_meta=False,
        )
        self.assertEqual(legacy, {})

        full = self.controller._pagination_meta_opt_in(
            total=73,
            limit=20,
            offset=0,
            page_size=20,
            include_full_meta=True,
        )
        self.assertEqual(full['next_offset'], 20)

    def test_date_range_rejects_inverted_period(self):
        with self.assertRaises(ValidationError):
            self.controller._date_range_params({
                'date_from': '2026-06-15 00:00:00',
                'date_to': '2026-06-14 00:00:00',
            })

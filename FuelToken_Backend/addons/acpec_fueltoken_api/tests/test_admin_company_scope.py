from odoo.exceptions import AccessError, ValidationError
from odoo.tests import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers.api_admin import AcpecFuelTokenAdminApi


@tagged('-at_install', 'post_install')
class TestAcpecFuelAdminCompanyScope(TransactionCase):

    def setUp(self):
        super().setUp()
        self.controller = AcpecFuelTokenAdminApi()
        self.controller._test_env = self.env
        self.company_a = self.env.company
        self.company_b = self.env['res.company'].sudo().create({
            'name': 'FuelToken Scope Other Company',
        })
        self.manager = self._create_user('ft-manager-scope', self.company_a, self.company_a)

    def _create_user(self, login_prefix, company, companies):
        login = '%s-%s@example.com' % (login_prefix, self.env.cr.dbname)
        return self.env['res.users'].sudo().with_context(no_reset_password=True).create({
            'name': login_prefix,
            'login': login,
            'company_id': company.id,
            'company_ids': [(6, 0, companies.ids)],
        })

    def _create_carnet_type(self, company):
        carnet_model = self.env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(930001, 930101):
            code = 'C%sT-%s' % (face_count, face_value)
            if not carnet_model.search([('company_id', '=', company.id), ('code', '=', code)], limit=1):
                return carnet_model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': company.id,
                })
        self.fail('Impossible de créer un type de carnet isolé pour le test.')

    def test_require_allowed_company_accepts_user_company(self):
        company = self.controller._require_allowed_company(self.manager, self.company_a.id)

        self.assertEqual(company, self.company_a)

    def test_require_allowed_company_rejects_foreign_company(self):
        with self.assertRaises(AccessError):
            self.controller._require_allowed_company(self.manager, self.company_b.id)

    def test_company_domain_is_restricted_to_user_companies(self):
        self.assertEqual(
            self.controller._company_domain_for_user(self.manager),
            [('company_id', 'in', [self.company_a.id])],
        )

    def test_record_company_scope_rejects_foreign_record(self):
        foreign_carnet = self._create_carnet_type(self.company_b)

        with self.assertRaises(AccessError):
            self.controller._check_record_company_allowed(self.manager, foreign_carnet)

    def test_station_user_must_belong_to_target_company(self):
        foreign_user = self._create_user('ft-station-foreign-scope', self.company_b, self.company_b)

        with self.assertRaises(ValidationError):
            self.controller._require_user_company_membership(foreign_user, self.company_a)

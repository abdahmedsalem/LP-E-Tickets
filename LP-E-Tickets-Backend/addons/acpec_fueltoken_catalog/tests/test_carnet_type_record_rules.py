from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCarnetTypeRecordRules(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Company = cls.env['res.company'].sudo()
        cls.Users = cls.env['res.users'].sudo().with_context(no_reset_password=True)
        cls.CarnetType = cls.env['acpec.fuel.carnet.type'].sudo()

        cls.company_a = cls.Company.create({'name': 'Patch27B Company A'})
        cls.company_b = cls.Company.create({'name': 'Patch27B Company B'})

        cls.portal_group = cls.env.ref('base.group_portal')
        cls.fuel_user_group = cls.env.ref('acpec_fueltoken_base.group_fuel_user')
        cls.fuel_manager_group = cls.env.ref('acpec_fueltoken_base.group_fuel_manager')
        cls.fuel_admin_group = cls.env.ref('acpec_fueltoken_base.group_fuel_admin')

        cls.type_a = cls.CarnetType.create({
            'face_count': 10,
            'face_value': 100,
            'company_id': cls.company_a.id,
        })
        cls.type_b = cls.CarnetType.create({
            'face_count': 20,
            'face_value': 200,
            'company_id': cls.company_b.id,
        })

    def _make_user(self, login, groups):
        partner = self.env['res.partner'].sudo().create({
            'name': login,
            'company_id': self.company_a.id,
        })
        return self.Users.create({
            'name': login,
            'login': login,
            'partner_id': partner.id,
            'company_id': self.company_a.id,
            'company_ids': [(6, 0, [self.company_a.id])],
            'group_ids': [(6, 0, [group.id for group in groups])],
        })

    def _visible_carnet_type_ids(self, user):
        return set(
            self.env['acpec.fuel.carnet.type']
            .with_user(user)
            .search([])
            .ids
        )

    def test_fuel_user_with_portal_baseline_sees_only_own_company_types(self):
        user = self._make_user(
            'patch27b_user@example.test',
            [self.portal_group, self.fuel_user_group],
        )

        visible_ids = self._visible_carnet_type_ids(user)

        self.assertIn(self.type_a.id, visible_ids)
        self.assertNotIn(self.type_b.id, visible_ids)

    def test_fuel_manager_sees_only_allowed_company_types(self):
        user = self._make_user(
            'patch27b_manager@example.test',
            [self.portal_group, self.fuel_manager_group],
        )

        visible_ids = self._visible_carnet_type_ids(user)

        self.assertIn(self.type_a.id, visible_ids)
        self.assertNotIn(self.type_b.id, visible_ids)

    def test_fuel_admin_sees_only_allowed_company_types(self):
        user = self._make_user(
            'patch27b_admin@example.test',
            [self.portal_group, self.fuel_admin_group],
        )

        visible_ids = self._visible_carnet_type_ids(user)

        self.assertIn(self.type_a.id, visible_ids)
        self.assertNotIn(self.type_b.id, visible_ids)

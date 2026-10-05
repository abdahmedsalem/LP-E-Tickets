from odoo.tests import TransactionCase


def enable_test_fueltoken_company(env):
    """Prepare the real single-company prerequisite inside the test transaction."""
    company = env.company.sudo()
    enabled = env['res.company'].sudo()._fueltoken_companies()
    if enabled and enabled != company:
        raise AssertionError('FuelToken test fixtures require the current company.')
    if not company.acpec_fueltoken_enabled:
        company.write({'acpec_fueltoken_enabled': True})
    return company


class FuelTokenTransactionCase(TransactionCase):
    """Business fixtures with FuelToken enabled, rolled back by TransactionCase."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        enable_test_fueltoken_company(cls.env)

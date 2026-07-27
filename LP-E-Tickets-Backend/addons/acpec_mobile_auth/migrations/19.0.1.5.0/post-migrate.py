from odoo import api, SUPERUSER_ID


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    env['res.users'].sudo()._acpec_migrate_mobile_user_baseline()
    env['res.users'].sudo()._acpec_migrate_legacy_mobile_pin_credentials()

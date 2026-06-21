from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    env['acpec.mobile.security.setting'].sudo()._migrate_from_ir_config_parameter()

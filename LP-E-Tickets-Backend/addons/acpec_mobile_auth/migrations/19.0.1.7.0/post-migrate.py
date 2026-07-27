from odoo import api, SUPERUSER_ID


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    env['acpec.mobile.web.credential.mixin'].sudo()._acpec_cleanup_mobile_only_web_credentials()

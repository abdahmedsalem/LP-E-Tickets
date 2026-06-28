# -*- coding: utf-8 -*-
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    Users = env['res.users'].sudo().with_context(
        active_test=False,
        acpec_allow_human_code_write=True,
    )
    missing = Users.search([
        '|',
        ('acpec_human_code', '=', False),
        ('acpec_human_code', '=', ''),
    ])
    for user in missing:
        user.write({
            'acpec_human_code': Users._acpec_create_unique_human_code(),
        })

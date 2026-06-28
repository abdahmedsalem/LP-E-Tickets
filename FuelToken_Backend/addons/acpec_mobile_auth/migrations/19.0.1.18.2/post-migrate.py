# -*- coding: utf-8 -*-
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    Users = env['res.users'].sudo().with_context(
        active_test=False,
        acpec_allow_human_code_write=True,
    )
    ambiguous = Users.search([
        ('acpec_human_code', '=like', 'I%'),
    ]) | Users.search([
        ('acpec_human_code', '=like', 'O%'),
    ])
    reserved = set(Users.search([
        ('acpec_human_code', '!=', False),
        ('acpec_human_code', '!=', ''),
    ]).mapped('acpec_human_code'))
    for user in ambiguous:
        reserved.discard(user.acpec_human_code)
        code = Users._acpec_create_unique_human_code(reserved_codes=reserved)
        user.write({'acpec_human_code': code})
        reserved.add(code)

# -*- coding: utf-8 -*-

from odoo import fields, models


class AcpecFuelCarnetTypeAdminIdempotency(models.Model):
    _inherit = 'acpec.fuel.carnet.type'

    admin_create_idempotency_key = fields.Char(
        string='Cle idempotence creation admin',
        index=True,
        copy=False,
    )
    admin_create_request_hash = fields.Char(
        string='Hash requête creation admin',
        index=True,
        copy=False,
    )
    admin_update_idempotency_key = fields.Char(
        string='Cle idempotence modification admin',
        index=True,
        copy=False,
    )
    admin_update_request_hash = fields.Char(
        string='Hash requête modification admin',
        index=True,
        copy=False,
    )
    admin_delete_idempotency_key = fields.Char(
        string='Cle idempotence suppression admin',
        index=True,
        copy=False,
    )
    admin_delete_request_hash = fields.Char(
        string='Hash requête suppression admin',
        index=True,
        copy=False,
    )

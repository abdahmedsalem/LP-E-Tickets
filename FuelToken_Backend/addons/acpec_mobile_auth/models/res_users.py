from odoo import fields, models


class ResUsers(models.Model):
    _inherit = 'res.users'

    mobile_phone = fields.Char(string='Mobile Phone', index=True)
    mobile_state = fields.Selection([
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], string='Mobile State', default='pending',)
    mobile_pin_set_at = fields.Datetime(string='Mobile PIN Set At', readonly=True)

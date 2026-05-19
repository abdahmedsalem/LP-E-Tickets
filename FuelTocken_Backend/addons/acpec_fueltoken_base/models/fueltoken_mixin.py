import secrets

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelTokenPublicCodeMixin(models.AbstractModel):
    _name = 'acpec.fuel.public.code.mixin'
    _description = 'FuelToken Public Code Mixin'

    public_code = fields.Char(string='Code public', readonly=True, copy=False, index=True)

    @api.model
    def _generate_public_code(self, prefix=False, size=24):
        token = secrets.token_urlsafe(size)
        return '%s-%s' % (prefix, token) if prefix else token

    @api.model
    def _create_unique_public_code(self, prefix=False, size=24):
        for _attempt in range(10):
            code = self._generate_public_code(prefix=prefix, size=size)
            if not self.search_count([('public_code', '=', code)]):
                return code
        raise ValidationError(_('Impossible de générer un code public unique.'))


class AcpecFuelTokenQuantityMixin(models.AbstractModel):
    _name = 'acpec.fuel.quantity.mixin'
    _description = 'FuelToken Quantity Mixin'

    @api.model
    def _check_positive_qty(self, qty, label=False):
        if qty <= 0:
            raise ValidationError(_('%s doit être strictement positif.') % (label or _('La quantité')))

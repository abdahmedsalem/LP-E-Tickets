import base64

from odoo import api, fields, models, _
from odoo.exceptions import AccessError, ValidationError
from odoo.tools import file_open

_DEFAULT_PAYMENT_METHOD_COLOR = '#0D6FCB'


class AcpecFuelPaymentMethod(models.Model):
    _name = 'acpec.fuel.payment.method'
    _description = 'Moyen de paiement FuelToken'
    _order = 'sequence, name, id'

    name = fields.Char(string='Nom', required=True, translate=True)
    code = fields.Char(string='Code technique', required=True, index=True)
    merchant_code = fields.Char(
        string='Code commercial',
        help=(
            'Bankily : saisissez exactement 5 ou 6 chiffres. Pour les autres '
            'moyens, saisissez le code commerçant fourni par le prestataire.'
        ),
    )
    can_edit_merchant_code = fields.Boolean(
        compute='_compute_can_edit_merchant_code',
    )

    image_1920 = fields.Image(string='Logo', max_width=1024, max_height=1024)
    image_128 = fields.Image(
        string='Logo mobile',
        related='image_1920',
        max_width=128,
        max_height=128,
        store=True,
        readonly=False,
    )
    instructions = fields.Text(string='Instructions', translate=True)
    color_hex = fields.Char(string='Couleur', default=_DEFAULT_PAYMENT_METHOD_COLOR)
    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=False)
    company_id = fields.Many2one('res.company', string='Société')

    _code_company_unique = models.Constraint(
        'UNIQUE(code, company_id)',
        'Le code du moyen de paiement doit être unique par société.',
    )

    @api.depends_context('uid')
    def _compute_can_edit_merchant_code(self):
        allowed = self._can_edit_merchant_code()
        for payment_method in self:
            payment_method.can_edit_merchant_code = allowed

    @api.model
    def _can_edit_merchant_code(self):
        return self.env.user.has_group(
            'acpec_fueltoken_purchase.group_payment_manager'
        )

    @api.model
    def _normalize_code(self, code):
        return str(code or '').strip().lower()

    @api.model
    def _normalize_payment_method_values(self, values):
        normalized_values = dict(values)
        if 'code' in normalized_values:
            normalized_values['code'] = self._normalize_code(normalized_values['code'])
        merchant_code = normalized_values.get('merchant_code')
        if merchant_code not in (None, False) and not isinstance(merchant_code, str):
            raise ValidationError(_('Le code commercial doit être du texte.'))
        color = normalized_values.get('color_hex')
        if color not in (None, False) and not isinstance(color, str):
            raise ValidationError(_('La couleur doit être du texte au format #RRGGBB.'))
        if color:
            normalized_values['color_hex'] = color.strip()
        return normalized_values

    @api.model_create_multi
    def create(self, vals_list):
        prepared_values = []
        for values in vals_list:
            if values.get('merchant_code'):
                self._check_merchant_code_access()
            prepared_values.append(self._normalize_payment_method_values(values))
        payment_methods = super().create(prepared_values)
        # Context defaults can populate the code even when vals omits it.
        if any(payment_methods.mapped('merchant_code')):
            self._check_merchant_code_access()
        # Odoo may skip the constraint if both fields are omitted at creation.
        payment_methods._check_merchant_code()
        return payment_methods

    def write(self, vals):
        if 'merchant_code' in vals:
            self._check_merchant_code_access()
        return super().write(self._normalize_payment_method_values(vals))

    @api.constrains('code')
    def _check_code(self):
        for payment_method in self:
            if not payment_method.code:
                raise ValidationError(_('Le code technique est obligatoire.'))
            if not payment_method.code.replace('_', '').replace('-', '').isalnum():
                raise ValidationError(
                    _('Le code technique ne doit contenir que lettres, chiffres, tirets ou underscores.')
                )

    @api.constrains('code', 'company_id')
    def _check_code_unique_by_scope(self):
        for payment_method in self:
            domain = [
                ('id', '!=', payment_method.id),
                ('code', '=', payment_method.code),
                ('company_id', '=', payment_method.company_id.id if payment_method.company_id else False),
            ]
            existing_method_count = (
                self.sudo()
                .with_context(active_test=False)
                .search_count(domain)
            )
            if existing_method_count:
                raise ValidationError(_('Le code du moyen de paiement doit être unique.'))

    @api.model
    def _check_merchant_code_access(self):
        # Check the actual user's group, including when a caller uses sudo().
        if not self._can_edit_merchant_code():
            raise AccessError(_(
                'Seul le groupe Moyens de paiement peut modifier le code commercial.'
            ))

    @api.constrains('merchant_code', 'active', 'code')
    def _check_merchant_code(self):
        for payment_method in self:
            merchant_code = payment_method.merchant_code or ''
            if payment_method.active and not merchant_code.strip():
                raise ValidationError(_(
                    'Renseignez le code commercial avant d’activer ce moyen de paiement.'
                ))
            if payment_method.code == 'bankily' and merchant_code and not (
                merchant_code.isascii()
                and merchant_code.isdigit()
                and len(merchant_code) in (5, 6)
            ):
                raise ValidationError(_(
                    'Le code commercial Bankily doit contenir exactement 5 ou 6 chiffres.'
                ))

    @api.constrains('color_hex')
    def _check_color_hex(self):
        for payment_method in self:
            color = (payment_method.color_hex or '').strip()
            if not color:
                continue
            if len(color) != 7 or not color.startswith('#'):
                raise ValidationError(_('La couleur doit être au format #RRGGBB.'))
            try:
                int(color[1:], 16)
            except ValueError:
                raise ValidationError(_('La couleur doit être au format #RRGGBB.'))

    @api.model
    def available_for_company(self, company):
        domain = [('active', '=', True)]
        if company:
            domain = [
                ('active', '=', True),
                '|',
                ('company_id', '=', False),
                ('company_id', '=', company.id),
            ]
        payment_methods = self.sudo().search(domain, order='sequence, id')
        methods_by_code = {}
        for payment_method in payment_methods:
            existing_method = methods_by_code.get(payment_method.code)
            is_company_specific = (
                payment_method.company_id and payment_method.company_id == company
            )
            # A company-specific method takes priority over the global method.
            if not existing_method or is_company_specific:
                methods_by_code[payment_method.code] = payment_method
        ordered_methods = sorted(
            methods_by_code.values(), key=lambda method: (method.sequence, method.id),
        )
        return self.browse([method.id for method in ordered_methods])

    @api.model
    def find_available_for_company(
        self,
        company,
        payment_method_id=False,
        payment_method_code=False,
    ):
        available_methods = self.available_for_company(company)
        payment_method_code = self._normalize_code(payment_method_code)
        has_payment_method_id = (
            payment_method_id is not False
            and payment_method_id is not None
            and payment_method_id != ''
        )
        if has_payment_method_id:
            if isinstance(payment_method_id, bool) or not isinstance(
                payment_method_id,
                (int, str),
            ):
                return self.browse()
            try:
                payment_method_id = int(payment_method_id)
            except (TypeError, ValueError):
                return self.browse()
            if payment_method_id <= 0:
                return self.browse()
            method = available_methods.filtered(
                lambda payment_method: payment_method.id == payment_method_id
            )[:1]
            # If the caller selected an ID, never silently substitute another
            # method by code when that selection is no longer available.
            if not method or (
                payment_method_code and method.code != payment_method_code
            ):
                return self.browse()
            return method
        if payment_method_code:
            return available_methods.filtered(
                lambda payment_method: payment_method.code == payment_method_code
            )[:1]
        return self.browse()

    @api.model
    def _seed_default_payment_methods(self, preset_colors=None):
        """Create payment presets using colors provided by the XML seed."""
        methods = self.sudo().with_context(active_test=False)
        preset_colors = preset_colors or {}
        presets = (
            ('bankily', 'Bankily', ('bankily',)),
            ('sedad', 'Sedad', ('sedad',)),
            ('masrivi', 'Masrivi', ('masrivi', 'masrvi')),
            ('clic', 'Clic', ('clic', 'click')),
            (
                'bfi_cash',
                'BFI Cash',
                ('bfi_cash', 'bficash', 'bfi-cash'),
            ),
        )
        for sequence, (code, name, aliases) in enumerate(presets, start=1):
            existing_methods = methods.search([('code', 'in', aliases)])
            preset_values = {
                'color_hex': preset_colors.get(code, _DEFAULT_PAYMENT_METHOD_COLOR),
            }
            with file_open(
                'acpec_fueltoken_purchase/static/img/payment_methods/%s.png' % code,
                'rb',
            ) as logo_file:
                preset_values['image_1920'] = base64.b64encode(logo_file.read())

            if existing_methods:
                # Keep activation and merchant configuration; refresh preset branding.
                existing_methods.write(preset_values)
                continue

            methods.create({
                'name': name,
                'code': code,
                'active': False,
                'company_id': False,
                'merchant_code': False,
                'sequence': sequence * 10,
                **preset_values,
                'instructions': _(
                    'Effectuez le paiement sur le code commercial affiché, '
                    'puis joignez votre preuve de paiement à la demande d’achat.'
                ),
            })
        return True

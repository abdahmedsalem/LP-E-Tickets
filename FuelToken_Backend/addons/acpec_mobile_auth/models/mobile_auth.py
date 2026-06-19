
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError


class AcpecMobileAuthAccountRequest(models.Model):
    _name = 'acpec.mobile.auth.account.request'
    _description = 'ACPEC Mobile Account Request'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(default='New', copy=False, readonly=True)
    active = fields.Boolean(default=True)
    name_display = fields.Char(string='Full Name', required=True, tracking=True)
    signup_identifier = fields.Char(required=True, tracking=True, index=True)
    signup_identifier_type = fields.Selection([
        ('phone', 'Phone'),
        ('email', 'Email'),
    ], required=True, tracking=True)
    phone = fields.Char(tracking=True, index=True)
    email = fields.Char(tracking=True, index=True)
    login = fields.Char(required=True, tracking=True, index=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company, tracking=True)
    partner_id = fields.Many2one('res.partner', readonly=True, copy=False)
    user_id = fields.Many2one('res.users', readonly=True, copy=False)
    state = fields.Selection([
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], default='pending', required=True, tracking=True)
    requested_at = fields.Datetime(default=fields.Datetime.now, readonly=True)
    reviewed_at = fields.Datetime(readonly=True, copy=False)
    reviewed_by = fields.Many2one('res.users', readonly=True, copy=False)
    rejection_reason = fields.Text(readonly=True, copy=False)
    note = fields.Text()

    _acpec_mobile_auth_account_request_name_unique = models.Constraint(
        'UNIQUE(name)',
        'The account request reference must be unique.',
    )

    @api.model_create_multi
    def create(self, vals_list):
        sequence = self.env['ir.sequence']
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = sequence.next_by_code('acpec.mobile.auth.account.request') or 'New'
            for key in ('signup_identifier', 'phone', 'email', 'login'):
                vals[key] = (vals.get(key) or '').strip()
        records = super().create(vals_list)
        records._check_unique_signup_identifier()
        return records

    def write(self, vals):
        for key in ('signup_identifier', 'phone', 'email', 'login'):
            if key in vals:
                vals[key] = (vals.get(key) or '').strip()
        result = super().write(vals)
        self._check_unique_signup_identifier()
        return result

    def _check_unique_signup_identifier(self):
        user_model = self.env['res.users'].sudo()
        for record in self:
            duplicate_request = self.search([
                ('id', '!=', record.id),
                ('signup_identifier', '=', record.signup_identifier),
                ('state', '=', 'pending'),
            ], limit=1)
            duplicate_user_domain = [('login', '=', record.login)]
            if record.signup_identifier_type == 'phone':
                duplicate_user_domain = ['|', ('login', '=', record.login), ('mobile_phone', '=', record.phone)]
            elif record.signup_identifier_type == 'email':
                duplicate_user_domain = ['|', ('login', '=', record.login), ('email', '=', record.email)]
            duplicate_user = user_model.search(duplicate_user_domain, limit=1)
            if duplicate_user and duplicate_user == record.user_id:
                duplicate_user = False
            if record.state == 'pending' and duplicate_request:
                raise ValidationError(_('A pending account request already exists for this identifier.'))
            if duplicate_user:
                raise ValidationError(_('A mobile account already exists for this identifier.'))

    def _mobile_user_group_ids(self):
        """Return groups for approved mobile-only FuelToken accounts.

        The technical Odoo type is portal, but the user remains functionally
        mobile-only. Business roles must be assigned by controlled back-office
        flows, not by the mobile client.
        """
        group_ids = []
        for xmlid in (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_user',
        ):
            group = self.env.ref(xmlid, raise_if_not_found=False)
            if group:
                group_ids.append(group.id)
        return group_ids

    def action_approve(self):
        group_ids = self._mobile_user_group_ids()
        now = fields.Datetime.now()
        for record in self:
            if record.state != 'pending':
                raise UserError(_('Only a pending account request can be approved.'))
            if not record.user_id:
                raise UserError(_('No linked user exists for this account request.'))
            vals = {
                'active': True,
                'mobile_only': True,
                'mobile_state': 'approved',
                'password': record.user_id._acpec_mobile_unusable_password(),
            }
            if group_ids:
                vals['group_ids'] = [(6, 0, group_ids)]
            if record.phone and not record.user_id.mobile_phone:
                vals['mobile_phone'] = record.phone
            if record.email and not record.user_id.email:
                vals['email'] = record.email
            record.user_id.sudo().with_context(acpec_mobile_allow_password_write=True, no_reset_password=True).write(vals)
            record.write({
                'state': 'approved',
                'reviewed_at': now,
                'reviewed_by': self.env.user.id,
            })
        return True

    def action_reject(self, reason=False):
        now = fields.Datetime.now()
        for record in self:
            if record.state != 'pending':
                raise UserError(_('Only a pending account request can be rejected.'))
            if record.user_id:
                record.user_id.sudo().write({
                    'mobile_state': 'rejected',
                    'active': False,
                })
            record.write({
                'state': 'rejected',
                'reviewed_at': now,
                'reviewed_by': self.env.user.id,
                'rejection_reason': reason or _('Rejected by administrator.'),
            })
        return True


class AcpecMobileAppVersionPolicy(models.Model):
    _name = 'acpec.mobile.app.version.policy'
    _description = 'ACPEC Mobile App Version Policy'
    _order = 'platform, sequence, id'

    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=True)
    platform = fields.Selection([
        ('android', 'Android'),
        ('ios', 'iOS'),
    ], required=True, index=True)
    min_supported_version = fields.Char(required=True)
    latest_version = fields.Char(required=True)
    min_supported_build = fields.Integer(default=0)
    latest_build = fields.Integer(default=0)
    force_update = fields.Boolean(default=False)
    message = fields.Text()

    @api.model
    def evaluate_version(self, platform, app_version=False, build_number=False):
        policy = self.search([('platform', '=', platform), ('active', '=', True)], order='sequence,id', limit=1)
        if not policy:
            return {
                'status': 'ok',
                'min_supported_version': False,
                'latest_version': False,
                'force_update': False,
                'message': False,
            }

        def parse_version(value):
            parts = []
            for chunk in (value or '').split('.'):
                try:
                    parts.append(int(chunk))
                except Exception:
                    parts.append(0)
            return tuple(parts)

        current = parse_version(app_version)
        minimum = parse_version(policy.min_supported_version)
        latest = parse_version(policy.latest_version)
        build_number = int(build_number or 0)

        if current < minimum or (policy.min_supported_build and build_number < policy.min_supported_build):
            status = 'update_required'
        elif current < latest or (policy.latest_build and build_number < policy.latest_build):
            status = 'update_recommended'
        else:
            status = 'ok'

        if policy.force_update and status != 'ok':
            status = 'update_required'

        return {
            'status': status,
            'min_supported_version': policy.min_supported_version,
            'latest_version': policy.latest_version,
            'force_update': policy.force_update,
            'message': policy.message,
        }

from odoo import _, api, models
from odoo.exceptions import ValidationError
from odoo.tools.safe_eval import safe_eval


class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.model
    def _acpec_fueltoken_mobile_partner_contacts_domain(self):
        return [('acpec_is_mobile_partner', '!=', True)]

    @api.model
    def _acpec_fueltoken_merge_contacts_action_domain(self, existing_domain):
        mobile_domain = self._acpec_fueltoken_mobile_partner_contacts_domain()
        existing_domain = (existing_domain or '').strip()
        if not existing_domain or existing_domain in ('[]', 'False', 'None'):
            return repr(mobile_domain)

        try:
            parsed_domain = safe_eval(existing_domain)
        except Exception:
            # Avoid corrupting a dynamic/unsupported action domain.
            return existing_domain

        if not parsed_domain:
            return repr(mobile_domain)

        if ('acpec_is_mobile_partner', '!=', True) in parsed_domain:
            return repr(parsed_domain)

        return repr(mobile_domain + parsed_domain)

    @api.model
    def _acpec_fueltoken_apply_mobile_partner_contacts_action_domain(self):
        xmlids = (
            'base.action_partner_form',
            'contacts.action_contacts',
        )
        actions = self.env['ir.actions.act_window'].sudo()
        for xmlid in xmlids:
            action = self.env.ref(xmlid, raise_if_not_found=False)
            if not action or action._name != 'ir.actions.act_window':
                continue
            if action.res_model != 'res.partner':
                continue
            actions |= action

        for action in actions:
            action.write({
                'domain': self._acpec_fueltoken_merge_contacts_action_domain(action.domain),
            })
        return True

    def _acpec_fueltoken_mobile_partner_identity_fields(self):
        return {'name', 'ref', 'acpec_is_mobile_partner'}

    def _acpec_fueltoken_linked_mobile_identity_users(self):
        if not self:
            return self.env['res.users']
        users = self.env['res.users'].sudo().with_context(active_test=False).search([
            ('partner_id', 'in', self.ids),
            ('acpec_mobile_only', '=', True),
        ])
        return users._acpec_fueltoken_is_mobile_identity_scope()

    def _acpec_fueltoken_partner_value_changed(self, partner, field, value):
        if field not in partner._fields:
            return False
        current = partner[field]
        if hasattr(current, 'id'):
            current = current.id or False
        if isinstance(value, (list, tuple)):
            return True
        return (current or False) != (value or False)

    def _check_acpec_fueltoken_mobile_partner_identity_write_allowed(self, vals):
        if self.env.context.get('acpec_fueltoken_allow_mobile_partner_identity_sync'):
            return True

        locked_fields = self._acpec_fueltoken_mobile_partner_identity_fields() & set(vals or {})
        if not locked_fields:
            return True

        linked_users = self._acpec_fueltoken_linked_mobile_identity_users()
        linked_partner_ids = set(linked_users.mapped('partner_id').ids)
        blocked_partners = self.env['res.partner']

        for partner in self.sudo():
            is_mobile_partner = bool(getattr(partner, 'acpec_is_mobile_partner', False)) or partner.id in linked_partner_ids
            if not is_mobile_partner:
                continue
            for field in locked_fields:
                if self._acpec_fueltoken_partner_value_changed(partner, field, vals.get(field)):
                    blocked_partners |= partner
                    break

        if blocked_partners:
            labels = ', '.join(
                str(partner.display_name or partner.name or partner.id)
                for partner in blocked_partners[:5]
            )
            if len(blocked_partners) > 5:
                labels = '%s, ... (+%s)' % (labels, len(blocked_partners) - 5)
            raise ValidationError(_(
                "Identité technique partenaire mobile FuelToken verrouillée : les champs %s "
                "ne peuvent pas être modifiés directement. Utilisez les actions contrôlées. "
                "Partenaires concernés: %s"
            ) % (', '.join(sorted(locked_fields)), labels))
        return True

    def write(self, vals):
        self._check_acpec_fueltoken_mobile_partner_identity_write_allowed(vals)
        return super().write(vals)

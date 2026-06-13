from odoo import api, models, _
from odoo.exceptions import ValidationError


class AcpecFuelCompanyGuardMixin(models.AbstractModel):
    _name = 'acpec.fuel.company.guard.mixin'
    _description = 'FuelToken Company Guard Mixin'

    def _get_distributor_for_partner(self, partner, company, include_inactive=True):
        if not partner or not company:
            return self.env['acpec.fuel.distributor'].browse()

        Distributor = self.env['acpec.fuel.distributor'].sudo()
        if include_inactive:
            Distributor = Distributor.with_context(active_test=False)

        return Distributor.search([
            ('partner_id', '=', partner.id),
            ('company_id', '=', company.id),
        ], limit=1)

    def _check_partner_is_not_distributor_wallet(self, wallet, message=None):
        if not wallet:
            return

        distributor = self._get_distributor_for_partner(
            wallet.partner_id,
            wallet.company_id,
            include_inactive=True,
        )
        if distributor:
            raise ValidationError(message or _(
                'Cette opération est interdite sur un Compte Société.'
            ))


class AcpecFuelQrCompanyGuard(models.Model):
    _inherit = 'acpec.fuel.qr'

    @api.model
    def _check_company_wallet_can_issue_qr(self, wallet):
        self.env['acpec.fuel.company.guard.mixin']._check_partner_is_not_distributor_wallet(
            wallet,
            _('Un Compte Société ne peut pas générer de QR. '
              'La société doit distribuer des carnets à ses membres.')
        )

    @api.model_create_multi
    def create(self, vals_list):
        Wallet = self.env['acpec.fuel.wallet'].sudo()
        for vals in vals_list:
            wallet_id = vals.get('wallet_id')
            if wallet_id:
                wallet = Wallet.browse(wallet_id).exists()
                if wallet:
                    self._check_company_wallet_can_issue_qr(wallet)
        return super().create(vals_list)

    @api.model
    def issue_from_available(self, wallet, requests, idempotency_key=False):
        self._check_company_wallet_can_issue_qr(wallet)
        return super().issue_from_available(
            wallet,
            requests,
            idempotency_key=idempotency_key,
        )


class AcpecFuelCarnetTransferCompanyGuard(models.Model):
    _inherit = 'acpec.fuel.carnet.transfer'

    @api.constrains('source_wallet_id', 'dest_wallet_id', 'company_id')
    def _check_company_distribution_rules(self):
        Guard = self.env['acpec.fuel.company.guard.mixin']

        for rec in self:
            source_distributor = Guard._get_distributor_for_partner(
                rec.source_partner_id,
                rec.company_id,
                include_inactive=True,
            )
            dest_distributor = Guard._get_distributor_for_partner(
                rec.dest_partner_id,
                rec.company_id,
                include_inactive=True,
            )

            if dest_distributor:
                raise ValidationError(_(
                    'Un Compte Société ne peut pas recevoir de transfert entrant. '
                    'L’alimentation du Compte Société doit venir du flux achat/validation.'
                ))

            if not source_distributor:
                continue

            if not source_distributor.active or source_distributor.state != 'active':
                raise ValidationError(_(
                    'Le Compte Société source doit être actif pour distribuer des carnets.'
                ))

            member_ids = set(source_distributor.member_partner_ids.ids)
            if rec.dest_partner_id.id not in member_ids:
                raise ValidationError(_(
                    'Le destinataire du transfert doit être un membre du Compte Société source.'
                ))


class AcpecFuelPurchaseCompanyGuard(models.Model):
    _inherit = 'acpec.fuel.purchase'

    def _check_before_submit(self):
        res = super()._check_before_submit()
        Guard = self.env['acpec.fuel.company.guard.mixin']

        for rec in self:
            distributor = Guard._get_distributor_for_partner(
                rec.partner_id,
                rec.company_id,
                include_inactive=True,
            )
            if distributor and (not distributor.active or distributor.state != 'active'):
                raise ValidationError(_(
                    'Le Compte Société doit être actif avant de soumettre ou valider un achat.'
                ))

        return res

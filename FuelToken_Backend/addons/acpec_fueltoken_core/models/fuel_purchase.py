from odoo import fields, models, _


class AcpecFuelPurchaseCore(models.Model):
    _inherit = 'acpec.fuel.purchase'

    def action_submit(self):
        res = super().action_submit()
        tx_model = self.env['acpec.fuel.transaction'].sudo()
        wallet_model = self.env['acpec.fuel.wallet'].sudo()
        for purchase in self:
            existing = tx_model.search([
                ('purchase_id', '=', purchase.id),
                ('transaction_type', '=', 'purchase_submitted'),
            ], limit=1)
            if existing:
                continue

            wallet = wallet_model.get_or_create(purchase.partner_id, purchase.company_id)
            tx_model.log(
                'purchase_submitted',
                purchase.company_id,
                wallet=wallet,
                purchase=purchase,
                lines=[
                    {
                        'purchase_id': purchase.id,
                        'purchase_line_id': line.id,
                        'face_value': line.face_value,
                        'qty': line.generated_face_qty,
                    }
                    for line in purchase.line_ids
                ],
                note=_("Demande d'achat soumise"),
                idempotency_key=purchase.idempotency_key,
            )
        return res

    def _create_face_lines_after_approval(self):
        """Create the real fuel value after purchase approval.

        This is the concrete override of the extension hook declared in
        ``acpec_fueltoken_purchase``. It is deliberately kept in core because
        core owns wallets, ticket face lines and transaction audit records.

        Idempotence is mandatory: approving or replaying the hook must never
        create duplicate ticket balances or duplicate ``purchase_approved``
        audit transactions. The purchase row is locked, ``fuel_value_created``
        is the primary guard, and the audit transaction is also checked by
        ``purchase_id`` + ``transaction_type``.
        """
        super()._create_face_lines_after_approval()
        face_model = self.env['acpec.fuel.face.line'].sudo()
        tx_model = self.env['acpec.fuel.transaction'].sudo()
        wallet_model = self.env['acpec.fuel.wallet'].sudo()
        for purchase in self:
            self.env.cr.execute(
                "SELECT id FROM acpec_fuel_purchase WHERE id = %s FOR UPDATE",
                (purchase.id,),
            )
            purchase.invalidate_recordset(['fuel_value_created'])
            if purchase.fuel_value_created:
                # The fuel value was already materialized by a previous
                # approval pass. Do not create ticket lines twice.
                continue

            with self.env.cr.savepoint():
                wallet = wallet_model.get_or_create(purchase.partner_id, purchase.company_id)
                tx_lines = []
                for line in purchase.line_ids:
                    expires_at = False
                    if line.carnet_type_id.validity_days:
                        expires_at = fields.Datetime.add(
                            purchase.approved_at or fields.Datetime.now(),
                            days=line.carnet_type_id.validity_days,
                        )
                    face_line = face_model.create({
                        'wallet_id': wallet.id,
                        'purchase_id': purchase.id,
                        'purchase_line_id': line.id,
                        'carnet_type_id': line.carnet_type_id.id,
                        'face_value': line.face_value,
                        'qty_initial': line.generated_face_qty,
                        'qty_available': line.generated_face_qty,
                        'expires_at': expires_at,
                    })
                    tx_lines.append({
                        'purchase_id': purchase.id,
                        'purchase_line_id': line.id,
                        'face_line_id': face_line.id,
                        'face_value': line.face_value,
                        'qty': line.generated_face_qty,
                    })

                if not tx_model.search([
                    ('purchase_id', '=', purchase.id),
                    ('transaction_type', '=', 'purchase_approved'),
                ], limit=1):
                    # Audit idempotence is separate from fuel-value idempotence:
                    # a purchase may have a submitted event and must still get
                    # exactly one approved event after ticket creation.
                    tx_model.log(
                        'purchase_approved',
                        purchase.company_id,
                        wallet=wallet,
                        purchase=purchase,
                        lines=tx_lines,
                        note=_("Achat approuve - tickets crees"),
                        idempotency_key=purchase.idempotency_key,
                    )
                purchase.sudo().write({'fuel_value_created': True})
        return True

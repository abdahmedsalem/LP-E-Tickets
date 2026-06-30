from odoo import fields, models, _
from odoo.exceptions import ValidationError


class AcpecFuelPurchaseCore(models.Model):
    _inherit = 'acpec.fuel.purchase'

    face_line_count = fields.Integer(
        string='Carnets',
        compute='_compute_face_line_count',
    )

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
                idempotency_key=purchase.idempotency_key, request_hash=purchase.request_hash,
            )
        return res

    def _compute_face_line_count(self):
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        for purchase in self:
            purchase.face_line_count = FaceLine.search_count([
                ('purchase_id', '=', purchase.id),
            ])

    def action_open_face_lines(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Carnets du lot achat'),
            'res_model': 'acpec.fuel.face.line',
            'view_mode': 'list,form',
            'domain': [('purchase_id', '=', self.id)],
            'context': {
                'group_by': 'carnet_type_id',
            },
        }

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
                purchase_ref = (purchase.name or ('PUR-%s' % purchase.id)).replace('/', '-')
                for line_index, line in enumerate(purchase.line_ids.sorted('id'), start=1):
                    expires_at = False
                    if line.carnet_type_id.validity_days:
                        expires_at = fields.Datetime.add(
                            purchase.approved_at or fields.Datetime.now(),
                            days=line.carnet_type_id.validity_days,
                        )

                    carnet_qty = int(line.carnet_qty or 0)
                    face_count = int(line.face_count or line.carnet_type_id.face_count or 0)
                    if carnet_qty <= 0:
                        raise ValidationError(_('Le nombre de carnets doit etre positif.'))
                    if face_count <= 0:
                        raise ValidationError(_('Le nombre de tickets par carnet doit etre positif.'))

                    lot_short_code = face_model._generate_lot_short_code(purchase.company_id)
                    for carnet_sequence in range(1, carnet_qty + 1):
                        carnet_suffix = 'C%03d' % carnet_sequence
                        carnet_no = '%s-L%02d-%s' % (purchase_ref, line_index, carnet_suffix)
                        carnet_short_code = face_model._generate_carnet_short_code(purchase.company_id)

                        face_line = face_model.create({
                            'wallet_id': wallet.id,
                            'purchase_id': purchase.id,
                            'purchase_line_id': line.id,
                            'carnet_type_id': line.carnet_type_id.id,
                            'face_value': line.face_value,
                            'qty_initial': face_count,
                            'qty_available': face_count,
                            'expires_at': expires_at,
                            'carnet_no': carnet_no,
                            'lot_short_code': lot_short_code,
                            'carnet_short_code': carnet_short_code,
                            'carnet_sequence': carnet_sequence,
                        })
                        tx_lines.append({
                            'purchase_id': purchase.id,
                            'purchase_line_id': line.id,
                            'face_line_id': face_line.id,
                            'face_value': line.face_value,
                            'qty': face_count,
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
                        idempotency_key=purchase.approval_idempotency_key or purchase.idempotency_key,
                        request_hash=purchase.approval_request_hash or purchase.request_hash,
                    )
                purchase.sudo().write({'fuel_value_created': True})
        return True

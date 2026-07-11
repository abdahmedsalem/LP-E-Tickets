from odoo import api, fields, models, _
from odoo.exceptions import ValidationError
from odoo.tools import float_compare


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
            # M20-B doctrine: purchase history is append-only.
            # action_submit creates the pending purchase transaction once. If a
            # purchase already has an audit TX, do not recreate a submitted row
            # during replay/repair.
            existing = tx_model.search([
                ('purchase_id', '=', purchase.id),
                ('transaction_type', 'in', ['purchase_submitted', 'purchase_approved']),
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

        M20-B append-only doctrine: approval is a new business event and must
        create a new ``purchase_approved`` transaction. The previously exposed
        ``purchase_submitted`` transaction stays unchanged and both rows share
        the same ``operation_ref``.

        Rejection is different: it creates no new TX and does not introduce a
        ``purchase_rejected`` type. The existing ``purchase_submitted`` TX keeps
        the same operation reference and exposes rejection through the related
        purchase fields.

        Idempotence is mandatory: approving or replaying the hook must never
        create duplicate ticket balances or duplicate approved purchase TX rows.
        The purchase row is locked and ``fuel_value_created`` remains the
        primary fuel-value guard.
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

                        face_line = face_model._create_internal({
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

                approved_tx = tx_model.search([
                    ('purchase_id', '=', purchase.id),
                    ('transaction_type', '=', 'purchase_approved'),
                ], limit=1)
                if not approved_tx:
                    submitted_tx = tx_model.search([
                        ('purchase_id', '=', purchase.id),
                        ('transaction_type', '=', 'purchase_submitted'),
                    ], limit=1)
                    operation_ref = submitted_tx.operation_ref if submitted_tx else False
                    if submitted_tx:
                        # M20-B: keep the submitted transaction immutable.
                        # Approval is a distinct append-only transaction that
                        # reuses the same operation_ref for mobile/business
                        # grouping, while name remains a new internal sequence.
                        # purchase_submitted_amount_guard_m20b:
                        # The submitted provisional amount and the materialized
                        # approved amount must stay coherent before the approved
                        # append-only row is created.
                        submitted_tx.invalidate_recordset(['amount_total'])
                        submitted_amount = submitted_tx.amount_total
                        approved_amount = sum(
                            (tx_line.get('face_value') or 0.0) * (tx_line.get('qty') or 0)
                            for tx_line in tx_lines
                        )
                        currency = purchase.company_id.currency_id
                        precision_rounding = currency.rounding or 0.01
                        if float_compare(
                            submitted_amount,
                            approved_amount,
                            precision_rounding=precision_rounding,
                        ):
                            raise ValidationError(_(
                                "Montant transaction achat incoherent entre soumission et approbation: %(submitted)s != %(approved)s."
                            ) % {
                                'submitted': submitted_amount,
                                'approved': approved_amount,
                            })
                    else:
                        # Repair/fallback path for legacy data where the submit
                        # TX is missing. Runtime should normally pass through
                        # purchase_submitted first; without it, approval gets a
                        # fresh operation_ref generated by tx_model.log().
                        operation_ref = False

                    tx_model.log(
                        'purchase_approved',
                        purchase.company_id,
                        wallet=wallet,
                        purchase=purchase,
                        lines=tx_lines,
                        note=_("Achat approuve - tickets crees"),
                        idempotency_key=purchase.approval_idempotency_key or purchase.idempotency_key,
                        request_hash=purchase.approval_request_hash or purchase.request_hash,
                        operation_ref=operation_ref,
                    )
                purchase.with_context(allow_fuel_purchase_update=True).sudo().write({
                    'fuel_value_created': True,
                })
        return True


class AcpecFuelPurchaseLineSnapshotRepairM21E(models.Model):
    _inherit = 'acpec.fuel.purchase.line'

    @api.model
    def _repair_m21e_snapshots_from_face_lines(self):
        self.env.cr.execute("""
            SELECT
                purchase_line_id,
                MIN(qty_initial) AS min_face_count,
                MAX(qty_initial) AS max_face_count,
                MIN(face_value) AS min_face_value,
                MAX(face_value) AS max_face_value
              FROM acpec_fuel_face_line
             WHERE purchase_line_id IS NOT NULL
             GROUP BY purchase_line_id
        """)
        repaired = 0
        purchase_ids = set()
        for row in self.env.cr.dictfetchall():
            line = self.sudo().browse(row['purchase_line_id']).exists()
            if not line:
                continue
            if row['min_face_count'] != row['max_face_count'] or row['min_face_value'] != row['max_face_value']:
                raise ValidationError(_(
                    'Réparation snapshot impossible : valeurs de carnets incohérentes pour la ligne achat %s.'
                ) % line.id)

            vals = {
                'face_count': int(row['min_face_count'] or 0),
                'face_value': row['min_face_value'] or 0.0,
            }
            if line.face_count != vals['face_count'] or line.face_value != vals['face_value']:
                line.with_context(allow_fuel_purchase_line_update=True).sudo().write(vals)
                if line.purchase_id:
                    purchase_ids.add(line.purchase_id.id)
                repaired += 1

        if purchase_ids:
            self.flush_model(['purchase_id', 'amount_total'])
            self.env.cr.execute("""
                UPDATE acpec_fuel_purchase purchase
                   SET amount_total = totals.amount_total,
                       write_uid = %s,
                       write_date = NOW()
                  FROM (
                      SELECT purchase_id, SUM(amount_total) AS amount_total
                        FROM acpec_fuel_purchase_line
                       WHERE purchase_id = ANY(%s)
                       GROUP BY purchase_id
                  ) totals
                 WHERE purchase.id = totals.purchase_id
            """, [self.env.uid, list(purchase_ids)])
            self.env['acpec.fuel.purchase'].sudo().browse(list(purchase_ids)).invalidate_recordset(['amount_total'])

        return repaired

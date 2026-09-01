import base64
import binascii
import os
import re

from odoo import SUPERUSER_ID, api, fields, models, _
from odoo.exceptions import AccessError, ValidationError, UserError


class AcpecFuelPurchase(models.Model):
    _name = 'acpec.fuel.purchase'
    _description = 'Lot achat FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Référence interne', default='New', readonly=True, copy=False)
    partner_id = fields.Many2one('res.partner', string='Client', required=True, index=True, tracking=True)
    company_id = fields.Many2one('res.company', string='Societe', default=lambda self: self.env.company, required=True, index=True)
    currency_id = fields.Many2one('res.currency', related='company_id.currency_id', store=True, readonly=True)
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('submitted', 'Soumis'),
        ('approved', 'Valide'),
        ('rejected', 'Rejete'),
    ], string='Etat', default='draft', required=True, tracking=True, index=True)
    line_ids = fields.One2many('acpec.fuel.purchase.line', 'purchase_id', string='Lignes')
    purchase_line_count = fields.Integer(string='Détail', compute='_compute_purchase_line_count')

    amount_total = fields.Monetary(string='Montant total', compute='_compute_totals', store=True)
    face_qty_total = fields.Integer(string='Nombre total de tickets', compute='_compute_totals', store=True)
    proof_attachment_ids = fields.Many2many(
        'ir.attachment',
        'acpec_fuel_purchase_attachment_rel',
        'purchase_id',
        'attachment_id',
        string='Preuves de paiement',
    )
    payment_reference = fields.Char(string='Reference paiement')
    payment_method_id = fields.Many2one('acpec.fuel.payment.method', string='Mode de paiement', readonly=True)
    payment_method_code = fields.Char(string='Code mode paiement', readonly=True)
    payment_method_name = fields.Char(string='Mode paiement', readonly=True)
    payment_merchant_code = fields.Char(
        string='Code commerçant / Numéro de téléphone',
        readonly=True,
    )
    idempotency_key = fields.Char(string='Cle idempotence', index=True, copy=False)
    request_hash = fields.Char(string='Hash requête idempotence', index=True, copy=False)
    approval_idempotency_key = fields.Char(string='Cle idempotence validation', index=True, copy=False)
    approval_request_hash = fields.Char(string='Hash requête validation', index=True, copy=False)
    rejection_idempotency_key = fields.Char(string='Cle idempotence rejet', index=True, copy=False)
    rejection_request_hash = fields.Char(string='Hash requête rejet', index=True, copy=False)
    submitted_at = fields.Datetime(string='Date soumission', readonly=True)
    approved_at = fields.Datetime(string='Date validation', readonly=True)
    approved_by = fields.Many2one('res.users', string='Valide par', readonly=True)
    rejected_at = fields.Datetime(string='Date rejet', readonly=True)
    rejected_by = fields.Many2one('res.users', string='Rejete par', readonly=True)
    rejection_reason = fields.Text(string='Motif de rejet')
    fuel_value_created = fields.Boolean(string='Valeur carburant creee', readonly=True, copy=False)

    _public_code_unique = models.Constraint(
        'UNIQUE(public_code)',
        'Le code public du lot doit etre unique.',
    )
    _idempotency_partner_unique = models.Constraint(
        'UNIQUE(partner_id, idempotency_key)',
        "Cette demande d'achat existe deja pour ce client.",
    )

    _purchase_internal_context_key = (
        'acpec_fueltoken_purchase_internal_operation'
    )
    _purchase_action_operation_context_key = (
        'acpec_fueltoken_purchase_action_operation'
    )
    _purchase_action_actor_context_key = (
        'acpec_fueltoken_purchase_action_actor_user_id'
    )

    @api.model
    def _purchase_internal_context_is_valid(self, operation):
        return bool(
            self.env.su
            and self.env.context.get(
                self._purchase_internal_context_key
            ) == operation
        )

    @api.model
    def _purchase_actor_has_group(self, actor, xmlid):
        if not actor:
            return False
        if actor.id == SUPERUSER_ID:
            return True

        group = self.env.ref(
            xmlid,
            raise_if_not_found=False,
        )
        if not group:
            return False

        self.env.cr.execute(
            """
            SELECT 1
              FROM res_groups_users_rel
             WHERE uid = %s
               AND gid = %s
             LIMIT 1
            """,
            (actor.id, group.id),
        )
        return bool(self.env.cr.fetchone())

    def _purchase_actor_can_admin_action(self, actor):
        return bool(
            self._purchase_actor_has_group(
                actor,
                'acpec_fueltoken_base.group_fuel_admin',
            )
            or self._purchase_actor_has_group(
                actor,
                'base.group_system',
            )
        )

    def _purchase_actor_can_approve_internal(self, actor):
        return bool(
            self._purchase_actor_can_admin_action(actor)
            or self._purchase_actor_has_group(
                actor,
                'acpec_fueltoken_base.group_fuel_manager',
            )
        )

    def _purchase_action_actor(self, actor_user=False):
        explicit_actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )

        if self.env.su:
            actor_id = int(
                self.env.context.get(
                    self._purchase_action_actor_context_key
                ) or 0
            )

            if (
                not actor_id
                and self.env.uid == SUPERUSER_ID
            ):
                actor_id = SUPERUSER_ID

            if (
                explicit_actor_id
                and explicit_actor_id != actor_id
            ):
                raise AccessError(_(
                    "L'acteur de la décision d'achat ne correspond "
                    "pas au contexte interne."
                ))
        else:
            actor_id = self.env.user.id
            if (
                explicit_actor_id
                and explicit_actor_id != actor_id
            ):
                raise AccessError(_(
                    "L'acteur de la décision d'achat doit être "
                    "l'utilisateur courant."
                ))

        actor = self.env[
            'res.users'
        ].sudo().browse(actor_id).exists()

        if not actor:
            raise AccessError(_(
                "Acteur de la décision d'achat introuvable."
            ))

        return actor

    def _assert_purchase_action_allowed(
        self,
        operation,
        actor,
    ):
        if operation not in ('approve', 'reject'):
            raise AccessError(_(
                "Opération de décision d'achat inconnue."
            ))

        if (
            self.env.su
            and self.env.uid == SUPERUSER_ID
            and actor.id == SUPERUSER_ID
            and not self.env.context.get(
                self._purchase_action_operation_context_key
            )
        ):
            return True

        if self.env.su:
            allowed = bool(
                self.env.context.get(
                    self._purchase_action_operation_context_key
                ) == operation
                and int(
                    self.env.context.get(
                        self._purchase_action_actor_context_key
                    ) or 0
                ) == actor.id
            )

            if allowed and operation == 'approve':
                allowed = (
                    self._purchase_actor_can_approve_internal(
                        actor
                    )
                )
            elif allowed:
                allowed = (
                    self._purchase_actor_can_admin_action(
                        actor
                    )
                )
        else:
            allowed = bool(
                actor.id == self.env.user.id
                and self._purchase_actor_can_admin_action(
                    actor
                )
            )

        if not allowed:
            raise AccessError(_(
                "Seul un administrateur FuelToken ou un flux "
                "interne autorisé peut valider ou rejeter "
                "un achat."
            ))

        return True

    def _approve_internal(self, actor_user):
        actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )
        actor = self.env[
            'res.users'
        ].sudo().browse(actor_id).exists()

        if (
            not actor
            or not self._purchase_actor_can_approve_internal(
                actor
            )
        ):
            raise AccessError(_(
                "L'acteur interne n'est pas autorisé à valider "
                "un achat."
            ))

        return self.sudo().with_context(
            acpec_fueltoken_purchase_action_operation=(
                'approve'
            ),
            acpec_fueltoken_purchase_action_actor_user_id=(
                actor.id
            ),
        ).action_approve(actor_user=actor)

    def _reject_internal(
        self,
        actor_user,
        reason=False,
    ):
        actor_id = (
            actor_user.id
            if hasattr(actor_user, 'id')
            else int(actor_user or 0)
        )
        actor = self.env[
            'res.users'
        ].sudo().browse(actor_id).exists()

        if (
            not actor
            or not self._purchase_actor_can_admin_action(
                actor
            )
        ):
            raise AccessError(_(
                "L'acteur interne n'est pas autorisé à rejeter "
                "un achat."
            ))

        return self.sudo().with_context(
            acpec_fueltoken_purchase_action_operation=(
                'reject'
            ),
            acpec_fueltoken_purchase_action_actor_user_id=(
                actor.id
            ),
        ).action_reject(
            reason=reason,
            actor_user=actor,
        )

    @api.model_create_multi
    def _create_internal(self, vals_list):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='create',
        ).create(vals_list)

    @api.model_create_multi
    def create(self, vals_list):
        if not self._purchase_internal_context_is_valid('create'):
            raise UserError(_(
                'La création de lots d’achat est réservée aux flux métier internes contrôlés.'
            ))
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('acpec.fuel.purchase') or 'New'
            if not vals.get('public_code'):
                vals['public_code'] = self._create_unique_public_code(prefix='LOT', size=16)
        return super().create(vals_list)

    @api.depends('line_ids.amount_total', 'line_ids.generated_face_qty')
    def _compute_totals(self):
        for rec in self:
            rec.amount_total = sum(rec.line_ids.mapped('amount_total'))
            rec.face_qty_total = sum(rec.line_ids.mapped('generated_face_qty'))

    _PROOF_MAX_BYTES = 5 * 1024 * 1024
    _PROOF_ALLOWED_EXTENSIONS = {'.pdf', '.png', '.jpg', '.jpeg'}
    _PROOF_ALLOWED_MIMETYPES = {'application/pdf', 'image/png', 'image/jpeg'}

    @api.model
    def _proof_upload_max_bytes(self):
        """Return max proof size in bytes.

        Configurable for deployments, but deliberately capped by default to avoid
        storing arbitrary large base64 payloads in ir.attachment.
        """
        raw_value = self.env['ir.config_parameter'].sudo().get_param(
            'acpec_fueltoken_purchase.proof_max_bytes',
            str(self._PROOF_MAX_BYTES),
        )
        try:
            max_bytes = int(raw_value)
        except (TypeError, ValueError):
            max_bytes = self._PROOF_MAX_BYTES
        return max(1, max_bytes)

    @api.model
    def _proof_upload_max_label(self, max_bytes):
        max_mb = max_bytes / float(1024 * 1024)
        if max_mb.is_integer():
            return '%s Mo' % int(max_mb)
        return '%.1f Mo' % max_mb

    @api.model
    def _sanitize_proof_filename_stem(self, filename):
        filename = (filename or '').replace('\\', '/')
        filename = os.path.basename(filename).strip()
        filename = re.sub(r'[^A-Za-z0-9_.()\- ]+', '_', filename)
        filename = filename[:120].strip(' .')
        stem = os.path.splitext(filename)[0].strip(' .')
        return stem or 'preuve_paiement'

    @api.model
    def _split_proof_data_uri(self, proof_data):
        if proof_data in (False, None, ''):
            raise ValidationError(_('La preuve de paiement est obligatoire.'))
        if isinstance(proof_data, bytes):
            proof_data = proof_data.decode('ascii', errors='ignore')
        proof_data = str(proof_data).strip()
        declared_mimetype = False
        if proof_data.lower().startswith('data:'):
            if ',' not in proof_data:
                raise ValidationError(_('La preuve de paiement doit etre un fichier base64 valide.'))
            header, proof_data = proof_data.split(',', 1)
            match = re.match(r'^data:([^;,]+);base64$', header.strip(), flags=re.IGNORECASE)
            if not match:
                raise ValidationError(_('La preuve de paiement doit etre un fichier base64 valide.'))
            declared_mimetype = match.group(1).lower()
        return declared_mimetype, re.sub(r'\s+', '', proof_data)

    @api.model
    def _detect_proof_mimetype(self, content):
        if content.startswith(b'%PDF-'):
            return 'application/pdf'
        if content.startswith(b'\x89PNG\r\n\x1a\n'):
            return 'image/png'
        if content.startswith(b'\xff\xd8\xff'):
            return 'image/jpeg'
        return False

    @api.model
    def _proof_extension_for_mimetype(self, mimetype):
        return {
            'application/pdf': '.pdf',
            'image/png': '.png',
            'image/jpeg': '.jpg',
        }.get(mimetype)

    @api.model
    def _validate_purchase_proof(self, proof_filename, proof_data):
        """Validate and normalize a payment proof before creating ir.attachment.

        Accepted formats are PDF, PNG and JPEG. The client filename is treated
        as a display hint only: the stored extension is derived from detected
        magic bytes. This avoids rejecting mobile screenshots when the handset or
        Flutter image picker changes the real image format without updating the
        original filename.
        """
        filename_stem = self._sanitize_proof_filename_stem(proof_filename)

        declared_mimetype, proof_data = self._split_proof_data_uri(proof_data)
        if declared_mimetype and declared_mimetype not in self._PROOF_ALLOWED_MIMETYPES:
            raise ValidationError(_('Format de preuve interdit. Formats autorises : PDF, PNG, JPG.'))

        max_bytes = self._proof_upload_max_bytes()
        max_label = self._proof_upload_max_label(max_bytes)
        max_encoded_len = ((max_bytes + 2) // 3) * 4 + 16
        if len(proof_data) > max_encoded_len:
            raise ValidationError(_('La preuve de paiement depasse la taille maximale autorisee de %s.') % max_label)

        try:
            content = base64.b64decode(proof_data, validate=True)
        except (binascii.Error, ValueError):
            raise ValidationError(_('La preuve de paiement doit etre un fichier base64 valide.'))

        if not content:
            raise ValidationError(_('La preuve de paiement est obligatoire.'))
        if len(content) > max_bytes:
            raise ValidationError(_('La preuve de paiement depasse la taille maximale autorisee de %s.') % max_label)

        detected_mimetype = self._detect_proof_mimetype(content)
        if detected_mimetype not in self._PROOF_ALLOWED_MIMETYPES:
            raise ValidationError(_('Format de preuve interdit. Formats autorises : PDF, PNG, JPG.'))
        if declared_mimetype and declared_mimetype != detected_mimetype:
            raise ValidationError(_('Le type MIME de la preuve ne correspond pas au contenu du fichier.'))

        extension = self._proof_extension_for_mimetype(detected_mimetype)
        filename = '%s%s' % (filename_stem, extension)
        return filename, base64.b64encode(content).decode('ascii'), detected_mimetype

    def _has_payment_proof_sudo(self):
        """Return True if a purchase has at least one payment proof.

        Mobile manager approval runs with the manager user, but mobile/portal
        users may not have read ACL on ir.attachment.  Keep approval itself
        under the manager user and only read proof existence with sudo.
        """
        self.ensure_one()
        if self.sudo().proof_attachment_ids:
            return True
        return bool(self.env['ir.attachment'].sudo().search_count([
            ('res_model', '=', self._name),
            ('res_id', '=', self.id),
        ]))

    @api.depends('line_ids')
    def _compute_purchase_line_count(self):
        for rec in self:
            rec.purchase_line_count = len(rec.line_ids)

    def action_open_purchase_lines(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Détail du lot achat'),
            'res_model': 'acpec.fuel.purchase.line',
            'view_mode': 'list',
            'views': [(self.env.ref('acpec_fueltoken_purchase.view_fuel_purchase_line_smart_list').id, 'list')],
            'domain': [('purchase_id', '=', self.id)],
            'context': {
                'default_purchase_id': self.id,
                'group_by': 'carnet_type_id',
            },
        }

    def action_open_payment_proof(self):
        """Open a modal preview wizard for payment proof with a Close button."""
        self.ensure_one()
        attachments = self.proof_attachment_ids.exists()
        image = attachments.filtered(
            lambda attachment: (attachment.mimetype or '').startswith('image/')
        )[:1]
        attachment = image or attachments[:1]
        if not attachment:
            raise UserError(_('Aucune preuve de paiement disponible.'))

        wizard = self.env['acpec.fuel.purchase.proof.wizard'].create({
            'purchase_id': self.id,
            'attachment_id': attachment.id,
        })

        return {
            'type': 'ir.actions.act_window',
            'name': _('Preuve de paiement — %s') % (attachment.name or self.name),
            'res_model': 'acpec.fuel.purchase.proof.wizard',
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'new',
        }

    def action_open_reject_wizard(self):
        self.ensure_one()
        actor = self._purchase_action_actor(False)
        self._assert_purchase_action_allowed(
            'reject',
            actor,
        )
        if self.state == 'approved':
            raise UserError(_('Un lot valide ne peut pas etre rejete.'))
        return {
            'type': 'ir.actions.act_window',
            'name': _('Rejeter le lot achat'),
            'res_model': 'acpec.fuel.purchase.reject.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_purchase_id': self.id,
                'default_rejection_reason': self.rejection_reason or '',
            },
        }



    def _check_before_submit(self):
        for rec in self:
            if not rec.line_ids:
                raise ValidationError(_('Le lot achat doit contenir au moins une ligne.'))
            if not rec._has_payment_proof_sudo():
                raise ValidationError(_('La preuve de paiement est obligatoire.'))
            for line in rec.line_ids:
                line._check_line_values()

    def action_submit(self):
        self._check_before_submit()
        for rec in self:
            if rec.state != 'draft':
                raise UserError(_('Seuls les lots en brouillon peuvent etre soumis.'))
            rec._write_submission_internal({
                'state': 'submitted',
                'submitted_at': fields.Datetime.now(),
            })

    def action_approve(self, actor_user=False):
        actor = self._purchase_action_actor(actor_user)
        self._assert_purchase_action_allowed(
            'approve',
            actor,
        )

        with self.env.cr.savepoint():
            self._check_before_submit()
            for rec in self:
                if rec.state not in (
                    'draft',
                    'submitted',
                ):
                    raise UserError(_(
                        'Seuls les lots brouillon ou soumis '
                        'peuvent etre valides.'
                    ))
                rec._write_approval_internal({
                    'state': 'approved',
                    'approved_at': fields.Datetime.now(),
                    'approved_by': actor.id,
                    'rejection_reason': False,
                })
            self._create_face_lines_after_approval()

        return True

    @api.model
    def _normalize_rejection_reason(self, reason):
        if reason is None or reason is False:
            reason = ''
        if isinstance(reason, bytes):
            reason = reason.decode('utf-8', errors='ignore')
        reason = str(reason).strip()
        if not reason:
            raise ValidationError(_('Le motif de rejet est obligatoire.'))
        return reason

    def action_reject(
        self,
        reason=False,
        actor_user=False,
    ):
        actor = self._purchase_action_actor(actor_user)
        self._assert_purchase_action_allowed(
            'reject',
            actor,
        )

        for rec in self:
            if rec.state == 'approved':
                raise UserError(_(
                    'Un lot valide ne peut pas etre rejete.'
                ))
            rejection_reason = (
                reason
                if reason not in (False, None)
                else rec.rejection_reason or False
            )
            rejection_reason = rec._normalize_rejection_reason(
                rejection_reason
            )
            rec._write_rejection_internal({
                'state': 'rejected',
                'rejected_at': fields.Datetime.now(),
                'rejected_by': actor.id,
                'rejection_reason': rejection_reason,
            })

        return True

    def _create_face_lines_after_approval(self):
        """Extension hook called after a purchase is approved.

        This implementation is intentionally empty. The purchase module owns
        only the commercial workflow: draft, submission, approval/rejection and
        payment proof handling. It must not create fuel value by itself.

        The real ticket/fuel-value creation is implemented in
        ``acpec_fueltoken_core``, which depends on this module and overrides
        this hook. Keep this method as a stable extension point and do not
        inline the core logic here.
        """
        return True

    _purchase_write_fields_by_operation = {
        'submission_write': frozenset({
            'state',
            'submitted_at',
        }),
        'approval_write': frozenset({
            'state',
            'approved_at',
            'approved_by',
            'rejection_reason',
        }),
        'rejection_write': frozenset({
            'state',
            'rejected_at',
            'rejected_by',
            'rejection_reason',
        }),
        'proof_write': frozenset({
            'proof_attachment_ids',
        }),
        'approval_idempotency_write': frozenset({
            'approval_idempotency_key',
            'approval_request_hash',
        }),
        'fuel_value_write': frozenset({
            'fuel_value_created',
        }),
    }

    def _write_submission_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='submission_write',
        ).write(vals)

    def _write_approval_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='approval_write',
        ).write(vals)

    def _write_rejection_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='rejection_write',
        ).write(vals)

    def _write_proof_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='proof_write',
        ).write(vals)

    def _write_approval_idempotency_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='approval_idempotency_write',
        ).write(vals)

    def _write_fuel_value_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_internal_operation='fuel_value_write',
        ).write(vals)

    def _check_purchase_write_vals(self, operation, vals):
        expected_fields = self._purchase_write_fields_by_operation.get(operation)
        if (
            not expected_fields
            or not self._purchase_internal_context_is_valid(operation)
            or set(vals) != expected_fields
        ):
            raise UserError(_(
                'Les modifications du lot achat sont reservees aux flux metier internes controles.'
            ))

        if operation == 'submission_write':
            if vals.get('state') != 'submitted' or not vals.get('submitted_at'):
                raise ValidationError(_('La soumission du lot achat est incomplete.'))
            if self.filtered(lambda purchase: purchase.state != 'draft'):
                raise UserError(_('Seuls les lots en brouillon peuvent etre soumis.'))

        elif operation == 'approval_write':
            if (
                vals.get('state') != 'approved'
                or not vals.get('approved_at')
                or not vals.get('approved_by')
                or vals.get('rejection_reason') not in (False, None, '')
            ):
                raise ValidationError(_('La validation du lot achat est incomplete.'))
            if self.filtered(lambda purchase: purchase.state not in ('draft', 'submitted')):
                raise UserError(_('Seuls les lots brouillon ou soumis peuvent etre valides.'))

        elif operation == 'rejection_write':
            vals['rejection_reason'] = self._normalize_rejection_reason(
                vals.get('rejection_reason')
            )
            if (
                vals.get('state') != 'rejected'
                or not vals.get('rejected_at')
                or not vals.get('rejected_by')
            ):
                raise ValidationError(_('Le rejet du lot achat est incomplet.'))
            if self.filtered(lambda purchase: purchase.state == 'approved'):
                raise UserError(_('Un lot valide ne peut pas etre rejete.'))

        elif operation == 'proof_write':
            if not vals.get('proof_attachment_ids'):
                raise ValidationError(_('La preuve de paiement est obligatoire.'))
            if self.filtered(lambda purchase: purchase.state != 'draft'):
                raise UserError(_('La preuve de paiement ne peut etre modifiee que sur un lot en brouillon.'))

        elif operation == 'approval_idempotency_write':
            idempotency_key = vals.get('approval_idempotency_key')
            request_hash = vals.get('approval_request_hash')
            if not idempotency_key or not request_hash:
                raise ValidationError(_('Les references techniques d idempotence de validation sont obligatoires.'))
            for purchase in self:
                current_key = purchase.approval_idempotency_key
                current_hash = purchase.approval_request_hash
                if bool(current_key) != bool(current_hash):
                    raise ValidationError(_('Les references techniques d idempotence de validation sont incoherentes.'))
                if (
                    current_key
                    and (
                        current_key != idempotency_key
                        or current_hash != request_hash
                    )
                ):
                    raise ValidationError(_('Les references techniques d idempotence de validation sont deja initialisees.'))

        elif operation == 'fuel_value_write':
            if vals.get('fuel_value_created') is not True:
                raise ValidationError(_('La valeur carburant creee ne peut etre que confirmee.'))
            if self.filtered(lambda purchase: purchase.state != 'approved'):
                raise UserError(_('La valeur carburant ne peut etre confirmee que sur un lot valide.'))

    def write(self, vals):
        if not vals:
            return True
        operation = self.env.context.get(
            self._purchase_internal_context_key
        )
        self._check_purchase_write_vals(operation, vals)
        return super().write(vals)

    def unlink(self):
        raise UserError(_(
            'Les lots d’achat ne doivent pas être supprimés.'
        ))

    def _set_approval_idempotency(self, idempotency_key, request_hash):
        self.ensure_one()
        return self._write_approval_idempotency_internal({
            'approval_idempotency_key': idempotency_key,
            'approval_request_hash': request_hash,
        })

    @api.model
    def create_from_api(
        self,
        partner,
        company,
        lines,
        proof_filename,
        proof_data,
        payment_reference=False,
        idempotency_key=False,
        request_hash=False,
        payment_method_id=False,
        payment_method_code=False,
    ):
        if idempotency_key:
            existing = self.sudo().search([
                ('partner_id', '=', partner.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing:
                if existing.request_hash and request_hash and existing.request_hash != request_hash:
                    raise ValidationError(_('idempotency_conflict: même idempotency_key avec payload différent.'))
                return existing
        proof_filename, proof_data, proof_mimetype = self._validate_purchase_proof(proof_filename, proof_data)
        payment_method = self.env['acpec.fuel.payment.method'].sudo().find_available_for_company(
            company,
            payment_method_id=payment_method_id,
            payment_method_code=payment_method_code,
        )
        if (payment_method_id or payment_method_code) and not payment_method:
            raise ValidationError(_('Mode de paiement indisponible.'))
        with self.env.cr.savepoint():
            purchase = self._create_internal({
                'partner_id': partner.id,
                'company_id': company.id,
                'payment_reference': payment_reference or False,
                'payment_method_id': payment_method.id if payment_method else False,
                'payment_method_code': payment_method.code if payment_method else False,
                'payment_method_name': payment_method.name if payment_method else False,
                'payment_merchant_code': payment_method.merchant_code if payment_method else False,
                'idempotency_key': idempotency_key or False,
                'request_hash': request_hash or False,
            })
            for item in lines:
                carnet_type = self.env['acpec.fuel.carnet.type'].sudo().browse(int(item.get('carnet_type_id') or 0)).exists()
                if not carnet_type:
                    raise ValidationError(_('Type de carnet introuvable.'))
                if not carnet_type.active:
                    raise ValidationError(_("Type de carnet '%s' desactive.") % carnet_type.display_name)
                if carnet_type.company_id and carnet_type.company_id != company:
                    raise ValidationError(_("Type de carnet '%s' indisponible pour cette societe.") % carnet_type.display_name)
                self.env['acpec.fuel.purchase.line']._create_internal({
                    'purchase_id': purchase.id,
                    'carnet_type_id': carnet_type.id,
                    'carnet_qty': int(item.get('carnet_qty') or 0),
                })
            attachment = self.env['ir.attachment'].sudo().create({
                'name': proof_filename,
                'datas': proof_data,
                'mimetype': proof_mimetype,
                'res_model': self._name,
                'res_id': purchase.id,
                'type': 'binary',
            })
            purchase._write_proof_internal({
                'proof_attachment_ids': [(4, attachment.id)],
            })
            purchase.action_submit()
            return purchase


class AcpecFuelPurchaseLine(models.Model):
    _name = 'acpec.fuel.purchase.line'
    _description = 'Ligne achat FuelToken'
    _order = 'purchase_id, id'
    _rec_name = 'name'
    name = fields.Char(string='Libellé', compute='_compute_name', store=True, readonly=True)

    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot achat', required=True, ondelete='cascade', index=True)
    company_id = fields.Many2one('res.company', related='purchase_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='purchase_id.currency_id', store=True, readonly=True)
    carnet_type_id = fields.Many2one('acpec.fuel.carnet.type', string='Type de carnet', required=True)
    carnet_qty = fields.Integer(string='Nombre de carnets', required=True, default=1)
    face_count = fields.Integer(string='Nombre de tickets par carnet', readonly=True)
    face_value = fields.Monetary(string='Valeur du ticket', readonly=True)
    generated_face_qty = fields.Integer(string='Tickets générés', compute='_compute_amounts', store=True)
    amount_total = fields.Monetary(string='Montant total', compute='_compute_amounts', store=True)

    _positive_carnet_qty = models.Constraint(
        'CHECK(carnet_qty > 0)',
        'Le nombre de carnets doit etre positif.',
    )



    _immutable_line_fields = {
        'purchase_id',
        'carnet_type_id',
        'carnet_qty',
        'face_count',
        'face_value',
        'generated_face_qty',
        'amount_total',
    }

    _purchase_line_internal_context_key = (
        'acpec_fueltoken_purchase_line_internal_operation'
    )
    _snapshot_write_fields = frozenset({
        'face_count',
        'face_value',
    })

    @api.model
    def _purchase_line_internal_context_is_valid(self, operation):
        return bool(
            self.env.su
            and self.env.context.get(
                self._purchase_line_internal_context_key
            ) == operation
        )

    @api.model_create_multi
    def _create_internal(self, vals_list):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_line_internal_operation='create',
        ).create(vals_list)

    def _write_snapshot_internal(self, vals):
        return self.sudo().with_context(
            acpec_fueltoken_purchase_line_internal_operation='snapshot_write',
        ).write(vals)

    @api.model_create_multi
    def create(self, vals_list):
        if not self._purchase_line_internal_context_is_valid('create'):
            raise UserError(_(
                'La creation de lignes achat est reservee aux flux metier internes controles.'
            ))
        purchase_ids = {
            vals.get('purchase_id')
            for vals in vals_list
            if vals.get('purchase_id')
        }
        purchases = self.env['acpec.fuel.purchase'].browse(list(purchase_ids)).exists()
        if purchases.filtered(lambda purchase: purchase.state != 'draft'):
            raise UserError(_('Impossible d ajouter une ligne sur un lot achat soumis, valide ou rejete.'))

        carnet_type_ids = {
            vals.get('carnet_type_id')
            for vals in vals_list
            if vals.get('carnet_type_id')
        }
        carnet_types = {
            carnet.id: carnet
            for carnet in self.env['acpec.fuel.carnet.type'].sudo().browse(list(carnet_type_ids)).exists()
        }
        for vals in vals_list:
            carnet_type = carnet_types.get(vals.get('carnet_type_id'))
            if carnet_type:
                vals['face_count'] = int(carnet_type.face_count or 0)
                vals['face_value'] = carnet_type.face_value or 0.0

        return super().create(vals_list)

    def write(self, vals):
        if not vals:
            return True
        if (
            not self._purchase_line_internal_context_is_valid('snapshot_write')
            or set(vals) != self._snapshot_write_fields
        ):
            raise UserError(_(
                'Les modifications de lignes achat sont reservees aux flux metier internes controles.'
            ))
        if (
            int(vals.get('face_count') or 0) <= 0
            or float(vals.get('face_value') or 0.0) <= 0.0
        ):
            raise ValidationError(_(
                'Les snapshots de ligne achat doivent avoir des valeurs positives.'
            ))
        return super().write(vals)

    def unlink(self):
        raise UserError(_(
            'Les lignes d’achat ne doivent pas être supprimées directement.'
        ))

    @api.depends('purchase_id.name', 'carnet_qty', 'face_count', 'face_value', 'currency_id')
    def _compute_name(self):
        for rec in self:
            lot_name = rec.purchase_id.name or _('Lot achat')
            currency_name = rec.currency_id.name or ''
            face_count = rec.face_count or 0
            face_value = rec.face_value or 0.0

            if float(face_value).is_integer():
                face_value_label = str(int(face_value))
            else:
                face_value_label = ('%.2f' % face_value).rstrip('0').rstrip('.')

            if face_count and face_value:
                carnet_label = 'C%sT-%s%s' % (
                    face_count,
                    face_value_label,
                    currency_name.replace(' ', ''),
                )
            elif rec.carnet_type_id:
                carnet_label = rec.carnet_type_id.display_name
            else:
                carnet_label = _('Type carnet')

            rec.name = '%s - %s' % (
                lot_name,
                carnet_label,
            )

    @api.depends('carnet_qty', 'face_count', 'face_value')
    def _compute_amounts(self):
        for rec in self:
            rec.generated_face_qty = rec.carnet_qty * rec.face_count
            rec.amount_total = rec.generated_face_qty * rec.face_value

    @api.constrains('carnet_type_id', 'purchase_id')
    def _check_carnet_type_company(self):
        for rec in self:
            if (
                rec.carnet_type_id.company_id
                and rec.purchase_id.company_id
                and rec.carnet_type_id.company_id != rec.purchase_id.company_id
            ):
                raise ValidationError(_(
                    "Le type de carnet '%s' n'appartient pas a la societe du lot d'achat."
                ) % rec.carnet_type_id.display_name)

    def _check_line_values(self):
        for rec in self:
            if rec.carnet_qty <= 0:
                raise ValidationError(_('Le nombre de carnets doit etre positif.'))
            if not rec.carnet_type_id:
                raise ValidationError(_('Le type de carnet est obligatoire.'))

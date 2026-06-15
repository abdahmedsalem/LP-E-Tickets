import base64
import binascii
import os
import re

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError


class AcpecFuelPurchase(models.Model):
    _name = 'acpec.fuel.purchase'
    _description = 'Lot achat FuelToken'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'acpec.fuel.public.code.mixin']
    _order = 'id desc'

    name = fields.Char(string='Reference interne', default='New', readonly=True, copy=False)
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
    amount_total = fields.Monetary(string='Montant total', compute='_compute_totals', store=True)
    face_qty_total = fields.Integer(string='Nombre de faces', compute='_compute_totals', store=True)
    proof_attachment_ids = fields.Many2many(
        'ir.attachment',
        'acpec_fuel_purchase_attachment_rel',
        'purchase_id',
        'attachment_id',
        string='Preuves de paiement',
    )
    payment_reference = fields.Char(string='Reference paiement')
    idempotency_key = fields.Char(string='Cle idempotence', index=True, copy=False)
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

    @api.model_create_multi
    def create(self, vals_list):
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

    def _check_before_submit(self):
        for rec in self:
            if not rec.line_ids:
                raise ValidationError(_('Le lot achat doit contenir au moins une ligne.'))
            if not rec.proof_attachment_ids:
                raise ValidationError(_('La preuve de paiement est obligatoire.'))
            for line in rec.line_ids:
                line._check_line_values()

    def action_submit(self):
        self._check_before_submit()
        for rec in self:
            if rec.state != 'draft':
                raise UserError(_('Seuls les lots en brouillon peuvent etre soumis.'))
            rec.write({'state': 'submitted', 'submitted_at': fields.Datetime.now()})

    def action_approve(self):
        with self.env.cr.savepoint():
            self._check_before_submit()
            for rec in self:
                if rec.state not in ('draft', 'submitted'):
                    raise UserError(_('Seuls les lots brouillon ou soumis peuvent etre valides.'))
                rec.write({
                    'state': 'approved',
                    'approved_at': fields.Datetime.now(),
                    'approved_by': self.env.user.id,
                    'rejection_reason': False,
                })
            self._create_face_lines_after_approval()

    def action_reject(self):
        for rec in self:
            if rec.state == 'approved':
                raise UserError(_('Un lot valide ne peut pas etre rejete.'))
            rec.write({
                'state': 'rejected',
                'rejected_at': fields.Datetime.now(),
                'rejected_by': self.env.user.id,
            })

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

    def write(self, vals):
        protected = {'line_ids', 'partner_id', 'company_id', 'proof_attachment_ids', 'payment_reference'}
        if protected.intersection(vals):
            for rec in self:
                if rec.state == 'approved':
                    raise UserError(_('Un lot valide ne peut pas etre modifie sur ses champs sensibles.'))
        return super().write(vals)

    @api.model
    def create_from_api(self, partner, company, lines, proof_filename, proof_data, payment_reference=False, idempotency_key=False):
        if idempotency_key:
            existing = self.sudo().search([
                ('partner_id', '=', partner.id),
                ('idempotency_key', '=', idempotency_key),
            ], limit=1)
            if existing:
                return existing
        proof_filename, proof_data, proof_mimetype = self._validate_purchase_proof(proof_filename, proof_data)
        with self.env.cr.savepoint():
            purchase = self.sudo().create({
                'partner_id': partner.id,
                'company_id': company.id,
                'payment_reference': payment_reference or False,
                'idempotency_key': idempotency_key or False,
            })
            for item in lines:
                carnet_type = self.env['acpec.fuel.carnet.type'].sudo().browse(int(item.get('carnet_type_id') or 0)).exists()
                if not carnet_type:
                    raise ValidationError(_('Type de carnet introuvable.'))
                if not carnet_type.active:
                    raise ValidationError(_("Type de carnet '%s' desactive.") % carnet_type.display_name)
                if carnet_type.company_id and carnet_type.company_id != company:
                    raise ValidationError(_("Type de carnet '%s' indisponible pour cette societe.") % carnet_type.display_name)
                purchase.line_ids.create({
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
            purchase.write({'proof_attachment_ids': [(4, attachment.id)]})
            purchase.action_submit()
            return purchase


class AcpecFuelPurchaseLine(models.Model):
    _name = 'acpec.fuel.purchase.line'
    _description = 'Ligne achat FuelToken'
    _order = 'purchase_id, id'

    purchase_id = fields.Many2one('acpec.fuel.purchase', string='Lot achat', required=True, ondelete='cascade', index=True)
    company_id = fields.Many2one('res.company', related='purchase_id.company_id', store=True, readonly=True)
    currency_id = fields.Many2one('res.currency', related='purchase_id.currency_id', store=True, readonly=True)
    carnet_type_id = fields.Many2one('acpec.fuel.carnet.type', string='Type de carnet', required=True)
    carnet_qty = fields.Integer(string='Nombre de carnets', required=True, default=1)
    face_count = fields.Integer(string='Taille carnet', related='carnet_type_id.face_count', store=True, readonly=True)
    face_value = fields.Monetary(string='Valeur de face', related='carnet_type_id.face_value', store=True, readonly=True)
    generated_face_qty = fields.Integer(string='Faces generees', compute='_compute_amounts', store=True)
    amount_total = fields.Monetary(string='Montant total', compute='_compute_amounts', store=True)

    _positive_carnet_qty = models.Constraint(
        'CHECK(carnet_qty > 0)',
        'Le nombre de carnets doit etre positif.',
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

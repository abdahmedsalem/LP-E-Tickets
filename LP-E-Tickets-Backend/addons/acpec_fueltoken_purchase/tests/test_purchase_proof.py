import base64

from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestAcpecFuelPurchaseProof(TransactionCase):

    def setUp(self):
        super().setUp()
        self.Purchase = self.env['acpec.fuel.purchase'].sudo()

    def _b64(self, content):
        return base64.b64encode(content).decode('ascii')

    def test_validate_pdf_with_missing_filename_uses_pdf_extension(self):
        filename, payload, mimetype = self.Purchase._validate_purchase_proof(
            False,
            self._b64(b'%PDF-1.4\n%test\n'),
        )

        self.assertEqual(filename, 'preuve_paiement.pdf')
        self.assertEqual(mimetype, 'application/pdf')
        self.assertEqual(base64.b64decode(payload), b'%PDF-1.4\n%test\n')

    def test_validate_png_derives_extension_from_content(self):
        filename, _payload, mimetype = self.Purchase._validate_purchase_proof(
            'preuve_paiement.pdf',
            self._b64(b'\x89PNG\r\n\x1a\n' + b'png-data'),
        )

        self.assertEqual(filename, 'preuve_paiement.png')
        self.assertEqual(mimetype, 'image/png')

    def test_validate_jpeg_derives_extension_from_content(self):
        filename, _payload, mimetype = self.Purchase._validate_purchase_proof(
            'capture.png',
            self._b64(b'\xff\xd8\xff\xe0' + b'jpeg-data'),
        )

        self.assertEqual(filename, 'capture.jpg')
        self.assertEqual(mimetype, 'image/jpeg')

    def test_validate_rejects_declared_mimetype_mismatch(self):
        with self.assertRaises(ValidationError):
            self.Purchase._validate_purchase_proof(
                'capture.png',
                'data:image/png;base64,%s' % self._b64(b'\xff\xd8\xff\xe0' + b'jpeg-data'),
            )

    def test_validate_rejects_invalid_base64(self):
        with self.assertRaises(ValidationError):
            self.Purchase._validate_purchase_proof('preuve.pdf', 'not valid base64 !!')

    def test_validate_rejects_empty_file(self):
        with self.assertRaises(ValidationError):
            self.Purchase._validate_purchase_proof('preuve.pdf', self._b64(b''))

    def test_validate_rejects_oversized_file(self):
        self.env['ir.config_parameter'].sudo().set_param(
            'acpec_fueltoken_purchase.proof_max_bytes',
            '8',
        )
        with self.assertRaises(ValidationError):
            self.Purchase._validate_purchase_proof(
                'preuve.pdf',
                self._b64(b'%PDF-1.4\n' + b'123456789'),
            )

    def test_open_payment_proof_opens_image_inline_in_new_tab(self):
        purchase = self.Purchase._create_internal({
            'partner_id': self.env.company.partner_id.id,
            'company_id': self.env.company.id,
        })
        pdf = self.env['ir.attachment'].sudo().create({
            'name': 'preuve.pdf',
            'datas': self._b64(b'%PDF-1.4\n%test\n'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
        })
        image = self.env['ir.attachment'].sudo().create({
            'name': 'preuve.png',
            'datas': self._b64(b'\x89PNG\r\n\x1a\nimage'),
            'mimetype': 'image/png',
            'res_model': purchase._name,
            'res_id': purchase.id,
        })
        purchase._write_proof_internal({
            'proof_attachment_ids': [(6, 0, (pdf | image).ids)],
        })

        action = purchase.action_open_payment_proof()

        self.assertEqual(action['type'], 'ir.actions.act_window')
        self.assertEqual(action['res_model'], 'acpec.fuel.purchase.proof.wizard')
        self.assertEqual(action['target'], 'new')
        wizard = self.env['acpec.fuel.purchase.proof.wizard'].browse(action['res_id'])
        self.assertEqual(wizard.attachment_id, image)

    def test_open_payment_proof_rejects_purchase_without_proof(self):
        purchase = self.Purchase._create_internal({
            'partner_id': self.env.company.partner_id.id,
            'company_id': self.env.company.id,
        })

        with self.assertRaises(UserError):
            purchase.action_open_payment_proof()

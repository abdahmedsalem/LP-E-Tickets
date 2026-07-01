from odoo.tests.common import TransactionCase


class TestPublicQrCarnetShortCodeFormat(TransactionCase):

    def test_j2_carnet_short_code_uses_cnt_year_sequence(self):
        FaceLine = self.env['acpec.fuel.face.line'].sudo()
        code = FaceLine._generate_carnet_short_code(self.env.company)
        self.assertRegex(code, r'^CNT/[0-9]{4}/[0-9]{5}$')

    def test_j2_face_line_has_name_identity_and_rec_name_keeps_short_code(self):
        FaceLine = self.env['acpec.fuel.face.line']
        self.assertIn('name', FaceLine._fields)
        self.assertIn('carnet_short_code', FaceLine._fields)
        self.assertEqual(FaceLine._rec_name, 'carnet_short_code')

from odoo.tests import TransactionCase, tagged
from odoo.tools.convert import convert_file


@tagged('-at_install', 'post_install')
class TestReviewConfigDefaults(TransactionCase):
    def _load_defaults(self):
        convert_file(
            self.env, 'acpec_google_play_review_access',
            'data/google_play_review_config.xml', {}, mode='init',
        )

    def test_existing_unlinked_parameters_are_preserved(self):
        params = self.env['ir.config_parameter'].sudo()
        prefix = 'acpec_google_play_review_access.'
        self.env['ir.model.data'].search([
            ('module', '=', 'acpec_google_play_review_access'),
            ('name', 'in', ['google_play_review_enabled', 'google_play_review_phone']),
        ]).unlink()
        params.set_param(prefix + 'enabled', 'False')
        params.set_param(prefix + 'phone', '32524659')
        self._load_defaults()
        self._load_defaults()
        self.assertEqual(params.get_param(prefix + 'enabled'), 'False')
        self.assertEqual(params.get_param(prefix + 'phone'), '32524659')

    def test_missing_parameters_are_initialized_once(self):
        params = self.env['ir.config_parameter'].sudo()
        prefix = 'acpec_google_play_review_access.'
        params.search([('key', 'in', [prefix + 'enabled', prefix + 'phone'])]).unlink()
        self._load_defaults()
        self._load_defaults()
        self.assertEqual(params.get_param(prefix + 'enabled'), 'True')
        self.assertEqual(params.get_param(prefix + 'phone'), '27919822,32524659')

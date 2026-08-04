from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged


@tagged('-at_install', 'post_install')
class TestGooglePlayReviewOtp(TransactionCase):

    REVIEW_PHONE = '27919822'
    SECOND_REVIEW_PHONE = '32524659'

    def setUp(self):
        super().setUp()
        self.params = self.env['ir.config_parameter'].sudo()
        self.params.set_param(
            'acpec_google_play_review_access.enabled',
            'True',
        )
        self.params.set_param(
            'acpec_google_play_review_access.phone',
            '%s,%s' % (self.REVIEW_PHONE, self.SECOND_REVIEW_PHONE),
        )
        partner = self.env['res.partner'].create({
            'name': 'Google Play Reviewer',
        })
        self.user = (
            self.env['res.users']
            .sudo()
            .with_context(no_reset_password=True)
            .create({
                'name': 'Google Play Reviewer',
                'login': self.REVIEW_PHONE,
                'partner_id': partner.id,
                'company_id': self.env.company.id,
                'company_ids': [(6, 0, [self.env.company.id])],
                'mobile_phone': self.REVIEW_PHONE,
            })
        )
        self.user.write({
            'active': True,
            'acpec_mobile_state': 'approved',
        })

    def test_review_phone_uses_fixed_otp_for_login(self):
        challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            self.REVIEW_PHONE,
            purpose='login',
            request_ip='10.90.0.1',
        )

        self.assertEqual(code, '000000')
        self.assertEqual(challenge.user_id, self.user)
        self.assertEqual(
            challenge.verify('000000', request_ip='10.90.0.1'),
            self.user,
        )

    def test_review_otp_is_refused_after_feature_is_disabled(self):
        challenge, code = self.env['acpec.mobile.auth.otp'].sudo().request_otp(
            self.REVIEW_PHONE,
            purpose='login',
            request_ip='10.90.0.2',
        )
        self.assertEqual(code, '000000')
        self.params.set_param(
            'acpec_google_play_review_access.enabled',
            'False',
        )

        with self.assertRaisesRegex(AccessError, 'Code OTP invalide'):
            challenge.verify('000000', request_ip='10.90.0.2')

    def test_review_mode_is_limited_to_login_and_configured_phone(self):
        otp_model = self.env['acpec.mobile.auth.otp'].sudo()

        self.assertTrue(
            otp_model._is_google_play_review_login(
                self.REVIEW_PHONE,
                'login',
            )
        )
        self.assertTrue(
            otp_model._is_google_play_review_login(
                self.SECOND_REVIEW_PHONE,
                'login',
            )
        )
        self.assertFalse(
            otp_model._is_google_play_review_login(
                self.REVIEW_PHONE,
                'register',
            )
        )
        self.assertFalse(
            otp_model._is_google_play_review_login(
                '27919823',
                'login',
            )
        )

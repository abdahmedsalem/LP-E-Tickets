{
    'name': 'ACPEC Google Play Review Access',
    'version': '19.0.1.0.0',
    'summary': 'Reusable OTP access for the dedicated Google Play review account',
    'category': 'Tools',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth_otp'],
    'data': [
        'data/google_play_review_config.xml',
        'views/res_config_settings.xml',
    ],
    'installable': True,
    'application': True,
}

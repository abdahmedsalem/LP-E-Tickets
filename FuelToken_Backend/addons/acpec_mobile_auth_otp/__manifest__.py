{
    'name': 'ACPEC Mobile Auth OTP',
    'version': '19.0.1.5.0',
    'summary': 'OTP authentication layer for ACPEC mobile applications',
    'description': 'Adds OTP request and verification flows on top of ACPEC Mobile Auth token sessions.',
    'category': 'Tools',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth', 'base_setup'],
    'data': [
        'security/ir.model.access.csv',
        'views/mobile_auth_otp_views.xml',
        'views/res_config_settings.xml',
    ],
    'installable': True,
    'application': False,
}

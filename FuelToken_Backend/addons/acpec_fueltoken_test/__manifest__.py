{
    'name': 'ACPEC FuelToken Test',
    'version': '19.0.1.2.4',
    'summary': 'Console navigateur de test pour les APIs FuelToken',
    'description': 'Console navigateur locale pour tester les endpoints reels ACPEC Mobile Auth et FuelToken. Les comportements dangereux de test OTP sont inertes sauf si ACPEC_FUELTOKEN_TEST_MODE=1.',
    'category': 'Tools',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['web', 'acpec_mobile_auth_otp', 'acpec_fueltoken_api'],
    'data': [
        'views/test_templates.xml',
    ],
    'application': False,
    'post_init_hook': 'post_init_hook',
    'uninstall_hook': 'uninstall_hook',
    'installable': True,
}
